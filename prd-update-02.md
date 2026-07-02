# PRD Update 02 — Multi-Language Launch (North America + Europe)

Applies on top of `prd-update-01.md`. Decisions below override/extend it where they conflict.

---

## 1. Market requirement: NA + EU launch, all EU official languages

The app is going to be published in North America and Europe. Date/task extraction must work for
notes written in any of the **24 EU official languages**: Bulgarian, Croatian, Czech, Danish,
Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Irish, Italian, Latvian,
Lithuanian, Maltese, Polish, Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish.

This list already covers North America's practical needs (English, French, Spanish are all in it),
so there is one language list to build against, not two.

**This supersedes `prd-update-01.md` §2's "bilingual German/English" framing** — German/English
were the first two languages built and validated (Milestone 0); this update generalizes that same
approach to all 24.

## 2. Extraction depth: hand-written rules per language, highest accuracy

**Replaces the "rely on NSDataDetector natively" fallback option considered for this update.**

Every language gets its own hand-written rule table (mirroring what German already has):
relative-date phrases (today/tomorrow/day-after-tomorrow equivalents), weekday names, "in N
days/weeks" patterns, common time-phrase patterns, priority signal words (urgent/asap
equivalents), category keywords. `NSDataDetector` remains the base layer for English-style dates
where it's actually reliable; each language's custom table is what fills its specific gaps, the
same way `RuleBasedExtractionService.englishCustomDateMatch` fills English's "next week" gap today.

No bundled/downloaded model for this — same constraint as `prd-update-01.md` §1, now extended
across all 24 languages, not just two.

## 3. Onboarding language selection

**New requirement — changes how language is resolved per line.**

- On first launch, an onboarding step asks the user to pick their primary language from the 24
  supported languages (defaulting to device locale's language if it's in the list, else English).
- The selected language becomes the **primary** rule table tried for each line — not per-line
  `NLLanguageRecognizer` detection. Per-line detection is downgraded to a **fallback/tie-breaker**:
  if the primary language's rules find nothing, still try the auto-detected language's rules
  before giving up (this preserves today's Denglisch-style mixed-language handling from
  `prd-update-01.md` §2, generalized).
- Rationale: per-line auto-detection is unreliable on short fragments even between just two
  languages (observed directly during Milestone 0 — a 2-3 word line is often too little signal).
  That unreliability only compounds across 24 languages, so asking once, up front, is both cheaper
  to build and more accurate than trying to auto-detect 24 ways every time.
- The selected language is changeable later from settings (not just onboarding).

## 4. Rollout: build and validate in batches, not all 24 at once

**New section — sets expectations for how this gets built.**

Authoring a hand-written, testable rule table per language is real content work, not a mechanical
translation — each language needs its own corpus cases and a real accuracy run (same process as
Milestone 0), not just translated keyword lists nobody has verified. Language coverage rolls out
in batches, each batch going through the same corpus-and-CI-accuracy-loop Milestone 0 established:

- **Batch 0 (done):** English, German — Milestone 0.
- **Batch 1:** French, Spanish, Italian, Portuguese, Dutch, Polish — largest remaining EU
  populations.
- **Batch 2+:** Swedish, Danish, Finnish, Greek, Czech, Slovak, Hungarian, Romanian, Bulgarian,
  Croatian, Slovenian, Estonian, Latvian, Lithuanian, Maltese, Irish.

**Known quality risk:** these rule tables are being hand-written without native-speaker review.
Confidence is higher for languages with broad, well-documented vocabulary (French, Spanish,
Italian, Portuguese, Dutch, Polish, Swedish, Danish) and markedly lower for ones with less
predictable grammar/idiom coverage from general knowledge alone (Finnish, Hungarian, Estonian,
Latvian, Lithuanian, Maltese, Irish). Before shipping a language publicly, a native-speaker or
professional-translation review pass of that language's rule table and category/priority keyword
list is recommended — flag this explicitly rather than silently shipping unverified rules.

## 5. Milestone reordering

- Milestone 0: rules engine validation for English/German (done, 100% on the corpus)
- **Milestone 0.5 (new): multi-language architecture + onboarding + Batch 1 languages**
- Milestone 1: notes screen redesign (per `prd-update-01.md` §3/§4) — the onboarding language
  picker becomes the very first screen shown before the notes surface
- Milestones 2–5: unchanged from `prd-update-01.md` §9
- **Milestone 6 (new, post-launch): Batch 2+ language rollout**, each with its own corpus +
  accuracy validation, plus the native-speaker review pass from §4
