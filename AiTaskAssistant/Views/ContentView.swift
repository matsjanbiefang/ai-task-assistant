import SwiftUI
import AppIntents

// User feedback (2026-07-02): swiping left to reach the calendar/tasks view didn't feel right —
// replaced with NoteView owning a swipe-up sheet (calendar icon in its bottom bar). ContentView no
// longer hosts a TabView; the notes surface is the sole top-level screen, which also fixes the
// bottom bar not docking to the keyboard (that was `.ignoresSafeArea()` on the old TabView
// suppressing normal keyboard-avoidance for its child views).
struct ContentView: View {
    @Binding var deepLinkDestination: AppDestination?
    @State private var activateDictation = false
    @State private var showTasks = false
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = ""

    var body: some View {
        if primaryLanguageCode.isEmpty {
            OnboardingLanguageView { language in
                primaryLanguageCode = language.rawValue
            }
        } else {
            NoteView(activateDictation: $activateDictation, showTasks: $showTasks)
                // swipe-design-concept.md §3: the whole "Lime" palette (paper/ink/lime) is defined
                // once, with no dark-mode variant — it's a deliberate paper-notebook identity, not
                // a color scheme that should invert with the system setting.
                .preferredColorScheme(.light)
                .onChange(of: deepLinkDestination) { _, destination in
                    switch destination {
                    case .assistant:
                        showTasks = true
                        deepLinkDestination = nil
                    case .compose:
                        activateDictation = true
                        deepLinkDestination = nil
                    case nil:
                        break
                    }
                }
                .task {
                    _ = await NotificationService.shared.requestPermission()
                }
        }
    }
}

#Preview {
    ContentView(deepLinkDestination: .constant(nil))
        .modelContainer(for: [TaskItem.self, NoteLine.self, EntityMemory.self, ShoppingItem.self], inMemory: true)
}
