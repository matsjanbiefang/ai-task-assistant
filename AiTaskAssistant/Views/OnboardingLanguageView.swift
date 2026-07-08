import SwiftUI
import Combine

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
    // Real-device feedback: "select your language" header cycling through each selectable
    // language's own translation of that phrase, 0.8s per language, looping — a quick, friendly
    // way to signal "pick one of these" before the user has decided which language they read.
    @State private var headerIndex = 0

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

    private static let selectLanguagePhrases: [String] = [
        "Select your language", "Sprache auswählen", "Selecciona tu idioma", "Choisis ta langue",
        "Seleziona la tua lingua", "Kies je taal", "Wybierz swój język", "Seleciona o teu idioma",
    ]

    private let headerTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

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

    // Real-device feedback: vertically centered like every other onboarding page, and the plain
    // iOS List (white rows, blue link-colored text) restyled as themed rows in a plain scroll —
    // same visual language as every other picker/menu in the app.
    private var list: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    Text(Self.selectLanguagePhrases[headerIndex])
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Color.ink)
                        .contentTransition(.opacity)
                        .id(headerIndex)
                        .transition(.opacity)
                        .onReceive(headerTimer) { _ in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                headerIndex = (headerIndex + 1) % Self.selectLanguagePhrases.count
                            }
                        }
                    VStack(spacing: 10) {
                        ForEach(sortedLanguages) { language in
                            languageRow(language)
                        }
                    }
                    .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.vertical, 24)
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
