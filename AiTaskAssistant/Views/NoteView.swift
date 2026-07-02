import SwiftUI
import SwiftData
import UIKit

// prd-update-01.md §3: free-form, persistent, Apple-Notes-style multi-line surface. Each committed
// line is a `NoteLine`; pressing return (or tapping away from an edited line) commits/re-parses it
// immediately — no submit-button ceremony. §4/§9: this stays the app's landing screen; Slide 2 is
// reached by swiping, not by an automatic post-submit jump (U1-7 removed that old transition).
struct NoteView: View {
    @Binding var activateDictation: Bool

    @Environment(\.modelContext) private var modelContext
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = "en"
    @Query(sort: \NoteLine.order) private var lines: [NoteLine]

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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
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
                micBar
            }
        }
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
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for line: NoteLine) -> some View {
        if focusedTarget == .line(line.id) {
            TextField("", text: editingTextBinding(for: line))
                .font(.title3)
                .focused($focusedTarget, equals: .line(line.id))
                .submitLabel(.done)
                .onSubmit {
                    Task { await commitLine(line, text: editingTexts[line.id] ?? line.text) }
                }
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    editingTexts[line.id] = line.text
                    focusedTarget = .line(line.id)
                } label: {
                    highlightedText(line.text)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                statusIcon(for: line)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private var composeRow: some View {
        TextField("What do you need to do?", text: $composeText)
            .font(.title3)
            .focused($focusedTarget, equals: .compose)
            .submitLabel(.done)
            .onSubmit {
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
    private func highlightedText(_ text: String) -> Text {
        let ranges = extraction.highlightRanges(in: text, primaryLanguageCode: primaryLanguageCode)
        guard !ranges.isEmpty else { return Text(text) }
        let mutable = NSMutableAttributedString(string: text)
        for range in ranges {
            mutable.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(range, in: text))
        }
        return Text(AttributedString(mutable))
    }

    // §3: Amy-pattern inline status icon — "1 task" (checkmark), "N tasks" (count badge), or a
    // subtle "unsure" state when any resulting task has low date confidence.
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

    private var micBar: some View {
        HStack {
            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(isRecording ? .red : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            Spacer()
            if permissionDenied {
                Text("Microphone or speech access denied. Enable in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
    private func commitLine(_ line: NoteLine, text: String) async {
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
    NoteView(activateDictation: .constant(false))
        .modelContainer(for: [TaskItem.self, NoteLine.self], inMemory: true)
}
