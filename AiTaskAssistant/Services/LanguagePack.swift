import Foundation

// MARK: - Language pack wire format (swipe-final-architecture.md §3)
//
// Mirrors the bundled JSON packs under AiTaskAssistant/LanguagePacks/<code>.json exactly, section
// by section. This is a pure DTO layer: `LanguagePackDTO.toLanguageRules()` is the only place that
// bridges into the engine's actual `LanguageRules` type (RuleBasedExtractionService.swift), which
// is otherwise untouched by this migration — every function that consumes `LanguageRules` keeps
// working unchanged. Every JSON key is always present in the packs (using `[]`/`{}`/`null` for
// empty), so plain synthesized `Decodable` is enough everywhere — no custom `init(from:)`.

struct LanguagePackDTO: Decodable {
    let code: String
    let dateRules: DateRulesDTO
    let timeWords: TimeWordsDTO
    let priorityKeywords: [PriorityPrefixDTO]
    let conjunctions: [String]
    let splitClassifiers: [String]
    let actionVerbs: ActionVerbsDTO
    let categoryKeywords: [String: [String]]
    let locationPatterns: LocationPatternsDTO
    let detailClauseMarkers: DetailClauseMarkersDTO
    let stopwords: StopwordsDTO
    let fillerPhrases: [String]
    let titleReductionRules: [TitleReductionRuleDTO]
    let sttPatterns: [String]
    let ambiguityRules: AmbiguityRulesDTO
}

struct DateRulesDTO: Decodable {
    let weekdayNames: [String: Int]
    let todayWords: [String]
    let tomorrowWords: [String]
    let dayAfterTomorrowWords: [String]
    let numberWords: [String: Int]
    let inDaysPattern: String?
    let inWeeksPattern: String?
    let weekdayPhraseRules: [WeekdayPhraseRuleDTO]
    let nextWeekPattern: String?
}

struct WeekdayPhraseRuleDTO: Decodable {
    let pattern: String
    let skipToday: Bool
    let confidence: Double
}

struct TimeWordsDTO: Decodable {
    let timePattern: String?
    let timeOfDayWords: [String: String]
    let vagueTimeOfDayWords: [String: String]
    let laterOffsetWords: [String]
}

struct PriorityPrefixDTO: Decodable {
    let pattern: String
    let priority: TaskPriority
}

struct ActionVerbsDTO: Decodable {
    let imperativeVerbs: [String]
    let verbSuffixes: [String]
}

struct LocationPatternsDTO: Decodable {
    let placeKeywords: [String: String]
    let addressPattern: String?
}

struct DetailClauseMarkersDTO: Decodable {
    let detailPatterns: [String]
    let detailContinuationPrefixes: [String]
    let referentialMarkers: [String]
}

struct StopwordsDTO: Decodable {
    let words: [String]
    let connectorWords: [String]
}

struct TitleReductionRuleDTO: Decodable {
    let pattern: String
    let template: String
}

// Reserved for Phase 2 (confidence-gate calibration) — decoded now so packs are forward-compatible,
// unused until that phase formalizes ambiguity handling beyond the inline confidence values already
// on WeekdayPhraseRule etc.
struct AmbiguityRulesDTO: Decodable {}

extension LanguagePackDTO {
    func toLanguageRules() -> LanguageRules {
        var resolvedCategoryKeywords: [TaskCategory: [String]] = [:]
        for (key, words) in categoryKeywords {
            if let category = TaskCategory(rawValue: key) {
                resolvedCategoryKeywords[category] = words
            }
        }
        return LanguageRules(
            code: code,
            weekdayNames: dateRules.weekdayNames,
            todayWords: dateRules.todayWords,
            tomorrowWords: dateRules.tomorrowWords,
            dayAfterTomorrowWords: dateRules.dayAfterTomorrowWords,
            numberWords: dateRules.numberWords,
            inDaysPattern: dateRules.inDaysPattern,
            inWeeksPattern: dateRules.inWeeksPattern,
            weekdayPhraseRules: dateRules.weekdayPhraseRules.map {
                WeekdayPhraseRule(pattern: $0.pattern, skipToday: $0.skipToday, confidence: $0.confidence)
            },
            nextWeekPattern: dateRules.nextWeekPattern,
            timePattern: timeWords.timePattern,
            timeOfDayWords: timeWords.timeOfDayWords,
            vagueTimeOfDayWords: timeWords.vagueTimeOfDayWords,
            laterOffsetWords: timeWords.laterOffsetWords,
            priorityPrefixes: priorityKeywords.map { (pattern: $0.pattern, priority: $0.priority) },
            categoryKeywords: resolvedCategoryKeywords,
            placeKeywords: locationPatterns.placeKeywords,
            addressPattern: locationPatterns.addressPattern,
            fillerPrefixes: fillerPhrases,
            fillerWords: stopwords.words,
            detailPatterns: detailClauseMarkers.detailPatterns,
            detailContinuationPrefixes: detailClauseMarkers.detailContinuationPrefixes,
            referentialMarkers: detailClauseMarkers.referentialMarkers,
            titleReductionRules: titleReductionRules.map {
                TitleReductionRule(pattern: $0.pattern, template: $0.template)
            },
            connectorWords: stopwords.connectorWords,
            conjunctionWords: conjunctions,
            sequentialWords: splitClassifiers,
            imperativeVerbs: Set(actionVerbs.imperativeVerbs),
            verbSuffixes: actionVerbs.verbSuffixes
        )
    }
}

// MARK: - Loader

enum LanguagePackLoader {
    static let supportedCodes = ["en", "de", "fr", "es", "it", "pt", "nl", "pl"]

    static func loadAll() -> [String: LanguageRules] {
        var tables: [String: LanguageRules] = [:]
        for code in supportedCodes {
            guard let url = Bundle.main.url(forResource: code, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                assertionFailure("Missing language pack resource: \(code).json")
                continue
            }
            do {
                let dto = try JSONDecoder().decode(LanguagePackDTO.self, from: data)
                tables[dto.code] = dto.toLanguageRules()
            } catch {
                assertionFailure("Failed to decode language pack \(code).json: \(error)")
            }
        }
        return tables
    }
}
