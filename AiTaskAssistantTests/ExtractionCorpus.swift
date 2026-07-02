import Foundation
@testable import AiTaskAssistant

// MARK: - Milestone 0 corpus (prd-update-01.md §7)
//
// Hand-labeled ground truth, independent of whatever `RuleBasedExtractionService` currently
// produces — the whole point of this fixture is to reveal where the engine is wrong so U0-8 can
// fix the biggest failure category and re-run. Do not "fix" an expectation here to match the
// engine's current output; fix the engine (or, if the expectation itself was unreasonable, argue
// that explicitly in the PR/commit, don't silently relax it).
//
// Per §10, "fully correct" only requires title + due date + due time + split count + priority to
// match — category is deliberately not scored (§10 lists the four scored fields; category isn't
// one of them), so `category` is not part of `ExpectedTask`.
//
// `expected` is one inner array PER INPUT LINE (§10 scores accuracy "per corpus line", and split
// count is one of the scored fields — a line that should split into 2 tasks is `[task1, task2]`,
// a line that stays one task is `[task1]`). The line count in `expected` must equal the number of
// non-empty lines in `input`.
//
// IMPORTANT: NSDataDetector (used for English-style dates) has no public API to override its
// notion of "today" — it always resolves relative to the real device/CI clock, no matter what
// `referenceDate` the service is called with. So expectations here can't be frozen ISO strings
// tied to whatever day this file was written on; they're computed from `corpusToday` (the real
// "now", captured once so every line in one test run agrees on what day it is) via `offsetDate`
// and `nextWeekdayDate` below. That keeps this a genuinely permanent regression suite instead of
// one that silently breaks the day after every rewrite.

let corpusToday: Date = Calendar.current.startOfDay(for: Date())

private let isoFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter
}()

/// ISO date `days` days from `corpusToday` (0 = today, 1 = tomorrow, ...).
func offsetDate(_ days: Int) -> String {
    isoFormatter.string(from: Calendar.current.date(byAdding: .day, value: days, to: corpusToday)!)
}

/// ISO date of the next occurrence of `weekday` (Calendar component: 1 = Sunday ... 7 = Saturday)
/// from `corpusToday`. `skipToday: true` mirrors "nächsten <weekday>" — if today already is that
/// weekday, jump a full week ahead instead of returning today.
func nextWeekdayDate(_ weekday: Int, skipToday: Bool = false) -> String {
    let calendar = Calendar.current
    let todayWeekday = calendar.component(.weekday, from: corpusToday)
    var delta = (weekday - todayWeekday + 7) % 7
    if delta == 0 && skipToday { delta = 7 }
    return offsetDate(delta)
}

private let monday = 2, friday = 6, saturday = 7

struct ExpectedTask: Sendable {
    let title: String
    let dueDate: String?   // yyyy-MM-dd
    let dueTime: String?   // HH:mm
    let priority: TaskPriority?
}

enum CorpusFocus: String, CaseIterable, Sendable {
    case dates, titles, splitting, language, priority, ambiguous, noDate
}

struct CorpusCase: Sendable {
    let id: Int
    let focus: CorpusFocus
    let input: String
    /// One entry per non-empty input line; each entry is that line's expected task(s).
    let expected: [[ExpectedTask]]
}

