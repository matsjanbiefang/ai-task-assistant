import AppIntents
import SwiftUI

// M4-1: App Intent — "Hey Siri, add a note to TaskMind"
// When triggered, opens the app directly into Slide 1 with dictation active.
//
// Real-device feedback: Siri frequently resolved "task"-worded phrases to the system Reminders
// app instead of this one — "task"/"reminder" are exactly the vocabulary Reminders' own Siri
// domain claims. Rephrasing around "note" (also a more accurate description of what actually gets
// captured — a note that's then parsed into tasks) sidesteps that collision.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a note"
    static let description = IntentDescription(
        "Add a new note to TaskMind using voice or text.",
        categoryName: "Notes"
    )

    // M4-2: Siri phrase — users can say "Add a note to TaskMind"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // M4-3: brief voice confirmation — Siri speaks this back to the user
        return .result(dialog: IntentDialog("Ready. What's on your mind?"))
    }
}

// Provides Siri with suggested phrases shown in Settings > Siri
struct AddTaskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a note to \(.applicationName)",
                "New note in \(.applicationName)",
                "Quick note for \(.applicationName)"
            ],
            shortTitle: "Add note",
            systemImageName: "plus.circle"
        )
    }
}
