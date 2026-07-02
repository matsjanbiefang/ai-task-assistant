import SwiftUI
import SwiftData
import UIKit

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
    @State private var targetTask: TaskItem?
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            row(for: line)
                        }
                        composeRow
                            .id("compose")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .onChange(of: lines.count) { _, _ in
                    withAnimation { proxy.scrollTo("compose", anchor: .bottom) }
                }
                .onChange(of: focusedTarget) { oldValue, newValue in
                    // Committing here (rather than from onSubmit) means a line's edits are saved
                    // no matter how focus leaves it — pressing Return, tapping a different line,
                    // tapping compose, or dismissing the keyboard all funnel through this single
                    // path instead of each needing their own commit call.
                    if case .line(let id) = oldValue, let line = lines.first(where: { $0.id == id }) {
                        Task { await commitLine(line) }
                    }
                    withAnimation {
                        switch newValue {
                        case .line(let id): proxy.scrollTo(id, anchor: .bottom)
                        case .compose: proxy.scrollTo("compose", anchor: .bottom)
                        case nil: break
                        }
                    }
                }
            }
            bottomBar
        }
        .background(Color(.systemBackground))
        .onAppear { focusedTarget = .compose }
        .onChange(of: activateDictation) { _, active in
            if active {
                activateDictation = false
                Task { await toggleRecording() }
            }
        }
        .onChange(of: speech.transcript) { _, new in
            if isRecording { composeText = new }
        }
        .sheet(isPresented: $showTasks) {
            AssistantView(initialTask: targetTask)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                    .font(.title3)
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
                        .font(.title3)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                targetTask = allTasks.first { $0.sourceLineID == line.id }
                showTasks = true
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
            .font(.title3)
            .lineLimit(1...6)
            .focused($focusedTarget, equals: .compose)
            .submitLabel(.done)
            .onSubmit {
                Task { await commitCompose() }
            }
            .onChange(of: composeText) { _, newValue in
                guard newValue.contains("\n") else { return }
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

    // §3 + user feedback: small icon row showing exactly what got extracted from the line (time /
    // category / priority / linked-step), not just a generic task-count badge — tapping it jumps
    // straight to the relevant task(s) in the sheet.
    @ViewBuilder
    private func statusIcon(for line: NoteLine) -> some View {
        let tasksForLine = allTasks.filter { $0.sourceLineID == line.id }
        if line.hasLowConfidence {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
        } else if !tasksForLine.isEmpty {
            HStack(spacing: 3) {
                if tasksForLine.contains(where: { $0.dueTime != nil }) {
                    Image(systemName: "clock")
                }
                if let category = tasksForLine.compactMap(\.category).first {
                    Image(systemName: categoryIcon(category))
                }
                if let priority = tasksForLine.compactMap(\.priority).first {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(priorityColor(priority))
                }
                if tasksForLine.contains(where: { $0.linkedGroupID != nil }) {
                    Image(systemName: "link")
                }
                if line.taskCount > 1 {
                    Text("\(line.taskCount)")
                        .font(.caption2.bold())
                }
            }
            .font(.caption)
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

    // Amy-style keyboard-docked bar: mic, open-task counts, keyboard dismiss, calendar/tasks.
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

            Button {
                targetTask = nil
                showTasks = true
            } label: {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
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
        line.hasLowConfidence = extracted.contains { $0.dateConfidence < 0.7 }

        for task in extracted {
            let dueDate = parsedDate(task.dueDate)
            let item = TaskItem(
                title: task.title,
                dueDate: dueDate,
                dueTime: parsedTime(task.dueTime, referenceDay: dueDate),
                priority: task.priority?.rawValue,
                category: task.category?.rawValue,
                dateConfidence: task.dateConfidence,
                sourceLineID: line.id,
                linkedGroupID: task.groupID,
                sequenceIndex: task.sequenceIndex
            )
            modelContext.insert(item)
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
        .modelContainer(for: [TaskItem.self, NoteLine.self], inMemory: true)
}
