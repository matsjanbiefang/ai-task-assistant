import Foundation
import NaturalLanguage

// MARK: - Schema

enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

enum TaskCategory: String, Codable, CaseIterable, Sendable {
    case work, personal, health, shopping, finance, other
}

struct ExtractedTask: Sendable {
    var title: String
    var dueDate: String?      // ISO 8601 YYYY-MM-DD, local calendar day
    var dueTime: String?      // HH:MM, 24h
    var priority: TaskPriority?
    var category: TaskCategory?
    var dateConfidence: Double
}

// MARK: - Per-language rule table (prd-update-02.md §2)
//
// Each supported language gets its own hand-written table of the phrases NSDataDetector doesn't
// reliably cover for that language (relative dates, weekday phrasing, time phrases, priority and
// category keywords, the word for "and", and imperative-verb signals for line splitting).
// `RuleBasedExtractionService.languageTables` is the single place new languages get added —
// everything else in this file is generic engine code that operates on whichever tables are
// selected for a given line.

struct WeekdayPhraseRule: Sendable {
    let pattern: String   // exactly one capture group: the weekday name
    let skipToday: Bool   // true = "next <weekday>" semantics; false = nearest occurrence including today
    let confidence: Double
}

struct LanguageRules: Sendable {
    let code: String
    let weekdayNames: [String: Int]              // lowercase name -> Calendar weekday (1=Sun...7=Sat)
    let todayWords: [String]
    let tomorrowWords: [String]
    let dayAfterTomorrowWords: [String]
    let numberWords: [String: Int]                // spelled-out small numbers used by the two patterns below
    let inDaysPattern: String?                    // regex, capture group 1 = number token (digits or a numberWords key)
    let inWeeksPattern: String?
    let weekdayPhraseRules: [WeekdayPhraseRule]    // ordered — more specific patterns (e.g. "next <weekday>") before bare weekday
    let nextWeekPattern: String?
    let timePattern: String?                      // capture group 1 = hour, group 2 = optional minute
    let timeOfDayWords: [String: String]           // colloquial time-of-day word -> fixed "HH:mm" (e.g. German "mittags" -> "12:00")
    let priorityPrefixes: [(pattern: String, priority: TaskPriority)]
    let categoryKeywords: [TaskCategory: [String]]
    let connectorWords: [String]                  // leftover words to trim from title edges after stripping a date phrase
    let conjunctionWords: [String]                // words meaning "and", used for line splitting
    let imperativeVerbs: Set<String>               // first-word check for splitting
    let verbSuffixes: [String]                     // last-word suffix check for splitting (e.g. German/Dutch "-en", Polish "-ć")
}

// MARK: - Service
//
// Rules-based extraction per prd-update-01.md §1 / prd-update-02.md §2: no bundled/downloaded
// model, runs on every device. NSDataDetector is the universal base layer (it understands a
// surprising amount across locales — e.g. German "15 Uhr" — not just English). Each language's
// `LanguageRules` table fills that language's specific gaps, tried before the NSDataDetector
// fallback. The primary language (set once during onboarding, prd-update-02.md §3) is tried
// first; the per-line `NLLanguageRecognizer` guess is tried second, so mixed-language lines still
// resolve without requiring per-line detection to carry the whole burden.

struct RuleBasedExtractionService: Sendable {
    static let shared = RuleBasedExtractionService()

    private static let dataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    func extract(from input: String, referenceDate: Date = .now, primaryLanguageCode: String = "en") -> [ExtractedTask] {
        input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { extractLine($0, referenceDate: referenceDate, primaryLanguageCode: primaryLanguageCode) }
    }

    func extractLine(_ line: String, referenceDate: Date = .now, primaryLanguageCode: String = "en") -> [ExtractedTask] {
        // Language is re-detected per sub-line after splitting, not once for the whole line —
        // a run-on line can genuinely mix languages either side of "and"/"und"/etc., and each
        // half deserves its own best-guess candidate list for date/priority/category matching.
        // The whole-line guess is still what drives the split decision itself, since we don't
        // know the sub-lines yet at that point.
        let splitRulesList = candidateRules(for: line, primaryLanguageCode: primaryLanguageCode)
        let subLines = splitConjunctions(line, rulesList: splitRulesList)

        // A run-on line usually states its date once, up front — "shopping tomorrow and painting
        // in the evening" means both happen tomorrow, not that the second clause has no date at
        // all. A later clause with no date of its own inherits the nearest earlier clause's date.
        var carryDate: (dueDate: String, confidence: Double)?
        var tasks: [ExtractedTask] = []
        for subLine in subLines {
            let rulesList = candidateRules(for: subLine, primaryLanguageCode: primaryLanguageCode)
            var task = buildTask(from: subLine, referenceDate: referenceDate, rulesList: rulesList)
            if task.dueDate == nil, let carryDate {
                task.dueDate = carryDate.dueDate
                task.dateConfidence = carryDate.confidence
            } else if let date = task.dueDate {
                carryDate = (date, task.dateConfidence)
            }
            tasks.append(task)
        }
        return tasks
    }

