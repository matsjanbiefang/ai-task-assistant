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

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: String? = nil,
        category: String? = nil,
        dateConfidence: Double = 1.0
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
    }
}