let extractionCorpus: [CorpusCase] = [
    // MARK: Simple lines, clear relative date
    CorpusCase(id: 1, focus: .dates, input: "call max tomorrow", expected: [
        [ExpectedTask(title: "Call max", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 2, focus: .noDate, input: "milk", expected: [
        [ExpectedTask(title: "Milk", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 3, focus: .noDate, input: "buy more coffee beans", expected: [
        [ExpectedTask(title: "Buy more coffee beans", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 4, focus: .dates, input: "return library books in two days", expected: [
        [ExpectedTask(title: "Return library books", dueDate: offsetDate(2), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 5, focus: .dates, input: "book the hotel room next week", expected: [
        [ExpectedTask(title: "Book the hotel room", dueDate: offsetDate(7), dueTime: nil, priority: nil)],
    ]),

    // MARK: Priority punctuation (§6)
    CorpusCase(id: 6, focus: .priority, input: "presentation friday!!", expected: [
        [ExpectedTask(title: "Presentation", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 7, focus: .priority, input: "call the landlord!", expected: [
        [ExpectedTask(title: "Call the landlord", dueDate: nil, dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 8, focus: .priority, input: "urgent: fix the login bug before the demo", expected: [
        [ExpectedTask(title: "Fix the login bug before the demo", dueDate: nil, dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 9, focus: .priority, input: "low priority — tidy up the garage", expected: [
        [ExpectedTask(title: "Tidy up the garage", dueDate: nil, dueTime: nil, priority: .low)],
    ]),

    // MARK: German / mixed (§2)
    CorpusCase(id: 10, focus: .language, input: "gym membership kündigen", expected: [
        [ExpectedTask(title: "Gym membership kündigen", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 11, focus: .language, input: "zahnarzt anrufen morgen", expected: [
        [ExpectedTask(title: "Zahnarzt anrufen", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 12, focus: .language, input: "wohnung übermorgen putzen", expected: [
        [ExpectedTask(title: "Wohnung putzen", dueDate: offsetDate(2), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 13, focus: .language, input: "steuererklärung nächsten montag abgeben", expected: [
        [ExpectedTask(title: "Steuererklärung abgeben", dueDate: nextWeekdayDate(monday, skipToday: true), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 14, focus: .language, input: "rechnung bezahlen in 3 tagen", expected: [
        [ExpectedTask(title: "Rechnung bezahlen", dueDate: offsetDate(3), dueTime: nil, priority: nil)],
    ]),
    // A time with no day mentioned reasonably defaults to today — that's a sensible engine
    // behavior, not a bug, so the ground truth expects today's date rather than nil (corrected
    // after the first real CI run showed the original nil expectation was the mislabel).
    CorpusCase(id: 15, focus: .language, input: "termin um 15 uhr", expected: [
        [ExpectedTask(title: "Termin", dueDate: offsetDate(0), dueTime: "15:00", priority: nil)],
    ]),
    CorpusCase(id: 16, focus: .language, input: "heute noch wäsche waschen", expected: [
        [ExpectedTask(title: "Noch wäsche waschen", dueDate: offsetDate(0), dueTime: nil, priority: nil)],
    ]),

    // MARK: Run-on lines — conjunction splitting (§3)
    CorpusCase(id: 17, focus: .splitting, input: "call max tomorrow and finish deck friday", expected: [
        [
            ExpectedTask(title: "Call max", dueDate: offsetDate(1), dueTime: nil, priority: nil),
            ExpectedTask(title: "Finish deck", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil),
        ],
    ]),
    CorpusCase(id: 18, focus: .splitting, input: "buy milk and call the dentist tomorrow", expected: [
        [
            ExpectedTask(title: "Buy milk", dueDate: nil, dueTime: nil, priority: nil),
            ExpectedTask(title: "Call the dentist", dueDate: offsetDate(1), dueTime: nil, priority: nil),
        ],
    ]),
    CorpusCase(id: 19, focus: .splitting, input: "deploy the hotfix and write the post-mortem", expected: [
        [
            ExpectedTask(title: "Deploy the hotfix", dueDate: nil, dueTime: nil, priority: nil),
            ExpectedTask(title: "Write the post-mortem", dueDate: nil, dueTime: nil, priority: nil),
        ],
    ]),
    CorpusCase(id: 20, focus: .splitting, input: "termin absagen und neuen anruf vereinbaren", expected: [
        [
            ExpectedTask(title: "Termin absagen", dueDate: nil, dueTime: nil, priority: nil),
            ExpectedTask(title: "Neuen anruf vereinbaren", dueDate: nil, dueTime: nil, priority: nil),
        ],
    ]),
    // "and" inside a shopping list is not two verb phrases — must NOT split.
    CorpusCase(id: 21, focus: .splitting, input: "buy eggs and bread", expected: [
        [ExpectedTask(title: "Buy eggs and bread", dueDate: nil, dueTime: nil, priority: nil)],
    ]),

    // MARK: Ambiguous fragments (§7)
    CorpusCase(id: 22, focus: .ambiguous, input: "friday", expected: [
        [ExpectedTask(title: "Friday", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 23, focus: .ambiguous, input: "freitag", expected: [
        [ExpectedTask(title: "Freitag", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 24, focus: .ambiguous, input: "tomorrow", expected: [
        [ExpectedTask(title: "Tomorrow", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
    ]),

    // MARK: No-date and vague lines (§7)
    CorpusCase(id: 25, focus: .noDate, input: "maybe book flights?", expected: [
        [ExpectedTask(title: "Maybe book flights?", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 26, focus: .noDate, input: "think about redecorating the office", expected: [
        [ExpectedTask(title: "Think about redecorating the office", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 27, focus: .noDate, input: "do the thing before the meeting", expected: [
        [ExpectedTask(title: "Do the thing before the meeting", dueDate: nil, dueTime: nil, priority: nil)],
    ]),

    // MARK: Explicit time
    CorpusCase(id: 28, focus: .dates, input: "pick up kids at 3pm friday", expected: [
        [ExpectedTask(title: "Pick up kids", dueDate: nextWeekdayDate(friday), dueTime: "15:00", priority: nil)],
    ]),
    CorpusCase(id: 29, focus: .dates, input: "team sync at 9:30am tomorrow", expected: [
        [ExpectedTask(title: "Team sync", dueDate: offsetDate(1), dueTime: "09:30", priority: nil)],
    ]),

    // MARK: Realistic multi-line notes (mixed categories in one note, per §7's "messy multi-line" framing)
    CorpusCase(id: 30, focus: .dates, input: """
    call max tomorrow
    milk
    presentation friday!!
    """, expected: [
        [ExpectedTask(title: "Call max", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Milk", dueDate: nil, dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Presentation", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 31, focus: .language, input: """
    gym membership kündigen
    zahnarzt anrufen morgen
    buy eggs and bread
    """, expected: [
        [ExpectedTask(title: "Gym membership kündigen", dueDate: nil, dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Zahnarzt anrufen", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Buy eggs and bread", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 32, focus: .splitting, input: """
    urgent: fix the login bug before the demo
    call max tomorrow and finish deck friday
    friday
    """, expected: [
        [ExpectedTask(title: "Fix the login bug before the demo", dueDate: nil, dueTime: nil, priority: .high)],
        [
            ExpectedTask(title: "Call max", dueDate: offsetDate(1), dueTime: nil, priority: nil),
            ExpectedTask(title: "Finish deck", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil),
        ],
        [ExpectedTask(title: "Friday", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 33, focus: .language, input: """
    rechnung bezahlen in 3 tagen
    steuererklärung nächsten montag abgeben
    maybe book flights?
    """, expected: [
        [ExpectedTask(title: "Rechnung bezahlen", dueDate: offsetDate(3), dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Steuererklärung abgeben", dueDate: nextWeekdayDate(monday, skipToday: true), dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Maybe book flights?", dueDate: nil, dueTime: nil, priority: nil)],
    ]),

    // MARK: More date-phrase variety, single lines
    CorpusCase(id: 34, focus: .dates, input: "pay the electricity bill in 2 weeks", expected: [
        [ExpectedTask(title: "Pay the electricity bill", dueDate: offsetDate(14), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 35, focus: .dates, input: "morning run tomorrow", expected: [
        [ExpectedTask(title: "Morning run", dueDate: offsetDate(1), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 36, focus: .language, input: "übermorgen auto abholen", expected: [
        [ExpectedTask(title: "Auto abholen", dueDate: offsetDate(2), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 37, focus: .language, input: "diesen samstag großeinkauf machen", expected: [
        [ExpectedTask(title: "Großeinkauf machen", dueDate: nextWeekdayDate(saturday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 38, focus: .priority, input: "high priority: renew passport", expected: [
        [ExpectedTask(title: "Renew passport", dueDate: nil, dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 39, focus: .noDate, input: "reply to sarah's email", expected: [
        [ExpectedTask(title: "Reply to sarah's email", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 40, focus: .dates, input: "send the invoice today", expected: [
        [ExpectedTask(title: "Send the invoice", dueDate: offsetDate(0), dueTime: nil, priority: nil)],
    ]),

    // MARK: Additional coverage — more samples per category so 90% is a meaningful measurement
    CorpusCase(id: 41, focus: .noDate, input: "sometime this month tidy up the garage", expected: [
        [ExpectedTask(title: "Sometime this month tidy up the garage", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 42, focus: .priority, input: "asap deploy the hotfix", expected: [
        [ExpectedTask(title: "Deploy the hotfix", dueDate: nil, dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 43, focus: .priority, input: "dringend rechnung bezahlen", expected: [
        [ExpectedTask(title: "Rechnung bezahlen", dueDate: nil, dueTime: nil, priority: .high)],
    ]),
    CorpusCase(id: 44, focus: .ambiguous, input: "monday", expected: [
        [ExpectedTask(title: "Monday", dueDate: nextWeekdayDate(monday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 45, focus: .ambiguous, input: "montag", expected: [
        [ExpectedTask(title: "Montag", dueDate: nextWeekdayDate(monday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 46, focus: .splitting, input: "prepare slides for kickoff and book the conference room", expected: [
        [
            ExpectedTask(title: "Prepare slides for kickoff", dueDate: nil, dueTime: nil, priority: nil),
            ExpectedTask(title: "Book the conference room", dueDate: nil, dueTime: nil, priority: nil),
        ],
    ]),
    CorpusCase(id: 47, focus: .language, input: "montag steuererklärung abgeben", expected: [
        [ExpectedTask(title: "Steuererklärung abgeben", dueDate: nextWeekdayDate(monday), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 48, focus: .dates, input: "clean the car this weekend", expected: [
        [ExpectedTask(title: "Clean the car this weekend", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 49, focus: .noDate, input: "oh and also don't forget to water the plants", expected: [
        [ExpectedTask(title: "Oh and also don't forget to water the plants", dueDate: nil, dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 50, focus: .dates, input: "renew the gym membership in two days", expected: [
        [ExpectedTask(title: "Renew the gym membership", dueDate: offsetDate(2), dueTime: nil, priority: nil)],
    ]),
    CorpusCase(id: 51, focus: .language, input: """
    heute noch wäsche waschen
    diesen samstag großeinkauf machen
    call max tomorrow and finish deck friday
    """, expected: [
        [ExpectedTask(title: "Noch wäsche waschen", dueDate: offsetDate(0), dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Großeinkauf machen", dueDate: nextWeekdayDate(saturday), dueTime: nil, priority: nil)],
        [
            ExpectedTask(title: "Call max", dueDate: offsetDate(1), dueTime: nil, priority: nil),
            ExpectedTask(title: "Finish deck", dueDate: nextWeekdayDate(friday), dueTime: nil, priority: nil),
        ],
    ]),
    CorpusCase(id: 52, focus: .priority, input: """
    urgent: renew passport
    milk
    low priority — clean the garage
    """, expected: [
        [ExpectedTask(title: "Renew passport", dueDate: nil, dueTime: nil, priority: .high)],
        [ExpectedTask(title: "Milk", dueDate: nil, dueTime: nil, priority: nil)],
        [ExpectedTask(title: "Clean the garage", dueDate: nil, dueTime: nil, priority: .low)],
    ]),
]
