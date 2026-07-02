# PRD Update 01 — Changes to MVP PRD

Apply these changes to the existing MVP PRD. Decisions below override the original where they conflict.

---

## 1. Extraction engine: rules-based core, NOT Foundation Models

**Replaces:** "Apple Foundation Models framework for extraction" as MVP dependency.

- Core extraction engine is rules-based, running on ALL devices (iPhone 13/14 fully supported — this is a hard requirement):
  - `NSDataDetector` for date/time detection per line
  - `NaturalLanguage` framework (`NLLanguageRecognizer`) for per-line language detection
  - Custom rules: date-phrase stripping for title cleanup, keyword matching for priority/category
- **No bundled LLM.** No model download of any size. App stays small (~20 MB class).
- **Foundation Models becomes an optional enhancement layer** (see §5), not an MVP dependency.

## 2. Bilingual parsing is a hard MVP requirement

**New requirement.**

- Users write mixed German/English ("gym membership kündigen", "morgen", "nächsten Freitag")
- Detect language per line via `NLLanguageRecognizer`, then run `NSDataDetector` with the matching locale — wrong locale silently misses German date phrases
- Milestone 0 test corpus must include German and Denglisch lines

## 3. Main screen redesign: messy Apple Notes with inline per-line feedback (Amy pattern)

**Replaces:** the original Slide 1 "single input field + submit" design.

- Slide 1 is a free-form, multi-line notes editor (looks/feels like Apple Notes). No submit button ceremony.
- Input: typing or speech-to-text dictation into the same notes surface
- **Per-line live parsing:** when a line is completed (newline / pause), it's parsed immediately
- **Inline status icon per line** (Amy-style): small icon next to each parsed line showing
  - 1 task created, or
  - N tasks created (when one line splits into multiple tasks)
  - Optionally a subtle "unsure" state when confidence is low (e.g. ambiguous date)
- Detected date phrases get subtle inline highlight (like Notes/Mail link detection)
- Line = default task boundary. Secondary splitting within a line on conjunctions ("and", "und") when two verb phrases are detected.

## 4. Slide 2: structured calendar view, reached by swipe right

**Refines:** original Slide 2 description.

- Swipe right from the notes screen → structured view of all created tasks
- Grouped by due date (Today / Upcoming / No date) — calendar-style organization
- Tap task → inline edit (title, date/time, priority, category)
- Notifications deep-link here
- Notes screen (Slide 1) remains the app's landing screen

## 5. Foundation Models as availability-gated enhancement layer (post-MVP)

**New section.**

- Runtime check: `SystemLanguageModel.default.availability`
- If available (iPhone 15 Pro / 16+, Apple Intelligence enabled): run parsed lines through Foundation Models as a refinement pass — title cleanup, run-on line splitting, mixed-language handling
- If unavailable: rules output ships as-is. **Identical features on all devices; the delta is quality only, never capability.**
- Foundation Models must never be the sole path for any feature
- Note: availability can be false even on new devices (Apple Intelligence off, unsupported region/language) — rules path must be genuinely good

## 6. New rule: punctuation as priority signal

**New extraction rule.**

- Trailing "!" / "!!" on a line → high priority (explicit user signal, consistent with explicit-signal-only principle)

## 7. Milestone 0 revision

**Replaces:** original Milestone 0 scope.

- **Goal:** the rules engine (not Foundation Models) reaches the 90% accuracy target defined in §10 — this is the exit criterion for Milestone 0
- Test corpus: **50–100** realistic **messy multi-line notes** (not clean sentences) — large enough that 90% is a meaningful measurement, small enough to hand-label. Must include:
  - Simple lines: "call max tomorrow", "milk"
  - Priority punctuation: "presentation friday!!"
  - German / mixed: "gym membership kündigen", "zahnarzt anrufen morgen"
  - Run-on lines: "call max tomorrow and finish deck friday"
  - Ambiguous fragments: a bare "friday" line
  - No-date and vague lines: "maybe book flights?"
- Output per line: `[{ title, due_date?, due_time?, priority?, category? }]`
- **Iteration loop (core of Milestone 0):** run corpus → score against hand-labeled expected output → categorize failures (date parsing / title cleanup / task splitting / language detection) → fix the biggest failure category with targeted rules → re-run. Repeat until §10 target is met or a failure category proves rules-resistant.
- Build the corpus + scoring as an automated test suite (XCTest), not a manual review — it becomes the permanent regression suite for every future parser change
- If run-on splitting is the only category blocking 90% → evaluate targeted fixes (verb-phrase detection, conjunction rules) before considering any model

## 8. Device support statement

**New section.**

- Minimum supported: iPhone 13/14 class (A15, 6 GB RAM) — full feature set
- Suggested deployment target: iOS 17
- Foundation Models enhancement: iPhone 15 Pro and newer, when Apple Intelligence is active

## 9. Milestone reordering

- Milestone 0: rules engine validation (per §7)
- Milestone 1: notes screen with per-line parsing + inline icons; swipe to structured view; local storage
- Milestone 2: speech-to-text dictation into notes surface
- Milestone 3: local notifications + deep-link + badge (unchanged)
- Milestone 4: Siri App Intent (unchanged)
- Milestone 5 (post-MVP): Foundation Models enhancement layer (per §5)

## 10. Accuracy target: 90% correct extraction

**New section — binding quality bar for this update cycle.**

- **Target: ≥90% of corpus lines fully correct** by the end of this update. "Fully correct" = title, date/time, task split count, and priority (when signaled) all match the hand-labeled expectation — partial credit doesn't count.
- Measured against the Milestone 0 corpus (§7); the automated test suite is the source of truth
- Track per-category accuracy separately (dates / titles / splitting / language) so fixes are targeted, not guesswork
- Expected easy wins to prioritize first: locale-aware date parsing (§2), date-phrase stripping for titles, "!!" priority rule (§6), line-based splitting
- Expected hardest category: run-on line splitting — acceptable to hit 90% overall with this category below average, as long as single-task lines are near-perfect
- If 90% proves unreachable with rules alone: the fallback decision is a mandatory review affordance on ambiguous lines (inline "unsure" state per §3), NOT adding a bundled model
