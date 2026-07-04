import Foundation

// All 24 EU official languages (prd-update-02.md §1) — this already covers North America's
// practical needs since English/French/Spanish are in the list. Not every case has a
// `LanguageRules` table yet (see `RuleBasedExtractionService.languageTables` — Batch 1 covers
// en/de/fr/es/it/pt/nl/pl; the rest are Milestone 6 follow-up per prd-update-02.md §4). Languages
// without a table still work via the universal NSDataDetector layer — they just don't get that
// language's custom date-phrase coverage yet, which is the "graceful degradation, not a capability
// gap" default the PRD already established for Foundation Models availability.
enum SupportedLanguage: String, CaseIterable, Identifiable, Sendable {
    case bg, hr, cs, da, nl, en, et, fi, fr, de, el, hu, ga, it, lv, lt, mt, pl, pt, ro, sk, sl, es, sv

    var id: String { rawValue }

    var displayName: String {
        Locale.current.localizedString(forLanguageCode: rawValue)?.localizedCapitalized ?? rawValue.uppercased()
    }

    /// The device's language if it's one of the 24 supported, else English.
    static var deviceDefault: SupportedLanguage {
        if let code = Locale.current.language.languageCode?.identifier, let match = SupportedLanguage(rawValue: code) {
            return match
        }
        return .en
    }

    /// Real-device feedback (2026-07-04): "reduce note taking language to the supported
    /// languages" — of these 24, only the ones with a real `LanguageRules` pack (see
    /// `LanguagePackLoader.supportedCodes`) should be offered as a note-taking language choice.
    /// The other 16 still work via the universal NSDataDetector fallback if somehow selected, but
    /// showing them in the picker implied per-language date/place/category coverage that isn't
    /// actually there yet.
    var isSupportedByLanguagePack: Bool {
        LanguagePackLoader.supportedCodes.contains(rawValue)
    }
}
