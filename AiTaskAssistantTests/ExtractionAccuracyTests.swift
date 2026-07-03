import Testing
import Foundation
@testable import AiTaskAssistant

// MARK: - Milestone 0 scoring harness (prd-update-01.md §7, §10)
//
// Permanent regression suite for the rules engine. Two entry points:
//   - `corpusCase(_:)` — one assertion per corpus line, for pinpointing exactly which line broke
//     during the "run → categorize failures → fix → re-run" loop in §7.
//   - `overallAccuracyMeetsTarget()` — the actual Milestone 0 exit criterion: ≥90% of corpus lines
//     fully correct (§10). This is EXPECTED TO FAIL until U0-8's iteration work is done — that
//     failure is the signal that Milestone 0 isn't finished yet, not a bug in the test.

private func matches(_ actual: [ExtractedTask], _ expected: [ExpectedTask]) -> Bool {
    guard actual.count == expected.count else { return false }
    return zip(actual, expected).allSatisfy { a, e in
        a.title == e.title
            && a.dueDate == e.dueDate
            && a.dueTime == e.dueTime
            && a.priority == e.priority
    }
}

private func nonEmptyLines(_ input: String) -> [String] {
    input
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

// Milestone 7 (CG-1, swipe-final-architecture.md §6): per-field breakdown for one corpus line,
// kept separate from `matches()` (used by `corpusCase(_:)`) so that test's existing per-line
// assertions and failure messages are untouched by this addition. `passed` is constructed to be
// exactly `matches()`'s logic (same length guard, same four-field check), so switching
// `scoreCorpus()` over to this struct cannot change the overall accuracy number.
private struct LineFieldScore {
    let splitCountMatches: Bool   // actual.count == expected.count
    let expectedSplit: Bool       // expected.count > 1
    let actualSplit: Bool         // actual.count > 1
    let titleMatches: [Bool]      // one entry per paired task; empty when splitCountMatches == false
    let dueDateMatches: [Bool]
    let dueTimeMatches: [Bool]
    let priorityMatches: [Bool]

    var passed: Bool {
        splitCountMatches
            && titleMatches.allSatisfy { $0 }
            && dueDateMatches.allSatisfy { $0 }
            && dueTimeMatches.allSatisfy { $0 }
            && priorityMatches.allSatisfy { $0 }
    }
}

private func fieldScore(_ actual: [ExtractedTask], _ expected: [ExpectedTask]) -> LineFieldScore {
    let splitCountMatches = actual.count == expected.count
    let pairs = splitCountMatches ? Array(zip(actual, expected)) : []
    return LineFieldScore(
        splitCountMatches: splitCountMatches,
        expectedSplit: expected.count > 1,
        actualSplit: actual.count > 1,
        titleMatches: pairs.map { $0.0.title == $0.1.title },
        dueDateMatches: pairs.map { $0.0.dueDate == $0.1.dueDate },
        dueTimeMatches: pairs.map { $0.0.dueTime == $0.1.dueTime },
        priorityMatches: pairs.map { $0.0.priority == $0.1.priority }
    )
}

/// Runs every corpus case and returns per-line field-level scoring, tagged with the case's focus category.
private func scoreCorpus() -> [(caseID: Int, focus: CorpusFocus, lineIndex: Int, score: LineFieldScore)] {
    let service = RuleBasedExtractionService.shared
    var results: [(caseID: Int, focus: CorpusFocus, lineIndex: Int, score: LineFieldScore)] = []
    for testCase in extractionCorpus {
        let lines = nonEmptyLines(testCase.input)
        for (index, line) in lines.enumerated() {
            let actual = service.extractLine(line, referenceDate: corpusToday)
            let expected = index < testCase.expected.count ? testCase.expected[index] : []
            results.append((testCase.id, testCase.focus, index, fieldScore(actual, expected)))
        }
    }
    return results
}

// Milestone 7 (CG-2, swipe-final-architecture.md §6): threshold-calibration tooling. Diagnostic
// only — reports real numbers, does not (yet) replace RuleBasedExtractionService's fixed
// `lowConfidenceThreshold`. Wiring calibrated per-language values into the runtime gate is
// deferred (CG-2b): today's corpus has only ~5 cases for each Batch 1 language, nowhere near
// enough to trust a 98%-precision estimate from, and replacing a single global threshold with a
// per-language one is a real data-structure + call-site change of its own.

private struct ConfidenceSample {
    let language: String   // NLLanguage.rawValue, e.g. "en", "de"
    let confidence: Double // ExtractedTask.dateConfidence
    let correct: Bool      // actual.dueDate == expected.dueDate
}

/// One sample per paired task across the whole corpus, tagged with the same language
/// classification the runtime pipeline itself would use for that line. Lines where the split
/// count didn't match are skipped — there's no valid actual/expected pairing to sample from.
private func calibrationSamples() -> [ConfidenceSample] {
    let service = RuleBasedExtractionService.shared
    var samples: [ConfidenceSample] = []
    for testCase in extractionCorpus {
        let lines = nonEmptyLines(testCase.input)
        for (index, line) in lines.enumerated() {
            let actual = service.extractLine(line, referenceDate: corpusToday)
            let expected = index < testCase.expected.count ? testCase.expected[index] : []
            guard actual.count == expected.count else { continue }
            let language = service.detectLanguage(line).rawValue
            for (a, e) in zip(actual, expected) {
                samples.append(ConfidenceSample(language: language, confidence: a.dateConfidence, correct: a.dueDate == e.dueDate))
            }
        }
    }
    return samples
}

/// Lowest confidence threshold t such that precision (fraction correct) among samples with
/// confidence >= t is >= targetPrecision, or nil if no threshold reaches it. Sweeps only at
/// distinct observed confidence values — precision can't change between them, so this can't miss
/// the true optimum the way an arbitrary fixed-step grid could.
private func calibrateThreshold(_ samples: [ConfidenceSample], targetPrecision: Double = 0.98) -> Double? {
    let candidates = Set(samples.map(\.confidence)).sorted()
    for t in candidates {
        let above = samples.filter { $0.confidence >= t }
        guard !above.isEmpty else { continue }
        let precision = Double(above.filter(\.correct).count) / Double(above.count)
        if precision >= targetPrecision { return t }
    }
    return nil
}

private let minimumCalibrationSampleSize = 20

private func describeCalibration(_ label: String, _ samples: [ConfidenceSample]) -> String {
    let sizeNote = samples.count < minimumCalibrationSampleSize
        ? " — insufficient sample size for a reliable calibration (need >= \(minimumCalibrationSampleSize))"
        : ""
    if let t = calibrateThreshold(samples) {
        return "  \(label): t=\(t) (n=\(samples.count))\(sizeNote)"
    } else {
        return "  \(label): no threshold reaches 98% precision (n=\(samples.count))\(sizeNote)"
    }
}

struct ExtractionAccuracyTests {

    @Test(arguments: extractionCorpus)
    func corpusCase(_ testCase: CorpusCase) {
        let service = RuleBasedExtractionService.shared
        let lines = nonEmptyLines(testCase.input)
        #expect(lines.count == testCase.expected.count, "case \(testCase.id): line count doesn't match expected array shape")

        for (index, line) in lines.enumerated() {
            guard index < testCase.expected.count else { continue }
            let actual = service.extractLine(line, referenceDate: corpusToday)
            let expected = testCase.expected[index]
            #expect(
                matches(actual, expected),
                "case \(testCase.id) line \(index) (\(testCase.focus.rawValue)): \"\(line)\" -> got \(actual), want \(expected)"
            )
        }
    }

    @Test
    func overallAccuracyMeetsTarget() {
        let results = scoreCorpus()
        let total = results.count
        let correct = results.filter(\.score.passed).count
        let accuracy = total == 0 ? 0 : Double(correct) / Double(total)

        var byFocus: [CorpusFocus: (correct: Int, total: Int)] = [:]
        for result in results {
            var bucket = byFocus[result.focus] ?? (0, 0)
            bucket.total += 1
            if result.score.passed { bucket.correct += 1 }
            byFocus[result.focus] = bucket
        }

        print("=== Extraction accuracy: \(correct)/\(total) (\(Int(accuracy * 100))%) ===")
        for focus in CorpusFocus.allCases where byFocus[focus] != nil {
            let bucket = byFocus[focus]!
            let pct = bucket.total == 0 ? 0 : Int(Double(bucket.correct) / Double(bucket.total) * 100)
            print("  \(focus.rawValue): \(bucket.correct)/\(bucket.total) (\(pct)%)")
        }

        // Milestone 7 (CG-1): per-field accuracy, reported separately per swipe-final-architecture.md
        // §6 ("blended single numbers are never reported alone") — diagnostic only, not its own gate
        // yet (that's CG-2's calibrated threshold work, deferred).
        func fieldPct(_ matches: [Bool]) -> String {
            guard !matches.isEmpty else { return "n/a" }
            let correct = matches.filter { $0 }.count
            return "\(correct)/\(matches.count) (\(Int(Double(correct) / Double(matches.count) * 100))%)"
        }
        print("--- Per-field accuracy ---")
        print("  title: \(fieldPct(results.flatMap(\.score.titleMatches)))")
        print("  dueDate: \(fieldPct(results.flatMap(\.score.dueDateMatches)))")
        print("  dueTime: \(fieldPct(results.flatMap(\.score.dueTimeMatches)))")
        print("  priority: \(fieldPct(results.flatMap(\.score.priorityMatches)))")

        // Milestone 7 (CG-1): segmentation precision/recall tracked on its own — "of lines that
        // should have split, how many did" (recall) and "of lines that did split, how many were
        // supposed to" (precision). Correctness bar is exact split count match, same bar the corpus
        // already scores elsewhere (`splitCountMatches`).
        let expectedSplitLines = results.filter(\.score.expectedSplit)
        let actualSplitLines = results.filter(\.score.actualSplit)
        let correctSplits = results.filter { $0.score.expectedSplit && $0.score.actualSplit && $0.score.splitCountMatches }
        let recall = expectedSplitLines.isEmpty ? 1.0 : Double(correctSplits.count) / Double(expectedSplitLines.count)
        let precision = actualSplitLines.isEmpty ? 1.0 : Double(correctSplits.count) / Double(actualSplitLines.count)
        print("--- Segmentation ---")
        print("  precision: \(Int(precision * 100))% (\(correctSplits.count)/\(actualSplitLines.count) split predictions correct)")
        print("  recall: \(Int(recall * 100))% (\(correctSplits.count)/\(expectedSplitLines.count) expected splits found)")

        // §10 exit criterion for Milestone 0. Expected to fail until U0-8 iterates the rules to
        // close the gap — do not raise/lower this to make the suite pass; fix the engine instead.
        #expect(accuracy >= 0.9, "overall accuracy \(Int(accuracy * 100))% is below the §10 target of 90%")
    }

    // Milestone 7 (CG-2): threshold-calibration tooling. Diagnostic only — see the comment above
    // `ConfidenceSample` for why this doesn't (yet) replace the app's fixed threshold.
    @Test
    func confidenceGateCalibration() {
        let samples = calibrationSamples()
        print("--- Confidence gate calibration (CG-2, diagnostic only — not yet wired into the app) ---")
        print(describeCalibration("overall", samples))

        var byLanguage: [String: [ConfidenceSample]] = [:]
        for sample in samples { byLanguage[sample.language, default: []].append(sample) }
        for language in byLanguage.keys.sorted() {
            print(describeCalibration(language, byLanguage[language]!))
        }
    }

    // Category is deliberately excluded from the scored corpus (see ExtractionCorpus.swift's own
    // policy comment) — verified directly here instead of being shoehorned into ExpectedTask.
    @Test
    func compoundGermanCategoryIsDetected() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("arzttermin später, muss an mein rezept denken", referenceDate: corpusToday)
        #expect(tasks.first?.category == .health)
    }

    // Real-device feedback (2026-07-02): "adjust the laptop and then inform Martin about it"
    // should split into two dependent steps, not two unrelated tasks — "and then"/"und dann"
    // marks the split as sequential, and both resulting tasks share a groupID (not part of the
    // scored corpus shape, so checked directly here).
    @Test
    func sequentialConnectorLinksSplitTasks() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("need to adjust the laptop and then inform martin about it", referenceDate: corpusToday)
        // Guarded rather than asserted directly: an out-of-bounds tasks[1] access on a failed
        // split would trap and abort the whole test binary before overallAccuracyMeetsTarget()
        // ever runs — exactly what happened the first time this test was written.
        guard tasks.count == 2 else {
            Issue.record("expected the line to split into 2 tasks, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[0].groupID != nil)
        #expect(tasks[0].groupID == tasks[1].groupID)
        #expect(tasks[0].sequenceIndex == 0)
        #expect(tasks[1].sequenceIndex == 1)
        #expect(tasks[1].title == "Inform martin about it")
    }

    @Test
    func plainConjunctionDoesNotLinkSplitTasks() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("buy milk and call the dentist", referenceDate: corpusToday)
        guard tasks.count == 2 else {
            Issue.record("expected the line to split into 2 tasks, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[0].groupID == nil)
        #expect(tasks[1].groupID == nil)
    }

    // MARK: Feedback round 3 — place and details are outside ExpectedTask's scored shape
    // (§10 scores title/date/time/split/priority only), so they're verified here directly.

    @Test
    func placeExtractedFromDestination() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("i need to go to the hospital tomorrow", referenceDate: corpusToday)
        #expect(tasks.first?.place == "Hospital")
    }

    @Test
    func placeExtractedFromKeyword() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("arzttermin morgen", referenceDate: corpusToday)
        #expect(tasks.first?.place == "Arzt")
    }

    @Test
    func detailClauseAttachedNotSplit() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("go to the doctor and take my recipes with me", referenceDate: corpusToday)
        guard tasks.count == 1 else {
            Issue.record("expected a single task with details, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[0].details?.lowercased().contains("recipes") == true)
    }

    @Test
    func verblessContinuationBecomesDetail() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("arzttermin später, muss an mein rezept denken und an meine überweisung", referenceDate: corpusToday)
        guard tasks.count == 1 else {
            Issue.record("expected a single task with details, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[0].title == "Arzttermin")
        #expect(tasks[0].details?.lowercased().contains("rezept") == true)
        #expect(tasks[0].details?.lowercased().contains("überweisung") == true)
    }

    @Test
    func coordinatedObjectsStayInTitle() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("buy eggs and bread", referenceDate: corpusToday)
        guard tasks.count == 1 else {
            Issue.record("expected a single task, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[0].title == "Buy eggs and bread")
        #expect(tasks[0].details == nil)
    }

    // MARK: Feedback round 3 — vague time-of-day and "later" offset. timeOfDay isn't part of
    // ExpectedTask's scored shape (dueTime specifically staying nil for vague words IS scored,
    // via the corpus cases above), so the qualitative label itself is checked here directly.

    @Test
    func vagueTimeOfDaySetsLabelNotDueTime() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("shopping tomorrow morning", referenceDate: corpusToday)
        guard let task = tasks.first else {
            Issue.record("expected at least one task")
            return
        }
        #expect(task.dueTime == nil)
        #expect(task.timeOfDay == "Morning")
        #expect(task.dueDate == offsetDate(1))
    }

    @Test
    func vagueTimeOfDayDoesNotCollideWithOrdinaryTitleUse() {
        // The exact regression this test guards: bare "morning" as an ordinary word in a title
        // ("morning run") must NOT be treated as a time signal — only date-anchored phrasing
        // ("tomorrow morning") should be.
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("morning run tomorrow", referenceDate: corpusToday)
        guard let task = tasks.first else {
            Issue.record("expected at least one task")
            return
        }
        #expect(task.title == "Morning run")
        #expect(task.timeOfDay == nil)
    }

    @Test
    func germanVagueTimeOfDaySetsLabel() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("morgen baumarkt einkaufen und abends zur wohnung streichen", referenceDate: corpusToday)
        guard tasks.count == 2 else {
            Issue.record("expected 2 tasks, got \(tasks.count): \(tasks)")
            return
        }
        #expect(tasks[1].dueTime == nil)
        #expect(tasks[1].timeOfDay == "Abends")
    }

    @Test
    func laterResolvesToSixHourOffset() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("later call the bank", referenceDate: corpusToday)
        guard let task = tasks.first else {
            Issue.record("expected at least one task")
            return
        }
        let expected = corpusToday.addingTimeInterval(6 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        #expect(task.dueTime == formatter.string(from: expected))
    }

    // MARK: Feedback round 5 — address/street-name place detection ("Greenwood Avenue" isn't in
    // any fixed keyword list; recognized by shape — "at/on <words> <street-type word>" — instead).

    @Test
    func addressStreetNameBecomesPlace() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("meeting at greenwood avenue tomorrow morning", referenceDate: corpusToday)
        guard let task = tasks.first else {
            Issue.record("expected at least one task")
            return
        }
        #expect(task.place == "Greenwood Avenue")
        #expect(task.dueTime == nil)
        #expect(task.timeOfDay == "Morning")
        #expect(task.dueDate == offsetDate(1))
    }

    @Test
    func germanCompoundStreetNameBecomesPlace() {
        let service = RuleBasedExtractionService.shared
        let tasks = service.extractLine("termin an der bahnhofstraße morgen", referenceDate: corpusToday)
        guard let task = tasks.first else {
            Issue.record("expected at least one task")
            return
        }
        #expect(task.place == "Bahnhofstraße")
    }
}
