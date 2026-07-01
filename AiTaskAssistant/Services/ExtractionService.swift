import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Schema (plain Codable — no Foundation Models needed)

enum TaskPriority: String, Codable, CaseIterable {
    case low, medium, high
}

enum TaskCategory: String, Codable, CaseIterable {
    case work, personal, health, shopping, finance, other
}

struct ExtractedTask {
    var title: String
    var dueDate: String?
    var dueTime: String?
    var priority: TaskPriority?
    var category: TaskCategory?
    var dateConfidence: Double
}

// MARK: - Loading state (observed by ModelLoadingView)

@Observable
@MainActor
final class LLMState {
    static let shared = LLMState()
    var progress: Double = 0
    var isReady = false
    var errorMessage: String?
}

// MARK: - Service

actor ExtractionService {
    static let shared = ExtractionService()

    private var container: ModelContainer?
    private let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    func load() async {
        guard container == nil else {
            await MainActor.run { LLMState.shared.isReady = true }
            return
        }
        do {
            let c = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: modelID)
            ) { progress in
                Task { @MainActor in
                    LLMState.shared.progress = progress.fractionCompleted
                }
            }
            container = c
            await MainActor.run { LLMState.shared.isReady = true }
        } catch {
            await MainActor.run { LLMState.shared.errorMessage = error.localizedDescription }
        }
    }

    func extract(from input: String, referenceDate: Date = .now) async throws -> [ExtractedTask] {
        if container == nil { await load() }
        guard let container else { throw ExtractionError.modelNotLoaded }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: referenceDate)

        let system = """
        Extract tasks from user input. Output ONLY valid JSON — no markdown, no explanation.
        Today: \(today).
        Schema: {"tasks":[{"title":"string","dueDate":"YYYY-MM-DD or null","dueTime":"HH:MM or null","priority":"low|medium|high or null","category":"work|personal|health|shopping|finance|other or null","dateConfidence":0.95}]}
        Rules: resolve relative dates; set priority/category only if explicitly stated; dateConfidence 1.0 when no date mentioned, ≥0.9 when clear, <0.7 when ambiguous.
        """
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": input]
        ]

        let output = try await container.perform { context in
            let lmInput = try await context.processor.prepare(
                input: UserInput(messages: messages)
            )
            let result = try MLXLMCommon.generate(
                input: lmInput,
                parameters: GenerateParameters(temperature: 0.1),
                context: context
            )
            return result.output
        }

        return try parseJSON(output)
    }

    // MARK: - JSON parsing

    private struct Root: Codable { let tasks: [JTask] }
    private struct JTask: Codable {
        let title: String
        let dueDate: String?
        let dueTime: String?
        let priority: String?
        let category: String?
        let dateConfidence: Double?
    }

    private func parseJSON(_ raw: String) throws -> [ExtractedTask] {
        var text = raw
        if let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}") {
            text = String(raw[s...e])
        }
        guard let data = text.data(using: .utf8) else { throw ExtractionError.parseError }
        let root = try JSONDecoder().decode(Root.self, from: data)
        return root.tasks.map { t in
            ExtractedTask(
                title: t.title,
                dueDate: t.dueDate,
                dueTime: t.dueTime,
                priority: t.priority.flatMap { TaskPriority(rawValue: $0) },
                category: t.category.flatMap { TaskCategory(rawValue: $0) },
                dateConfidence: t.dateConfidence ?? 1.0
            )
        }
    }
}

enum ExtractionError: Error {
    case modelNotLoaded
    case parseError
}
