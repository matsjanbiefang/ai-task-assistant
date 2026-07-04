import SwiftUI
import SwiftData

// swipe-design-concept.md §6 "Week" (formerly AssistantView — renamed to match what this screen
// now actually is). Default view: a 7-day strip for the current week (today filled lime), a
// category legend, tasks grouped by day as rounded cards, then "No date" (dashed border) for
// undated tasks. Arriving via one of Notebook's stat-bar taps (`initialFilter`) swaps the header
// label and shows a "Show all" chip back to the full view, per §6's "Arriving via a stat filter".
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

    private var undatedTasks: [TaskItem] { tasks.filter { $0.dueDate == nil } }

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
        if !hasAnyDated && undatedTasks.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(weekDates, id: \.self) { date in
                    let dayTasks = tasks(on: date)
                    if !dayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(Theme.Typography.fieldLabel)
                                .foregroundStyle(Theme.Color.mutedGrey)
                            ForEach(dayTasks) { task in taskCard(task) }
                        }
                    }
                }
                if !undatedTasks.isEmpty {
                    undatedSection
                }
            }
        }
    }

    // §6: "styled with a dashed border so it reads as 'unanchored' rather than just another day."
    private var undatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No date")
                .font(Theme.Typography.fieldLabel)
                .foregroundStyle(Theme.Color.mutedGrey)
            VStack(spacing: 8) {
                ForEach(undatedTasks) { task in taskCard(task) }
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Theme.Color.mutedGrey.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
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
            emptyState
        } else {
            VStack(spacing: 8) {
                ForEach(items) { task in taskCard(task) }
            }
        }
    }

    // MARK: - Task card

    private func taskCard(_ task: TaskItem) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(task.isCompleted ? Theme.Color.hairline : Theme.Color.lime)
                .frame(width: Theme.Metrics.accentBarWidth)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title)
                        .font(Theme.Typography.taskCardTitle)
                        .foregroundStyle(task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                        .strikethrough(task.isCompleted)
                    Spacer()
                    Button {
                        toggleCompletion(task)
                    } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(task.isCompleted ? Theme.Color.limeDeep : Theme.Color.mutedGrey)
                    }
                    .buttonStyle(.plain)
                }
                metaLine(task)
                if let details = task.details {
                    Text(details)
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Color.mutedGrey)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .background(SwiftUI.Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Color.hairline)
        )
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
    }

    @ViewBuilder
    private func metaLine(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            if let category = task.category, let icon = Theme.categoryIcon(category) {
                Image(systemName: icon)
            }
            if let date = task.dueDate, let endDate = task.dueEndDate {
                // Real-device feedback (2026-07-03): a range renders as "Jul 9 – Jul 11".
                Text("\(date.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
            }
            if let time = task.dueTime {
                Text(time.formatted(.dateTime.hour().minute()))
            } else if let timeOfDay = task.timeOfDay {
                Label(timeOfDay, systemImage: "clock")
            }
            if let place = task.place {
                Label(place, systemImage: "mappin.and.ellipse")
            }
            if task.linkedGroupID != nil {
                Label("Step \((task.sequenceIndex ?? 0) + 1) of 2", systemImage: "link")
            }
            if let priority = task.priority {
                priorityBadge(priority)
            }
            if RuleBasedExtractionService.isLowConfidence(task.dateConfidence) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.Color.mutedGrey)
    }

    private func priorityBadge(_ priority: String) -> some View {
        Text(priority)
            .font(Theme.Typography.meta.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Color.hairline, in: Capsule())
            .foregroundStyle(Theme.Color.ink)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.mutedGrey.opacity(0.6))
            Text("Nothing here")
                .font(Theme.Typography.body(14))
                .foregroundStyle(Theme.Color.mutedGrey)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func toggleCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        try? modelContext.save()
        if task.isCompleted {
            Task { await NotificationService.shared.cancel(taskID: task.id.uuidString) }
            modelContext.deleteLineIfAllTasksComplete(for: task)
        }
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
