import Foundation
import SwiftData

// U1-5: the notes surface (prd-update-01.md §3) persists as an ordered list of lines rather than
// one big text blob, so each line can carry its own parse status (task count, low-confidence
// "unsure" state) for the inline Amy-style icon, and so TaskItem can reference back to the line it
// came from — editing a line re-parses it and replaces its old tasks instead of duplicating them.
@Model
final class NoteLine {
    var id: UUID
    var text: String
    var order: Int
    var taskCount: Int
    var hasLowConfidence: Bool
    var createdAt: Date

    init(id: UUID = UUID(), text: String = "", order: Int) {
        self.id = id
        self.text = text
        self.order = order
        self.taskCount = 0
        self.hasLowConfidence = false
        self.createdAt = .now
    }
}
