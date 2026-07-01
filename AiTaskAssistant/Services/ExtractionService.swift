import Foundation
import FoundationModels

// MARK: - Schema

@Generable
enum TaskPriority: String, Codable, CaseIterable {
    case low, medium, high
}

@Generable
enum TaskCategory: String, Codable, CaseIterable {
    case work, personal, health, shopping, finance, other
}

@Generable
struct ExtractedTask {
    @Guide(description: "Short, action-oriented task title derived from the input. Omit filler words.")
    var title: String

    @Guide(description: "Due date in ISO 8601 format (YYYY-MM-DD). Resolve relative expressions like 'tomorrow' or 'next Friday' against today's date. Null if no date mentioned.")
    var dueDate: String?

    @Guide(description: "Due time in HH:MM (24h) format if an explicit time was mentioned. Null otherwise.")
    var dueTime: String?

    @Guide(description: "Priority level. Set ONLY when the input contains an explicit signal such as 'urgent', 'ASAP', 'high priority', 'low priority'. Null otherwise — do not infer priority silently.")
    var priority: TaskPriority?

    @Guide(description: "Category from the fixed set. Set ONLY when the input contains an explicit project name or category signal (e.g. 'for work', 'health appointment', 'grocery'). Null otherwise.")
    var category: TaskCategory?

    @Guide(description: "Confidence level for the due date extraction (0.0 = not confident, 1.0 = fully confident). Low confidence should be shown to the user as an indicator.")
    var dateConfidence: Double
}

@Generable
struct ExtractionResult {
    @Guide(description: "List of extracted tasks. One input may produce multiple tasks if the user described several distinct actions.")
    var tasks: [ExtractedTask]
}

// MARK: - Service

actor ExtractionService {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession()
    }

    func extract(from input: String, referenceDate: Date = .now) async throws -> [ExtractedTask] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayString = formatter.string(from: referenceDate)

        let prompt = """
        Today's date is \(todayString).
        Extract all tasks from the following user input. The user may describe one or multiple tasks in a single message.

        Rules:
        - Resolve relative dates ("tomorrow", "next Friday", "in two weeks") against today's date.
        - Set priority only when there is an explicit signal in the text. Do not guess.
        - Set category only when the user explicitly mentions a project or domain. Do not guess.
        - If a date is mentioned but ambiguous, set dateConfidence below 0.7.
        - If no date is mentioned, leave dueDate null and set dateConfidence to 1.0.

        User input: \(input)
        """

        let result = try await session.respond(
            to: prompt,
            generating: ExtractionResult.self
        )
        return result.content.tasks
    }
}
