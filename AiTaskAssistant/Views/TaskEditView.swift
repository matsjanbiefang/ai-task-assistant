import SwiftUI
import SwiftData

// swipe-design-concept.md §6 "Detail": "Title, category chip, and four fields — date, time,
// place, category — each in its own tappable row for quick editing. One primary action (mark
// done) and one quiet destructive one (delete), visually de-emphasized so it's not accidentally
// hit." The doc leaves the exact editing mechanism unresolved (§7 "Editing flow"); this keeps the
// proven toggle-then-DatePicker interaction (each field IS its own tappable Form row already) and
// layers the header/chip/button restyle on top of it rather than inventing a new interaction.
struct TaskEditView: View {
    @Bindable var task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Milestone 8: snapshot on appear so the "Done" handler can tell whether the user actually
    // changed `place` (a ground-truth correction) vs. leaving it as the engine extracted it.
    @State private var originalPlace: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Title", text: $task.title)
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Color.ink)
                        categoryChipMenu
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(SwiftUI.Color.clear)

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

                    // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday
                    // to Saturday" — same toggle/picker shape as "Has due date" above.
                    Toggle("Has end date", isOn: Binding(
                        get: { task.dueEndDate != nil },
                        set: { if !$0 { task.dueEndDate = nil } else { task.dueEndDate = task.dueDate ?? .now } }
                    ))
                    if task.dueEndDate != nil {
                        DatePicker("End date", selection: Binding(
                            get: { task.dueEndDate ?? .now },
                            set: { task.dueEndDate = $0 }
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
                            Text(timeOfDay).foregroundStyle(Theme.Color.mutedGrey)
                        }
                    }
                }

                if task.linkedGroupID != nil {
                    Section("Linked task") {
                        Label("Step \((task.sequenceIndex ?? 0) + 1) of 2 — part of a multi-step task", systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(Theme.Color.mutedGrey)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: Binding(
                        get: { task.priority ?? "" },
                        set: { task.priority = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(TaskPriorityLevel.allCases, id: \.rawValue) { p in
                            Text(p.rawValue.capitalized).tag(p.rawValue)
                        }
                    }
                }

                // §6: "One primary action (mark done) and one quiet destructive one (delete),
                // visually de-emphasized so it's not accidentally hit."
                Section {
                    Button {
                        toggleCompletion()
                    } label: {
                        Text(task.isCompleted ? "Mark as not done" : "Mark as done")
                    }
                    .buttonStyle(.lime)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(SwiftUI.Color.clear)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete task")
                            .font(Theme.Typography.body(14))
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(SwiftUI.Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.paper)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { originalPlace = task.place }
            .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteTask() }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Temporarily disabled: see the matching note in NoteView.reparse — this
                        // hook hits the same reproducible on-device SwiftData crash
                        // (swift_dynamicCastFailure in DefaultStore.createSnapshot) via
                        // EntityMemoryService's fetch/save path. Nothing reads EntityMemory yet,
                        // so disabling this costs no functionality while it's investigated.
                        // if let newPlace = task.place, !newPlace.isEmpty, newPlace != originalPlace {
                        //     EntityMemoryService.recordCorrection(newPlace, type: .place, categoryHint: task.category, context: modelContext)
                        // }
                        try? modelContext.save()
                        dismiss()
                    }
                    .foregroundStyle(Theme.Color.ink)
                }
            }
        }
    }

    // §4: categories are told apart by icon shape, never hue — the chip mirrors that everywhere
    // else it appears (Notebook row, task card meta line, Week legend).
    private var categoryChipMenu: some View {
        Menu {
            Button("None") { task.category = nil }
            ForEach(TaskCategoryType.allCases, id: \.rawValue) { category in
                Button {
                    task.category = category.rawValue
                } label: {
                    if let icon = Theme.categoryIcon(category.rawValue) {
                        Label(Theme.categoryLabel(category.rawValue), systemImage: icon)
                    } else {
                        Text(Theme.categoryLabel(category.rawValue))
                    }
                }
            }
        } label: {
            if let category = task.category, let icon = Theme.categoryIcon(category) {
                Label(Theme.categoryLabel(category), systemImage: icon)
                    .font(Theme.Typography.fieldLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.Color.hairline, in: Capsule())
                    .foregroundStyle(Theme.Color.ink)
            } else {
                Label("Add category", systemImage: "tag")
                    .font(Theme.Typography.fieldLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.Color.hairline, in: Capsule())
                    .foregroundStyle(Theme.Color.mutedGrey)
            }
        }
    }

    private func toggleCompletion() {
        task.isCompleted.toggle()
        try? modelContext.save()
        if task.isCompleted {
            modelContext.deleteLineIfAllTasksComplete(for: task)
        }
    }

    private func deleteTask() {
        Task { await NotificationService.shared.cancel(taskID: task.id.uuidString) }
        modelContext.delete(task)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    TaskEditView(task: TaskItem(title: "Sample"))
        .modelContainer(for: [TaskItem.self, NoteLine.self], inMemory: true)
}
