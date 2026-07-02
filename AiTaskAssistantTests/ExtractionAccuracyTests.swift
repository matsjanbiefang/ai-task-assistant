import Testing
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

/// Runs every corpus case and returns per-line pass/fail, tagged with the case's focus category.
private func scoreCorpus() -> [(caseID: Int, focus: CorpusFocus, lineIndex: Int, passed: Bool)] {
    let service = RuleBasedExtractionService.shared
    var results: [(caseID: Int, focus: CorpusFocus, lineIndex: Int, passed: Bool)] = []
    for testCase in extractionCorpus {
        let lines = nonEmptyLines(testCase.input)
        for (index, line) in lines.enumerated() {
            let actual = service.extractLine(line, referenceDate: corpusToday)
            let expected = index < testCase.expected.count ? testCase.expected[index] : []
            results.append((testCase.id, testCase.focus, index, matches(actual, expected)))
        }
    }
    return results
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
        let correct = results.filter(\.passed).count
        let accuracy = total == 0 ? 0 : Double(correct) / Double(total)

        var byFocus: [CorpusFocus: (correct: Int, total: Int)] = [:]
        for result in results {
            var bucket = byFocus[result.focus] ?? (0, 0)
            bucket.total += 1
            if result.passed { bucket.correct += 1 }
            byFocus[result.focus] = bucket
        }

        print("=== Extraction accuracy: \(correct)/\(total) (\(Int(accuracy * 100))%) ===")
        for focus in CorpusFocus.allCases where byFocus[focus] != nil {
            let bucket = byFocus[focus]!
            let pct = bucket.total == 0 ? 0 : Int(Double(bucket.correct) / Double(bucket.total) * 100)
            print("  \(focus.rawValue): \(bucket.correct)/\(bucket.total) (\(pct)%)")
        }

        // §10 exit criterion for Milestone 0. Expected to fail until U0-8 iterates the rules to
        // close the gap — do not raise/lower this to make the suite pass; fix the engine instead.
        #expect(accuracy >= 0.9, "overall accuracy \(Int(accuracy * 100))% is below the §10 target of 90%")
    }
}
