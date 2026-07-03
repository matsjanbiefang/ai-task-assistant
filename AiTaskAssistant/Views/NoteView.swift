import SwiftUI
import SwiftData
import UIKit
import Combine

// prd-update-01.md §3: free-form, persistent, Apple-Notes-style multi-line surface. Each committed
// line is a `NoteLine`; pressing return (or tapping away from an edited line) commits/re-parses it
// immediately — no submit-button ceremony. §4/§9: this stays the app's landing screen.
//
// User feedback (2026-07-02) folded in: word-wrapping lines instead of horizontal shift, a
// keyboard-docked bottom bar (mic / open task counts / dismiss keyboard / calendar), tapping a
// line's status icon jumps to the tasks sheet instead of only editing text, and completed tasks
// show struck through in place.
struct NoteView: View {
    @Binding var activateDictation: Bool
    @Binding var showTasks: Bool

    @Environment(\.modelContext) private var modelContext
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = "en"
    @Query(sort: \NoteLine.order) private var lines: [NoteLine]
    @Query private var allTasks: [TaskItem]

    @State private var editingTexts: [UUID: String] = [:]
    @State private var composeText = ""
    @State private var permissionDenied = false
    @State private var speech = SpeechRecognizer()
    @State private var editTask: TaskItem?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedTarget: FocusTarget?

    private let extraction = RuleBasedExtractionService.shared

    private enum FocusTarget: Hashable {
        case line(UUID)
        case compose
    }

