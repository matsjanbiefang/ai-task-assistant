import SwiftUI
import SwiftData
import UserNotifications

@main
struct AiTaskAssistantApp: App {
    @State private var deepLinkDestination: AppDestination?
    private let sharedContainer = SharedModelContainer.make()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        SubscriptionService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkDestination: $deepLinkDestination)
                .modelContainer(sharedContainer)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Notification taps and the widgets' deep links arrive via openURL with a custom scheme,
        // e.g. aitask://assistant or aitask://compose (Phase 3's quick-add widget).
        if url.host == "assistant" {
            deepLinkDestination = .assistant
        } else if url.host == "compose" {
            deepLinkDestination = .compose
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
    case compose
}
