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
    // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday to Saturday" —
    // set only by dateRangeMatch, alongside dueDate as the range's start. nil for every task with
    // just a single date, which is still the overwhelming majority.
    var dueEndDate: String? = nil
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

// Milestone 7 (CG-3, swipe-final-architecture.md §6): the single definition of "low confidence" —
// previously a `dateConfidence < 0.7` literal duplicated separately in NoteView and AssistantView.
// A future calibrated per-language threshold (CG-2) replaces `lowConfidenceThreshold` here; this is
// the only place that change needs to happen.
extension RuleBasedExtractionService {
    static let lowConfidenceThreshold = 0.7

    static func isLowConfidence(_ dateConfidence: Double) -> Bool {
        dateConfidence < lowConfidenceThreshold
    }
}

// Feedback round 3 (§Stage 4): reduces a full action clause to its head phrase when the WHOLE
// clause matches — "go to the hospital" -> "Hospital". `template`'s "$1" is replaced with capture
// group 1, which also becomes the task's place.
struct TitleReductionRule: Sendable {
    let pattern: String
    let template: String
}

// Milestone 10 (STT-1, swipe-final-architecture.md §0.5): a recurring transcription-error fix —
// regex `pattern` matched and rewritten to `replacement` (NSRegularExpression replacement
// template syntax, "$1" etc. supported) before segmentation. Packs ship this empty today (no real
// dictation-error data exists yet to seed it with — same "grows from corpus failures only" rule
// the rest of the pack system follows).
struct STTPattern: Sendable {
    let pattern: String
    let replacement: String
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
    // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday to Saturday" —
    // the two connector words for a weekday-name date range ("from"/"to"). Both nil today except
    // English, matching the STT-1 precedent: only populate a language once it's been verified,
    // not translated speculatively.
    let rangeFromWord: String?
    let rangeToWord: String?
    let timePattern: String?                      // capture group 1 = hour, group 2 = optional minute
    let timeOfDayWords: [String: String]           // UNAMBIGUOUS time-of-day word -> fixed "HH:mm" (e.g. German "mittags" -> "12:00")
    // Feedback round 3: "morning"/"evening" etc. span hours, not a single instant — guessing a
    // specific clock time for them was actively wrong (a real-device report: "shopping tomorrow
    // morning" got assigned an evening time by NSDataDetector's own date resolution). These set
    // ONLY a qualitative label (ExtractedTask.timeOfDay), never a dueTime.
    let vagueTimeOfDayWords: [String: String]  // vague word -> canonical display label ("morning")
    // "later"/"später" etc.: resolves to referenceDate + a fixed offset (6h) rather than just
    // "today with no time" — a specific, computed answer per explicit user request.
    let laterOffsetWords: [String]
    let priorityPrefixes: [(pattern: String, priority: TaskPriority)]
    let categoryKeywords: [TaskCategory: [String]]
    // Feedback round 3 — clause-classification pipeline fields:
    let placeKeywords: [String: String]            // lowercase keyword (word-start match) -> canonical place display value
    // Feedback round 5: a street/address name ("Greenwood Avenue") is never going to be in a
    // fixed keyword list — this instead recognizes the SHAPE "at/on/in <words> <street-type
    // word>" and captures the whole phrase, regardless of which specific street it names.
    let addressPattern: String?
    // Real-device feedback (2026-07-04): "add milk to shopping list" / "Milch auf die
    // Einkaufsliste" should route straight into the shopping list rather than becoming a normal
    // dated task. One capture group — the item phrase(s), split on `conjunctionWords`/commas by
    // `RuleBasedExtractionService.shoppingListItems`. Must match the ENTIRE (filler-stripped)
    // line, same convention as `titleReductionRules`/`detailPatterns`, so it can't misfire on a
    // clause that only mentions "shopping list" in passing. nil except en/de today — same
    // "populate only where verified" precedent as STT-1/RDF-2.
    let shoppingListPattern: String?
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
    let sttPatterns: [STTPattern]                  // Milestone 10 (STT-1): recurring transcription-error fixes, applied before segmentation

