import SwiftUI

// prd-update-02.md §3: ask once, up front, instead of relying solely on per-line auto-detection —
// per-line detection is unreliable on short fragments even between two languages, and that
// unreliability only compounds across 24. The selection here becomes the primary language tried
// first by `RuleBasedExtractionService`; per-line detection remains a fallback for mixed lines.
struct OnboardingLanguageView: View {
    // Phase 5: folded into the multi-page onboarding tour as its final page. `embedded` suppresses
    // this view's own Continue button (OnboardingFlowView provides one for every page) and writes
    // the selection straight into `selected` instead of only firing on tap-Continue.
    var embedded: Bool = false
    var selected: Binding<SupportedLanguage>?
    var onSelect: ((SupportedLanguage) -> Void)?

    // Real-device feedback (2026-07-04): "reduce note taking language to the supported
    // languages" — `SupportedLanguage` lists all 24 EU languages (a future-extensibility list,
    // see its own doc comment), but only 8 have a real `LanguageRules` pack today. Showing the
    // other 16 implied a level of support that doesn't exist yet.
    @State private var internalSelected = SupportedLanguage.deviceDefault.isSupportedByLanguagePack
        ? SupportedLanguage.deviceDefault : .en

    private var currentSelection: SupportedLanguage {
        selected?.wrappedValue ?? internalSelected
    }

    private var sortedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
            .filter(\.isSupportedByLanguagePack)
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        Group {
            if embedded {
                list
            } else {
                NavigationStack {
                    list
                        .navigationTitle("Choose your language")
                        .safeAreaInset(edge: .bottom) { continueButton }
                }
            }
        }
        .onAppear {
            if let selected, selected.wrappedValue != internalSelected {
                internalSelected = selected.wrappedValue
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sortedLanguages) { language in
                languageRow(language)
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ language: SupportedLanguage) -> some View {
        let isSelected = language == currentSelection
        Button {
            internalSelected = language
            selected?.wrappedValue = language
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
            onSelect?(internalSelected)
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