    private func candidateRules(for line: String, primaryLanguageCode: String) -> [LanguageRules] {
        var codes = [primaryLanguageCode]
        let detected = detectLanguage(line).rawValue
        if detected != primaryLanguageCode { codes.append(detected) }
        return codes.compactMap { Self.languageTables[$0] }
    }

    // MARK: - Per-sub-line task assembly

    private func buildTask(from rawSubLine: String, referenceDate: Date, rulesList: [LanguageRules]) -> ExtractedTask {
        var text = rawSubLine

        var priority: TaskPriority?
        (text, priority) = stripBangPriority(text)
        if priority == nil {
            for rules in rulesList {
                guard let (remaining, matched) = applyPriorityKeywords(text, rules: rules) else { continue }
                text = remaining
                priority = matched
                break
            }
        }

        var category: TaskCategory?
        for rules in rulesList {
            if let matched = applyCategoryKeywords(text, rules: rules) {
                category = matched
                break
            }
        }

        var dueDate: String?
        var dueTime: String?
        var confidence = 1.0
        var rangesToStrip: [Range<String.Index>] = []
        var dateFound = false

        for rules in rulesList {
            guard let match = customDateMatch(in: text, referenceDate: referenceDate, rules: rules) else { continue }
            dueDate = isoDate(match.date)
            confidence = match.confidence
            rangesToStrip.append(match.range)
            dateFound = true
            break
        }
        if !dateFound, let match = englishDateMatch(in: text) {
            dueDate = isoDate(match.date)
            dueTime = match.time
            confidence = match.confidence
            rangesToStrip.append(match.range)
            dateFound = true
        }

        if dueTime == nil {
            for rules in rulesList {
                guard let timeMatch = anyTimeMatch(in: text, rules: rules) else { continue }
                dueTime = timeMatch.time
                rangesToStrip.append(timeMatch.range)
                break
            }
        }

        let stripped = removeRanges(rangesToStrip, from: text)
        let title = cleanTitle(stripped, fallback: rawSubLine, rulesList: rulesList)

        return ExtractedTask(
            title: title,
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            category: category,
            dateConfidence: dateFound ? confidence : 1.0
        )
    }

    // MARK: - Language detection (§2)

    private func detectLanguage(_ text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Line splitting on conjunctions (§3)

    private func splitConjunctions(_ line: String, rulesList: [LanguageRules]) -> [String] {
        let conjunctions = Set(rulesList.flatMap(\.conjunctionWords))
        for word in conjunctions {
            let separator = " \(word) "
            guard let range = line.range(of: separator, options: .caseInsensitive) else { continue }
            let before = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard before.split(separator: " ").count >= 2,
                  after.split(separator: " ").count >= 2,
                  containsVerb(before, rulesList: rulesList), containsVerb(after, rulesList: rulesList) else { continue }
            return [before, after]
        }
        return [line]
    }

    // Curated per-language verb signals are checked before NLTagger, which is unreliable on 2-3
    // word context-free imperative fragments ("call max", "book the conference room") — it tends
    // to default ambiguous words to their more common noun sense.
    private func containsVerb(_ text: String, rulesList: [LanguageRules]) -> Bool {
        let words = text.split(separator: " ").map { $0.lowercased() }
        guard let first = words.first, let last = words.last else { return false }
        for rules in rulesList {
            if rules.imperativeVerbs.contains(first) { return true }
            if last.count >= 4, rules.verbSuffixes.contains(where: { !$0.isEmpty && last.hasSuffix($0) }) { return true }
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .verb { found = true; return false }
            return true
        }
        return found
    }

    // MARK: - Priority (§6 + per-language keyword signals)

    private func stripBangPriority(_ text: String) -> (String, TaskPriority?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("!") else { return (text, nil) }
        var stripped = trimmed
        while stripped.hasSuffix("!") { stripped.removeLast() }
        return (stripped.trimmingCharacters(in: .whitespaces), .high)
    }

    private func applyPriorityKeywords(_ text: String, rules: LanguageRules) -> (String, TaskPriority)? {
        let nsRange = NSRange(text.startIndex..., in: text)
        for rule in rules.priorityPrefixes {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text),
                  range.lowerBound == text.startIndex else { continue }
            return (String(text[range.upperBound...]), rule.priority)
        }
        return nil
    }

    // MARK: - Category keywords