    // Explicit initializer, not the synthesized memberwise one: Swift's synthesized init does not
    // keep defaulted parameters (vagueTimeOfDayWords/laterOffsetWords) at their declared position
    // — repeated attempts to match its actual generated order (declared position, then end-of-
    // list) both failed to compile ("extra arguments"), so this makes the parameter order and
    // defaults explicit and unambiguous instead of relying on synthesis.
    init(
        code: String,
        weekdayNames: [String: Int],
        todayWords: [String],
        tomorrowWords: [String],
        dayAfterTomorrowWords: [String],
        numberWords: [String: Int],
        inDaysPattern: String?,
        inWeeksPattern: String?,
        weekdayPhraseRules: [WeekdayPhraseRule],
        nextWeekPattern: String?,
        rangeFromWord: String? = nil,
        rangeToWord: String? = nil,
        timePattern: String?,
        timeOfDayWords: [String: String],
        vagueTimeOfDayWords: [String: String] = [:],
        laterOffsetWords: [String] = [],
        priorityPrefixes: [(pattern: String, priority: TaskPriority)],
        categoryKeywords: [TaskCategory: [String]],
        placeKeywords: [String: String],
        addressPattern: String? = nil,
        shoppingListPattern: String? = nil,
        fillerPrefixes: [String],
        fillerWords: [String],
        detailPatterns: [String],
        detailContinuationPrefixes: [String],
        referentialMarkers: [String],
        titleReductionRules: [TitleReductionRule],
        connectorWords: [String],
        conjunctionWords: [String],
        sequentialWords: [String],
        imperativeVerbs: Set<String>,
        verbSuffixes: [String],
        sttPatterns: [STTPattern] = []
    ) {
        self.code = code
        self.weekdayNames = weekdayNames
        self.todayWords = todayWords
        self.tomorrowWords = tomorrowWords
        self.dayAfterTomorrowWords = dayAfterTomorrowWords
        self.numberWords = numberWords
        self.inDaysPattern = inDaysPattern
        self.inWeeksPattern = inWeeksPattern
        self.weekdayPhraseRules = weekdayPhraseRules
        self.nextWeekPattern = nextWeekPattern
        self.rangeFromWord = rangeFromWord
        self.rangeToWord = rangeToWord
        self.timePattern = timePattern
        self.timeOfDayWords = timeOfDayWords
        self.vagueTimeOfDayWords = vagueTimeOfDayWords
        self.laterOffsetWords = laterOffsetWords
        self.priorityPrefixes = priorityPrefixes
        self.categoryKeywords = categoryKeywords
        self.placeKeywords = placeKeywords
        self.addressPattern = addressPattern
        self.shoppingListPattern = shoppingListPattern
        self.fillerPrefixes = fillerPrefixes
        self.fillerWords = fillerWords
        self.detailPatterns = detailPatterns
        self.detailContinuationPrefixes = detailContinuationPrefixes
        self.referentialMarkers = referentialMarkers
        self.titleReductionRules = titleReductionRules
        self.connectorWords = connectorWords
        self.conjunctionWords = conjunctionWords
        self.sequentialWords = sequentialWords
        self.imperativeVerbs = imperativeVerbs
        self.verbSuffixes = verbSuffixes
        self.sttPatterns = sttPatterns
    }
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
        let normalizedLine = applySTTPatterns(line, rulesList: lineRules)
        let clauses = segmentClauses(normalizedLine, rulesList: lineRules)

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
                // Explicit "and then" — the user stated sequencing; that wins over detail rules,
                // verb or not. Previously gated on containsVerb, which silently merged a verbless
                // continuation ("...and then to dinner") back into the first task's title instead
                // of splitting it — the explicit connector is a strong enough signal on its own
                // (segmentClauses already guarantees clause.text is non-empty).
                actions.append(PendingAction(text: clause.text, sequential: true, details: []))
                sawSequential = true
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

