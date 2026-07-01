import UserNotifications
import SwiftData

actor NotificationService {
    static let shared = NotificationService()

    // M3-1: request permission on first launch
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // M3-2: schedule a local notification for a task
    func schedule(taskID: String, title: String, at date: Date) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        // M3-3: deep-link payload — app uses this to switch to Slide 2
        content.userInfo = ["taskID": taskID, "destination": "assistant"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: taskID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(taskID: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskID])
    }

    // M3-4: update badge to count of tasks due today
    func updateBadge(todayCount: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(todayCount)
        } catch {}
    }
}
