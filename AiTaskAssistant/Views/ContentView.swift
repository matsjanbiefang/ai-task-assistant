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
                .onChange(of: deepLinkDestination) { _, destination in
                    if destination == .assistant {
                        showTasks = true
                        deepLinkDestination = nil
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
        .modelContainer(for: [TaskItem.self, NoteLine.self], inMemory: true)
}
