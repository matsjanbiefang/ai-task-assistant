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
            AssistantView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for line: NoteLine) -> some View {
        if focusedTarget == .line(line.id) {
            TextField("", text: editingTextBinding(for: line), axis: .vertical)
                .font(.title3)
                .lineLimit(1...6)
                .focused($focusedTarget, equals: .line(line.id))
                .submitLabel(.done)
                .onSubmit {
                    Task { await commitLine(line) }
                }
                .onChange(of: editingTexts[line.id]) { _, newValue in
                    guard let newValue, newValue.contains("\n") else { return }
                    editingTexts[line.id] = newValue.replacingOccurrences(of: "\n", with: "")
                    Task { await commitLine(line) }
                }
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    editingTexts[line.id] = line.text
                    // Setting focus in the same tick the row swaps from Text to TextField can be
                    // dropped by SwiftUI — the TextField isn't in the view tree yet at the moment
                    // focusedTarget changes. Deferring one runloop tick makes it reliable.
                    DispatchQueue.main.async {
                        focusedTarget = .line(line.id)
                    }
                } label: {
                    highlightedText(line.text, struckThrough: isLineCompleted(line))
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    showTasks = true
                } label: {
                    statusIcon(for: line)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
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

    // §3: Amy-pattern inline status icon — tapping it jumps to the tasks sheet (user feedback).
    @ViewBuilder
    private func statusIcon(for line: NoteLine) -> some View {
        if line.hasLowConfidence {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
        } else if line.taskCount > 1 {
            Text("\(line.taskCount)")
                .font(.caption2.bold())
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
        } else if line.taskCount == 1 {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
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
    // Reads live state (editingTexts) rather than taking the text as a parameter, so if both
    // onSubmit and the newline-fallback in `row(for:)` somehow fire for the same commit, the
    // second call harmlessly re-commits already-committed text instead of double-processing a
    // stale value.
    private func commitLine(_ line: NoteLine) async {
        let text = editingTexts[line.id] ?? line.text
        editingTexts[line.id] = nil
        focusedTarget = nil
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
            let item = TaskItem(
                title: task.title,
                dueDate: parsedDate(task.dueDate),
                priority: task.priority?.rawValue,
                category: task.category?.rawValue,
                dateConfidence: task.dateConfidence,
                sourceLineID: line.id
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
