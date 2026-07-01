import SwiftUI
import AppIntents

struct ContentView: View {
    @Binding var deepLinkDestination: AppDestination?
    @State private var selectedTab = 0
    @State private var activateDictation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NoteView(onSubmit: { selectedTab = 1 }, activateDictation: $activateDictation)
                .tag(0)
            AssistantView()
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: deepLinkDestination) { _, destination in
            if destination == .assistant {
                selectedTab = 1
                deepLinkDestination = nil
            }
        }
        .onContinueUserActivity(NSStringFromClass(AddTaskIntent.self)) { _ in
            // M4-1: Siri opened the app via AddTaskIntent — go to Slide 1 and start dictation
            selectedTab = 0
            activateDictation = true
        }
        .task {
            // M3-1: request notification permission on first launch
            _ = await NotificationService.shared.requestPermission()
        }
    }
}

#Preview {
    ContentView(deepLinkDestination: .constant(nil))
        .modelContainer(for: TaskItem.self, inMemory: true)
}
