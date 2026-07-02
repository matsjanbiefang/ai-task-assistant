import SwiftUI
import SwiftData
import UserNotifications

@main
struct AiTaskAssistantApp: App {
    @State private var deepLinkDestination: AppDestination?

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkDestination: $deepLinkDestination)
                .modelContainer(for: [TaskItem.self, NoteLine.self])
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Notification taps arrive via openURL with a custom scheme
        // e.g. aitask://assistant
        if url.host == "assistant" {
            deepLinkDestination = .assistant
        }
    }
}

// M3-3: notification delegate — converts tap into a deep-link URL the app can handle
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["destination"] as? String == "assistant" {
            // Open the app and navigate to Slide 2
            if let url = URL(string: "aitask://assistant") {
                Task { @MainActor in UIApplication.shared.open(url) }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

enum AppDestination {
    case assistant
}
