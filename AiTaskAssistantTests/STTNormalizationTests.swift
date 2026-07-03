import Testing
@testable import AiTaskAssistant

// Milestone 10 (STT-1): proves applySTTPatterns applies each language's sttPatterns as a
// find/replace pass before segmentation, and is a true no-op when sttPatterns is empty — the
// property every real shipped pack has today, and the same one the "build" CI job's unchanged
// 105/113 corpus baseline has to hold for it to have been safe to wire into extractLine.
struct STTNormalizationTests {
    private func makeRules(sttPatterns: [STTPattern]) -> LanguageRules {
        LanguageRules(
            code: "en",
            weekdayNames: [:],
            todayWords: [],
            tomorrowWords: [],
            dayAfterTomorrowWords: [],
            numberWords: [:],
            inDaysPattern: nil,
            inWeeksPattern: nil,
            weekdayPhraseRules: [],
            nextWeekPattern: nil,
            timePattern: nil,
            timeOfDayWords: [:],
            priorityPrefixes: [],
            categoryKeywords: [:],
            placeKeywords: [:],
            fillerPrefixes: [],
            fillerWords: [],
            detailPatterns: [],
            detailContinuationPrefixes: [],
            referentialMarkers: [],
            titleReductionRules: [],
            connectorWords: [],
            conjunctionWords: [],
            sequentialWords: [],
            imperativeVerbs: [],
            verbSuffixes: [],
            sttPatterns: sttPatterns
        )
    }

    @Test
    func rewritesTextMatchingAPattern() {
        let rules = makeRules(sttPatterns: [STTPattern(pattern: "grinwood", replacement: "greenwood")])
        let result = RuleBasedExtractionService.shared.applySTTPatterns("meet at grinwood avenue", rulesList: [rules])
        #expect(result == "meet at greenwood avenue")
    }

    @Test
    func leavesNonMatchingTextUntouched() {
        let rules = makeRules(sttPatterns: [STTPattern(pattern: "grinwood", replacement: "greenwood")])
        let result = RuleBasedExtractionService.shared.applySTTPatterns("buy milk tomorrow", rulesList: [rules])
        #expect(result == "buy milk tomorrow")
    }

    @Test
    func emptyPatternsIsANoOp() {
        let rules = makeRules(sttPatterns: [])
        let text = "call max tomorrow and finish deck friday"
        #expect(RuleBasedExtractionService.shared.applySTTPatterns(text, rulesList: [rules]) == text)
    }

    @Test
    func multiplePatternsApplyInOrder() {
        let rules = makeRules(sttPatterns: [
            STTPattern(pattern: "grinwood", replacement: "greenwood"),
            STTPattern(pattern: "avenoo", replacement: "avenue")
        ])
        let result = RuleBasedExtractionService.shared.applySTTPatterns("meet at grinwood avenoo", rulesList: [rules])
        #expect(result == "meet at greenwood avenue")
    }
}