    private func applyCategoryKeywords(_ text: String, rules: LanguageRules) -> TaskCategory? {
        let lower = text.lowercased()
        for (category, words) in rules.categoryKeywords {
            for word in words {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
                if lower.range(of: pattern, options: .regularExpression) != nil {
                    return category
                }
            }
        }
        return nil
    }

    // MARK: - Date matching

    private struct DateMatch {
        let range: Range<String.Index>
        let date: Date
        let time: String?
        let confidence: Double
    }

    private struct TimeMatch {
        let range: Range<String.Index>
        let time: String
    }

    // NSDataDetector has no public API to override its notion of "today" — it always resolves
    // relative to the real device/CI clock. Callers (and the test corpus) must treat dates it
    // finds as anchored to the actual current date, never a frozen historical one.
    private func englishDateMatch(in text: String) -> DateMatch? {
        guard let detector = Self.dataDetector else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = detector.matches(in: text, options: [], range: nsRange).first,
              let range = Range(match.range, in: text),
              let date = match.date else { return nil }

        let matchedText = String(text[range])
        let time = englishTimeString(from: date, matchedText: matchedText)
        let lineWordCount = text.split(separator: " ").count
        // A short line that's almost entirely the matched date phrase leaves an ambiguous task
        // (e.g. a bare "friday" line) — surface that with the low-confidence "unsure" state (§3, §7).
        let confidence = lineWordCount <= 2 ? 0.6 : 0.9
        return DateMatch(range: range, date: date, time: time, confidence: confidence)
    }

    private func englishTimeString(from date: Date, matchedText: String) -> String? {
        let hasTimeHint = matchedText.range(of: #"\d{1,2}(:\d{2})?\s*(am|pm)"#, options: [.regularExpression, .caseInsensitive]) != nil
            || matchedText.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
        guard hasTimeHint else { return nil }
        return formattedTime(from: date)
    }

    // Generic engine over a single language's rule table. Order: day-after-tomorrow / today /
    // tomorrow (exact words) -> "in N days/weeks" -> weekday phrases (caller orders specific
    // patterns like "next <weekday>" before the bare-weekday catch-all) -> "next week".
    private func customDateMatch(in text: String, referenceDate: Date, rules: LanguageRules) -> DateMatch? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        struct Rule {
            let pattern: String
            let confidence: Double
            let resolve: (NSTextCheckingResult, String) -> Date
        }

        func wordAlternation(_ words: [String]) -> String? {
            guard !words.isEmpty else { return nil }
            return words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        }

        func numberValue(_ match: NSTextCheckingResult, _ source: String) -> Int {
            let raw = (source as NSString).substring(with: match.range(at: 1)).lowercased()
            return Int(raw) ?? rules.numberWords[raw] ?? 1
        }

        var ruleList: [Rule] = []

        if let alt = wordAlternation(rules.dayAfterTomorrowWords) {
            ruleList.append(Rule(pattern: "\\b(\(alt))\\b", confidence: 0.9) { _, _ in
                calendar.date(byAdding: .day, value: 2, to: today)!
            })
        }
        if let alt = wordAlternation(rules.todayWords) {
            ruleList.append(Rule(pattern: "\\b(\(alt))\\b", confidence: 0.9) { _, _ in today })
        }
        if let alt = wordAlternation(rules.tomorrowWords) {
            ruleList.append(Rule(pattern: "\\b(\(alt))\\b", confidence: 0.85) { _, _ in
                calendar.date(byAdding: .day, value: 1, to: today)!
            })
        }
        if let pattern = rules.inDaysPattern {
            ruleList.append(Rule(pattern: pattern, confidence: 0.85) { match, source in
                calendar.date(byAdding: .day, value: numberValue(match, source), to: today)!
            })
        }
        if let pattern = rules.inWeeksPattern {
            ruleList.append(Rule(pattern: pattern, confidence: 0.85) { match, source in
                calendar.date(byAdding: .day, value: numberValue(match, source) * 7, to: today)!
            })
        }
        for weekdayRule in rules.weekdayPhraseRules {
            ruleList.append(Rule(pattern: weekdayRule.pattern, confidence: weekdayRule.confidence) { match, source in
                let name = (source as NSString).substring(with: match.range(at: 1)).lowercased()
                let weekday = rules.weekdayNames[name] ?? 2
                return nextOccurrence(of: weekday, from: today, calendar: calendar, skipToday: weekdayRule.skipToday)
            })
        }
        if let pattern = rules.nextWeekPattern {
            ruleList.append(Rule(pattern: pattern, confidence: 0.5) { _, _ in
                calendar.date(byAdding: .day, value: 7, to: today)!
            })
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        for rule in ruleList {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            return DateMatch(range: range, date: rule.resolve(match, text), time: nil, confidence: rule.confidence)
        }
        return nil
    }

    private func customTimeMatch(in text: String, rules: LanguageRules) -> TimeMatch? {
        guard let pattern = rules.timePattern,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else { return nil }
        let ns = text as NSString
        let hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
        var minute = 0
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
            minute = Int(ns.substring(with: match.range(at: 2))) ?? 0
        }
        return TimeMatch(range: range, time: String(format: "%02d:%02d", hour, minute))
    }

