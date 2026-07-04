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

    init(id: UUID = UUID(), text: String, order: Int) {
        self.id = id
        self.text = text
        self.order = order
        self.isCompleted = false
        self.createdAt = .now
    }
}

extension ShoppingItem {
    // Shared by ShoppingListView's own compose row and NoteView's "add milk to shopping list"
    // cue-phrase routing (RuleBasedExtractionService.shoppingListItems) — one place that decides
    // the next `order` value, so both entry points append rather than collide.
    static func add(_ texts: [String], context: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.order, order: .reverse)])
        var nextOrder = ((try? context.fetch(descriptor))?.first?.order ?? -1) + 1
        for text in texts {
            context.insert(ShoppingItem(text: text, order: nextOrder))
            nextOrder += 1
        }
        try? context.save()
    }
}
