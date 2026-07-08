import Foundation
import SwiftData

// swipe-design-concept.md §6 "Shopping list": "a second, simpler notebook — same capture-line
// pattern, same checkbox language, no dates or categories." Each line typed there IS the item —
// unlike NoteLine, there's no extraction step, just an ordered checklist.
@Model
final class ShoppingItem {
    var id: UUID
    var text: String
    var order: Int
    var isCompleted: Bool
    var createdAt: Date
    // Real-device feedback: "when I put something on the shopping list, still leave it in
    // Notes" — the originating NoteLine is kept (rather than deleted/never created) instead of
    // the line being fully diverted away, and this links a shopping item back to it so NoteView
    // can show a status icon and so re-editing that line doesn't duplicate items.
    var sourceLineID: UUID?

    init(id: UUID = UUID(), text: String, order: Int, sourceLineID: UUID? = nil) {
        self.id = id
        self.text = text
        self.order = order
        self.isCompleted = false
        self.createdAt = .now
        self.sourceLineID = sourceLineID
    }
}

extension ShoppingItem {
    // Shared by ShoppingListView's own compose row and NoteView's "add milk to shopping list"
    // cue-phrase routing (RuleBasedExtractionService.shoppingListItems) — one place that decides
    // the next `order` value, so both entry points append rather than collide.
    static func add(_ texts: [String], context: ModelContext, sourceLineID: UUID? = nil) {
        let descriptor = FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.order, order: .reverse)])
        var nextOrder = ((try? context.fetch(descriptor))?.first?.order ?? -1) + 1
        for text in texts {
            context.insert(ShoppingItem(text: text, order: nextOrder, sourceLineID: sourceLineID))
            nextOrder += 1
        }
        try? context.save()
    }
}
