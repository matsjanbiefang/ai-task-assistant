import SwiftUI

// prd-update-02.md §3: ask once, up front, instead of relying solely on per-line auto-detection —
// per-line detection is unreliable on short fragments even between two languages, and that
// unreliability only compounds across 24. The selection here becomes the primary language tried
// first by `RuleBasedExtractionService`; per-line detection remains a fallback for mixed lines.
struct OnboardingLanguageView: View {
    // Phase 5: folded into the multi-page onboarding tour as its first page. `embedded` suppresses
    // this view's own Continue button (OnboardingFlowView provides one for every page) and writes
    // the selection straight into `selected` instead of only firing on tap-Continue.
    //
    // Real-device feedback: this page used to default to the device's language (or English),
    // showing a row pre-checked before the user had chosen anything. `selected` is now Optional —
    // nothing is highlighted until an explicit tap, and the enclosing flow disables its Continue
    // button while it's nil.
    var embedded: Bool = false
    var selected: Binding<SupportedLanguage?>?
    var onSelect: ((SupportedLanguage) -> Void)?

    @State private var internalSelected: SupportedLanguage?

    private var currentSelection: SupportedLanguage? {
        selected?.wrappedValue ?? internalSelected
    }

    // Real-device feedback (2026-07-04): "reduce note taking language to the supported
    // languages" — `SupportedLanguage` lists all 24 EU languages (a future-extensibility list,
    // see its own doc comment), but only 8 have a real `LanguageRules` pack today. Showing the
    // other 16 implied a level of support that doesn't exist yet.
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
                        .background(Theme.Color.paper)
                        .navigationTitle("Choose your language")
                        .safeAreaInset(edge: .bottom) { continueButton }
                }
            }
        }
    }

    // Real-device feedback: the plain iOS List (white rows, blue link-colored text) didn't match
    // the rest of the app's paper/ink/lime look anywhere it appeared — restyled as themed rows in
    // a plain scroll, same visual language as every other picker/menu in the app.
    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(sortedLanguages) { language in
                    languageRow(language)
                }
            }
            .padding(.horizontal, 20)
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
                    .font(Theme.Typography.body(16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Color.limeDeep)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Theme.Color.lime.opacity(0.35) : SwiftUI.Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Theme.Color.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            if let internalSelected { onSelect?(internalSelected) }
        } label: {
            Text("Continue")
                .font(Theme.Typography.body(16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Color.lime)
        .foregroundStyle(Theme.Color.ink)
        .disabled(internalSelected == nil)
        .padding()
        .background(Theme.Color.paper)
    }
}

#Preview {
    OnboardingLanguageView(onSelect: { _ in })
}
