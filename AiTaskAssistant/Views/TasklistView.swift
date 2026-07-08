import SwiftUI
import SwiftData
import WidgetKit

// Real-device feedback (2026-07-04): "leave tasks without date out of the calendar but add
// another module 'Tasklist' where you add them. But you are still able to add a date, when they
// are moved from tasklist to Calendar." Undated tasks now live here instead of in Week's old
// dashed "No date" section. No explicit "move" step exists or is needed: a task's `dueDate` is
// the single source of truth both screens filter on, so setting a date in TaskEditView (or
// clearing one) makes it disappear from here and appear in Week (or vice versa) automatically.
struct TasklistView: View {
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var allTasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: TaskItem?

    private var undatedTasks: [TaskItem] { allTasks.filter { $0.dueDate == nil } }
    private var openTasks: [TaskItem] { undatedTasks.filter { !$0.isCompleted } }
    private var doneTasks: [TaskItem] { undatedTasks.filter(\.isCompleted) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if undatedTasks.isEmpty {
                        EmptyStateView(icon: "checkmark.circle", message: "No undated tasks")
                    } else {
                        ForEach(openTasks) { task in card(for: task) }
                        if !doneTasks.isEmpty {
                            Text("Completed")
                                .font(Theme.Typography.fieldLabel)
                                .foregroundStyle(Theme.Color.mutedGrey)
                                .padding(.top, 12)
                            ForEach(doneTasks) { task in card(for: task) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.Color.paper)
            .navigationTitle("Tasklist")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTask) { task in
                TaskEditView(task: task)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func card(for task: TaskItem) -> TaskCardView {
        TaskCardView(task: task, onToggleCompletion: { toggleCompletion(task) }, onTap: { editingTask = task })
    }

    private func toggleCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        try? modelContext.save()
        if task.isCompleted {
            Task { await NotificationService.shared.cancel(taskID: task.id.uuidString) }
            modelContext.deleteLineIfAllTasksComplete(for: task)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    TasklistView()
        .modelContainer(for: [TaskItem.self, NoteLine.self, EntityMemory.self, CustomCategory.self], inMemory: true)
}
