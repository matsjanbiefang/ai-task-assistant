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
    // Set when this task was split from a line via a sequential connector ("and then"/"und
    // dann") — shared by the other step(s) from the same line. sequenceIndex is this task's
    // 0-based position among them (always a pair currently, since splitting only ever produces
    // two sub-lines).
    var linkedGroupID: UUID?
    var sequenceIndex: Int?
    // Feedback round 3: where the task happens (extraction destination/keyword or user-edited),
    // and supplementary details pulled out of the note line ("take my recipes with me").
    var place: String?
    var details: String?
    // A vague period ("Morning"/"Evening") mentioned without an exact hour — kept separate from
    // dueTime rather than guessing a specific clock time for it (feedback round 3).
    var timeOfDay: String?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        priority: String? = nil,
        category: String? = nil,
        dateConfidence: Double = 1.0,
        sourceLineID: UUID? = nil,
        linkedGroupID: UUID? = nil,
        sequenceIndex: Int? = nil,
        place: String? = nil,
        details: String? = nil,
        timeOfDay: String? = nil
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
        self.linkedGroupID = linkedGroupID
        self.sequenceIndex = sequenceIndex
        self.place = place
        self.details = details
        self.timeOfDay = timeOfDay
    }
}
