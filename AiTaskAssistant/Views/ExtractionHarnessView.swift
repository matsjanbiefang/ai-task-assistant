import SwiftUI

// Debug-only screen for Milestone 0: validate extraction accuracy before building UI.
// Remove or gate behind #if DEBUG before App Store submission.
#if DEBUG
struct ExtractionHarnessView: View {
    @State private var results: [(sentence: String, output: String)] = []
    @State private var isRunning = false
    @State private var progress = 0

    private let service = ExtractionService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isRunning {
                    ProgressView("Running \(progress)/\(testSentences.count)...")
                        .padding()
                }
                List(results, id: \.sentence) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.sentence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.output)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Extraction PoC")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Run All") { Task { await runAll() } }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { results = [] }
                }
            }
        }
    }

    private func runAll() async {
        isRunning = true
        results = []
        progress = 0
        for sentence in testSentences {
            let output: String
            do {
                let extracted = try await service.extract(from: sentence)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(extracted.map { CodableExtractedTask($0) })
                output = String(data: data, encoding: .utf8) ?? "encode error"
            } catch {
                output = "ERROR: \(error)"
            }
            let sentence = sentence
            await MainActor.run {
                results.append((sentence: sentence, output: output))
                progress += 1
            }
        }
        await MainActor.run { isRunning = false }
    }
}

// Thin Codable wrapper so we can JSON-encode ExtractedTask for display
private struct CodableExtractedTask: Encodable {
    let title: String
    let dueDate: String?
    let dueTime: String?
    let priority: String?
    let category: String?
    let dateConfidence: Double

    init(_ t: ExtractedTask) {
        title = t.title
        dueDate = t.dueDate
        dueTime = t.dueTime
        priority = t.priority?.rawValue
        category = t.category?.rawValue
        dateConfidence = t.dateConfidence
    }
}

// MARK: - 20 Test Sentences (M0-4)

private let testSentences: [String] = [
    // 1. Single task, relative date
    "Remind me to call the dentist tomorrow",

    // 2. Single task, explicit date
    "Submit the quarterly report on July 15th",

    // 3. Single task, no date
    "Buy more coffee beans",

    // 4. Single task with time
    "Pick up kids at 3pm on Friday",

    // 5. Two tasks in one sentence
    "Buy milk and call the dentist tomorrow",

    // 6. Three tasks, mixed dates
    "I need to send the invoice today, schedule a team sync next Monday, and review the PR by end of week",

    // 7. Explicit priority signal
    "Urgent: fix the login bug before the demo",

    // 8. Explicit low priority
    "Low priority — tidy up the garage sometime this month",

    // 9. Explicit category signal (work)
    "For work: prepare slides for the Thursday kickoff",

    // 10. Explicit category signal (health)
    "Health appointment — blood test next Tuesday morning",

    // 11. Shopping category
    "Grocery run this weekend, need eggs, bread, and orange juice",

    // 12. Messy dictation, relative date
    "uh yeah so I need to uh finish writing that blog post by like next friday I think",

    // 13. Messy dictation, no date
    "oh and also don't forget to reply to Sarah's email",

    // 14. Relative date — "next week"
    "Book the hotel room for the conference next week",

    // 15. Relative date — "in two days"
    "Return the library books in two days",

    // 16. Ambiguous date (should trigger low confidence)
    "Do the thing before the meeting",

    // 17. Implicit time of day (morning)
    "Morning run tomorrow",

    // 18. Multiple tasks + priority in one
    "ASAP: deploy the hotfix, then write the post-mortem",

    // 19. Finance category
    "Pay the electricity bill before the end of the month",

    // 20. Run-on conversational phrasing with mixed tasks
    "so basically I gotta finish the report today and also set up the new laptop and oh yeah send mom a birthday message she's turning 60 on the 12th"
]

#Preview {
    ExtractionHarnessView()
}
#endif
