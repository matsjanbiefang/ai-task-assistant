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
    // Set when this task was split off a line via a sequential connector ("and then"/"und dann")
    // rather than a plain "and" — signals the two tasks are dependent steps, not independent
    // to-dos. groupID is shared by both; sequenceIndex is this task's 0-based position in the pair.
    var groupID: UUID? = nil
    var sequenceIndex: Int? = nil
    // Feedback round 3: where the task happens (destination capture or place keyword), and
    // supplementary detail clauses ("take my recipes with me") that belong inside the task
    // rather than in its title or as a separate task.
    var place: String? = nil
    var details: String? = nil
    // Feedback round 3: a vague time period ("morning"/"evening") the user mentioned without an
    // exact hour — kept separate from dueTime rather than guessing a specific clock time for it.
    var timeOfDay: String? = nil
}

// Feedback round 3 (§Stage 4): reduces a full action clause to its head phrase when the WHOLE
// clause matches — "go to the hospital" -> "Hospital". `template`'s "$1" is replaced with capture
// group 1, which also becomes the task's place.
struct TitleReductionRule: Sendable {
    let pattern: String
    let template: String
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
    let timeOfDayWords: [String: String]           // UNAMBIGUOUS time-of-day word -> fixed "HH:mm" (e.g. German "mittags" -> "12:00")
    // Feedback round 3: "morning"/"evening" etc. span hours, not a single instant — guessing a
    // specific clock time for them was actively wrong (a real-device report: "shopping tomorrow
    // morning" got assigned an evening time by NSDataDetector's own date resolution). These set
    // ONLY a qualitative label (ExtractedTask.timeOfDay), never a dueTime.
    let vagueTimeOfDayWords: [String: String] = [:]  // vague word -> canonical display label ("morning")
    // "later"/"später" etc.: resolves to referenceDate + a fixed offset (6h) rather than just
    // "today with no time" — a specific, computed answer per explicit user request.
    let laterOffsetWords: [String] = []
    let priorityPrefixes: [(pattern: String, priority: TaskPriority)]
    let categoryKeywords: [TaskCategory: [String]]
    // Feedback round 3 — clause-classification pipeline fields:
    let placeKeywords: [String: String]            // lowercase keyword (word-start match) -> canonical place display value
    let fillerPrefixes: [String]                   // modal/discourse lead-ins stripped from clause start ("i need to", "ich muss")
    let fillerWords: [String]                      // discourse fillers stripped from clause edges ("also", "bitte", "nicht vergessen")
    let detailPatterns: [String]                   // full-clause regexes marking a clause as a DETAIL of the previous action
    let detailContinuationPrefixes: [String]       // a VERBLESS clause starting with one of these is a detail continuation ("an meine überweisung")
    let referentialMarkers: [String]               // phrases referring back to the main action ("with me", "mit mir") -> detail
    let titleReductionRules: [TitleReductionRule]  // full-clause head-phrase reductions ("go to the X" -> "X")
    let connectorWords: [String]                  // leftover words to trim from title edges after stripping a date phrase
    let conjunctionWords: [String]                // words meaning "and", used for line splitting
    let sequentialWords: [String]                  // words meaning "then" — marks a split as dependent/sequential rather than two independent tasks
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
        // Feedback round 3: clause-classification pipeline. The line is segmented into clauses
        // (commas + conjunctions), and each clause is classified by ROLE — action, sequential
        // action, or detail — instead of the old binary "split or don't" decision. Details
        // ("take my recipes with me", "an meine überweisung") attach to the nearest preceding
        // action instead of polluting its title or becoming a bogus second task.
        let lineRules = candidateRules(for: line, primaryLanguageCode: primaryLanguageCode)
        let clauses = segmentClauses(line, rulesList: lineRules)

        struct PendingAction {
            var text: String
            var sequential: Bool
            var details: [String]
        }
        var actions: [PendingAction] = []
        var sawSequential = false

        for clause in clauses {
            // Language is re-detected per clause — a run-on line can genuinely mix languages
            // either side of "and"/"und". The WHOLE line's rules are appended as a fallback:
            // short fragments ("an meine überweisung") are exactly where per-clause detection
            // is least reliable, and misdetecting one must not break its classification.
            var clauseRules = candidateRules(for: clause.text, primaryLanguageCode: primaryLanguageCode)
            for rules in lineRules where !clauseRules.contains(where: { $0.code == rules.code }) {
                clauseRules.append(rules)
            }
            guard !actions.isEmpty else {
                // The first clause is always an action — a line means *something* to do.
                actions.append(PendingAction(text: clause.text, sequential: false, details: []))
                continue
            }
            if clause.separator == .sequential {
                // Explicit "and then" — the user stated sequencing; that wins over detail rules.
                if clause.text.split(separator: " ").count >= 2, containsVerb(clause.text, rulesList: clauseRules) {
                    actions.append(PendingAction(text: clause.text, sequential: true, details: []))
                    sawSequential = true
                } else {
                    actions[actions.count - 1].text += clause.joinerText + clause.text
                }
                continue
            }
            if isDetailClause(clause.text, rulesList: clauseRules) {
                actions[actions.count - 1].details.append(clause.text)
                continue
            }
            let isVerby = containsVerb(clause.text, rulesList: clauseRules)
            if !isVerby {
                if startsWithDetailContinuation(clause.text, rulesList: clauseRules) {
                    // Verbless prepositional continuation ("und an meine überweisung") — a
                    // detail of the previous action, not part of its title.
                    actions[actions.count - 1].details.append(clause.text)
                } else {
                    // Coordinated objects ("buy eggs AND BREAD") — stays in the same clause.
                    actions[actions.count - 1].text += clause.joinerText + clause.text
                }
                continue
            }
            if clause.text.split(separator: " ").count >= 2,
               actions[actions.count - 1].text.split(separator: " ").count >= 2 {
                actions.append(PendingAction(text: clause.text, sequential: false, details: []))
            } else {
                actions[actions.count - 1].text += clause.joinerText + clause.text
            }
        }

