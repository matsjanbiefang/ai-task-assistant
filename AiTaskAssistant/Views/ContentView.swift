import SwiftUI
import AppIntents

struct ContentView: View {
    @Binding var deepLinkDestination: AppDestination?
    @State private var selectedTab = 0
    @State private var activateDictation = false
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = ""

    var body: some View {
        if primaryLanguageCode.isEmpty {
            OnboardingLanguageView { language in
                primaryLanguageCode = language.rawValue
            }
        } else {
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
            .task {
                _ = await NotificationService.shared.requestPermission()
            }
        }
    }
}

#Preview {
    ContentView(deepLinkDestination: .constant(nil))
        .modelContainer(for: TaskItem.self, inMemory: true)
}
