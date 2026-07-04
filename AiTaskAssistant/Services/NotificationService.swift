@preconcurrency import UserNotifications
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

    // M3-2: schedule a local notification for a task.
    // Real-device feedback (2026-07-04): a Settings toggle ("notifications enabled") and a
    // configurable lead time ("remind me X before") — both read directly from UserDefaults
    // (the same storage `@AppStorage` in SettingsView writes to) rather than threaded through
    // every call site, so callers stay exactly as simple as "here's when this is due".
    func schedule(taskID: String, title: String, at date: Date) async {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.object(forKey: "notificationsEnabled") == nil
            || defaults.bool(forKey: "notificationsEnabled")
        guard notificationsEnabled else { return }

        let leadMinutes = defaults.object(forKey: "reminderLeadTimeMinutes") != nil
            ? defaults.integer(forKey: "reminderLeadTimeMinutes") : 15
        let fireDate = date.addingTimeInterval(-TimeInterval(leadMinutes * 60))
        guard fireDate > .now else { return }

        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        // M3-3: deep-link payload — app uses this to switch to Slide 2
        content.userInfo = ["taskID": taskID, "destination": "assistant"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: taskID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(taskID: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskID])
    }

    // Real-device feedback (2026-07-04): backs Settings' "Delete all data".
    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // M3-4: update badge to count of tasks due today
    func updateBadge(todayCount: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(todayCount)
        } catch {}
    }
}
