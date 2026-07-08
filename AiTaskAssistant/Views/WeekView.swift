import SwiftUI
import SwiftData
import WidgetKit

// swipe-design-concept.md §6 "Week" (formerly AssistantView — renamed to match what this screen
// now actually is). Default view: a 7-day strip for the current week (today filled lime), a
// category legend, tasks grouped by day as rounded cards. Arriving via one of Notebook's stat-bar
// taps (`initialFilter`) swaps the header label and shows a "Show all" chip back to the full
// view, per §6's "Arriving via a stat filter".
//
// Real-device feedback (2026-07-04): undated tasks used to show here in a dashed "No date"
// section — moved out entirely. Week is now the calendar (dated tasks only); undated tasks live
// in the new Tasklist module (TasklistView) instead, and "move" into Week automatically the
// moment a date is added to them (TaskItem.dueDate driving both screens' filters is the only
// mechanism needed — no explicit "move" action).
enum WeekFilter: Equatable {
    case open, today, week

    var headerLabel: String {
        switch self {
        case .open: return "Open tasks"
        case .today: return "Today"
        case .week: return "This week"
        }
    }
}

struct WeekView: View {
    var initialFilter: WeekFilter? = nil

    @Query(sort: \TaskItem.dueDate, order: .forward) private var tasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: TaskItem?
    @State private var activeFilter: WeekFilter?

    private var weekDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if activeFilter == nil {
                        weekStrip
                        legend
                        weekGroupedContent
                    } else {
                        filteredList(activeFilter!)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.Color.paper)
            .navigationTitle(activeFilter?.headerLabel ?? "Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if activeFilter != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            activeFilter = nil
                        } label: {
                            Label("Show all", systemImage: "xmark.circle.fill")
                        }
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditView(task: task)
                    .presentationDragIndicator(.visible)
            }
            .onAppear { activeFilter = initialFilter }
            .onChange(of: initialFilter) { _, new in activeFilter = new }
            .onChange(of: tasks) { _, _ in
                Task { await refreshBadge() }
            }
        }
    }

    // MARK: - Default (unfiltered) week view

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDates, id: \.self) { date in
                let isToday = Calendar.current.isDateInToday(date)
                VStack(spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                    Text(date.formatted(.dateTime.day()))
                        .font(Theme.Typography.dayNumber)
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isToday ? Theme.Color.lime : SwiftUI.Color.clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // §4: "A small legend under the week strip spells out what each icon means, so the system is
    // self-documenting the first time someone sees it."
    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Theme.legendCategories, id: \.self) { category in
                    if let icon = Theme.categoryIcon(category) {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                            Text(Theme.categoryLabel(category))
                        }
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                    }
                }
            }
        }
    }

    private func tasks(on date: Date) -> [TaskItem] {
        tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return Calendar.current.isDate(due, inSameDayAs: date)
        }
    }

    @ViewBuilder
    private var weekGroupedContent: some View {
        let hasAnyDated = weekDates.contains { !tasks(on: $0).isEmpty }
        if !hasAnyDated {
            EmptyStateView(icon: "checkmark.circle", message: "Nothing here")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(weekDates, id: \.self) { date in
                    let dayTasks = tasks(on: date)
                    if !dayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(Theme.Typography.fieldLabel)
                                .foregroundStyle(Theme.Color.mutedGrey)
                            ForEach(dayTasks) { task in card(for: task) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filtered (stat-bar) view

    private func filteredTasks(_ filter: WeekFilter) -> [TaskItem] {
        switch filter {
        case .open:
            return tasks.filter { !$0.isCompleted }
        case .today:
            return tasks.filter { isToday($0.dueDate) && !$0.isCompleted }
        case .week:
            return tasks.filter { task in
                guard let due = task.dueDate else { return false }
                return weekDates.contains { Calendar.current.isDate($0, inSameDayAs: due) }
            }
        }
    }

    @ViewBuilder
    private func filteredList(_ filter: WeekFilter) -> some View {
        let items = filteredTasks(filter)
        if items.isEmpty {
            EmptyStateView(icon: "checkmark.circle", message: "Nothing here")
        } else {
            VStack(spacing: 8) {
                ForEach(items) { task in card(for: task) }
            }
        }
    }

    private func card(for task: TaskItem) -> TaskCardView {
        TaskCardView(task: task, onToggleCompletion: { toggleCompletion(task) }, onTap: { editingTask = task })
    }

    // MARK: - Actions

    private func toggleCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        try? modelContext.save()
        if task.isCompleted {
            Task { await NotificationService.shared.cancel(taskID: task.id.uuidString) }
            modelContext.deleteLineIfAllTasksComplete(for: task)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshBadge() async {
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.dueDate != nil &&
                task.dueDate! >= today &&
                task.dueDate! < tomorrow &&
                !task.isCompleted
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        await NotificationService.shared.updateBadge(todayCount: count)
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

#Preview {
    WeekView()
        .modelContainer(for: [TaskItem.self, NoteLine.self, EntityMemory.self], inMemory: true)
}