    // Milestone 10 (STT-1, swipe-final-architecture.md §0.5): applies each candidate language's
    // sttPatterns — regex find/replace for recurring transcription errors — before segmentation.
    // internal (not private) so it's directly unit-testable with a synthetic LanguageRules, same
    // reasoning as detectLanguage's visibility change in Milestone 7. Packs ship empty sttPatterns
    // today (no real dictation-error data exists to seed them with) — this wires the APPLICATION
    // mechanism now so a future pack update needs zero engine changes, matching the pack system's
    // own governing principle. A no-op today (every shipped pack's sttPatterns is []).
    func applySTTPatterns(_ text: String, rulesList: [LanguageRules]) -> String {
        var result = text
        for rules in rulesList {
            for sttPattern in rules.sttPatterns {
                guard let regex = try? NSRegularExpression(pattern: sttPattern.pattern) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: sttPattern.replacement)
            }
        }
        return result
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
        var dueEndDate: String?
        var dueTime: String?
        var timeOfDay: String?
        var confidence = 1.0
        var rangesToStrip: [Range<String.Index>] = []
        var dateFound = false

        // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday to
        // Saturday" — tried first so a range wins over the single-date matchers below
        // accidentally grabbing just its start or end weekday.
        for rules in rulesList {
            guard let match = dateRangeMatch(in: text, referenceDate: referenceDate, rules: rules) else { continue }
            dueDate = isoDate(match.startDate)
            dueEndDate = isoDate(match.endDate)
            confidence = match.confidence
            rangesToStrip.append(match.range)
            dateFound = true
            break
        }
        if !dateFound {
            for rules in rulesList {
                guard let match = laterOffsetMatch(in: text, referenceDate: referenceDate, rules: rules) else { continue }
                dueDate = isoDate(match.date)
                dueTime = match.time
                confidence = match.confidence
                rangesToStrip.append(match.range)
                dateFound = true
                break
            }
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
            place = placeAddressMatch(in: rawSubLine, rulesList: rulesList)
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
            dueEndDate: dueEndDate,
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

    // A street/address name ("Greenwood Avenue") is never going to be in a fixed keyword list —
    // this recognizes the SHAPE "at/on/in <words> <street-type word>" instead of any specific
    // name, so it generalizes to any address rather than only the ones hand-listed like
    // placeKeywords. Tried against the ORIGINAL line (not the date/time-stripped text) since the
    // address itself is never part of what gets stripped anyway.
    private func placeAddressMatch(in text: String, rulesList: [LanguageRules]) -> String? {
        for rules in rulesList {
            guard let pattern = rules.addressPattern,
                  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let words = text[range].split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return words.joined(separator: " ")
        }
        return nil
    }

    // MARK: - Shopping list detection (real-device feedback, 2026-07-04)

    // "add milk to shopping list" / "Milch auf die Einkaufsliste" — a dedicated cue phrase that
    // routes the whole line into the shopping list instead of the normal task pipeline. Requires
    // a FULL-line match (after filler-stripping), same convention as `reduceTitle`/
    // `isDetailClause`, so an incidental mention of "shopping list" inside an ordinary task
    // ("mention the shopping list at the meeting") can't misfire. Returns nil when no language's
    // `shoppingListPattern` matches — the caller then falls through to normal task extraction.
    func shoppingListItems(in rawLine: String, primaryLanguageCode: String) -> [String]? {
        let rulesList = candidateRules(for: rawLine, primaryLanguageCode: primaryLanguageCode)
        let text = stripFillers(rawLine.trimmingCharacters(in: .whitespaces), rulesList: rulesList)
        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for rules in rulesList {
            guard let pattern = rules.shoppingListPattern,
                  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: fullRange),
                  match.range.location == 0, match.range.length == nsText.length,
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let items = splitConjoinedItems(String(text[range]), rules: rules)
            guard !items.isEmpty else { continue }
            return items
        }
        return nil
    }

