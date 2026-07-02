import SwiftUI
import SwiftData

struct NoteView: View {
    var onSubmit: () -> Void
    @Binding var activateDictation: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var inputText = ""
    @State private var isExtracting = false
    @State private var permissionDenied = false
    @State private var speech = SpeechRecognizer()
    @FocusState private var isFocused: Bool

    private let extraction = RuleBasedExtractionService.shared

    private var isRecording: Bool { speech.state == .recording }
    private var canSubmit: Bool { !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExtracting }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                TextField("What do you need to do?", text: $inputText, axis: .vertical)
                    .font(.title3)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .lineLimit(1...8)
                    .padding(.horizontal, 24)
                    .onChange(of: speech.transcript) { _, new in
                        if isRecording { inputText = new }
                    }

                if permissionDenied {
                    Text("Microphone or speech access denied. Enable in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer()

                HStack(alignment: .center) {
                    // Mic button
                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                            .font(.title2)
                            .foregroundStyle(isRecording ? .red : .secondary)
                            .frame(width: 44, height: 44)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.leading, 24)

                    Spacer()

                    // Submit button
                    Button {
                        if isRecording { speech.stopRecording() }
                        Task { await submit() }
                    } label: {
                        if isExtracting {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 56, height: 56)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                        }
                    }
                    .background(canSubmit ? Color.accentColor : Color.secondary, in: Circle())
                    .disabled(!canSubmit)
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: activateDictation) { _, active in
            if active {
                activateDictation = false
                Task { await toggleRecording() }
            }
        }
    }

    private func toggleRecording() async {
        if isRecording {
            speech.stopRecording()
            return
        }
        let granted = await speech.requestPermissions()
        if granted {
            isFocused = false
            speech.startRecording()
        } else {
            permissionDenied = true
        }
    }

    private func submit() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isExtracting = true
        defer { isExtracting = false }

        let extracted = extraction.extract(from: text)
        for task in extracted {
            let item = TaskItem(
                title: task.title,
                dueDate: parsedDate(task.dueDate),
                priority: task.priority?.rawValue,
                category: task.category?.rawValue,
                dateConfidence: task.dateConfidence
            )
            modelContext.insert(item)
            // M3-2: schedule notification if task has a future due date
            if let date = item.dueDate, date > .now {
                await NotificationService.shared.schedule(
                    taskID: item.id.uuidString,
                    title: item.title,
                    at: date
                )
            }
        }
        try? modelContext.save()

        // M3-4: refresh badge count
        await refreshBadge()

        inputText = ""
        onSubmit()
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
    NoteView(onSubmit: {}, activateDictation: .constant(false))
        .modelContainer(for: TaskItem.self, inMemory: true)
}
