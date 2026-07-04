import SwiftUI

// prd-update-02.md §3: ask once, up front, instead of relying solely on per-line auto-detection —
// per-line detection is unreliable on short fragments even between two languages, and that
// unreliability only compounds across 24. The selection here becomes the primary language tried
// first by `RuleBasedExtractionService`; per-line detection remains a fallback for mixed lines.
struct OnboardingLanguageView: View {
    var onSelect: (SupportedLanguage) -> Void

    // Real-device feedback (2026-07-04): "reduce note taking language to the supported
    // languages" — `SupportedLanguage` lists all 24 EU languages (a future-extensibility list,
    // see its own doc comment), but only 8 have a real `LanguageRules` pack today. Showing the
    // other 16 implied a level of support that doesn't exist yet.
    @State private var selected = SupportedLanguage.deviceDefault.isSupportedByLanguagePack
        ? SupportedLanguage.deviceDefault : .en

    private var sortedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
            .filter(\.isSupportedByLanguagePack)
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedLanguages) { language in
                    languageRow(language)
                }
            }
            .navigationTitle("Choose your language")
            .safeAreaInset(edge: .bottom) {
                continueButton
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ language: SupportedLanguage) -> some View {
        let isSelected = language == selected
        Button {
            selected = language
        } label: {
            HStack {
                Text(language.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var continueButton: some View {
        Button {
            onSelect(selected)
        } label: {
            Text("Continue")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    OnboardingLanguageView(onSelect: { _ in })
}
