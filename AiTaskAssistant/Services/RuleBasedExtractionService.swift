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

// MARK: - Service
//
// Rules-based extraction per prd-update-01.md §1: no bundled/downloaded model, runs on every
// device. NSDataDetector covers English-style date phrases; a hand-written German rule set covers
// colloquial German date phrases NSDataDetector does not reliably parse (§2). Both are always
// attempted per line — order is chosen by NLLanguageRecognizer's per-line guess, but the other
// still runs as a fallback so a wrong language guess never silently drops a date (§2).

struct RuleBasedExtractionService: Sendable {
    static let shared = RuleBasedExtractionService()

    private static let dataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    func extract(from input: String, referenceDate: Date = .now) -> [ExtractedTask] {
        input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { extractLine($0, referenceDate: referenceDate) }
    }

    func extractLine(_ line: String, referenceDate: Date = .now) -> [ExtractedTask] {
        splitConjunctions(line).map { buildTask(from: $0, referenceDate: referenceDate) }
    }

    // MARK: - Per-sub-line task assembly

    private func buildTask(from rawSubLine: String, referenceDate: Date) -> ExtractedTask {
        var text = rawSubLine

        var priority: TaskPriority?
        (text, priority) = stripBangPriority(text)
        if priority == nil {
            (text, priority) = applyPriorityKeywords(text)
        }

        var category: TaskCategory?
        category = applyCategoryKeywords(text)

        let language = detectLanguage(text)
        var dueDate: String?
        var dueTime: String?
        var confidence = 1.0
        var rangesToStrip: [Range<String.Index>] = []

        let germanFirst = language == .german

        func tryGerman() -> Bool {
            guard let match = germanDateMatch(in: text, referenceDate: referenceDate) else { return false }
            dueDate = isoDate(match.date)
            confidence = match.confidence
            rangesToStrip.append(match.range)
            return true
        }
        func tryEnglish() -> Bool {
            guard let match = englishDateMatch(in: text, referenceDate: referenceDate) else { return false }
            dueDate = isoDate(match.date)
            dueTime = match.time
            confidence = match.confidence
            rangesToStrip.append(match.range)
            return true
        }

        let dateFound = germanFirst ? (tryGerman() || tryEnglish()) : (tryEnglish() || tryGerman())

        if dueTime == nil, let timeMatch = germanTimeMatch(in: text) {
            dueTime = timeMatch.time
            rangesToStrip.append(timeMatch.range)
        }

        let stripped = removeRanges(rangesToStrip, from: text)
        let title = cleanTitle(stripped, fallback: rawSubLine)

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

    private func splitConjunctions(_ line: String) -> [String] {
        for separator in [" and ", " und "] {
            guard let range = line.range(of: separator, options: .caseInsensitive) else { continue }
            let before = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard before.split(separator: " ").count >= 2,
                  after.split(separator: " ").count >= 2,
                  containsVerb(before), containsVerb(after) else { continue }
            return [before, after]
        }
        return [line]
    }

    // NLTagger's POS model is unreliable on 2-3 word context-free imperative fragments ("call
    // max", "book the conference room") — it tends to default ambiguous words like "book" to
    // their more common noun sense. A curated imperative-verb list is a much stronger signal at
    // this length, checked before falling back to NLTagger.
    private static let englishImperativeVerbs: Set<String> = [
        "call", "buy", "finish", "deploy", "write", "prepare", "book", "pay", "clean", "reply",
        "send", "schedule", "review", "fix", "renew", "cancel", "water", "tidy", "return", "pick",
        "think", "do", "get", "make", "take", "bring", "check", "confirm", "submit", "order",
        "drop", "pack", "email", "text", "message", "update", "install", "download", "upload",
    ]

    private func containsVerb(_ text: String) -> Bool {
        let words = text.split(separator: " ").map { $0.lowercased() }
        if let first = words.first, Self.englishImperativeVerbs.contains(first) { return true }
        // German task notes are frequently noun-first, infinitive-last ("termin absagen") —
        // infinitives reliably end in "en", a stronger signal here than generic POS tagging.
        if let last = words.last, last.count >= 4, last.hasSuffix("en") { return true }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .verb { found = true; return false }
            return true
        }
        return found
    }

    // MARK: - Priority (§6 + keyword signals)

    private func stripBangPriority(_ text: String) -> (String, TaskPriority?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("!") else { return (text, nil) }
        var stripped = trimmed
        while stripped.hasSuffix("!") { stripped.removeLast() }
        return (stripped.trimmingCharacters(in: .whitespaces), .high)
    }

