import Foundation
import SwiftData

// Phase 3 (Widgets): the widget extension runs in a separate process and needs to read the same
// SwiftData store as the main app, so both targets build their `ModelContainer` from this single
// definition pointed at the shared App Group container instead of the default per-app sandbox
// location.
enum SharedModelContainer {
    private static let appGroupID = "group.com.matsb.AiTaskAssistant"

    static func make() -> ModelContainer {
        let schema = Schema([TaskItem.self, NoteLine.self, EntityMemory.self, ShoppingItem.self, CustomCategory.self])
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("AiTaskAssistant.sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL ?? URL.documentsDirectory.appendingPathComponent("AiTaskAssistant.sqlite"))
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
