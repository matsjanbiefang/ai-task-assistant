import Foundation
import SwiftData
import WidgetKit

// Phase 3 (Widgets): shared read model + timeline provider for all four widgets. Runs in the
// widget extension's own process, reading the same SwiftData store as the main app via
// `SharedModelContainer` (App Group-backed). Premium gating reads the flag `SubscriptionService`
// mirrors into the same App Group's UserDefaults on every entitlement check — the widget process
// can't call the RevenueCat SDK itself.
struct TaskSummary: Identifiable {
    let id: UUID
    let title: String
    let dueTime: Date?
}

struct TaskWidgetEntry: TimelineEntry {
    let date: Date
    let todayTasks: [TaskSummary]
    let openCount: Int
    let completedTodayCount: Int
    let isPremium: Bool

    static let placeholder = TaskWidgetEntry(
        date: .now,
        todayTasks: [
            TaskSummary(id: UUID(), title: "Call the dentist", dueTime: nil),
            TaskSummary(id: UUID(), title: "Finish the deck", dueTime: nil)
        ],
        openCount: 5,
        completedTodayCount: 2,
        isPremium: true
    )
}

struct TaskWidgetProvider: TimelineProvider {
    private static let appGroupID = "group.com.matsb.AiTaskAssistant"

    func placeholder(in context: Context) -> TaskWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // The app also explicitly reloads timelines on every task create/complete/delete; this
        // refresh is just a fallback for whatever time the widget happens to be on screen.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> TaskWidgetEntry {
        let isPremium = UserDefaults(suiteName: Self.appGroupID)?.bool(forKey: "isPremium") ?? false

        let context = ModelContext(SharedModelContainer.make())
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let openTasks = allTasks.filter { !$0.isCompleted }

        let calendar = Calendar.current
        let today = openTasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return calendar.isDateInToday(due)
            }
            .sorted { ($0.dueTime ?? $0.dueDate ?? .distantFuture) < ($1.dueTime ?? $1.dueDate ?? .distantFuture) }
            .prefix(5)
            .map { TaskSummary(id: $0.id, title: $0.title, dueTime: $0.dueTime) }

        let completedToday = allTasks.filter { task in
            task.isCompleted && (task.dueDate.map(calendar.isDateInToday) ?? false)
        }.count

        return TaskWidgetEntry(
            date: .now,
            todayTasks: Array(today),
            openCount: openTasks.count,
            completedTodayCount: completedToday,
            isPremium: isPremium
        )
    }
}
