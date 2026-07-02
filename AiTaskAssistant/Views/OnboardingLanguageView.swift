import SwiftUI

// prd-update-02.md §3: ask once, up front, instead of relying solely on per-line auto-detection —
// per-line detection is unreliable on short fragments even between two languages, and that
// unreliability only compounds across 24. The selection here becomes the primary language tried
// first by `RuleBasedExtractionService`; per-line detection remains a fallback for mixed lines.
struct OnboardingLanguageView: View {
    var onSelect: (SupportedLanguage) -> Void

    @State private var selected = SupportedLanguage.deviceDefault

    private var sortedLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            List(sortedLanguages) { language in
                Button {
                    selected = language
                } label: {
                    HStack {
                        Text(language.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if language == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Choose your language")
            .safeAreaInset(edge: .bottom) {
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
    }
}

#Preview {
    OnboardingLanguageView(onSelect: { _ in })
}