    // Colloquial time-of-day words ("mittags"/"noon", "abends"/"evening") resolve to a fixed
    // approximate clock time — less precise than an explicit "um 15 uhr"/"at 3pm", but still a
    // clear, explicit user signal that shouldn't be dropped just because no exact minute was given.
    private func timeOfDayMatch(in text: String, rules: LanguageRules) -> TimeMatch? {
        let nsRange = NSRange(text.startIndex..., in: text)
        for (word, time) in rules.timeOfDayWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            return TimeMatch(range: range, time: time)
        }
        return nil
    }

    private func anyTimeMatch(in text: String, rules: LanguageRules) -> TimeMatch? {
        customTimeMatch(in: text, rules: rules) ?? timeOfDayMatch(in: text, rules: rules)
    }

    // MARK: - Inline highlight support (§3 — notes-editor visual affordance, not scored)

    // Pattern strings only, no date resolution — deliberately mirrors the rule construction in
    // `customDateMatch`'s `ruleList`. If a new kind of date rule is added there, add its pattern
    // here too, or that phrase will parse correctly but stop getting highlighted.
    private func datePatternStrings(for rules: LanguageRules) -> [String] {
        func wordAlternation(_ words: [String]) -> String? {
            guard !words.isEmpty else { return nil }
            return words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        }

        var patterns: [String] = []
        if let alt = wordAlternation(rules.dayAfterTomorrowWords) { patterns.append("\\b(\(alt))\\b") }
        if let alt = wordAlternation(rules.todayWords) { patterns.append("\\b(\(alt))\\b") }
        if let alt = wordAlternation(rules.tomorrowWords) { patterns.append("\\b(\(alt))\\b") }
        if let pattern = rules.inDaysPattern { patterns.append(pattern) }
        if let pattern = rules.inWeeksPattern { patterns.append(pattern) }
        patterns.append(contentsOf: rules.weekdayPhraseRules.map(\.pattern))
        if let pattern = rules.nextWeekPattern { patterns.append(pattern) }
        if let pattern = rules.timePattern { patterns.append(pattern) }
        if let alt = wordAlternation(Array(rules.timeOfDayWords.keys)) { patterns.append("\\b(\(alt))\\b") }
        return patterns
    }

    /// Ranges in `line` that look like date/time phrases, for the notes editor's inline highlight
    /// (§3). Purely a visual affordance — not used for extraction correctness/scoring. Reuses the
    /// same per-language patterns extraction matches against, plus `NSDataDetector`, so highlights
    /// stay honest about what the engine actually detects.
    func highlightRanges(in line: String, primaryLanguageCode: String) -> [Range<String.Index>] {
        let rulesList = candidateRules(for: line, primaryLanguageCode: primaryLanguageCode)
        let nsRange = NSRange(line.startIndex..., in: line)
        var ranges: [Range<String.Index>] = []

        for rules in rulesList {
            for pattern in datePatternStrings(for: rules) {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                for match in regex.matches(in: line, range: nsRange) {
                    if let range = Range(match.range, in: line) { ranges.append(range) }
                }
            }
        }
        if let detector = Self.dataDetector {
            for match in detector.matches(in: line, options: [], range: nsRange) {
                if let range = Range(match.range, in: line) { ranges.append(range) }
            }
        }
        return mergeOverlappingRanges(ranges)
    }

    private func mergeOverlappingRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - Helpers

    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func removeRanges(_ ranges: [Range<String.Index>], from text: String) -> String {
        var accepted: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = accepted.last, range.lowerBound < last.upperBound { continue }
            accepted.append(range)
        }
        var result = text
        for range in accepted.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    private static let universalConnectors: Set<String> = [",", "-", "–", "—", ":", ";", "."]

    private func cleanTitle(_ text: String, fallback: String, rulesList: [LanguageRules]) -> String {
        let connectors = Self.universalConnectors.union(rulesList.flatMap(\.connectorWords).map { $0.lowercased() })

        var cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,–—-:;."))

        var words = cleaned.split(separator: " ").map(String.init)
        while let first = words.first, connectors.contains(first.lowercased()) {
            words.removeFirst()
        }
        while let last = words.last, connectors.contains(last.lowercased()) {
            words.removeLast()
        }
        cleaned = words.joined(separator: " ")

        guard !cleaned.isEmpty else {
            let trimmedFallback = fallback.trimmingCharacters(in: .whitespaces)
            return trimmedFallback.prefix(1).uppercased() + trimmedFallback.dropFirst()
        }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}

