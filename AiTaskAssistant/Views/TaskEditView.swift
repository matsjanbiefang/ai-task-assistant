import SwiftUI
import SwiftData
import WidgetKit

// swipe-design-concept.md §6 "Detail", matched directly against the "lime-v4" reference mockup
// (real-device feedback, 2026-07-04): a gradient hero card (back chevron + edit pencil, big
// title, category chip) sits above four pill-shaped field rows (date, time, place, category),
// a lime primary "Mark as done" button, and a quiet "Delete task" text link. No NavigationStack
// chrome — the hero card's own back chevron is the dismiss action, exactly like the reference.
// Extra fields (priority, details, linked-task) get their own pill row too, but ONLY when
// present, so a task with none of them (like the reference mockup's) renders pixel-identical to
// it — matching Notebook's "icons only when present" rule rather than diverging from the mockup.
struct TaskEditView: View {
    @Bindable var task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCategory.createdAt) private var customCategories: [CustomCategory]

    @State private var isEditingTitle = false
    @State private var editingField: EditingField?
    @State private var showDeleteConfirmation = false
    @State private var showAddCategory = false
    // Milestone 8: snapshot on appear so a future re-enable of EntityMemoryService.
    // recordCorrection can tell whether the user actually changed `place` (a ground-truth
    // correction) vs. leaving it as the engine extracted it.
    @State private var originalPlace: String?

    private enum EditingField: Identifiable {
        case date, time, place, details, priority
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                fieldRow(
                    label: "Date",
                    value: dateRowValue,
                    isPlaceholder: task.dueDate == nil
                ) { editingField = .date }
                fieldRow(
                    label: "Time",
                    value: timeRowValue,
                    isPlaceholder: task.dueTime == nil && task.timeOfDay == nil
                ) { editingField = .time }
                fieldRow(
                    label: "Place",
                    value: task.place ?? "",
                    isPlaceholder: task.place == nil
                ) { editingField = .place }
                categoryFieldRow
                if let priority = task.priority {
                    fieldRow(label: "Priority", value: priority.capitalized, isPlaceholder: false) {
                        editingField = .priority
                    }
                }
                if let details = task.details {
                    fieldRow(label: "Details", value: details, isPlaceholder: false) {
                        editingField = .details
                    }
                }
                if task.linkedGroupID != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Step \((task.sequenceIndex ?? 0) + 1) of 2 — part of a multi-step task")
                    }
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.Color.mutedGrey)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                Button {
                    toggleCompletion()
                } label: {
                    Text(task.isCompleted ? "Mark as not done" : "Mark as done")
                }
                .buttonStyle(.lime)
                .padding(.top, 8)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete task")
                        .font(Theme.Typography.body(14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.mutedGrey)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(Theme.Color.paper)
        .onAppear { originalPlace = task.place }
        .onDisappear { try? modelContext.save() }
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteTask() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingField) { field in
            editorSheet(for: field)
        }
        .sheet(isPresented: $showAddCategory) {
            AddCustomCategoryView()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                try? modelContext.save()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 40, height: 40)
                    .background(SwiftUI.Color.white, in: Circle())
            }
            .buttonStyle(.plain)

            // Real-device feedback: the separate pencil button didn't visibly do anything (it
            // just swapped in a same-looking TextField) and the category chip up here duplicated
            // the "Category" field row below — tapping the title itself now opens the same inline
            // editor, and category is set from the one field row only.
            if isEditingTitle {
                // Real-device feedback: a multi-line TextField (axis: .vertical) never fires
                // onSubmit — the keyboard's checkmark/done key just inserts a newline instead of
                // confirming, same class of bug already fixed for note lines/compose. Same fix:
                // detect the inserted "\n", strip it, and treat that as "done" here too.
                TextField("Title", text: $task.title, axis: .vertical)
                    .font(Theme.Typography.display(30, weight: .bold))
                    .foregroundStyle(task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                    .submitLabel(.done)
                    .onSubmit { isEditingTitle = false }
                    .onChange(of: task.title) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        task.title = newValue.replacingOccurrences(of: "\n", with: "")
                        isEditingTitle = false
                    }
            } else {
                Text(task.title)
                    .font(Theme.Typography.display(30, weight: .bold))
                    .foregroundStyle(task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                    .strikethrough(task.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditingTitle = true }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Real-device feedback: "Mark as done" should visibly greyscale the whole detail screen,
        // not just the list card — the hero gradient swaps to a flat grey wash and every field
        // row below follows via `task.isCompleted`, all under one `withAnimation` in
        // `toggleCompletion()` so the change reads as active/immediate. The ViewBuilder form of
        // `.background` (a closure, not a ShapeStyle) is used here since the two branches
        // (Color vs. LinearGradient) don't share a common ShapeStyle-conforming type.
        .background {
            RoundedRectangle(cornerRadius: Theme.Metrics.heroCardRadius, style: .continuous)
                .fill(task.isCompleted ? AnyShapeStyle(Theme.Color.hairline.opacity(0.6)) : AnyShapeStyle(
                    LinearGradient(
                        colors: [Theme.Color.skyPaleWash, Theme.Color.lime],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ))
        }
    }

    // §4: categories are told apart by icon shape, never hue — the chip mirrors that everywhere
    // else it appears (Notebook row, Week card meta line, Week legend).
    // MARK: - Field rows

    // `label` is `LocalizedStringKey` — see the same fix/comment in NoteView's statPill/filterChip
    // and SettingsView's rowLabel; `value` stays `String` since it's always dynamic task data.
    private func fieldRow(label: LocalizedStringKey, value: String, isPlaceholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.Typography.body(15))
                    .foregroundStyle(Theme.Color.mutedGrey)
                Spacer()
                Text(value)
                    .font(Theme.Typography.body(16, weight: .semibold))
                    .foregroundStyle(isPlaceholder || task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                task.isCompleted ? Theme.Color.hairline.opacity(0.4) : SwiftUI.Color.white,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.fieldRowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var categoryMenuItems: some View {
        Button("None") { task.category = nil }
        ForEach(TaskCategoryType.allCases, id: \.rawValue) { category in
            Button {
                task.category = category.rawValue
            } label: {
                if let icon = Theme.categoryIcon(category.rawValue) {
                    Label(LocalizedStringKey(Theme.categoryLabel(category.rawValue)), systemImage: icon)
                } else {
                    Text(LocalizedStringKey(Theme.categoryLabel(category.rawValue)))
                }
            }
        }
        ForEach(customCategories) { custom in
            Button {
                task.category = custom.name
            } label: {
                Label(custom.name, systemImage: custom.iconName)
            }
        }
        Button {
            showAddCategory = true
        } label: {
            Label("Add category…", systemImage: "plus")
        }
    }

    // Category picker as a field row — the hero card's own duplicate chip was removed (real-
    // device feedback: it just repeated this same control).
    private var categoryFieldRow: some View {
        Menu {
            categoryMenuItems
        } label: {
            HStack {
                Text("Category")
                    .font(Theme.Typography.body(15))
                    .foregroundStyle(Theme.Color.mutedGrey)
                Spacer()
                Text(task.category.map { LocalizedStringKey(Theme.categoryLabel($0)) } ?? "")
                    .font(Theme.Typography.body(16, weight: .semibold))
                    .foregroundStyle(task.category == nil || task.isCompleted ? Theme.Color.mutedGrey : Theme.Color.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                task.isCompleted ? Theme.Color.hairline.opacity(0.4) : SwiftUI.Color.white,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.fieldRowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // Real-device feedback (2026-07-04): an explicit "Add" placeholder read as filled-in
    // content at a glance — an empty value (still a tappable row, per `isPlaceholder`'s muted
    // styling) reads unambiguously as "nothing here yet".
    private var dateRowValue: String {
        guard let date = task.dueDate else { return "" }
        let start = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard let end = task.dueEndDate else { return start }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var timeRowValue: String {
        guard let time = task.dueTime else {
            return task.timeOfDay ?? ""
        }
        let start = time.formatted(.dateTime.hour().minute())
        guard let end = task.dueEndTime else { return start }
        return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
    }

    // MARK: - Field editor sheets

    // Real-device feedback (2026-07-04): "don't do this swipe thing [toolbar Done button],
    // only swipe down" — every sheet in the app dismisses by swipe only now. Saving moves to
    // `onDisappear`, which fires for a swipe dismissal exactly the same as any other.
    @ViewBuilder
    private func editorSheet(for field: EditingField) -> some View {
        NavigationStack {
            Form {
                switch field {
                case .date: dateEditor
                case .time: timeEditor
                case .place: placeEditor
                case .details: detailsEditor
                case .priority: priorityEditor
                }
            }
            // Real-device feedback: these editor sheets still looked like a stock white iOS Form
            // instead of the app's paper/ink/lime look everywhere else. Full custom-row styling
            // is a larger follow-up; this at least brings the background, tint, and title font
            // in line rather than leaving system defaults untouched.
            .scrollContentBackground(.hidden)
            .background(Theme.Color.paper)
            .tint(Theme.Color.limeDeep)
            .navigationTitle(titleForField(field))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Color.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear { try? modelContext.save() }
    }

    private func titleForField(_ field: EditingField) -> String {
        switch field {
        case .date: return "Date"
        case .time: return "Time"
        case .place: return "Place"
        case .details: return "Details"
        case .priority: return "Priority"
        }
    }

    // Real-device feedback (2026-07-04): the previous "Has due date"/"Has end date" toggle pair
    // could end up both ON with the SAME day (toggling "Has end date" always defaulted it to
    // `dueDate`), rendering a nonsensical "Saturday, 4. Jul – 4. Jul" range in the field row for
    // a task nobody asked to have a range. Presence is now driven directly by whether the
    // optional itself is nil — an explicit "Add end date" button is the only way to create one,
    // and "Remove" is the only way to clear it back to empty.
    @ViewBuilder
    private var dateEditor: some View {
        Section {
            if let due = task.dueDate {
                DatePicker("Due date", selection: Binding(
                    get: { due },
                    set: { task.dueDate = $0 }
                ), displayedComponents: .date)
                Button("Remove date", role: .destructive) {
                    task.dueDate = nil
                    task.dueEndDate = nil
                }
            } else {
                Button("Add date") { task.dueDate = .now }
            }
        }
        // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday to
        // Saturday" — an end date only makes sense once there's a start date.
        if task.dueDate != nil {
            Section {
                if let end = task.dueEndDate {
                    DatePicker("End date", selection: Binding(
                        get: { end },
                        set: { task.dueEndDate = $0 }
                    ), displayedComponents: .date)
                    Button("Remove end date", role: .destructive) { task.dueEndDate = nil }
                } else {
                    Button("Add end date") { task.dueEndDate = task.dueDate }
                }
            }
        }
    }

    @ViewBuilder
    private var timeEditor: some View {
        Section {
            if let due = task.dueTime {
                DatePicker("Due time", selection: Binding(
                    get: { due },
                    set: { task.dueTime = $0 }
                ), displayedComponents: .hourAndMinute)
                Button("Remove time", role: .destructive) {
                    task.dueTime = nil
                    task.dueEndTime = nil
                }
            } else {
                Button("Add time") { task.dueTime = .now }
            }
            if let timeOfDay = task.timeOfDay {
                HStack {
                    Text("Time of day")
                    Spacer()
                    Text(timeOfDay).foregroundStyle(Theme.Color.mutedGrey)
                }
            }
        }
        // Real-device feedback (2026-07-04): "Arzttermin 10 bis 12 Uhr" — an end time only makes
        // sense once there's a start time.
        if task.dueTime != nil {
            Section {
                if let end = task.dueEndTime {
                    DatePicker("End time", selection: Binding(
                        get: { end },
                        set: { task.dueEndTime = $0 }
                    ), displayedComponents: .hourAndMinute)
                    Button("Remove end time", role: .destructive) { task.dueEndTime = nil }
                } else {
                    Button("Add end time") { task.dueEndTime = task.dueTime }
                }
            }
        }
    }

    private var placeEditor: some View {
        Section {
            TextField("Place", text: Binding(
                get: { task.place ?? "" },
                set: { task.place = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var detailsEditor: some View {
        Section {
            TextField("Details", text: Binding(
                get: { task.details ?? "" },
                set: { task.details = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(1...4)
        }
    }

    private var priorityEditor: some View {
        Section {
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
    }

    // MARK: - Actions

    private func toggleCompletion() {
        withAnimation(.easeInOut(duration: 0.25)) {
            task.isCompleted.toggle()
        }
        try? modelContext.save()
        if task.isCompleted {
            modelContext.deleteLineIfAllTasksComplete(for: task)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteTask() {
        Task { await NotificationService.shared.cancel(taskID: task.id.uuidString) }
        modelContext.delete(task)
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

#Preview {
    TaskEditView(task: TaskItem(title: "Sample"))
        .modelContainer(for: [TaskItem.self, NoteLine.self, CustomCategory.self], inMemory: true)
}
