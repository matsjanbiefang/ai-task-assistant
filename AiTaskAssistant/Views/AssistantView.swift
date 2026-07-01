import SwiftUI
import SwiftData

struct AssistantView: View {
    @Query(sort: \TaskItem.dueDate, order: .forward) private var tasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: TaskItem?

    private var todayTasks: [TaskItem] { tasks.filter { isToday($0.dueDate) && !$0.isCompleted } }
    private var upcomingTasks: [TaskItem] { tasks.filter { isFuture($0.dueDate) && !$0.isCompleted } }
    private var undatedTasks: [TaskItem] { tasks.filter { $0.dueDate == nil && !$0.isCompleted } }

    var body: some View {
        NavigationStack {
            List {
                if !todayTasks.isEmpty {
                    Section("Today") {
                        ForEach(todayTasks) { task in taskRow(task) }
                    }
                }
                if !upcomingTasks.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingTasks) { task in taskRow(task) }
                    }
                }
                if !undatedTasks.isEmpty {
                    Section("No date") {
                        ForEach(undatedTasks) { task in taskRow(task) }
                    }
                }
                if tasks.filter({ !$0.isCompleted }).isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checkmark.circle", description: Text("Swipe right to add one"))
                }
            }
            .navigationTitle("Tasks")
            .sheet(item: $editingTask) { task in
                TaskEditView(task: task)
            }
            .onChange(of: tasks) { _, _ in
                Task { await refreshBadge() }
            }
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

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        Button { editingTask = task } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let p = task.priority {
                        priorityBadge(p)
                    }
                }
                HStack(spacing: 6) {
                    if let date = task.dueDate {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(task.dateConfidence < 0.7 ? .orange : .secondary)
                        if task.dateConfidence < 0.7 {
                            Image(systemName: "questionmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let cat = task.category {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func priorityBadge(_ priority: String) -> some View {
        Text(priority)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.15), in: Capsule())
            .foregroundStyle(priorityColor(priority))
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high": return .red
        case "medium": return .orange
        default: return .secondary
        }
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func isFuture(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date > Calendar.current.startOfDay(for: .now) && !Calendar.current.isDateInToday(date)
    }
}

#Preview {
    AssistantView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
