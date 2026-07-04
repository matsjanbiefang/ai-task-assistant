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

extension ModelContext {
    // Explicit request: once every task from a note line is done, the line itself disappears from
    // the Notebook rather than sitting there struck through. A "linked" multi-step line's other
    // step(s) must ALSO be complete first — checked via `allSatisfy` over every task sharing the
    // same `sourceLineID`, not just the one just completed. Shared by TaskEditView's "Mark
    // complete" button and WeekView's card checkbox — both need the exact same cleanup.
    func deleteLineIfAllTasksComplete(for task: TaskItem) {
        guard let lineID = task.sourceLineID else { return }
        let taskDescriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.sourceLineID == lineID })
        guard let siblingTasks = try? fetch(taskDescriptor), siblingTasks.allSatisfy(\.isCompleted) else { return }
        let lineDescriptor = FetchDescriptor<NoteLine>(predicate: #Predicate<NoteLine> { $0.id == lineID })
        guard let line = try? fetch(lineDescriptor).first else { return }
        delete(line)
        try? save()
    }
}
