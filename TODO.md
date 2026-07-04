# AI Task Assistant — TODO (PRD Updates 01 + 02)

> Workflow: Before starting any item, re-read `prd-update-01.md` and `prd-update-02.md`. After
> finishing any item, re-read them again before starting the next one, to keep the end-to-end
> vision in view.
> Log every completed item in `IMPLEMENTATION-LOG.md`.
> Original MVP TODO/history is preserved in git log — this file supersedes it.

**Key pivot from MVP:** the bundled MLX LLM (`mlx-community/Llama-3.2-1B-Instruct-4bit`) extraction
pipeline built during MVP is being removed entirely. Extraction becomes rules-based
(`NSDataDetector` + `NaturalLanguage`), runs on all devices, no model download. Foundation Models
becomes an optional post-MVP enhancement layer only (§5). See `prd-update-01.md` §1.

**Market expansion (prd-update-02.md):** launching in North America + Europe means extraction must
work across all 24 EU official languages (which already covers NA's English/French/Spanish), each
with its own hand-written rule table validated the same corpus-and-CI way Milestone 0 was. Rolled
out in batches (§4), not all at once. An onboarding language picker (§3) sets the primary language
per user instead of relying solely on per-line auto-detection.

---

## Milestone 0 — Rules Engine Validation

- [x] **U0-1** Remove MLX/bundled-LLM extraction pipeline: delete `MLXLLM`/`MLXLMCommon` usage in
      `ExtractionService.swift`, delete `ModelLoadingView.swift` + `LLMState`, remove package
      dependencies from `project.pbxproj`, unwire `ContentView`'s loading-gate
- [x] **U0-2** Build hand-labeled test corpus (50–100 messy multi-line notes) per §7 — include simple
      lines, `!!` priority lines, German/Denglisch lines, run-on lines, bare ambiguous fragments,
      no-date/vague lines. Store as a fixture (e.g. JSON) with expected `{title, due_date?, due_time?,
      priority?, category?}` per line
- [x] **U0-3** Build `RuleBasedExtractionService`: per-line `NLLanguageRecognizer` detection feeding the
      matching locale into `NSDataDetector` for date/time extraction (§2)
- [x] **U0-4** Add title cleanup rules (strip matched date phrases from the title text)
- [x] **U0-5** Add keyword-matching rules for priority/category, including the `!`/`!!` trailing-punctuation
      → high-priority rule (§6)
- [x] **U0-6** Add line-splitting rules: line is the default task boundary; secondary split on
      conjunctions ("and"/"und") when two verb phrases are detected
- [x] **U0-7** Build an XCTest scoring harness that runs the corpus through the service, diffs against
      expected output, and reports per-category accuracy (dates / titles / splitting / language) —
      this becomes the permanent regression suite
- [x] **U0-8** Iterated via GitHub Actions (macos-15 runner) since no local Mac is available: 73% →
      93% → **100% (64/64)** across dates/splitting/language/priority/ambiguous/noDate. §10 target
      met and exceeded. See `IMPLEMENTATION-LOG.md` for the specific bugs found and fixed each round

## Milestone 0.5 — Multi-Language Architecture + Onboarding + Batch 1 (prd-update-02.md)

- [x] **L-1** Refactor `RuleBasedExtractionService`'s German-specific rule logic into a data-driven,
      per-language rule table structure (weekdays, relative-date phrases, time-phrase patterns,
      priority/category keywords keyed by language code) so adding a language doesn't mean
      duplicating control flow — German's existing rules become the first table under this structure
- [x] **L-2** Add an onboarding screen: pick primary language from the 24 supported, defaulting to
      device locale if supported else English (§3). Store the selection (e.g. `@AppStorage`),
      editable later from settings
- [x] **L-3** Wire primary-language-first resolution: try the onboarding-selected language's rules
      first, fall back to per-line `NLLanguageRecognizer`-detected language's rules, matching §3's
      "ask once, still handle mixed lines" approach
- [x] **L-4** Author Batch 1 rule tables: French, Spanish, Italian, Portuguese, Dutch, Polish (§4)
- [x] **L-5** Extend the corpus with cases per Batch 1 language and validate via the CI accuracy
      harness (same loop as U0-8) until each language is in good shape — **100% (94/94)** across all
      8 languages (en/de/fr/es/it/pt/nl/pl). Not native-speaker verified — see `IMPLEMENTATION-LOG.md`
      quality-risk note before treating this as launch-ready
- [ ] **L-6** Flag remaining languages (Swedish, Danish, Finnish, Greek, Czech, Slovak, Hungarian,
      Romanian, Bulgarian, Croatian, Slovenian, Estonian, Latvian, Lithuanian, Maltese, Irish) as
      Milestone 6 follow-up work, not silently shipped unverified

## Milestone 0.6 — Language Pack JSON Migration (swipe-final-architecture.md, Phase 1)

- [x] **LP-1** Move the 8 shipped languages' `LanguageRules` (en/de/fr/es/it/pt/nl/pl) from compiled
      Swift struct literals to bundled JSON packs (`AiTaskAssistant/LanguagePacks/*.json`), per
      `swipe-final-architecture.md` §3's governing principle: language knowledge lives in data
      packs, never engine code. Pure data migration — engine logic (segmentation, clause
      classification, date/time extraction, etc.) and `LanguageRules` itself are unchanged. New
      `LanguagePack.swift` adds the DTO/loader layer. All 8 languages carried forward as-is.
- [x] **LP-2** Wire the 8 JSON packs into the Xcode project as bundled app-target resources
      (`project.pbxproj`), verified they load via `Bundle.main` in both the real app and the
      test-hosted `AiTaskAssistantTests` target.
- [x] **LP-3** CI regression run surfaced a **pre-existing, migration-unrelated** bug: English has
      no bare-weekday `weekdayPhraseRules` (unlike every other language) and no `timePattern` for
      am/pm times, so it relies entirely on `NSDataDetector` for both. On a day where "today" is
      literally the named weekday, `NSDataDetector` resolves a bare weekday name to *next* week's
      occurrence instead of today (6 corpus cases: 6, 17, 22, 28, 30, 32 — all "friday"-related).
      Confirmed unrelated to the migration: English's `weekdayPhraseRules` is `[]` in both the old
      and new code (byte-identical), German's equivalent bare-weekday case (23, "freitag") passes
      via the engine's own `nextWeekdayDate` logic, and the failure was 100% reproducible across two
      independent CI runs (not flaky). A minimal fix (add English's own bare-weekday rule, mirroring
      German/French's pattern) was considered but rejected here — it would make `customDateMatch`
      claim the date first and skip `englishDateMatch`, which is also the *only* thing extracting
      12-hour am/pm times for English today (case 28's "3pm" has nowhere else to be parsed, since
      `timePattern` is `nil` and `timeOfDayWords` only covers "noon"/"midday"). Properly fixing this
      needs an engine-level am/pm time parser, not just a data change — tracked as **LP-4** below,
      not fixed as part of this data-only migration.
- [ ] **LP-4** (follow-up) Add an English bare-weekday date rule *and* an am/pm-capable
      `timePattern` (with engine support to interpret am/pm — the `timePattern` contract today is
      hour + optional minute only, no am/pm group) so English's date/time resolution stops depending
      entirely on `NSDataDetector`. This is an engine change, not a pack-only addition — plan and
      test it as its own unit of work, not bundled into another change.

## Milestone 1 — Notes Screen + Structured View Redesign

- [x] **U1-1** Redesign `NoteView` (Slide 1) as a free-form, multi-line notes editor (Apple Notes
      look/feel) — remove the submit-button ceremony (§3). Lines now persist as `NoteLine` records
      instead of one ephemeral text field
- [x] **U1-2** Wire per-line live parsing: when a line is completed (newline / pause), parse it
      immediately via `RuleBasedExtractionService`. Implemented via return-key commit; debounced
      "pause without pressing return" detection was not attempted (see IMPLEMENTATION-LOG.md)
- [x] **U1-3** Add inline per-line status icon (Amy pattern): "1 task", "N tasks", or a subtle "unsure"
      state on low date confidence
- [x] **U1-4** Add subtle inline highlighting of detected date phrases within the note text —
      `RuleBasedExtractionService.highlightRanges(in:primaryLanguageCode:)` reuses the same
      per-language patterns extraction matches against
- [x] **U1-5** Update `TaskItem`/persistence so tasks are traceable back to their source line (needed for
      re-parsing a line on edit without duplicating tasks) — `TaskItem.sourceLineID`
- [x] **U1-6** Update `AssistantView` (Slide 2, reached by swipe right): confirm grouping (Today /
      Upcoming / No date) and tap-to-edit still work against the new save path (§4) — needed no
      changes, it only ever queried `TaskItem` directly
- [x] **U1-7** Confirm notes screen (Slide 1) remains the app's landing screen; remove any now-dead
      code from the old single-field submit flow — removed the onSubmit-triggers-tab-switch wiring;
      Slide 2 is now reached only by swiping, never automatically

**Verification gap:** all of Milestone 1 compiled clean and passed the extraction test suite via CI
(no local Mac/simulator available), but the actual interaction feel — focus handoff between rows,
scroll-to-compose behavior, attributed-string highlight rendering, dictation targeting the compose
row — has not been visually/manually verified on a simulator or device. Do the real-device pass
from `IMPLEMENTATION-LOG.md`'s "Next actions" before considering Milestone 1 truly done.

## Milestone 2 — Voice Input into Notes Surface

- [x] **U2-1** `SpeechRecognizer.formatWithLineBreaks` inserts a line break at speech-pause gaps
      (≥1.2s between `SFTranscriptionSegment`s) instead of one flat transcript string;
      `NoteView.commitDictatedText()` splits the accumulated compose text on those breaks and
      commits each as its own `NoteLine` when recording stops (button tap or auto-finalize via
      `speech.state` leaving `.recording`), reusing the same per-line `reparse` path typed-and-
      returned lines already go through. The existing typing-Return-commits-immediately handler is
      now gated to `!isRecording` so it doesn't fire on dictation's own multi-newline updates.
      **Verification gap, stated explicitly**: no microphone in any CI environment — this compiles
      and passes the corpus suite (zero extraction-logic changes) but is unverified end-to-end;
      needs a real-device pass. The 1.2s pause threshold is an initial, uncalibrated guess.
- [ ] **U2-2** Validate multi-task splitting and bilingual parsing with dictated input; tune rules if
      needed — blocked on the same real-device pass as U2-1's verification gap.

## Milestone 3 — Reminders (carry over, verify against new flow)

- [ ] **U3-1** Verify notification scheduling still fires correctly from the new per-line save path
      (no more single "submit" event to hook)
- [ ] **U3-2** Verify notification tap deep-link and app badge count still work end-to-end

## Milestone 4 — Siri Integration (carry over, verify against new flow)

- [ ] **U4-1** Verify `AddTaskIntent` still opens the app onto the notes surface and activates
      dictation correctly with the redesigned Slide 1

## Milestone 5 — Foundation Models Enhancement Layer (post-MVP, optional)

- [ ] **U5-1** Runtime availability check via `SystemLanguageModel.default.availability`
- [ ] **U5-2** When available: run parsed lines through Foundation Models as a refinement pass (title
      cleanup, run-on splitting, mixed-language handling) — never the sole path for any feature
- [ ] **U5-3** When unavailable: confirm rules output ships as-is with identical features (quality-only
      delta, never a capability gap) (§5, §8)

## Milestone 6 — Batch 2+ Language Rollout (post-launch, prd-update-02.md §4)

- [ ] **L-7** Author + validate remaining EU language rule tables in batches (Swedish, Danish,
      Finnish, Greek, Czech, Slovak, Hungarian, Romanian, Bulgarian, Croatian, Slovenian first —
      larger populations; Estonian, Latvian, Lithuanian, Maltese, Irish after), each going through
      its own corpus + CI accuracy loop before being marked supported
- [ ] **L-8** Native-speaker or professional-translation review pass per language before it's
      surfaced as fully supported in the language picker — confidence from general knowledge alone
      is markedly lower for Finnish, Hungarian, Estonian, Latvian, Lithuanian, Maltese, Irish

## Milestone 7 — Confidence Gate Calibration (swipe-final-architecture.md, Phase 2)

- [x] **CG-1** (partial) Extend the corpus scorer to report per-field accuracy (title / date /
      time / priority) and segmentation precision/recall separately, not just per-line pass/fail
      and per-`focus` bucket — both derivable from the existing 101-case corpus with zero schema
      changes; new `LineFieldScore`/`fieldScore()` in `ExtractionAccuracyTests.swift`, printed as
      diagnostics (not yet a hard-gated assertion — that's CG-2). **Category scoring deferred**:
      `category` is deliberately excluded from `ExpectedTask` (see its own policy comment) — adding
      it means deciding whether to backfill all 101 cases or make it optional/incremental; not
      attempted in this pass.
- [x] **CG-2** (diagnostic only) Threshold-calibration tooling in `ExtractionAccuracyTests.swift`:
      per-task `ConfidenceSample`s (language via `RuleBasedExtractionService.detectLanguage`, now
      internal instead of private) + `calibrateThreshold()` (lowest t where precision on
      confidence-≥-t tasks is ≥ 98%, swept only at distinct observed confidence values) + a new
      `confidenceGateCalibration()` test printing overall and per-language results, flagging any
      bucket under 20 samples as statistically unreliable rather than reporting it as trustworthy.
      Runs every CI build, per the doc's "re-run on every engine or pack change." **Not wired into
      the app**: see CG-2b.
- [ ] **CG-2b** Replace `RuleBasedExtractionService.lowConfidenceThreshold`'s single fixed 0.7 with
      the calibrated per-language values CG-2 now computes. Blocked less by engineering effort than
      by data: today's corpus has ~5 cases per Batch 1 language, nowhere near enough for a
      trustworthy 98%-precision estimate — revisit once Milestone 6 grows those corpora. Needs a
      storage decision too (new Swift dict? a section in each `LanguagePack` JSON?) plus updating
      `isLowConfidence(_:)` and its two call sites to be language-aware.
- [x] **CG-3** Centralize the confidence gate — `RuleBasedExtractionService.isLowConfidence(_:)` /
      `.lowConfidenceThreshold` replaces the `dateConfidence < 0.7` literal previously duplicated in
      both `NoteView.swift` and `AssistantView.swift`. Still date-confidence-only (no
      title/priority/segmentation confidence exists yet) — CG-2b's calibrated threshold is the next
      thing to plug in here.

## Milestone 8 — Entity Memory (swipe-final-architecture.md, Phase 3)

- [x] **EM-1** Added `EntityMemory` SwiftData `@Model` (`entity`, `type`, `categoryHint`,
      `frequency`, `confidence`, `lastSeen`, `source`), following `TaskItem`/`NoteLine`'s exact
      conventions. Registered in all 4 `.modelContainer` call sites (`AiTaskAssistantApp.swift`
      plus 3 `#Preview` blocks in `ContentView.swift`/`NoteView.swift`/`AssistantView.swift`).
- [x] **EM-2** (partial, **currently disabled** — see EM-2d) `EntityMemoryService.recordMention`/
      `recordCorrection` implement stage 6 (user correction → confidence 1.0 overwrite, wired from
      `TaskEditView`'s "Done" button via an on-appear snapshot + diff of `place`) and the AUTO side
      of stage 3's recording rules (unknown entity → low confidence; repeat mention → frequency
      grows, confidence climbs, capped at 1.0 — wired from `NoteView.reparse`). No hardcoded global
      entity lists — per-user learned entities only. **Not done**: actually feeding entity memory
      back into extraction confidence (the "resolution + confidence adjustment" half of stage 3) —
      needs real accumulated data to design a defensible formula against, and a distinct API change
      to `RuleBasedExtractionService`. Also not done: person/thing entity extraction — the engine
      only extracts `place` today, so `EntityType.person`/`.thing` are modeled but never populated.
- [ ] **EM-2d** (new, urgent) Both `EM-2` call sites are commented out as an emergency crash fix —
      see IMPLEMENTATION-LOG.md's "Emergency fix" entry. Real crash logs from TestFlight build 10
      (2026-07-03, iPhone 14 / iOS 26.5) show a reproducible `EXC_CRASH`/`SIGABRT`
      (`swift_dynamicCastFailure` inside SwiftData's `DefaultStore.createSnapshot`) on both fetch
      (`EntityMemoryService.find`) and save (`ModelContext.save()`) paths involving `EntityMemory`
      — reproducible even on a completely fresh install, so not a migration/stale-data issue. No
      documented fix found; looks like an iOS 26.5-era SwiftData bug, not a schema mistake (the
      model is plain primitives, no native enums, no relationships). Needs either a real fix
      (workaround the specific SwiftData bug, once identified) or a deliberate decision to
      re-architect how `EntityMemory` is persisted before re-enabling.
- [ ] **EM-2b** Wire entity memory into extraction confidence (stage 3's other half) once there's
      enough real recorded data to calibrate against.
- [ ] **EM-2c** Person/thing entity extraction — a prerequisite for EM-2/EM-2b to ever populate
      `EntityType.person`/`.thing`; doesn't exist in the engine at all today.
- [ ] **EM-3** Optional Contacts seeding at onboarding (permission-gated) to mitigate cold start.

## Milestone 9 — Foundation Models Fallback (swipe-final-architecture.md, Phase 4)

- [x] **FM-1** Runtime availability double-gate — `FoundationModelsFallback.isAvailable(forLanguageCode:)`
      checks device (`SystemLanguageModel.default.availability == .available`) AND language support
      (`SystemLanguageModel.default.supportsLocale(_:)`), behind `#if canImport(FoundationModels)` +
      `@available(iOS 26, *)`. Callable unconditionally from anywhere (returns `false` outside that
      guard) — deployment target stays iOS 17.0, this is purely additive, never a hard dependency.
- [x] **FM-2** (scaffolding only) `SystemLanguageModel(useCase: .contentTagging)`, `@Generable`
      `RefinedFields` schema (title / dueDate / `@Guide(.anyOf(...))`-constrained priority), guided
      generation only via `LanguageModelSession.respond(to:generating:)` — no free-text parsing.
      **Not wired into `RuleBasedExtractionService.extractLine`** — that function is fully
      synchronous today; threading an async FM call into it is a real pipeline change, and its
      actual behavior can't be verified in CI regardless (no Apple Intelligence hardware exists on
      any CI runner, ever — this is a permanent ceiling, not a "current tooling" gap).
- [ ] **FM-2b** Wire `FoundationModelsFallback.refine(...)` into `extractLine`'s stage-4 confidence
      gate (call only when `RuleBasedExtractionService.isLowConfidence` is true; the caller decides
      whether to call refine, not `refine` itself). Needs its own design pass for the sync→async
      transition, and real-device testing once available (simulators can't run Apple Intelligence).
- [x] **FM-3** On-device-only enforced by convention (this project has no lint tooling): every
      reference goes through `SystemLanguageModel.default`, documented directly in
      `FoundationModelsFallback.swift` as a review-checklist item — never construct a session
      against a remote/cloud configuration.

## Milestone 10 — STT Normalization (swipe-final-architecture.md, Phase 0.5)

- [x] **STT-1** `STTPattern` (regex `pattern`/`replacement`) added to `LanguageRules`, wired through
      `LanguagePackDTO.toLanguageRules()` (was previously decoded and silently discarded).
      `RuleBasedExtractionService.applySTTPatterns` applies each candidate language's patterns
      before segmentation, wired into `extractLine` as stage 0.5. All 8 packs still ship
      `sttPatterns: []` — no real dictation-error data exists yet to seed them with (same
      "grows from corpus failures only" rule the rest of the pack system follows) — so this is a
      provable no-op today: the corpus suite's overall accuracy must stay exactly 105/113 (92%),
      verified against CI before merge. Adding a pattern to a pack needs zero further engine
      changes.
- [x] **STT-2** `EntityMemoryService.levenshteinDistance`/`fuzzyMatch` — Levenshtein ≤ 2 lookup
      against stored entities, unit-tested standalone (near-miss matches, distance-3 doesn't, an
      exact match returns `nil`). **Not wired into the extraction pipeline** — needs a
      `ModelContext`, which `extractLine` doesn't take today; giving it one is a real
      signature/threading change to the pipeline every corpus test depends on. See **STT-2b**
      below.
- [ ] **STT-2b** (new follow-up) Wire `EntityMemoryService.fuzzyMatch` into the live extraction
      pipeline — needs a `ModelContext`-threading design pass through `extractLine` (or a
      pre/post-processing hook at a call site that already has one, e.g. `NoteView.reparse`), plus
      a decision on which extracted substrings are worth fuzzy-checking as proper-noun candidates
      in the first place. Same shape as CG-2b/EM-2b/FM-2b: deferred because it's an architecture
      decision, not because the underlying capability isn't ready.

## Real-device feedback fixes (2026-07-03)

- [x] **RDF-1** Verbless `.sequential` clauses ("...and then to dinner") now become their own task
      instead of silently merging into the previous task's title — `extractLine`'s `.sequential`
      branch (`RuleBasedExtractionService.swift`) dropped the `containsVerb` gate, since the
      explicit "and then"/"und dann" connector is a strong enough signal on its own. Title reads
      literally ("To dinner"), not an inferred-verb form ("Go to dinner") — a known cosmetic
      limitation, not solved here. Zero corpus risk confirmed before the change (no existing test
      case exercised the `.sequential` branch at all).
- [x] **RDF-2** Weekday-name date ranges ("business trip to Hamburg from Thursday to Saturday") —
      new `ExtractedTask.dueEndDate`/`TaskItem.dueEndDate`, a new `dateRangeMatch` matcher
      (`RuleBasedExtractionService.swift`), and two new per-language fields
      (`rangeFromWord`/`rangeToWord`). **English only** for now — every other pack leaves these
      `null` (decodes to `nil` automatically), matching STT-1's "populate only where verified"
      precedent. Discovered along the way: `en.json`'s `weekdayNames` was empty (`{}`) — English
      has always relied entirely on `NSDataDetector` for weekday resolution (see the pre-existing
      Friday-bug). Populated it with the standard 1=Sun...7=Sat mapping so `dateRangeMatch` has
      something to resolve against; `weekdayPhraseRules` stays empty, so this doesn't change bare
      "friday"-style single-date behavior or the known Friday-bug baseline at all — only the new
      range matcher consumes it. UI: `TaskEditView` gets a "Has end date" toggle mirroring "Has due
      date" exactly; `AssistantView`'s task row renders `"Jul 9 – Jul 11"` when a range is present.

## Real-device feedback fixes (2026-07-04)

- [x] **RDF-3** German `addressPattern` required a leading preposition ("in der"/"an der"/"bei
      der"/"in"/"an"/"bei") before a street name — "Meeting Rosenstraße" (no preposition) wasn't
      recognized at all. The preposition group in `de.json`'s `addressPattern` is now optional, so
      the street-type-suffix shape alone (`straße`/`strasse`/`allee`/`weg`/`platz`/`gasse`) is
      enough to match, same as before when a preposition WAS present.
- [x] **RDF-4** German date ranges ("Trip nächste Woche von Dienstag bis Donnerstag") produced no
      range at all — `dateRangeMatch` (RDF-2) requires `rangeFromWord`/`rangeToWord`, which were
      `null` for every language except English. Populated `de.json`'s `dateRules.rangeFromWord`/
      `rangeToWord` with "von"/"bis" — same mechanism, no engine changes needed, matching RDF-2's
      "populate only where verified" precedent.
- [x] **RDF-5** Dictation only ever recognized English regardless of the app's chosen note-taking
      language — `SpeechRecognizer` built its `SFSpeechRecognizer` from `Locale.current` (the
      device's system language) once at `init()`, never from `primaryLanguageCode`. Now rebuilt
      per-recording from a `languageCode` parameter (`SpeechRecognizer.swift`), mapped to a
      region-qualified locale identifier (e.g. "de" -> "de-DE"); `NoteView` passes
      `primaryLanguageCode` in.
- [x] **RDF-6** "add milk to shopping list" / "Milch auf die Einkaufsliste" now routes into a new
      Shopping list feature instead of becoming a normal task — `RuleBasedExtractionService.
      shoppingListItems` (new `shoppingListPattern` per-language field, en/de populated, same
      "populate only where verified" precedent), a new `ShoppingItem` model, and `ShoppingListView`
      (reachable from Notebook's new top-bar cart icon). `NoteView`'s three commit paths
      (`commitCompose`/`commitDictatedText`/`commitLine`) check the cue phrase first and skip
      normal `NoteLine`/task creation when it matches.

## Design pass — swipe-design-concept.md "Lime v4" (2026-07-04)

- [x] Bundled Bricolage Grotesque + Outfit (OFL, from google/fonts) under `AiTaskAssistant/Fonts/`,
      registered via `UIAppFonts` in Info.plist. **NOT verified on-device** (no Mac toolchain in
      this environment) — see the font-name caveat in `Theme.swift`'s `Typography` doc comment
      before assuming the display font is actually rendering as Bricolage Grotesque rather than a
      silent system-font fallback.
- [x] New `DesignSystem/Theme.swift` — the Lime palette (§3), typography scale (§5), and the
      category-icon mapping (§4, `TaskCategoryType` has 6 cases vs. the doc's 3, so the extra 3
      were given icons in the same spirit rather than left inconsistent).
- [x] Notebook (`NoteView`) restyled to §6: top bar now just calendar/cart (center) + settings
      (top-right), status icons only render for fields actually found (previously always-visible
      with crossed-out variants for absent fields), stat bar is now three tappable Open/Today/Week
      pills that filter Week. **Line-tap-to-edit behavior deliberately left unchanged** (explicit
      user decision) even though §6 describes tap-to-complete — see the doc comment on
      `TaskEditView`/`WeekView` "Detail"/"Week" for where completion actually happens now.
- [x] `AssistantView` renamed to `WeekView` and rebuilt to §6 "Week": 7-day strip (today filled
      lime), category legend, day-grouped rounded cards with a lime/grey open-vs-done accent bar,
      dashed-border "No date" section, and a stat-bar filtered mode (header swap + "Show all" chip).
- [x] `TaskEditView` restyled to §6 "Detail": category chip menu, lime-filled primary "Mark as
      done"/"Mark as not done" button, and a new quiet destructive "Delete task" action (didn't
      exist before this pass at all).
- [x] New minimal `SettingsView` (language picker only) and `ShoppingListView`, both reachable from
      Notebook's restyled top bar — the doc's §7 "Settings — icon exists, screen doesn't" and
      "Shopping list" open questions.
- Still open per the doc's own §7 list (not attempted here): swipe-to-delete anywhere, and
      designed empty states beyond the plain ones added to Week/Shopping list.
