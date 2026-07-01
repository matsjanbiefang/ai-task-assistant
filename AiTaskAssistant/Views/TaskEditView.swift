import SwiftUI
import SwiftData

struct TaskEditView: View {
    @Bindable var task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $task.title)
                }

                Section("Schedule") {
                    DatePicker("Due date", selection: Binding(
                        get: { task.dueDate ?? .now },
                        set: { task.dueDate = $0 }
                    ), displayedComponents: .date)
                    Toggle("Has due date", isOn: Binding(
                        get: { task.dueDate != nil },
                        set: { if !$0 { task.dueDate = nil } else { task.dueDate = .now } }
                    ))
                }

                Section("Details") {
                    Picker("Priority", selection: Binding(
                        get: { task.priority ?? "" },
                        set: { task.priority = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(TaskPriorityLevel.allCases, id: \.rawValue) { p in
                            Text(p.rawValue.capitalized).tag(p.rawValue)
                        }
                    }

                    Picker("Category", selection: Binding(
                        get: { task.category ?? "" },
                        set: { task.category = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(TaskCategoryType.allCases, id: \.rawValue) { c in
                            Text(c.rawValue.capitalized).tag(c.rawValue)
                        }
                    }
                }

                Section {
                    Button("Mark complete", role: .destructive) {
                        task.isCompleted = true
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