    private var isRecording: Bool { speech.state == .recording }
    private var openTasks: [TaskItem] { allTasks.filter { !$0.isCompleted } }
    private var todayOpenCount: Int { openTasks.filter { isToday($0.dueDate) }.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            row(for: line)
                        }
                        composeRow
                            .id("compose")
                        // Reserves scrollable room below the last row equal to the keyboard's
                        // own height. This is a deliberate belt-and-suspenders fix: even if a
                        // scrollTo call above lands slightly early/late relative to the keyboard's
                        // slide animation, there's always enough space to scroll the active row
                        // fully clear of the keyboard rather than partially behind it.
                        Color.clear.frame(height: keyboardHeight)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: lines.count) { _, _ in
                    withAnimation { proxy.scrollTo("compose", anchor: .bottom) }
                }
                // Typing at the bottom of a long note: focus doesn't change while typing, so the
                // focus-change scroll below never fires — scroll on the text itself growing.
                .onChange(of: composeText) { _, _ in
                    proxy.scrollTo("compose", anchor: .bottom)
                }
                // keyboardWillShow/Hide (not keyboardWillChangeFrame — that one also fires for
                // every predictive-text-bar height tweak, not just actual show/hide, and was
                // re-laying out the whole scroll content on every one of those, which is almost
                // certainly what made typing feel laggy) fire once per actual keyboard transition,
                // with the target frame available before the slide animation starts so the
                // reserved-space padding can animate in sync with it.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                    let screenHeight = UIScreen.main.bounds.height
                    let newHeight = max(0, screenHeight - frame.origin.y)
                    withAnimation { keyboardHeight = newHeight }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation { keyboardHeight = 0 }
                }
                // The focus-change scroll runs BEFORE the keyboard finishes its slide-up
                // animation, so the scrolled-to position can end up covered anyway. keyboardDid-
                // ShowNotification fires after the animation — re-scroll then with final sizes.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    withAnimation { scrollToFocus(proxy) }
                }
                .onChange(of: focusedTarget) { oldValue, _ in
                    // Committing here (rather than from onSubmit) means a line's edits are saved
                    // no matter how focus leaves it — pressing Return, tapping a different line,
                    // tapping compose, or dismissing the keyboard all funnel through this single
                    // path instead of each needing their own commit call.
                    if case .line(let id) = oldValue, let line = lines.first(where: { $0.id == id }) {
                        Task { await commitLine(line) }
                    }
                    withAnimation { scrollToFocus(proxy) }
                }
            }
            bottomBar
        }
        .background(Color(.systemBackground))
        .onAppear { focusedTarget = .compose }
        .onDisappear { speech.stopRecording() }
        .onChange(of: activateDictation) { _, active in
            if active {
                activateDictation = false
                Task { await toggleRecording() }
            }
        }
        .onChange(of: speech.transcript) { _, new in
            if isRecording { composeText = new }
        }
        // U2-1: commit on the recording→not-recording transition, not just the mic-button tap —
        // `speech.state` can also go idle internally (e.g. `result.isFinal` auto-stopping), which
        // a button-tap-only trigger would miss.
        .onChange(of: speech.state) { old, new in
            if old == .recording && new != .recording {
                Task { await commitDictatedText() }
            }
        }
        .sheet(isPresented: $showTasks) {
            AssistantView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Feedback round 3: tapping a single-task line's indicator opens that task's editor
        // directly — no task list in between.
        .sheet(item: $editTask) { task in
            TaskEditView(task: task)
        }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        switch focusedTarget {
        case .line(let id): proxy.scrollTo(id, anchor: .bottom)
        case .compose: proxy.scrollTo("compose", anchor: .bottom)
        case nil: break
        }
    }

    // MARK: - Rows

    // Always mounts a real TextField (never conditionally swaps it for a Text/Button pair) —
    // tapping to re-enter edit mode is then just the OS's normal text-field-tap-to-focus
    // behavior, not something SwiftUI's conditional view identity can silently drop. The styled/
    // highlighted rendering sits on top as a non-interactive overlay while unfocused, with the
    // real field's own text made invisible so it doesn't show twice.
    private func row(for line: NoteLine) -> some View {
        let isEditing = focusedTarget == .line(line.id)
        return HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextField("", text: editingTextBinding(for: line), axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .focused($focusedTarget, equals: .line(line.id))
                    .foregroundStyle(isEditing ? Color.primary : Color.clear)
                    .submitLabel(.done)
                    .onSubmit { focusedTarget = nil }
                    .onChange(of: editingTexts[line.id]) { _, newValue in
                        guard let newValue, newValue.contains("\n") else { return }
                        editingTexts[line.id] = newValue.replacingOccurrences(of: "\n", with: "")
                        focusedTarget = nil
                    }

                if !isEditing {
                    highlightedText(line.text, struckThrough: isLineCompleted(line))
                        .font(.body)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Relying solely on the invisible TextField's own native tap-to-focus was reported as
            // needing several taps to register — its hit-testable bounds evidently don't always
            // line up with the highlighted overlay's visible bounds (e.g. after text wraps to a
            // second line). A simultaneous (not exclusive) tap gesture guarantees a single tap
            // focuses the row, without blocking normal cursor-repositioning taps once already
            // editing — simultaneousGesture lets both the TextField's own gesture and this one
            // fire, unlike onTapGesture/gesture() which would swallow the tap exclusively.
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !isEditing {
                        focusedTarget = .line(line.id)
                    }
                }
            )

            Button {
                let tasksForLine = allTasks.filter { $0.sourceLineID == line.id }
                if tasksForLine.count == 1 {
                    editTask = tasksForLine[0]
                } else {
                    // several tasks came out of this line — no single editor to jump to
                    showTasks = true
                }
            } label: {
                statusIcon(for: line)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .id(line.id)
    }

    private var composeRow: some View {
        TextField("What do you need to do?", text: $composeText, axis: .vertical)
            .font(.body)
            .lineLimit(1...6)
            .focused($focusedTarget, equals: .compose)
            .submitLabel(.done)
            .onSubmit {
                Task { await commitCompose() }
            }
            .onChange(of: composeText) { _, newValue in
                // U2-1: while dictating, composeText can legitimately carry multiple embedded
                // "\n"s (one per detected speech pause) as the transcript streams in — those are
                // committed as separate lines all at once when recording stops, not one at a
                // time here. This handler is only for the single-Return-press typing case, where
                // "\n" means "commit and clear," not "insert a newline character."
                guard !isRecording, newValue.contains("\n") else { return }
                composeText = newValue.replacingOccurrences(of: "\n", with: "")
                Task { await commitCompose() }
            }
            .padding(.vertical, 4)
    }

    private func editingTextBinding(for line: NoteLine) -> Binding<String> {
        Binding(
            get: { editingTexts[line.id] ?? line.text },
            set: { editingTexts[line.id] = $0 }
        )
    }

    // §3: subtle inline highlight on detected date phrases, like Notes/Mail link detection —
    // purely visual, computed fresh from the same rules the extraction engine matches against.
    // Completed lines (every task from this line marked done) render struck through.
    private func highlightedText(_ text: String, struckThrough: Bool) -> Text {
        let ranges = extraction.highlightRanges(in: text, primaryLanguageCode: primaryLanguageCode)
        let mutable = NSMutableAttributedString(string: text)
        for range in ranges {
            mutable.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(range, in: text))
        }
        if struckThrough {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            mutable.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: fullRange)
        }
        return Text(AttributedString(mutable))
    }

    private func isLineCompleted(_ line: NoteLine) -> Bool {
        let tasksForLine = allTasks.filter { $0.sourceLineID == line.id }
        guard !tasksForLine.isEmpty else { return false }
        return tasksForLine.allSatisfy(\.isCompleted)
    }

    // Feedback round 3: always-visible extraction indicators. Time and place ALWAYS show — an
    // uncrossed icon means the engine found that signal, a crossed/dimmed one means it didn't —
    // so a glance tells the user exactly what got logged. Details/link/category/priority icons
    // appear only when present.
    @ViewBuilder
    private func statusIcon(for line: NoteLine) -> some View {
        let tasksForLine = allTasks.filter { $0.sourceLineID == line.id }
        if line.hasLowConfidence {
            Image(systemName: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if !tasksForLine.isEmpty {
            let hasTime = tasksForLine.contains { $0.dueTime != nil || $0.timeOfDay != nil }
            let hasPlace = tasksForLine.contains { $0.place != nil }
            HStack(spacing: 3) {
                Image(systemName: hasTime ? "clock" : "clock.badge.xmark")
                    .foregroundStyle(hasTime ? Color.secondary : Color.secondary.opacity(0.35))
                Image(systemName: hasPlace ? "mappin.and.ellipse" : "mappin.slash")
                    .foregroundStyle(hasPlace ? Color.secondary : Color.secondary.opacity(0.35))
                if tasksForLine.contains(where: { $0.details != nil }) {
                    Image(systemName: "note.text")
                }
                if tasksForLine.contains(where: { $0.linkedGroupID != nil }) {
                    Image(systemName: "link")
                }
                if let category = tasksForLine.compactMap(\.category).first {
                    Image(systemName: categoryIcon(category))
                }
                if let priority = tasksForLine.compactMap(\.priority).first {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(priorityColor(priority))
                }
                if line.taskCount > 1 {
                    Text("\(line.taskCount)")
                        .font(.caption2.bold())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "work": return "briefcase"
        case "health": return "heart"
        case "shopping": return "cart"
        case "finance": return "dollarsign.circle"
        case "personal": return "person"
        default: return "tag"
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high": return .red
        case "medium": return .orange
        default: return .secondary
        }
    }

    // Fixed header, NOT inside the ScrollView — a sibling of it in the root VStack. Its purpose
    // is purely structural: since it's a separate, opaque view sitting above the scroll area, the
    // note content's own top edge can never visually end up "behind" the system status bar/notch
    // the way it could when the ScrollView's content was allowed to scroll all the way to y=0.
    // The calendar icon lives here now (moved from the bottom bar) per explicit request.
    private var topBar: some View {
        HStack {
            Text("Notes")
                .font(.headline)
            Spacer()
            Button {
                showTasks = true
            } label: {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // Amy-style keyboard-docked bar: mic, open-task counts, keyboard dismiss.
    // Sits as the last item in the root VStack with no ancestor ignoresSafeArea() — SwiftUI's
    // normal keyboard-avoidance then slides it to sit directly above the keyboard.
    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(isRecording ? .red : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }

            taskCountsPill

            if permissionDenied {
                Text("Mic access denied")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if focusedTarget != nil {
                Button {
                    focusedTarget = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var taskCountsPill: some View {
        HStack(spacing: 4) {
            Text("\(openTasks.count)")
                .fontWeight(.semibold)
            Text("open")
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(todayOpenCount)")
                .fontWeight(.semibold)
            Text("today")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    // MARK: - Actions

    private func toggleRecording() async {
        if isRecording {
            speech.stopRecording()
            return
        }
        let granted = await speech.requestPermissions()
        if granted {
            focusedTarget = .compose
            speech.startRecording()
        } else {
            permissionDenied = true
        }
    }

    private func commitCompose() async {
        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (lines.map(\.order).max() ?? -1) + 1
        let newLine = NoteLine(text: trimmed, order: nextOrder)
        modelContext.insert(newLine)
        composeText = ""
        await reparse(newLine)
    }

    // U2-1: dictation's composeText can carry multiple "\n"-separated segments (one per detected
    // speech pause) by the time recording stops — commitCompose() assumes a single line and would
    // pass an embedded "\n" straight into extraction, which isn't designed to split on interior
    // newlines the way extract(from:) (plural) does. Each segment becomes its own NoteLine here,
    // in order, mirroring what typing-and-returning multiple lines already produces.
    private func commitDictatedText() async {
        let segments = composeText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else {
            composeText = ""
            return
        }
        var nextOrder = (lines.map(\.order).max() ?? -1) + 1
        for segment in segments {
            let newLine = NoteLine(text: segment, order: nextOrder)
            nextOrder += 1
            modelContext.insert(newLine)
            await reparse(newLine)
        }
        composeText = ""
    }

    // U1-5: editing a committed line replaces its old tasks rather than duplicating them.
    // Reads live state (editingTexts) rather than taking the text as a parameter — this is now
    // called exactly once per focus-leaving-the-line event (from the ScrollView's onChange(of:
    // focusedTarget) in `body`), so there's no longer a double-commit path to guard against, but
    // reading live state instead of a captured value is still the safer default.
    private func commitLine(_ line: NoteLine) async {
        let text = editingTexts[line.id] ?? line.text
        editingTexts[line.id] = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await deleteLine(line)
        } else {
            line.text = trimmed
            await reparse(line)
        }
    }

    private func reparse(_ line: NoteLine) async {
        await removeTasks(forLineID: line.id)

        let extracted = extraction.extractLine(line.text, primaryLanguageCode: primaryLanguageCode)
        line.taskCount = extracted.count
        line.hasLowConfidence = extracted.contains { RuleBasedExtractionService.isLowConfidence($0.dateConfidence) }

        for task in extracted {
            let dueDate = parsedDate(task.dueDate)
            let item = TaskItem(
                title: task.title,
                dueDate: dueDate,
                dueTime: parsedTime(task.dueTime, referenceDay: dueDate),
                dueEndDate: parsedDate(task.dueEndDate),
                priority: task.priority?.rawValue,
                category: task.category?.rawValue,
                dateConfidence: task.dateConfidence,
                sourceLineID: line.id,
                linkedGroupID: task.groupID,
                sequenceIndex: task.sequenceIndex,
                place: task.place,
                details: task.details,
                timeOfDay: task.timeOfDay
            )
            modelContext.insert(item)
            // Temporarily disabled: EntityMemoryService.recordMention(place:...) reproducibly
            // crashes on-device (TestFlight builds 10) with EXC_CRASH/SIGABRT — a
            // swift_dynamicCastFailure deep inside SwiftData's DefaultStore.createSnapshot,
            // confirmed via two real crash logs (one during the fetch in
            // EntityMemoryService.find, one during this line's ModelContext.save()), reproducible
            // even on a completely fresh install. No known fix found (looks like an iOS
            // 26.5-era SwiftData bug, not a mistake in EntityMemory's schema). Safe to disable:
            // nothing reads EntityMemory yet (EM-2b, wiring it into extraction, was already
            // deferred), so this is pure write-only telemetry — losing it costs nothing
            // functional while this is investigated further.
            // if let place = item.place {
            //     EntityMemoryService.recordMention(place, type: .place, categoryHint: item.category, context: modelContext)
            // }
            if let date = item.dueDate, date > .now {
                await NotificationService.shared.schedule(taskID: item.id.uuidString, title: item.title, at: date)
            }
        }
        try? modelContext.save()
        await refreshBadge()
    }

    private func deleteLine(_ line: NoteLine) async {
        await removeTasks(forLineID: line.id)
        modelContext.delete(line)
        try? modelContext.save()
        await refreshBadge()
    }

    private func removeTasks(forLineID lineID: UUID) async {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.sourceLineID == lineID })
        guard let oldTasks = try? modelContext.fetch(descriptor) else { return }
        for task in oldTasks {
            await NotificationService.shared.cancel(taskID: task.id.uuidString)
            modelContext.delete(task)
        }
    }

    private func parsedDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: string)
    }

    // Combines an extracted "HH:mm" with the task's own due day (or today, if undated) so
    // TaskItem.dueTime is a coherent Date rather than just floating minutes with no day at all.
    private func parsedTime(_ hhmm: String?, referenceDay: Date?) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDay ?? .now)
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func refreshBadge() async {
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.dueDate != nil &&
                task.dueDate! >= today &&
                task.dueDate! < tomorrow &&
                !task.isCompleted
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        await NotificationService.shared.updateBadge(todayCount: count)
    }
}

#Preview {
    NoteView(activateDictation: .constant(false), showTasks: .constant(false))
        .modelContainer(for: [TaskItem.self, NoteLine.self, EntityMemory.self], inMemory: true)
}
