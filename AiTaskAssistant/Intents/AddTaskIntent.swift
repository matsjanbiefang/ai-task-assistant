import AppIntents
import SwiftUI

// M4-1: App Intent — "Hey Siri, add a task to my assistant"
// When triggered, opens the app directly into Slide 1 with dictation active.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task"
    static let description = IntentDescription(
        "Add a new task to your AI Task Assistant using voice or text.",
        categoryName: "Tasks"
    )

    // M4-2: Siri phrase — users can say "Add a task to my assistant"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // M4-3: brief voice confirmation — Siri speaks this back to the user
        return .result(dialog: IntentDialog("Ready. What's your task?"))
    }
}

// Provides Siri with suggested phrases shown in Settings > Siri
struct AddTaskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "New task in \(.applicationName)",
                "Remind me in \(.applicationName)"
            ],
            shortTitle: "Add task",
            systemImageName: "plus.circle"
        )
    }
}
