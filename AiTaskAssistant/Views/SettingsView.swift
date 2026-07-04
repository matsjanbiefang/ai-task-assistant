import SwiftUI

// swipe-design-concept.md §6/§7: "Settings — icon exists, screen doesn't" was an open question;
// this is the minimal version that makes the Notebook's top-bar gear icon lead somewhere real —
// the one setting the app already has state for (`primaryLanguageCode`, set at onboarding).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("primaryLanguageCode") private var primaryLanguageCode = "en"

    private var sortedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases.sorted { $0.displayName < $1.displayName }
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
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.Color.ink)
                }
            }
        }
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
}

#Preview {
    SettingsView()
}