private func nextOccurrence(of weekday: Int, from referenceDate: Date, calendar: Calendar, skipToday: Bool) -> Date {
    let todayWeekday = calendar.component(.weekday, from: referenceDate)
    var delta = (weekday - todayWeekday + 7) % 7
    if delta == 0 && skipToday { delta = 7 }
    return calendar.date(byAdding: .day, value: delta, to: referenceDate)!
}

// MARK: - Language tables (prd-update-02.md §4 — Batch 0: en/de, Batch 1: fr/es/it/pt/nl/pl)

extension RuleBasedExtractionService {
    static let languageTables: [String: LanguageRules] = {
        var tables: [String: LanguageRules] = [:]
        for rules in [englishRules, germanRules, frenchRules, spanishRules, italianRules, portugueseRules, dutchRules, polishRules] {
            tables[rules.code] = rules
        }
        return tables
    }()

    private static let punctSep = #"[:\-–—]?\s*"#

    private static let englishRules = LanguageRules(
        code: "en",
        weekdayNames: [:],
        todayWords: ["later"],
        tomorrowWords: [],
        dayAfterTomorrowWords: [],
        numberWords: ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10],
        inDaysPattern: #"\bin\s+(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+days?\b"#,
        inWeeksPattern: #"\bin\s+(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+weeks?\b"#,
        weekdayPhraseRules: [],
        nextWeekPattern: #"\bnext week\b"#,
        timePattern: nil,
        timeOfDayWords: ["morning": "08:00", "noon": "12:00", "midday": "12:00", "afternoon": "15:00", "evening": "19:00", "night": "22:00"],
        priorityPrefixes: [
            (#"^(urgent|asap|important)\b\#(punctSep)"#, .high),
            (#"^(high priority)\b\#(punctSep)"#, .high),
            (#"^(low priority|whenever)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["work", "meeting", "deadline", "project", "client", "office", "kickoff"],
            .health: ["doctor", "dentist", "gym", "workout", "appointment", "fitness", "membership"],
            .shopping: ["buy", "groceries", "shopping", "store"],
            .finance: ["pay", "bill", "invoice", "bank", "tax"],
        ],
        connectorWords: ["on", "at", "by", "for", "this", "next", "am"],
        conjunctionWords: ["and"],
        imperativeVerbs: [
            "call", "buy", "finish", "deploy", "write", "prepare", "book", "pay", "clean", "reply",
            "send", "schedule", "review", "fix", "renew", "cancel", "water", "tidy", "return", "pick",
            "think", "do", "get", "make", "take", "bring", "check", "confirm", "submit", "order",
            "drop", "pack", "email", "text", "message", "update", "install", "download", "upload",
        ],
        verbSuffixes: []
    )

    private static let germanRules = LanguageRules(
        code: "de",
        weekdayNames: [
            "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
            "donnerstag": 5, "freitag": 6, "samstag": 7, "sonnabend": 7,
        ],
        todayWords: ["heute", "später"],
        tomorrowWords: ["morgen"],
        dayAfterTomorrowWords: ["übermorgen"],
        numberWords: [:],
        inDaysPattern: #"\bin\s+(\d+)\s+tagen\b"#,
        inWeeksPattern: #"\bin\s+(\d+)\s+wochen\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\b(?:nächsten|nächste|kommenden|kommende)\s+(sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend)\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(?:diesen|diese)\s+(sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bnächste\s+woche\b"#,
        timePattern: #"\bum\s+(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b"#,
        timeOfDayWords: ["morgens": "08:00", "vormittags": "10:00", "mittags": "12:00", "nachmittags": "15:00", "abends": "19:00", "nachts": "22:00"],
        priorityPrefixes: [
            (#"^(dringend|wichtig)\b\#(punctSep)"#, .high),
            (#"^(hohe priorität)\b\#(punctSep)"#, .high),
            (#"^(niedrige priorität)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["büro", "arbeit", "projekt", "kickoff"],
            .health: ["arzt", "zahnarzt", "termin", "fitness"],
            .shopping: ["kaufen", "einkaufen"],
            .finance: ["rechnung", "bezahlen", "steuer"],
        ],
        connectorWords: ["am", "um", "den", "der", "die", "das", "für", "zu", "zur"],
        conjunctionWords: ["und"],
        imperativeVerbs: [],
        verbSuffixes: ["en"]
    )

    private static let frenchRules = LanguageRules(
        code: "fr",
        weekdayNames: [
            "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4,
            "jeudi": 5, "vendredi": 6, "samedi": 7,
        ],
        todayWords: ["aujourd'hui", "plus tard"],
        tomorrowWords: ["demain"],
        dayAfterTomorrowWords: ["après-demain"],
        numberWords: ["un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10],
        inDaysPattern: #"\bdans\s+(\d+|un|deux|trois|quatre|cinq|six|sept|huit|neuf|dix)\s+jours?\b"#,
        inWeeksPattern: #"\bdans\s+(\d+|un|deux|trois|quatre|cinq|six|sept|huit|neuf|dix)\s+semaines?\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\b(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+prochain\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\bce\s+(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bsemaine\s+prochaine\b"#,
        timePattern: #"\bà\s+(\d{1,2})\s*h\s*(\d{2})?\b"#,
        timeOfDayWords: ["matin": "08:00", "midi": "12:00", "après-midi": "15:00", "soir": "19:00", "nuit": "22:00"],
        priorityPrefixes: [
            (#"^(urgent|asap|important|importante|priorité haute|haute priorité)\b\#(punctSep)"#, .high),
            (#"^(priorité basse|basse priorité|faible priorité)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["travail", "réunion", "projet", "client", "bureau"],
            .health: ["médecin", "dentiste", "rendez-vous", "gym", "santé"],
            .shopping: ["acheter", "courses", "magasin"],
            .finance: ["payer", "facture", "banque", "impôts"],
        ],
        connectorWords: ["à", "de", "le", "la"],
        conjunctionWords: ["et"],
        imperativeVerbs: [
            "appeler", "acheter", "finir", "préparer", "réserver", "payer", "nettoyer", "répondre",
            "envoyer", "planifier", "réviser", "réparer", "renouveler", "annuler", "arroser",
            "ranger", "rendre", "prendre", "penser", "faire", "apporter", "vérifier", "confirmer",
            "soumettre", "commander",
        ],
        verbSuffixes: []
    )

    private static let spanishRules = LanguageRules(
        code: "es",
        weekdayNames: [
            "domingo": 1, "lunes": 2, "martes": 3, "miércoles": 4,
            "jueves": 5, "viernes": 6, "sábado": 7,
        ],
        todayWords: ["hoy", "más tarde"],
        tomorrowWords: ["mañana"],
        dayAfterTomorrowWords: ["pasado mañana"],
        numberWords: ["un": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10],
        inDaysPattern: #"\ben\s+(\d+|un|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)\s+días?\b"#,
        inWeeksPattern: #"\ben\s+(\d+|un|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)\s+semanas?\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\bpróximo\s+(lunes|martes|miércoles|jueves|viernes|sábado|domingo)\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\beste\s+(lunes|martes|miércoles|jueves|viernes|sábado|domingo)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(lunes|martes|miércoles|jueves|viernes|sábado|domingo)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bpróxima\s+semana\b"#,
        timePattern: #"\ba\s+las\s+(\d{1,2})(?::(\d{2}))?\b"#,
        // "mañana" is already the word for "tomorrow" — the multi-word "por la mañana" form is
        // used here for "in the morning" instead of the bare word, to avoid colliding with it.
        timeOfDayWords: ["por la mañana": "08:00", "mediodía": "12:00", "por la tarde": "15:00", "por la noche": "20:00"],
        priorityPrefixes: [
            (#"^(urgente|asap|importante|alta prioridad|prioridad alta)\b\#(punctSep)"#, .high),
            (#"^(baja prioridad|prioridad baja)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["trabajo", "reunión", "proyecto", "cliente", "oficina"],
            .health: ["médico", "dentista", "cita", "gimnasio", "salud"],
            .shopping: ["comprar", "compras", "tienda"],
            .finance: ["pagar", "factura", "banco", "impuestos"],
        ],
        connectorWords: ["a", "el", "la", "las"],
        conjunctionWords: ["y"],
        imperativeVerbs: [
            "llamar", "comprar", "terminar", "preparar", "reservar", "pagar", "limpiar", "responder",
            "enviar", "programar", "revisar", "arreglar", "renovar", "cancelar", "regar", "ordenar",
            "devolver", "recoger", "pensar", "hacer", "traer", "comprobar", "confirmar",
        ],
        verbSuffixes: []
    )

    private static let italianRules = LanguageRules(
        code: "it",
        weekdayNames: [
            "domenica": 1, "lunedì": 2, "martedì": 3, "mercoledì": 4,
            "giovedì": 5, "venerdì": 6, "sabato": 7,
        ],
        todayWords: ["oggi", "più tardi"],
        tomorrowWords: ["domani"],
        dayAfterTomorrowWords: ["dopodomani"],
        numberWords: ["un": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9, "dieci": 10],
        inDaysPattern: #"\btra\s+(\d+|un|due|tre|quattro|cinque|sei|sette|otto|nove|dieci)\s+giorni\b"#,
        inWeeksPattern: #"\btra\s+(\d+|un|due|tre|quattro|cinque|sei|sette|otto|nove|dieci)\s+settimane\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\b(lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica)\s+prossimo\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\bquesto\s+(lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bprossima\s+settimana\b"#,
        timePattern: #"\balle\s+(\d{1,2})(?::(\d{2}))?\b"#,
        timeOfDayWords: ["mattina": "08:00", "mezzogiorno": "12:00", "pomeriggio": "15:00", "sera": "19:00", "notte": "22:00"],
        priorityPrefixes: [
            (#"^(urgente|asap|importante|alta priorità)\b\#(punctSep)"#, .high),
            (#"^(bassa priorità)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["lavoro", "riunione", "progetto", "cliente", "ufficio"],
            .health: ["medico", "dentista", "appuntamento", "palestra", "salute"],
            .shopping: ["comprare", "spesa", "negozio"],
            .finance: ["pagare", "fattura", "banca", "tasse"],
        ],
        connectorWords: ["a", "il", "la", "lo"],
        conjunctionWords: ["e"],
        imperativeVerbs: [
            "chiamare", "comprare", "finire", "preparare", "prenotare", "pagare", "pulire",
            "rispondere", "inviare", "programmare", "rivedere", "riparare", "rinnovare",
            "cancellare", "annaffiare", "riordinare", "restituire", "ritirare", "pensare", "fare",
            "portare", "controllare", "confermare",
        ],
        verbSuffixes: []
    )

    private static let portugueseRules = LanguageRules(
        code: "pt",
        weekdayNames: [
            "domingo": 1, "segunda": 2, "terça": 3, "quarta": 4,
            "quinta": 5, "sexta": 6, "sábado": 7,
        ],
        todayWords: ["hoje", "mais tarde"],
        tomorrowWords: ["amanhã"],
        dayAfterTomorrowWords: ["depois de amanhã"],
        numberWords: ["um": 1, "dois": 2, "três": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8, "nove": 9, "dez": 10],
        inDaysPattern: #"\bem\s+(\d+|um|dois|três|quatro|cinco|seis|sete|oito|nove|dez)\s+dias\b"#,
        inWeeksPattern: #"\bem\s+(\d+|um|dois|três|quatro|cinco|seis|sete|oito|nove|dez)\s+semanas\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\bpróxim[oa]\s+(segunda|terça|quarta|quinta|sexta|sábado|domingo)\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\best[ae]\s+(segunda|terça|quarta|quinta|sexta|sábado|domingo)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(segunda|terça|quarta|quinta|sexta|sábado|domingo)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bpróxima\s+semana\b"#,
        timePattern: #"\bàs\s+(\d{1,2})[h:](\d{2})?\b"#,
        timeOfDayWords: ["manhã": "08:00", "meio-dia": "12:00", "tarde": "15:00", "noite": "19:00"],
        priorityPrefixes: [
            (#"^(urgente|asap|importante|alta prioridade)\b\#(punctSep)"#, .high),
            (#"^(baixa prioridade)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["trabalho", "reunião", "projeto", "cliente", "escritório"],
            .health: ["médico", "dentista", "consulta", "academia", "saúde"],
            .shopping: ["comprar", "compras", "loja"],
            .finance: ["pagar", "fatura", "banco", "impostos"],
        ],
        connectorWords: ["a", "o", "às", "de"],
        conjunctionWords: ["e"],
        imperativeVerbs: [
            "ligar", "comprar", "terminar", "preparar", "reservar", "pagar", "limpar", "responder",
            "enviar", "agendar", "revisar", "consertar", "renovar", "cancelar", "regar", "arrumar",
            "devolver", "buscar", "pensar", "fazer", "trazer", "verificar", "confirmar",
        ],
        verbSuffixes: []
    )

    private static let dutchRules = LanguageRules(
        code: "nl",
        weekdayNames: [
            "zondag": 1, "maandag": 2, "dinsdag": 3, "woensdag": 4,
            "donderdag": 5, "vrijdag": 6, "zaterdag": 7,
        ],
        todayWords: ["vandaag", "later"],
        tomorrowWords: ["morgen"],
        dayAfterTomorrowWords: ["overmorgen"],
        numberWords: ["een": 1, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6, "zeven": 7, "acht": 8, "negen": 9, "tien": 10],
        inDaysPattern: #"\bover\s+(\d+|een|twee|drie|vier|vijf|zes|zeven|acht|negen|tien)\s+dagen\b"#,
        inWeeksPattern: #"\bover\s+(\d+|een|twee|drie|vier|vijf|zes|zeven|acht|negen|tien)\s+weken\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\bvolgende\s+(maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)\b"#, skipToday: true, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\bdeze\s+(maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)\b"#, skipToday: false, confidence: 0.85),
            WeekdayPhraseRule(pattern: #"\b(maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bvolgende\s+week\b"#,
        timePattern: #"\bom\s+(\d{1,2})(?:[:.](\d{2}))?\s*uur\b"#,
        timeOfDayWords: ["ochtend": "08:00", "middag": "12:00", "namiddag": "15:00", "avond": "19:00", "nacht": "22:00"],
        priorityPrefixes: [
            (#"^(urgent|asap|belangrijk|hoge prioriteit)\b\#(punctSep)"#, .high),
            (#"^(lage prioriteit)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["werk", "vergadering", "project", "klant", "kantoor"],
            .health: ["dokter", "tandarts", "afspraak", "sportschool", "gezondheid"],
            .shopping: ["kopen", "boodschappen", "winkel"],
            .finance: ["betalen", "factuur", "bank", "belasting"],
        ],
        connectorWords: ["op", "om", "de", "het"],
        conjunctionWords: ["en"],
        imperativeVerbs: [
            "bellen", "kopen", "afmaken", "voorbereiden", "boeken", "betalen", "schoonmaken",
            "antwoorden", "sturen", "plannen", "controleren", "repareren", "verlengen",
            "annuleren", "opruimen", "terugbrengen", "ophalen", "denken", "doen", "brengen",
            "bevestigen",
        ],
        verbSuffixes: ["en"]
    )

    private static let polishRules = LanguageRules(
        code: "pl",
        weekdayNames: [
            "niedziela": 1, "poniedziałek": 2, "wtorek": 3, "środa": 4, "środę": 4,
            "czwartek": 5, "piątek": 6, "sobota": 7, "sobotę": 7,
        ],
        todayWords: ["dziś", "dzisiaj", "później"],
        tomorrowWords: ["jutro"],
        dayAfterTomorrowWords: ["pojutrze"],
        numberWords: ["jeden": 1, "dwa": 2, "trzy": 3, "cztery": 4, "pięć": 5, "sześć": 6, "siedem": 7, "osiem": 8, "dziewięć": 9, "dziesięć": 10],
        inDaysPattern: #"\bza\s+(\d+|jeden|dwa|trzy|cztery|pięć|sześć|siedem|osiem|dziewięć|dziesięć)\s+dni\b"#,
        inWeeksPattern: #"\bza\s+(\d+|jeden|dwa|trzy|cztery|pięć|sześć|siedem|osiem|dziewięć|dziesięć)\s+tygodni\b"#,
        weekdayPhraseRules: [
            WeekdayPhraseRule(pattern: #"\bprzyszły[m]?\s+(poniedziałek|wtorek|środę|czwartek|piątek|sobotę|niedzielę)\b"#, skipToday: true, confidence: 0.75),
            WeekdayPhraseRule(pattern: #"\bw\s+t[aeo]\s+(poniedziałek|wtorek|środę|czwartek|piątek|sobotę|niedzielę)\b"#, skipToday: false, confidence: 0.7),
            WeekdayPhraseRule(pattern: #"\b(poniedziałek|wtorek|środa|czwartek|piątek|sobota|niedziela)\b"#, skipToday: false, confidence: 0.6),
        ],
        nextWeekPattern: #"\bprzyszłym\s+tygodniu\b"#,
        timePattern: #"\bo\s+godzinie\s+(\d{1,2})(?::(\d{2}))?\b"#,
        timeOfDayWords: ["rano": "08:00", "południe": "12:00", "popołudniu": "15:00", "wieczorem": "19:00", "noc": "22:00"],
        priorityPrefixes: [
            (#"^(pilne|asap|ważne|wysoki priorytet)\b\#(punctSep)"#, .high),
            (#"^(niski priorytet)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["praca", "spotkanie", "projekt", "klient", "biuro"],
            .health: ["lekarz", "dentysta", "wizyta", "siłownia", "zdrowie"],
            .shopping: ["kupić", "zakupy", "sklep"],
            .finance: ["zapłacić", "faktura", "bank", "podatki"],
        ],
        connectorWords: ["w", "na", "o"],
        conjunctionWords: ["i"],
        imperativeVerbs: [
            "zadzwonić", "kupić", "skończyć", "przygotować", "zarezerwować", "zapłacić",
            "posprzątać", "odpowiedzieć", "wysłać", "zaplanować", "sprawdzić", "naprawić",
            "odnowić", "anulować", "podlać", "zwrócić", "odebrać", "pomyśleć", "zrobić",
            "przynieść", "potwierdzić",
        ],
        verbSuffixes: ["ć"]
    )
}