    private static let priorityPrefixes: [(pattern: String, priority: TaskPriority)] = [
        (#"^(urgent|asap|dringend)[:\-–—]?\s*"#, .high),
        (#"^(high priority|hohe priorität)[:\-–—]?\s*"#, .high),
        (#"^(low priority|niedrige priorität|whenever)[:\-–—]?\s*"#, .low),
    ]

    private func applyPriorityKeywords(_ text: String) -> (String, TaskPriority?) {
        let nsRange = NSRange(text.startIndex..., in: text)
        for rule in Self.priorityPrefixes {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text),
                  range.lowerBound == text.startIndex else { continue }
            return (String(text[range.upperBound...]), rule.priority)
        }
        return (text, nil)
    }

    // MARK: - Category keywords

    private static let categoryKeywords: [TaskCategory: [String]] = [
        .work: ["work", "meeting", "deadline", "project", "client", "office", "kickoff", "büro", "arbeit", "projekt"],
        .health: ["doctor", "dentist", "gym", "workout", "appointment", "arzt", "zahnarzt", "termin", "fitness", "membership"],
        .shopping: ["buy", "groceries", "shopping", "store", "kaufen", "einkaufen"],
        .finance: ["pay", "bill", "invoice", "bank", "rechnung", "bezahlen", "steuer", "tax"],
    ]

    private func applyCategoryKeywords(_ text: String) -> TaskCategory? {
        let lower = text.lowercased()
        for (category, words) in Self.categoryKeywords {
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

    // `referenceDate` is intentionally unused here: NSDataDetector has no public API to override
    // its notion of "today" — it always resolves relative to the real device clock. Callers (and
    // the test corpus) must treat English relative dates as anchored to the actual current date,
    // never a frozen historical one. The German rules below, being hand-written, do honor it.
    private func englishDateMatch(in text: String, referenceDate: Date) -> DateMatch? {
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

    private static let germanWeekdays: [String: Int] = [
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
        "donnerstag": 5, "freitag": 6, "samstag": 7, "sonnabend": 7,
    ]

    private func germanDateMatch(in text: String, referenceDate: Date) -> DateMatch? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let weekdayNames = Self.germanWeekdays.keys.joined(separator: "|")

        struct Rule {
            let pattern: String
            let confidence: Double
            let resolve: (NSTextCheckingResult, String) -> Date
        }

        let rules: [Rule] = [
            Rule(pattern: #"\bübermorgen\b"#, confidence: 0.9) { _, _ in
                calendar.date(byAdding: .day, value: 2, to: today)!
            },
            Rule(pattern: #"\bheute\b"#, confidence: 0.9) { _, _ in today },
            Rule(pattern: #"\bmorgen\b"#, confidence: 0.85) { _, _ in
                calendar.date(byAdding: .day, value: 1, to: today)!
            },
            Rule(pattern: #"\bin\s+(\d+)\s+tagen\b"#, confidence: 0.85) { match, source in
                let n = Int((source as NSString).substring(with: match.range(at: 1))) ?? 1
                return calendar.date(byAdding: .day, value: n, to: today)!
            },
            Rule(pattern: #"\bin\s+(\d+)\s+wochen\b"#, confidence: 0.85) { match, source in
                let n = Int((source as NSString).substring(with: match.range(at: 1))) ?? 1
                return calendar.date(byAdding: .day, value: n * 7, to: today)!
            },
            Rule(pattern: #"\b(nächsten|nächste|kommenden|kommende)\s+(\#(weekdayNames))\b"#, confidence: 0.85) { match, source in
                let name = (source as NSString).substring(with: match.range(at: 2)).lowercased()
                return nextOccurrence(of: Self.germanWeekdays[name] ?? 2, from: today, calendar: calendar, skipToday: true)
            },
            Rule(pattern: #"\b(diesen|diese)\s+(\#(weekdayNames))\b"#, confidence: 0.85) { match, source in
                let name = (source as NSString).substring(with: match.range(at: 2)).lowercased()
                return nextOccurrence(of: Self.germanWeekdays[name] ?? 2, from: today, calendar: calendar, skipToday: false)
            },
            Rule(pattern: #"\bnächste\s+woche\b"#, confidence: 0.5) { _, _ in
                calendar.date(byAdding: .day, value: 7, to: today)!
            },
            Rule(pattern: #"\b(\#(weekdayNames))\b"#, confidence: 0.6) { match, source in
                let name = (source as NSString).substring(with: match.range).lowercased()
                return nextOccurrence(of: Self.germanWeekdays[name] ?? 2, from: today, calendar: calendar, skipToday: false)
            },
        ]

        let nsRange = NSRange(text.startIndex..., in: text)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            let date = rule.resolve(match, text)
            return DateMatch(range: range, date: date, time: nil, confidence: rule.confidence)
        }
        return nil
    }

    private func germanTimeMatch(in text: String) -> TimeMatch? {
        guard let regex = try? NSRegularExpression(pattern: #"\bum\s+(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b"#, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else { return nil }
        let ns = text as NSString
        let hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let minute: Int
        if match.range(at: 2).location != NSNotFound {
            minute = Int(ns.substring(with: match.range(at: 2))) ?? 0
        } else {
            minute = 0
        }
        return TimeMatch(range: range, time: String(format: "%02d:%02d", hour, minute))
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

    private static let leftoverConnectors: Set<String> = [
        "on", "at", "by", "for", "this", "next", "am", "um", "den", "der", "die", "das", "-", "–", "—", ":",
    ]

    private func cleanTitle(_ text: String, fallback: String) -> String {
        var cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,–—-:;."))

        var words = cleaned.split(separator: " ").map(String.init)
        while let first = words.first, Self.leftoverConnectors.contains(first.lowercased()) {
            words.removeFirst()
        }
        while let last = words.last, Self.leftoverConnectors.contains(last.lowercased()) {
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
