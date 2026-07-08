import WidgetKit
import SwiftUI

@main
struct AiTaskAssistantWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        QuickAddWidget()
        TaskProgressWidget()
        LockScreenWidget()
        CalendarWidget()
        TasksWidget()
        ShoppingListWidget()
    }
}

// Kept out of Theme.swift (not part of this target) so the widget extension doesn't need the
// DesignSystem/Fonts sources too — just the one accent color that matters at a glance.
enum WidgetTheme {
    static let lime = Color(red: 0.86, green: 0.92, blue: 0.45)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.06)
    static let mutedGrey = Color(red: 0.54, green: 0.54, blue: 0.49)
}

struct LockedWidgetContent: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .foregroundStyle(WidgetTheme.mutedGrey)
            Text("TaskMind Pro")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetTheme.ink)
        }
        .widgetURL(URL(string: "aitask://assistant"))
    }
}

struct TodayTasksWidget: Widget {
    let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Tasks")
        .description("Your open tasks due today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayTasksWidgetView: View {
    let entry: TaskWidgetEntry

    var body: some View {
        if !entry.isPremium {
            LockedWidgetContent()
        } else if entry.todayTasks.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(WidgetTheme.mutedGrey)
                Text("Nothing due today")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.mutedGrey)
            }
            .widgetURL(URL(string: "aitask://assistant"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.mutedGrey)
                ForEach(entry.todayTasks.prefix(4)) { task in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(WidgetTheme.lime)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .widgetURL(URL(string: "aitask://assistant"))
        }
    }
}

struct QuickAddWidget: Widget {
    let kind = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("Quick Add")
        .description("Jump straight into adding a task by voice or text.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickAddWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.title)
                .foregroundStyle(WidgetTheme.ink)
            Text("Add a task")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "aitask://compose"))
    }
}

struct TaskProgressWidget: Widget {
    let kind = "TaskProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            TaskProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Task Progress")
        .description("How many tasks you've finished today.")
        .supportedFamilies([.systemSmall])
    }
}

struct TaskProgressWidgetView: View {
    let entry: TaskWidgetEntry

    private var total: Int { entry.openCount + entry.completedTodayCount }

    var body: some View {
        if !entry.isPremium {
            LockedWidgetContent()
        } else {
            VStack(spacing: 6) {
                Text("\(entry.completedTodayCount)/\(max(total, entry.completedTodayCount))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WidgetTheme.ink)
                Text("done today")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.mutedGrey)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "aitask://assistant"))
        }
    }
}

struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("Open task count or your next task, on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskWidgetEntry

    var body: some View {
        if !entry.isPremium {
            Image(systemName: "lock.fill")
                .widgetURL(URL(string: "aitask://assistant"))
        } else {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(entry.openCount), in: 0...max(Double(entry.openCount), 1)) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text("\(entry.openCount)")
                }
                .gaugeStyle(.accessoryCircular)
                .widgetURL(URL(string: "aitask://assistant"))
            default:
                Text(entry.todayTasks.first?.title ?? "No tasks today")
                    .lineLimit(2)
                    .widgetURL(URL(string: "aitask://assistant"))
            }
        }
    }
}

// Real-device feedback: "add some more widgets, like calendar, tasks, shopping list."

struct CalendarWidget: Widget {
    let kind = "CalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("Your next dated tasks for the coming week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CalendarWidgetView: View {
    let entry: TaskWidgetEntry

    var body: some View {
        if !entry.isPremium {
            LockedWidgetContent()
        } else if entry.upcomingTasks.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(WidgetTheme.mutedGrey)
                Text("Nothing coming up")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.mutedGrey)
            }
            .widgetURL(URL(string: "aitask://assistant"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Upcoming")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.mutedGrey)
                ForEach(entry.upcomingTasks.prefix(4)) { task in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(WidgetTheme.lime)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .widgetURL(URL(string: "aitask://assistant"))
        }
    }
}

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("Your open tasks that don't have a date yet.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TasksWidgetView: View {
    let entry: TaskWidgetEntry

    var body: some View {
        if !entry.isPremium {
            LockedWidgetContent()
        } else if entry.undatedTasks.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(WidgetTheme.mutedGrey)
                Text("No open tasks")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.mutedGrey)
            }
            .widgetURL(URL(string: "aitask://assistant"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tasks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.mutedGrey)
                ForEach(entry.undatedTasks.prefix(4)) { task in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(WidgetTheme.lime)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .widgetURL(URL(string: "aitask://assistant"))
        }
    }
}

struct ShoppingListWidget: Widget {
    let kind = "ShoppingListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            ShoppingListWidgetView(entry: entry)
        }
        .configurationDisplayName("Shopping List")
        .description("Your open shopping list items.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShoppingListWidgetView: View {
    let entry: TaskWidgetEntry

    var body: some View {
        if !entry.isPremium {
            LockedWidgetContent()
        } else if entry.shoppingItems.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "cart")
                    .foregroundStyle(WidgetTheme.mutedGrey)
                Text("Shopping list is empty")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.mutedGrey)
            }
            .widgetURL(URL(string: "aitask://assistant"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shopping List")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.mutedGrey)
                ForEach(Array(entry.shoppingItems.prefix(4)), id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "cart.fill")
                            .font(.caption2)
                            .foregroundStyle(WidgetTheme.lime)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .widgetURL(URL(string: "aitask://assistant"))
        }
    }
}