    // "milk and eggs" -> ["Milk", "Eggs"] — reuses the same conjunction words line-splitting
    // already relies on, plus a plain comma, so "milk, eggs and bread" also splits correctly.
    private func splitConjoinedItems(_ phrase: String, rules: LanguageRules) -> [String] {
        var parts = [phrase]
        for conjunction in rules.conjunctionWords {
            parts = parts.flatMap { $0.components(separatedBy: " \(conjunction) ") }
        }
        parts = parts.flatMap { $0.components(separatedBy: ",") }
        return parts
            .map { capitalizeFirst($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Language detection (§2)

    // Milestone 7 (CG-2): visible (not private) so ExtractionAccuracyTests' calibration tooling can
    // bucket corpus samples by the same language classification the runtime pipeline actually uses.
    func detectLanguage(_ text: String) -> NLLanguage {
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

    private struct DateRangeMatch {
        let range: Range<String.Index>
        let startDate: Date
        let endDate: Date
        let confidence: Double
    }

    // Real-device feedback (2026-07-03): "business trip to Hamburg from Thursday to Saturday" —
    // scoped to weekday-name ranges only (matches the reported case), reusing weekdayNames and
    // nextOccurrence exactly as weekdayPhraseRules resolution does below. Requires "from" directly
    // before a weekday name, so it can't false-positive on an unrelated "to <place>" earlier in
    // the same line (e.g. "trip to Hamburg" doesn't have "from" + a weekday before "Hamburg").
    // rangeFromWord/rangeToWord are nil for every language except English today — same
    // "mechanism for all, populate only where verified" precedent as Milestone 10's STT-1.
    private func dateRangeMatch(in text: String, referenceDate: Date, rules: LanguageRules) -> DateRangeMatch? {
        guard let fromWord = rules.rangeFromWord, let toWord = rules.rangeToWord,
              !rules.weekdayNames.isEmpty else { return nil }
        let weekdayAlt = rules.weekdayNames.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fromWord))\\s+(\(weekdayAlt))\\s+\(NSRegularExpression.escapedPattern(for: toWord))\\s+(\(weekdayAlt))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let ns = text as NSString
        let name1 = ns.substring(with: match.range(at: 1)).lowercased()
        let name2 = ns.substring(with: match.range(at: 2)).lowercased()
        guard let weekday1 = rules.weekdayNames[name1], let weekday2 = rules.weekdayNames[name2] else { return nil }
        let start = nextOccurrence(of: weekday1, from: today, calendar: calendar, skipToday: false)
        var end = nextOccurrence(of: weekday2, from: today, calendar: calendar, skipToday: false)
        if end < start { end = calendar.date(byAdding: .day, value: 7, to: end)! }
        return DateRangeMatch(range: range, startDate: start, endDate: end, confidence: 0.85)
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
        if let fromWord = rules.rangeFromWord, let toWord = rules.rangeToWord, !rules.weekdayNames.isEmpty {
            let weekdayAlt = rules.weekdayNames.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            patterns.append("\\b\(NSRegularExpression.escapedPattern(for: fromWord))\\s+(\(weekdayAlt))\\s+\(NSRegularExpression.escapedPattern(for: toWord))\\s+(\(weekdayAlt))\\b")
        }
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

// MARK: - Language tables (swipe-final-architecture.md §3 — bundled JSON packs, one per language,
// under AiTaskAssistant/LanguagePacks/. Adding language 9+ is a data + corpus task per that doc's
// rollout checklist (§9); these 8 (en/de/fr/es/it/pt/nl/pl) were migrated as-is from the previous
// compiled-Swift-literal tables, not rebuilt — see LanguagePack.swift for the DTO/loader.)

extension RuleBasedExtractionService {
    static let languageTables: [String: LanguageRules] = LanguagePackLoader.loadAll()
}