        let groupID: UUID? = (sawSequential && actions.count > 1) ? UUID() : nil

        // A run-on line usually states its date once, up front — "shopping tomorrow and painting
        // in the evening" means both happen tomorrow, not that the second clause has no date at
        // all. A later clause with no date of its own inherits the nearest earlier clause's date.
        var carryDate: (dueDate: String, confidence: Double)?
        var tasks: [ExtractedTask] = []
        for (index, action) in actions.enumerated() {
            var rulesList = candidateRules(for: action.text, primaryLanguageCode: primaryLanguageCode)
            for rules in lineRules where !rulesList.contains(where: { $0.code == rules.code }) {
                rulesList.append(rules)
            }
            var task = buildTask(from: action.text, referenceDate: referenceDate, rulesList: rulesList, detailClauses: action.details)
            if task.dueDate == nil, let carryDate {
                task.dueDate = carryDate.dueDate
                task.dateConfidence = carryDate.confidence
            } else if let date = task.dueDate {
                carryDate = (date, task.dateConfidence)
            }
            task.groupID = groupID
            task.sequenceIndex = groupID != nil ? index : nil
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

    private func buildTask(from rawSubLine: String, referenceDate: Date, rulesList: [LanguageRules], detailClauses: [String] = []) -> ExtractedTask {
        // Stage 1: modal/discourse filler stripping ("i need to", "ich muss", trailing "bitte")
        // before anything else, and again after priority stripping — "dringend: ich muss..." and
        // "ich muss dringend..." both need to end up clean.
        var text = stripFillers(rawSubLine, rulesList: rulesList)

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
        text = stripFillers(text, rulesList: rulesList)

        var category: TaskCategory?
        for rules in rulesList {
            if let matched = applyCategoryKeywords(text, rules: rules) {
                category = matched
                break
            }
        }

        var dueDate: String?
        var dueTime: String?
        var timeOfDay: String?
        var confidence = 1.0
        var rangesToStrip: [Range<String.Index>] = []
        var dateFound = false

        for rules in rulesList {
            guard let match = laterOffsetMatch(in: text, referenceDate: referenceDate, rules: rules) else { continue }
            dueDate = isoDate(match.date)
            dueTime = match.time
            confidence = match.confidence
            rangesToStrip.append(match.range)
            dateFound = true
            break
        }
        if !dateFound {
            for rules in rulesList {
                guard let match = customDateMatch(in: text, referenceDate: referenceDate, rules: rules) else { continue }
                dueDate = isoDate(match.date)
                confidence = match.confidence
                rangesToStrip.append(match.range)
                dateFound = true
                break
            }
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
        if dueTime == nil {
            for rules in rulesList {
                guard let vagueMatch = vagueTimeOfDayMatch(in: text, rules: rules) else { continue }
                timeOfDay = vagueMatch.label
                rangesToStrip.append(vagueMatch.range)
                break
            }
        }

        // Fillers again after date/time removal: "heute NOCH wäsche waschen" only exposes its
        // leading "noch" once "heute" is gone.
        let stripped = stripFillers(removeRanges(rangesToStrip, from: text), rulesList: rulesList)

        // Stage 4: head-phrase reduction ("go to the hospital" -> "Hospital") + Stage 5: place.
        var place: String?
        let title: String
        if let reduced = reduceTitle(normalizeClause(stripped), rulesList: rulesList) {
            title = capitalizeFirst(reduced.title)
            place = capitalizeFirst(reduced.place)
        } else {
            title = cleanTitle(stripped, fallback: rawSubLine, rulesList: rulesList)
        }
        if place == nil {
            place = placeKeywordMatch(in: rawSubLine, rulesList: rulesList)
        }

        let cleanedDetails = detailClauses
            .map { capitalizeFirst(stripFillers(normalizeClause($0), rulesList: rulesList)) }
            .filter { !$0.isEmpty }
        let details = cleanedDetails.isEmpty ? nil : cleanedDetails.joined(separator: "; ")

        return ExtractedTask(
            title: title,
            dueDate: dueDate,
            dueTime: dueTime,
            priority: priority,
            category: category,
            dateConfidence: dateFound ? confidence : 1.0,
            place: place,
            details: details,
            timeOfDay: timeOfDay
        )
    }

    // MARK: - Fillers, title reduction, place (feedback round 3)

    private func stripFillers(_ text: String, rulesList: [LanguageRules]) -> String {
        let prefixes = rulesList.flatMap(\.fillerPrefixes).sorted { $0.count > $1.count }
        let edgeWords = rulesList.flatMap(\.fillerWords).sorted { $0.count > $1.count }
        let boundaryTrim = CharacterSet(charactersIn: " :,–—-")

        var result = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed && !result.isEmpty {
            changed = false
            for prefix in prefixes {
                guard let match = result.range(of: prefix, options: [.caseInsensitive, .anchored]) else { continue }
                // word boundary required: end of clause, or a separator character
                if match.upperBound == result.endIndex {
                    result = ""
                } else {
                    let next = result[match.upperBound]
                    guard next == " " || next == ":" || next == "," || next == "-" else { continue }
                    result = String(result[match.upperBound...]).trimmingCharacters(in: boundaryTrim)
                }
                changed = true
                break
            }
            if changed { continue }
            for word in edgeWords {
                if let match = result.range(of: word + " ", options: [.caseInsensitive, .anchored]) {
                    result = String(result[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                    changed = true
                    break
                }
                if let match = result.range(of: " " + word, options: [.caseInsensitive, .anchored, .backwards]),
                   match.upperBound == result.endIndex {
                    result = String(result[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
                    changed = true
                    break
                }
            }
        }
        // A clause that is ALL filler ("nicht vergessen") keeps its original text — an empty
        // title helps nobody, and cleanTitle's fallback path expects something to work with.
        return result.isEmpty ? text.trimmingCharacters(in: .whitespaces) : result
    }

    private func normalizeClause(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: ",", with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,–—-:;.!?"))
    }

    private func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // Stage 4: the WHOLE remaining clause must match a reduction pattern — partial matches never
    // fire, so ordinary titles ("call the dentist") can't be damaged. The capture is rejected if
    // it still contains a verb ("zur wohnung streichen" must NOT reduce to "wohnung streichen"
    // with a place of a whole activity), falling back to the normal cleanTitle path.
    private func reduceTitle(_ text: String, rulesList: [LanguageRules]) -> (title: String, place: String)? {
        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for rules in rulesList {
            for rule in rules.titleReductionRules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: text, range: fullRange),
                      match.range.location == 0, match.range.length == nsText.length,
                      match.numberOfRanges > 1,
                      let captureRange = Range(match.range(at: 1), in: text) else { continue }
                let capture = String(text[captureRange]).trimmingCharacters(in: .whitespaces)
                guard !capture.isEmpty,
                      capture.split(separator: " ").count <= 4,
                      !containsVerb(capture, rulesList: rulesList) else { continue }
                let title = rule.template.replacingOccurrences(of: "$1", with: capture)
                return (title, capture)
            }
        }
        return nil
    }

    // Stage 5: place from keyword scan (destination captures from reduceTitle take precedence at
    // the call site). Word-START matching ("\barzt") deliberately, so German compounds like
    // "arzttermin" still hit "arzt" — a \b on both sides can never match inside a compound.
    private func placeKeywordMatch(in text: String, rulesList: [LanguageRules]) -> String? {
        let lower = text.lowercased()
        for rules in rulesList {
            for (keyword, canonical) in rules.placeKeywords.sorted(by: { $0.key.count > $1.key.count }) {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))"
                if lower.range(of: pattern, options: .regularExpression) != nil {
                    return canonical
                }
            }
        }
        return nil
    }

    // MARK: - Language detection (§2)

    private func detectLanguage(_ text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Clause segmentation + role classification (§3, feedback round 3)

    private enum ClauseSeparator {
        case leading      // first clause of the line
        case comma
        case conjunction  // "and"/"und"/...
        case sequential   // "and then"/"und dann"/", dann"
    }

    private struct Clause {
        var text: String
        let separator: ClauseSeparator
        let joinerText: String  // verbatim joiner, for rejoining clauses that turn out to be one
    }

    private func segmentClauses(_ line: String, rulesList: [LanguageRules]) -> [Clause] {
        let conjunctions = Set(rulesList.flatMap(\.conjunctionWords).map { $0.lowercased() })
        let sequentials = Set(rulesList.flatMap(\.sequentialWords).map { $0.lowercased() })

        func stripLeadingWord(_ text: inout String, from words: Set<String>) -> String? {
            let lower = text.lowercased()
            for word in words where lower.hasPrefix(word + " ") {
                text = String(text.dropFirst(word.count + 1)).trimmingCharacters(in: .whitespaces)
                return word
            }
            return nil
        }

        var clauses: [Clause] = []
        for (partIndex, rawPart) in line.components(separatedBy: ",").enumerated() {
            var part = rawPart.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }

            var separator: ClauseSeparator = partIndex == 0 ? .leading : .comma
            var joiner = partIndex == 0 ? "" : ", "
            // ", und X" / ", dann X" — the comma part itself starts with a connector word
            if let conj = stripLeadingWord(&part, from: conjunctions) {
                joiner += conj + " "
                separator = .conjunction
            }
            if let seq = stripLeadingWord(&part, from: sequentials) {
                joiner += seq + " "
                separator = .sequential
            }

            // Split the remainder on inner " and "/" und " occurrences, left to right.
            var remaining = part
            var currentSeparator = separator
            var currentJoiner = joiner
            while true {
                var earliest: (range: Range<String.Index>, word: String)?
                for word in conjunctions {
                    guard let r = remaining.range(of: " \(word) ", options: .caseInsensitive) else { continue }
                    if earliest == nil || r.lowerBound < earliest!.range.lowerBound {
                        earliest = (r, word)
                    }
                }
                guard let found = earliest else { break }
                let before = String(remaining[..<found.range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var after = String(remaining[found.range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var nextSeparator: ClauseSeparator = .conjunction
                var nextJoiner = " \(found.word) "
                if let seq = stripLeadingWord(&after, from: sequentials) {
                    nextJoiner += seq + " "
                    nextSeparator = .sequential
                }
                if !before.isEmpty {
                    clauses.append(Clause(text: before, separator: currentSeparator, joinerText: currentJoiner))
                }
                currentSeparator = nextSeparator
                currentJoiner = nextJoiner
                remaining = after
            }
            if !remaining.isEmpty {
                clauses.append(Clause(text: remaining, separator: currentSeparator, joinerText: currentJoiner))
            }
        }
        return clauses
    }

    // A clause is a DETAIL when it matches a full-clause detail pattern ("take … with me",
    // "an … denken") or contains a referential marker pointing back at the main action.
    private func isDetailClause(_ text: String, rulesList: [LanguageRules]) -> Bool {
        let trimmed = normalizeClause(text)
        guard !trimmed.isEmpty else { return false }
        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for rules in rulesList {
            for pattern in rules.detailPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: trimmed, range: fullRange),
                      match.range.location == 0, match.range.length == nsText.length else { continue }
                return true
            }
            for marker in rules.referentialMarkers {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: marker))\\b"
                if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    return true
                }
            }
        }
        return false
    }

    private func startsWithDetailContinuation(_ text: String, rulesList: [LanguageRules]) -> Bool {
        guard let first = text.split(separator: " ").first?.lowercased() else { return false }
        return rulesList.contains { $0.detailContinuationPrefixes.contains(first) }
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

    private struct TimeOfDayMatch {
        let range: Range<String.Index>
        let label: String
    }

    // Feedback round 3: "later"/"später" resolves to a computed, specific answer (now + 6h) per
    // explicit request, rather than the round-2 behavior of just flagging "today, no time".
    private func laterOffsetMatch(in text: String, referenceDate: Date, rules: LanguageRules) -> DateMatch? {
        guard !rules.laterOffsetWords.isEmpty else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        for word in rules.laterOffsetWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            let target = referenceDate.addingTimeInterval(6 * 3600)
            return DateMatch(range: range, date: target, time: formattedTime(from: target), confidence: 0.8)
        }
        return nil
    }

    // A vague period ("morning"/"evening") spans hours, not one instant — this sets a qualitative
    // label only, deliberately never a specific dueTime (see LanguageRules.vagueTimeOfDayWords).
    private func vagueTimeOfDayMatch(in text: String, rules: LanguageRules) -> TimeOfDayMatch? {
        guard !rules.vagueTimeOfDayWords.isEmpty else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        for (word, label) in rules.vagueTimeOfDayWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            return TimeOfDayMatch(range: range, label: label)
        }
        return nil
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
        if let alt = wordAlternation(Array(rules.vagueTimeOfDayWords.keys)) { patterns.append("\\b(\(alt))\\b") }
        if let alt = wordAlternation(rules.laterOffsetWords) { patterns.append("\\b(\(alt))\\b") }
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
        // When two matches start at the same point (e.g. a plain date match on "tomorrow" and a
        // context-anchored vague-time match on "tomorrow morning"), prefer the LONGER one so the
        // more complete phrase is what actually leaves the title, not just whichever happened to
        // be appended to the list first.
        let sorted = ranges.sorted { lhs, rhs in
            if lhs.lowerBound != rhs.lowerBound { return lhs.lowerBound < rhs.lowerBound }
            return text.distance(from: lhs.lowerBound, to: lhs.upperBound)
                > text.distance(from: rhs.lowerBound, to: rhs.upperBound)
        }
        var accepted: [Range<String.Index>] = []
        for range in sorted {
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

        // Stripping a matched date/time phrase from the middle of a sentence (e.g. "arzttermin
        // <später>, muss...") often leaves an orphaned comma that trimming edges alone won't
        // catch, since it's no longer at the start/end once the phrase around it is gone. Commas
        // rarely carry meaning in a short task title, so just drop them outright rather than only
        // trimming the string's own edges.
        var cleaned = text.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
        todayWords: [],
        tomorrowWords: [],
        dayAfterTomorrowWords: [],
        numberWords: ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10],
        inDaysPattern: #"\bin\s+(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+days?\b"#,
        inWeeksPattern: #"\bin\s+(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+weeks?\b"#,
        weekdayPhraseRules: [],
        nextWeekPattern: #"\bnext week\b"#,
        timePattern: nil,
        // Bare "morning"/"evening"/"night"/"afternoon" deliberately excluded — English commonly
        // uses them as an ordinary descriptive word in a task title itself ("morning run",
        // "evening walk"), and stripping them out as if they were a scheduling signal broke
        // exactly that case in the corpus. "noon"/"midday" don't have the same collision risk.
        timeOfDayWords: ["noon": "12:00", "midday": "12:00"],
        priorityPrefixes: [
            (#"^(urgent|asap|important)\b\#(punctSep)"#, .high),
            (#"^(high priority)\b\#(punctSep)"#, .high),
            (#"^(low priority|whenever)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["work", "meeting", "deadline", "project", "client", "office", "kickoff"],
            .health: ["doctor", "dentist", "gym", "workout", "appointment", "fitness", "membership", "hospital"],
            .shopping: ["buy", "groceries", "shopping", "store"],
            .finance: ["pay", "bill", "invoice", "bank", "tax"],
        ],
        placeKeywords: [
            "hospital": "Hospital", "doctor": "Doctor", "dentist": "Dentist", "office": "Office",
            "school": "School", "university": "University", "supermarket": "Supermarket",
            "pharmacy": "Pharmacy", "bank": "Bank", "gym": "Gym", "station": "Station",
            "airport": "Airport", "hairdresser": "Hairdresser", "garage": "Garage",
            "kindergarten": "Kindergarten", "post office": "Post office", "bakery": "Bakery",
            "restaurant": "Restaurant", "church": "Church", "library": "Library",
            "town hall": "Town hall", "hardware store": "Hardware store",
        ],
        fillerPrefixes: [
            "i need to", "i have to", "i must", "i should", "i want to", "i would like to",
            "i wanna", "i gotta", "i'd like to", "i think i need to", "i really need to",
            "we need to", "we have to", "we should", "need to", "have to", "gotta",
            "remember to", "don't forget to", "dont forget to", "make sure to", "make sure i",
            "note to self", "todo", "to-do", "maybe i should", "should probably",
        ],
        fillerWords: ["oh and", "and also", "also", "please", "btw"],
        detailPatterns: [
            #"^take\s+.+\s+with\s+(?:me|us)$"#,
            #"^take\s+(?:my|your|our)\s+.+$"#,
            #"^(?:bring|pack|grab)\s+.+$"#,
            #"^remember\s+.+$"#,
            #"^keep\s+in\s+mind\s+.+$"#,
            #"^don'?t\s+forget\s+(?!to\s).+$"#,
        ],
        detailContinuationPrefixes: ["with", "for", "about", "plus"],
        referentialMarkers: ["with me", "with us"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^(?:go|going|drive|head|walk|run|get)\s+(?:to|into)\s+(?:the\s+|a\s+|an\s+)?(.+)$"#, template: "$1"),
            TitleReductionRule(pattern: #"^(?:doctor'?s?\s+)?appointment\s+(?:at|with)\s+(?:the\s+)?(.+)$"#, template: "Appointment: $1"),
        ],
        connectorWords: ["on", "at", "by", "for", "this", "next", "am"],
        conjunctionWords: ["and"],
        sequentialWords: ["then"],
        imperativeVerbs: [
            "call", "buy", "finish", "deploy", "write", "prepare", "book", "pay", "clean", "reply",
            "send", "schedule", "review", "fix", "renew", "cancel", "water", "tidy", "return", "pick",
            "think", "do", "get", "make", "take", "bring", "check", "confirm", "submit", "order",
            "drop", "pack", "email", "text", "message", "update", "install", "download", "upload",
            "inform", "adjust", "notify", "tell", "ask", "arrange",
            // Common modal-verb sentence starters ("need to adjust the laptop") — NLTagger's
            // lexicalClass tagging on short, lowercase, context-free fragments isn't reliable
            // enough to trust for these on its own (see comment on containsVerb below).
            "need", "want", "have", "should", "must", "plan",
        ],
        verbSuffixes: [],
        // Anchored to "tomorrow"/"this"/standalone "tonight" specifically so "morning run" is
        // never touched — only a clear date-relative reference to a period of day counts.
        vagueTimeOfDayWords: [
            "tomorrow morning": "Morning", "tomorrow afternoon": "Afternoon",
            "tomorrow evening": "Evening", "tomorrow night": "Night",
            "this morning": "Morning", "this afternoon": "Afternoon", "this evening": "Evening",
            "tonight": "Night",
        ],
        laterOffsetWords: ["later"]
    )

    private static let germanRules = LanguageRules(
        code: "de",
        weekdayNames: [
            "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
            "donnerstag": 5, "freitag": 6, "samstag": 7, "sonnabend": 7,
        ],
        todayWords: ["heute"],
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
        // "um" is optional — "20.april 12 uhr arzt" states the time without that preposition.
        timePattern: #"\b(?:um\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b"#,
        timeOfDayWords: ["mittags": "12:00"],
        priorityPrefixes: [
            (#"^(dringend|wichtig)\b\#(punctSep)"#, .high),
            (#"^(hohe priorität)\b\#(punctSep)"#, .high),
            (#"^(niedrige priorität)\b\#(punctSep)"#, .low),
        ],
        categoryKeywords: [
            .work: ["büro", "arbeit", "projekt", "kickoff"],
            // German compounds nouns without a space ("Arzttermin"), so a bare "arzt" keyword
            // never matches inside it — \b requires a boundary, and there isn't one mid-compound.
            // Listing the common compounds directly is the only reliable fix for this pattern.
            .health: ["arzt", "arzttermin", "arztbesuch", "hausarzt", "frauenarzt", "zahnarzt", "termin", "fitness", "krankenhaus"],
            .shopping: ["kaufen", "einkaufen"],
            .finance: ["rechnung", "bezahlen", "steuer"],
        ],
        placeKeywords: [
            "krankenhaus": "Krankenhaus", "klinik": "Klinik", "arzt": "Arzt", "zahnarzt": "Zahnarzt",
            "praxis": "Praxis", "büro": "Büro", "schule": "Schule", "universität": "Universität",
            "uni": "Uni", "supermarkt": "Supermarkt", "apotheke": "Apotheke", "bank": "Bank",
            "fitnessstudio": "Fitnessstudio", "bahnhof": "Bahnhof", "flughafen": "Flughafen",
            "baumarkt": "Baumarkt", "friseur": "Friseur", "werkstatt": "Werkstatt", "kita": "Kita",
            "post": "Post", "bäcker": "Bäcker", "restaurant": "Restaurant", "kirche": "Kirche",
            "bibliothek": "Bibliothek", "rathaus": "Rathaus",
        ],
        fillerPrefixes: [
            "ich muss noch", "ich muss unbedingt", "ich muss mal", "ich muss", "ich müsste",
            "ich sollte", "ich soll", "ich will", "ich möchte", "wir müssen", "wir sollten",
            "man muss", "muss ich", "sollte ich", "muss", "denk daran", "daran denken",
            "dran denken", "nicht vergessen", "nich vergessen", "ich darf nicht vergessen",
        ],
        fillerWords: ["bitte", "unbedingt", "noch", "mal", "auch noch", "ach ja", "übrigens", "nicht vergessen", "nich vergessen"],
        detailPatterns: [
            #"^(?:muss\s+|noch\s+)?an\s+.+\s+denken$"#,
            #"^.+\s+(?:mitnehmen|mitbringen|einpacken|dabeihaben)$"#,
            #"^.+\s+dabei\s+haben$"#,
            #"^.+\s+nicht\s+vergessen$"#,
            #"^.+\s+erwähnen$"#,
        ],
        detailContinuationPrefixes: ["an", "mit", "für", "wegen", "dazu", "außerdem"],
        referentialMarkers: ["mit mir", "mit uns", "dabei"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^(?:geh(?:e|en)?\s+|fahr(?:e|en)?\s+|lauf(?:e|en)?\s+)?(?:zum|zur|zu|ins|in\s+die|in\s+den|nach|auf\s+die|aufs)\s+(.+?)(?:\s+(?:gehen|fahren|laufen))?$"#, template: "$1"),
            TitleReductionRule(pattern: #"^termin\s+(?:beim|bei\s+der|bei|mit|im|in\s+der)\s+(.+)$"#, template: "Termin $1"),
        ],
        connectorWords: ["am", "um", "den", "der", "die", "das", "für", "zu", "zur"],
        conjunctionWords: ["und"],
        sequentialWords: ["dann"],
        imperativeVerbs: [],
        verbSuffixes: ["en"],
        vagueTimeOfDayWords: ["morgens": "Morgens", "vormittags": "Vormittags", "nachmittags": "Nachmittags", "abends": "Abends", "nachts": "Nachts"],
        laterOffsetWords: ["später"]
    )

    private static let frenchRules = LanguageRules(
        code: "fr",
        weekdayNames: [
            "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4,
            "jeudi": 5, "vendredi": 6, "samedi": 7,
        ],
        todayWords: ["aujourd'hui"],
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
        timeOfDayWords: ["midi": "12:00"],
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
        placeKeywords: [
            "hôpital": "Hôpital", "médecin": "Médecin", "dentiste": "Dentiste", "bureau": "Bureau",
            "école": "École", "université": "Université", "supermarché": "Supermarché",
            "pharmacie": "Pharmacie", "banque": "Banque", "gare": "Gare", "aéroport": "Aéroport",
            "coiffeur": "Coiffeur", "poste": "Poste", "boulangerie": "Boulangerie",
            "restaurant": "Restaurant", "église": "Église", "bibliothèque": "Bibliothèque",
        ],
        fillerPrefixes: [
            "je dois", "je devrais", "je voudrais", "je veux", "il faut", "il faudrait",
            "nous devons", "on doit", "penser à", "ne pas oublier de", "n'oublie pas de",
        ],
        fillerWords: ["s'il te plaît", "svp", "aussi"],
        detailPatterns: [
            #"^(?:apporter|prendre)\s+.+$"#,
            #"^penser\s+à\s+.+$"#,
            #"^ne\s+pas\s+oublier\s+.+$"#,
        ],
        detailContinuationPrefixes: ["avec", "pour"],
        referentialMarkers: ["avec moi", "avec nous"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^aller\s+(?:à\s+la\s+|à\s+l['’]|au\s+|aux\s+|chez\s+|à\s+|en\s+)(.+)$"#, template: "$1"),
        ],
        connectorWords: ["à", "de", "le", "la"],
        conjunctionWords: ["et"],
        sequentialWords: ["puis"],
        imperativeVerbs: [
            "appeler", "acheter", "finir", "préparer", "réserver", "payer", "nettoyer", "répondre",
            "envoyer", "planifier", "réviser", "réparer", "renouveler", "annuler", "arroser",
            "ranger", "rendre", "prendre", "penser", "faire", "apporter", "vérifier", "confirmer",
            "soumettre", "commander",
        ],
        verbSuffixes: [],
        vagueTimeOfDayWords: ["matin": "Matin", "après-midi": "Après-midi", "soir": "Soir", "nuit": "Nuit"],
        laterOffsetWords: ["plus tard"]
    )

    private static let spanishRules = LanguageRules(
        code: "es",
        weekdayNames: [
            "domingo": 1, "lunes": 2, "martes": 3, "miércoles": 4,
            "jueves": 5, "viernes": 6, "sábado": 7,
        ],
        todayWords: ["hoy"],
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
        timeOfDayWords: ["mediodía": "12:00"],
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
        placeKeywords: [
            "hospital": "Hospital", "médico": "Médico", "dentista": "Dentista", "oficina": "Oficina",
            "escuela": "Escuela", "universidad": "Universidad", "supermercado": "Supermercado",
            "farmacia": "Farmacia", "banco": "Banco", "gimnasio": "Gimnasio", "estación": "Estación",
            "aeropuerto": "Aeropuerto", "peluquería": "Peluquería", "correos": "Correos",
            "panadería": "Panadería", "restaurante": "Restaurante", "iglesia": "Iglesia",
            "biblioteca": "Biblioteca",
        ],
        fillerPrefixes: [
            "tengo que", "tenemos que", "debo", "debería", "hay que", "quiero", "necesito",
            "acordarme de", "no olvidar", "no olvidarme de",
        ],
        fillerWords: ["por favor", "también"],
        detailPatterns: [
            #"^(?:llevar|traer)\s+.+$"#,
            #"^acordar(?:me|se)\s+de\s+.+$"#,
            #"^no\s+olvidar\s+.+$"#,
        ],
        detailContinuationPrefixes: ["con", "para"],
        referentialMarkers: ["conmigo", "con nosotros"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^ir\s+(?:al\s+|a\s+la\s+|a\s+)(.+)$"#, template: "$1"),
        ],
        connectorWords: ["a", "el", "la", "las"],
        conjunctionWords: ["y"],
        sequentialWords: ["luego"],
        imperativeVerbs: [
            "llamar", "comprar", "terminar", "preparar", "reservar", "pagar", "limpiar", "responder",
            "enviar", "programar", "revisar", "arreglar", "renovar", "cancelar", "regar", "ordenar",
            "devolver", "recoger", "pensar", "hacer", "traer", "comprobar", "confirmar",
        ],
        verbSuffixes: [],
        vagueTimeOfDayWords: ["por la mañana": "Mañana", "por la tarde": "Tarde", "por la noche": "Noche"],
        laterOffsetWords: ["más tarde"]
    )

    private static let italianRules = LanguageRules(
        code: "it",
        weekdayNames: [
            "domenica": 1, "lunedì": 2, "martedì": 3, "mercoledì": 4,
            "giovedì": 5, "venerdì": 6, "sabato": 7,
        ],
        todayWords: ["oggi"],
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
        timeOfDayWords: ["mezzogiorno": "12:00"],
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
        placeKeywords: [
            "ospedale": "Ospedale", "medico": "Medico", "dentista": "Dentista", "ufficio": "Ufficio",
            "scuola": "Scuola", "università": "Università", "supermercato": "Supermercato",
            "farmacia": "Farmacia", "banca": "Banca", "palestra": "Palestra", "stazione": "Stazione",
            "aeroporto": "Aeroporto", "parrucchiere": "Parrucchiere", "posta": "Posta",
            "panetteria": "Panetteria", "ristorante": "Ristorante", "chiesa": "Chiesa",
            "biblioteca": "Biblioteca",
        ],
        fillerPrefixes: [
            "devo", "dovrei", "dobbiamo", "bisogna", "voglio", "ho bisogno di",
            "ricordarmi di", "non dimenticare di",
        ],
        fillerWords: ["per favore", "anche"],
        detailPatterns: [
            #"^(?:portare|prendere)\s+.+$"#,
            #"^ricordar(?:mi|si)\s+di\s+.+$"#,
            #"^non\s+dimenticare\s+.+$"#,
        ],
        detailContinuationPrefixes: ["con", "per"],
        referentialMarkers: ["con me", "con noi"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^andare\s+(?:al\s+|alla\s+|all['’]|dal\s+|da\s+|in\s+)(.+)$"#, template: "$1"),
        ],
        connectorWords: ["a", "il", "la", "lo"],
        conjunctionWords: ["e"],
        sequentialWords: ["poi"],
        imperativeVerbs: [
            "chiamare", "comprare", "finire", "preparare", "prenotare", "pagare", "pulire",
            "rispondere", "inviare", "programmare", "rivedere", "riparare", "rinnovare",
            "cancellare", "annaffiare", "riordinare", "restituire", "ritirare", "pensare", "fare",
            "portare", "controllare", "confermare",
        ],
        verbSuffixes: [],
        vagueTimeOfDayWords: ["mattina": "Mattina", "pomeriggio": "Pomeriggio", "sera": "Sera", "notte": "Notte"],
        laterOffsetWords: ["più tardi"]
    )

    private static let portugueseRules = LanguageRules(
        code: "pt",
        weekdayNames: [
            "domingo": 1, "segunda": 2, "terça": 3, "quarta": 4,
            "quinta": 5, "sexta": 6, "sábado": 7,
        ],
        todayWords: ["hoje"],
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
        timeOfDayWords: ["meio-dia": "12:00"],
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
        placeKeywords: [
            "hospital": "Hospital", "médico": "Médico", "dentista": "Dentista",
            "escritório": "Escritório", "escola": "Escola", "universidade": "Universidade",
            "supermercado": "Supermercado", "farmácia": "Farmácia", "banco": "Banco",
            "academia": "Academia", "estação": "Estação", "aeroporto": "Aeroporto",
            "cabeleireiro": "Cabeleireiro", "correios": "Correios", "padaria": "Padaria",
            "restaurante": "Restaurante", "igreja": "Igreja", "biblioteca": "Biblioteca",
        ],
        fillerPrefixes: [
            "tenho que", "tenho de", "temos que", "devo", "deveria", "preciso", "quero",
            "lembrar de", "não esquecer de",
        ],
        fillerWords: ["por favor", "também"],
        detailPatterns: [
            #"^(?:levar|trazer)\s+.+$"#,
            #"^lembrar\s+de\s+.+$"#,
            #"^não\s+esquecer\s+.+$"#,
        ],
        detailContinuationPrefixes: ["com", "para"],
        referentialMarkers: ["comigo", "conosco"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^ir\s+(?:ao\s+|à\s+|para\s+o\s+|para\s+a\s+|para\s+)(.+)$"#, template: "$1"),
        ],
        connectorWords: ["a", "o", "às", "de"],
        conjunctionWords: ["e"],
        sequentialWords: ["depois"],
        imperativeVerbs: [
            "ligar", "comprar", "terminar", "preparar", "reservar", "pagar", "limpar", "responder",
            "enviar", "agendar", "revisar", "consertar", "renovar", "cancelar", "regar", "arrumar",
            "devolver", "buscar", "pensar", "fazer", "trazer", "verificar", "confirmar",
        ],
        verbSuffixes: [],
        vagueTimeOfDayWords: ["manhã": "Manhã", "tarde": "Tarde", "noite": "Noite"],
        laterOffsetWords: ["mais tarde"]
    )

    private static let dutchRules = LanguageRules(
        code: "nl",
        weekdayNames: [
            "zondag": 1, "maandag": 2, "dinsdag": 3, "woensdag": 4,
            "donderdag": 5, "vrijdag": 6, "zaterdag": 7,
        ],
        todayWords: ["vandaag"],
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
        timeOfDayWords: [:],
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
        placeKeywords: [
            "ziekenhuis": "Ziekenhuis", "dokter": "Dokter", "tandarts": "Tandarts",
            "kantoor": "Kantoor", "school": "School", "universiteit": "Universiteit",
            "supermarkt": "Supermarkt", "apotheek": "Apotheek", "bank": "Bank",
            "sportschool": "Sportschool", "station": "Station", "vliegveld": "Vliegveld",
            "kapper": "Kapper", "postkantoor": "Postkantoor", "bakker": "Bakker",
            "restaurant": "Restaurant", "kerk": "Kerk", "bibliotheek": "Bibliotheek",
        ],
        fillerPrefixes: [
            "ik moet nog", "ik moet", "ik zou", "we moeten", "ik wil",
            "niet vergeten", "denk eraan", "vergeet niet",
        ],
        fillerWords: ["alsjeblieft", "ook nog", "ook", "even"],
        detailPatterns: [
            #"^.+\s+(?:meenemen|meebrengen)$"#,
            #"^denken?\s+aan\s+.+$"#,
            #"^niet\s+vergeten\s+.+$"#,
        ],
        detailContinuationPrefixes: ["met", "voor"],
        referentialMarkers: ["met mij", "met ons"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^(?:ga(?:an)?\s+)?naar\s+(?:de\s+|het\s+)?(.+?)(?:\s+gaan)?$"#, template: "$1"),
        ],
        connectorWords: ["op", "om", "de", "het"],
        conjunctionWords: ["en"],
        sequentialWords: ["dan"],
        imperativeVerbs: [
            "bellen", "kopen", "afmaken", "voorbereiden", "boeken", "betalen", "schoonmaken",
            "antwoorden", "sturen", "plannen", "controleren", "repareren", "verlengen",
            "annuleren", "opruimen", "terugbrengen", "ophalen", "denken", "doen", "brengen",
            "bevestigen",
        ],
        verbSuffixes: ["en"],
        vagueTimeOfDayWords: ["ochtend": "Ochtend", "middag": "Middag", "namiddag": "Namiddag", "avond": "Avond", "nacht": "Nacht"],
        laterOffsetWords: ["later"]
    )

    private static let polishRules = LanguageRules(
        code: "pl",
        weekdayNames: [
            "niedziela": 1, "poniedziałek": 2, "wtorek": 3, "środa": 4, "środę": 4,
            "czwartek": 5, "piątek": 6, "sobota": 7, "sobotę": 7,
        ],
        todayWords: ["dziś", "dzisiaj"],
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
        timeOfDayWords: ["południe": "12:00"],
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
        placeKeywords: [
            "szpital": "Szpital", "lekarz": "Lekarz", "dentysta": "Dentysta", "biuro": "Biuro",
            "szkoła": "Szkoła", "uniwersytet": "Uniwersytet", "supermarket": "Supermarket",
            "apteka": "Apteka", "bank": "Bank", "siłownia": "Siłownia", "dworzec": "Dworzec",
            "lotnisko": "Lotnisko", "fryzjer": "Fryzjer", "poczta": "Poczta",
            "piekarnia": "Piekarnia", "restauracja": "Restauracja", "kościół": "Kościół",
            "biblioteka": "Biblioteka",
        ],
        fillerPrefixes: [
            "muszę", "musimy", "powinienem", "powinnam", "trzeba", "chcę",
            "nie zapomnieć", "pamiętać żeby", "pamiętaj żeby",
        ],
        fillerWords: ["proszę", "też", "jeszcze"],
        detailPatterns: [
            #"^(?:zabrać|przynieść|wziąć)\s+.+$"#,
            #"^pamiętać\s+o\s+.+$"#,
            #"^nie\s+zapomnieć\s+o?\s*.+$"#,
        ],
        detailContinuationPrefixes: ["z", "o", "dla"],
        referentialMarkers: ["ze mną", "z nami"],
        titleReductionRules: [
            TitleReductionRule(pattern: #"^(?:iść|pójść|jechać|pojechać)\s+do\s+(.+)$"#, template: "$1"),
        ],
        connectorWords: ["w", "na", "o"],
        conjunctionWords: ["i"],
        sequentialWords: ["potem"],
        imperativeVerbs: [
            "zadzwonić", "kupić", "skończyć", "przygotować", "zarezerwować", "zapłacić",
            "posprzątać", "odpowiedzieć", "wysłać", "zaplanować", "sprawdzić", "naprawić",
            "odnowić", "anulować", "podlać", "zwrócić", "odebrać", "pomyśleć", "zrobić",
            "przynieść", "potwierdzić",
        ],
        verbSuffixes: ["ć"],
        vagueTimeOfDayWords: ["rano": "Rano", "popołudniu": "Popołudniu", "wieczorem": "Wieczorem", "noc": "Noc"],
        laterOffsetWords: ["później"]
    )
}
