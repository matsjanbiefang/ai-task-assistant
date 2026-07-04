import SwiftUI
import SwiftData

// swipe-design-concept.md §6/§7: "Settings — icon exists, screen doesn't" was an open question;
// grown since (real-device feedback, 2026-07-04) into: note-taking language (filtered to the
// languages that actually have a rule pack), reminder notifications (on/off + configurable lead
// time), placeholder Terms/Privacy/Support entries, and a destructive "Delete all data" escape
// hatch. No toolbar "Done" button — swipe down is the only dismissal, same as every other sheet.
struct SettingsView: View {
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = "en"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("reminderLeadTimeMinutes") private var reminderLeadTimeMinutes = 15

    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteAllConfirmation = false
    @State private var showCustomReminderEditor = false

    // Real-device feedback: "reduce note taking language to the supported languages" — see
    // `SupportedLanguage.isSupportedByLanguagePack`'s doc comment for why the other 16 of 24 EU
    // languages are left out here.
    private var sortedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
            .filter(\.isSupportedByLanguagePack)
            .sorted { $0.displayName < $1.displayName }
    }

    private static let presetLeadTimes: [(label: String, minutes: Int)] = [
        ("At due time", 0),
        ("15 minutes before", 15),
        ("1 hour before", 60),
        ("1 day before", 1440),
    ]
    private static let customTag = -1

    private var isCustomLeadTime: Bool {
        !Self.presetLeadTimes.contains { $0.minutes == reminderLeadTimeMinutes }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedLanguages) { language in
                        languageRow(language)
                    }
                } header: {
                    Text("Note-taking language")
                } footer: {
                    Text("Used to recognize dates, times, places, and categories in what you type or say.")
                }

                Section {
                    Toggle("Notifications", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        Picker("Remind me", selection: Binding(
                            get: { isCustomLeadTime ? Self.customTag : reminderLeadTimeMinutes },
                            set: { newValue in
                                if newValue == Self.customTag {
                                    showCustomReminderEditor = true
                                } else {
                                    reminderLeadTimeMinutes = newValue
                                }
                            }
                        )) {
                            ForEach(Self.presetLeadTimes, id: \.minutes) { preset in
                                Text(preset.label).tag(preset.minutes)
                            }
                            Text(isCustomLeadTime ? customLeadTimeLabel : "Custom…").tag(Self.customTag)
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if notificationsEnabled {
                        Text("How far ahead of a task's due time to send a reminder.")
                    }
                }

                Section("About") {
                    NavigationLink("Terms of Service") {
                        LegalPlaceholderView(title: "Terms of Service")
                    }
                    NavigationLink("Privacy Policy") {
                        LegalPlaceholderView(title: "Privacy Policy")
                    }
                    // Placeholder address (real-device feedback, 2026-07-04) — replace once a
                    // real support inbox exists.
                    Link(destination: URL(string: "mailto:support@taskmind.app")!) {
                        HStack {
                            Text("Support")
                                .foregroundStyle(Theme.Color.ink)
                            Spacer()
                            Text("support@taskmind.app")
                                .foregroundStyle(Theme.Color.mutedGrey)
                        }
                    }
                }

                Section {
                    Button("Delete all data", role: .destructive) {
                        showDeleteAllConfirmation = true
                    }
                } footer: {
                    Text("Permanently deletes every task, note, and shopping list item. This can't be undone.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete all data?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every task, note, and shopping list item. This can't be undone.")
            }
            .sheet(isPresented: $showCustomReminderEditor) {
                CustomReminderView(minutes: $reminderLeadTimeMinutes)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var customLeadTimeLabel: String {
        let minutes = reminderLeadTimeMinutes
        if minutes > 0, minutes % 1440 == 0 {
            let days = minutes / 1440
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
        if minutes > 0, minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s") before"
    }

    @ViewBuilder
    private func languageRow(_ language: SupportedLanguage) -> some View {
        let isSelected = language.rawValue == primaryLanguageCode
        Button {
            primaryLanguageCode = language.rawValue
        } label: {
            HStack {
                Text(language.displayName)
                    .font(Theme.Typography.body(16))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Color.limeDeep)
                }
            }
        }
    }

    private func deleteAllData() {
        deleteAll(TaskItem.self)
        deleteAll(NoteLine.self)
        deleteAll(ShoppingItem.self)
        deleteAll(EntityMemory.self)
        try? modelContext.save()
        Task { await NotificationService.shared.cancelAll() }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        guard let items = try? modelContext.fetch(FetchDescriptor<T>()) else { return }
        for item in items { modelContext.delete(item) }
    }
}

// Real-device feedback (2026-07-04): "add terms and data policies placeholder in settings" —
// plain in-app text for now; swap for real copy (and/or a hosted URL, which Apple requires for
// App Store submission) before shipping externally.
private struct LegalPlaceholderView: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Color.ink)
                Text("Placeholder — the full \(title.lowercased()) will go here before this app is submitted for review.")
                    .font(Theme.Typography.body(15))
                    .foregroundStyle(Theme.Color.mutedGrey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.Color.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// A flexible lead time ("1 day before", "5 hours before", ...) — any whole number of minutes,
// hours, or days. No Done button: the value commits on `onDisappear`, same as every other sheet.
private struct CustomReminderView: View {
    @Binding var minutes: Int
    @State private var amount = 1
    @State private var unit = Unit.hours

    private enum Unit: String, CaseIterable {
        case minutes = "Minutes", hours = "Hours", days = "Days"
        var multiplier: Int {
            switch self {
            case .minutes: return 1
            case .hours: return 60
            case .days: return 1440
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Amount: \(amount)", value: $amount, in: 1...999)
                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Remind me \(amount) \(unit.rawValue.lowercased()) before a task is due.")
                }
            }
            .navigationTitle("Custom Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Decompose the current value into the largest whole unit so re-opening this editor
            // shows something sensible instead of always resetting to "1 hour".
            if minutes > 0, minutes % 1440 == 0 {
                amount = minutes / 1440
                unit = .days
            } else if minutes > 0, minutes % 60 == 0 {
                amount = minutes / 60
                unit = .hours
            } else {
                amount = max(minutes, 1)
                unit = .minutes
            }
        }
        .onDisappear {
            minutes = amount * unit.multiplier
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [TaskItem.self, NoteLine.self, ShoppingItem.self, EntityMemory.self], inMemory: true)
}
