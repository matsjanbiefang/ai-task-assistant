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
                    TextField("Place", text: Binding(
                        get: { task.place ?? "" },
                        set: { task.place = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Details", text: Binding(
                        get: { task.details ?? "" },
                        set: { task.details = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(1...4)
                }

                Section("Schedule") {
                    // Pickers only appear once their toggle is on. Showing a DatePicker bound to
                    // `task.dueDate ?? .now` unconditionally (the previous behavior) displayed the
                    // actual current wall-clock time as a misleading fallback whenever dueTime was
                    // genuinely nil — almost certainly what looked like "the app set 8pm" when the
                    // engine had actually left the time unset, exactly as intended.
                    Toggle("Has due date", isOn: Binding(
                        get: { task.dueDate != nil },
                        set: { if !$0 { task.dueDate = nil } else { task.dueDate = .now } }
                    ))
                    if task.dueDate != nil {
                        DatePicker("Due date", selection: Binding(
                            get: { task.dueDate ?? .now },
                            set: { task.dueDate = $0 }
                        ), displayedComponents: .date)
                    }

                    Toggle("Has due time", isOn: Binding(
                        get: { task.dueTime != nil },
                        set: { if !$0 { task.dueTime = nil } else { task.dueTime = .now } }
                    ))
                    if task.dueTime != nil {
                        DatePicker("Due time", selection: Binding(
                            get: { task.dueTime ?? .now },
                            set: { task.dueTime = $0 }
                        ), displayedComponents: .hourAndMinute)
                    }

                    if let timeOfDay = task.timeOfDay {
                        HStack {
                            Text("Time of day")
                            Spacer()
                            Text(timeOfDay).foregroundStyle(.secondary)
                        }
                    }
                }

                if task.linkedGroupID != nil {
                    Section("Linked task") {
                        Label("Step \((task.sequenceIndex ?? 0) + 1) of 2 — part of a multi-step task", systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
