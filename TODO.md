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

- [ ] **L-1** Refactor `RuleBasedExtractionService`'s German-specific rule logic into a data-driven,
      per-language rule table structure (weekdays, relative-date phrases, time-phrase patterns,
      priority/category keywords keyed by language code) so adding a language doesn't mean
      duplicating control flow — German's existing rules become the first table under this structure
- [ ] **L-2** Add an onboarding screen: pick primary language from the 24 supported, defaulting to
      device locale if supported else English (§3). Store the selection (e.g. `@AppStorage`),
      editable later from settings
- [ ] **L-3** Wire primary-language-first resolution: try the onboarding-selected language's rules
      first, fall back to per-line `NLLanguageRecognizer`-detected language's rules, matching §3's
      "ask once, still handle mixed lines" approach
- [ ] **L-4** Author Batch 1 rule tables: French, Spanish, Italian, Portuguese, Dutch, Polish (§4)
- [ ] **L-5** Extend the corpus with cases per Batch 1 language and validate via the CI accuracy
      harness (same loop as U0-8) until each language is in good shape; document results and any
      known gaps in `IMPLEMENTATION-LOG.md`
- [ ] **L-6** Flag remaining languages (Swedish, Danish, Finnish, Greek, Czech, Slovak, Hungarian,
      Romanian, Bulgarian, Croatian, Slovenian, Estonian, Latvian, Lithuanian, Maltese, Irish) as
      Milestone 6 follow-up work, not silently shipped unverified

## Milestone 1 — Notes Screen + Structured View Redesign

- [ ] **U1-1** Redesign `NoteView` (Slide 1) as a free-form, multi-line notes editor (Apple Notes
      look/feel) — remove the submit-button ceremony (§3)
- [ ] **U1-2** Wire per-line live parsing: when a line is completed (newline / pause), parse it
      immediately via `RuleBasedExtractionService`
- [ ] **U1-3** Add inline per-line status icon (Amy pattern): "1 task", "N tasks", or a subtle "unsure"
      state on low date confidence
- [ ] **U1-4** Add subtle inline highlighting of detected date phrases within the note text
- [ ] **U1-5** Update `TaskItem`/persistence so tasks are traceable back to their source line (needed for
      re-parsing a line on edit without duplicating tasks)
- [ ] **U1-6** Update `AssistantView` (Slide 2, reached by swipe right): confirm grouping (Today /
      Upcoming / No date) and tap-to-edit still work against the new save path (§4)
- [ ] **U1-7** Confirm notes screen (Slide 1) remains the app's landing screen; remove any now-dead
      code from the old single-field submit flow

## Milestone 2 — Voice Input into Notes Surface

- [ ] **U2-1** Adapt mic/dictation to insert transcribed text into the notes surface (multi-line) rather
      than a single text field, respecting per-line parsing as dictation produces line breaks
- [ ] **U2-2** Validate multi-task splitting and bilingual parsing with dictated input; tune rules if
      needed

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
