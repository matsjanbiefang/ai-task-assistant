import Foundation
import SwiftData

enum TaskPriorityLevel: String, Codable, CaseIterable {
    case low, medium, high
}

enum TaskCategoryType: String, Codable, CaseIterable {
    case work, personal, health, shopping, finance, other
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var dueDate: Date?
    var dueTime: Date?
    var priority: String?
    var category: String?
    var isCompleted: Bool
    var dateConfidence: Double
    var createdAt: Date
    // U1-5: which NoteLine this task was parsed from, so re-parsing an edited line can replace
    // its old tasks instead of duplicating them. nil for tasks with no line to trace back to
    // (shouldn't normally happen post-redesign, but keeps old/imported data from crashing lookups).
    var sourceLineID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: String? = nil,
        category: String? = nil,
        dateConfidence: Double = 1.0,
        sourceLineID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.priority = priority
        self.category = category
        self.isCompleted = false
        self.dateConfidence = dateConfidence
        self.createdAt = .now
        self.sourceLineID = sourceLineID
    }
}
