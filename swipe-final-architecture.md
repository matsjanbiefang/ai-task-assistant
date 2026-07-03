# Swipe — Final Extraction Architecture

Canonical architecture document. Supersedes Architecture Update 02 and the extraction sections of PRD Update 01. UI/UX decisions (Amy pattern, two-screen swipe navigation) remain as specified in the PRD and are out of scope here.

**Design constraints (non-negotiable):**
- Local-first. No LLM APIs, no network calls for extraction, ever.
- No bundled model. App stays in the ~20 MB class.
- Full functionality on iPhone 13/14 (rules tier).
- Languages scale over time: 8 languages (EN, DE, FR, ES, IT, PT, NL, PL) already built and validated in TestFlight (Batch 1); more added continuously via the rollout checklist (§9).

**Governing principle:** *Adding a language is a data + corpus task, never an engine change.*

---

## 1. Architecture overview

```
┌─────────────────────────────────────────────────┐
│ UI (SwiftUI) — Notes screen / Assistant screen  │
└──────────────────┬──────────────────────────────┘
                   │ raw line in → [Task] out
┌──────────────────▼──────────────────────────────┐
│ EXTRACTION ENGINE (language-agnostic Swift)     │
│  pipeline stages 0–6, reads Language Packs      │
├─────────────────────────────────────────────────┤
│ LANGUAGE PACKS (bundled data, per language)     │
│  date rules · keywords · conjunctions · stops   │
├─────────────────────────────────────────────────┤
│ FM FALLBACK (on-device only, availability- and  │
│  language-gated, @Generable guided generation)  │
├─────────────────────────────────────────────────┤
│ ENTITY MEMORY (SwiftData) — language-agnostic   │
└─────────────────────────────────────────────────┘
```

The engine contains no language-specific logic in code. All language knowledge lives in data packs. This is the single most important structural decision for scaling languages.

---

## 2. Pipeline (per completed note line)

```
0.  Language routing          primary language (onboarding) as prior;
                              NLLanguageRecognizer per line with the
                              primary passed as languageHint; the prior
                              is overridden only when detection confidence
                              clears a calibrated threshold — very short
                              lines (≲3 tokens) always keep the prior
0.5 STT normalization         fuzzy match against entity memory,
                              STT error-pattern table (per language pack)
1.  Segmentation              split into task candidates at conjunction/
                              verb boundaries classified as sequential
                              (language pack splitClassifiers); boundaries
                              classified as dependent attach as a detail
                              clause to the current candidate instead of
                              starting a new one
2.  Rule extraction           per candidate:
                              - date/time: NSDataDetector (locale from step 0)
                                + custom date rule layer (language pack)
                              - location: locationPatterns (language pack)
                              - priority: keyword tiers (language pack)
                              - category: keyword match (language pack)
                              - detail: detailClauseMarkers → attached
                                detail field, not a separate task
                              - title: strip matched date/priority/detail/
                                location phrases, stopwords, fillerPhrases,
                                then apply titleReductionRules
3.  Entity memory pass        resolve known people/places/things,
                              boost or lower candidate confidence
4.  Confidence gate           calibrated threshold (see §6):
                              ≥ t → finalize from rules
                              < t AND FM available for this language
                                  → FM refines this candidate only
                              < t AND FM unavailable
                                  → finalize, flag low-confidence inline
5.  Finalize + store          write task; corrections feed back (§7)
6.  Feedback capture          user edit → entity memory update (conf 1.0)
                              + (input, corrected output) logged as
                              future corpus material
```

Multi-task lines produce an array; the inline icon count on the notes screen reflects array length (Amy pattern, unchanged).

---

## 3. Language Pack system

A language pack is a bundled, versioned data file (JSON) per language. The engine loads packs at startup; a new language ships as a new pack + corpus, zero engine changes.

**Pack contents:**

| Section | Contents | Example (DE) |
|---|---|---|
| `dateRules` | relative-date patterns NSDataDetector misses in this locale | "übermorgen", "in 14 Tagen", "nächste Woche Freitag" |
| `timeWords` | fuzzy time-of-day terms + default clock mapping | "abends" → 19:00 default |
| `priorityKeywords` | URGENT / HIGH / LOW tiers | "dringend, sofort" → URGENT |
| `conjunctions` | segmentation split points | "und dann", "danach", "später" |
| `splitClassifiers` | per conjunction/boundary: sequential (new task) vs. dependent (trailing detail on the current task) | "und" → sequential; "wegen" → dependent |
| `actionVerbs` | verb-boundary hints for segmentation | "kaufen, anrufen, abholen" |
| `categoryKeywords` | category signal words | "Arzt, Termin" → HEALTH |
| `locationPatterns` | prepositions/patterns for place/address extraction | "bei, im, zur, nach" + address-shape hints |
| `detailClauseMarkers` | keywords marking a trailing clause as a detail attached to the current task, not extracted as its own field or task | "wegen, mitbringen, denk dran" |
| `stopwords` | single filler words stripped during title cleanup | "mal, eben, bitte" |
| `fillerPhrases` | multi-word filler stripped as a unit (stopword removal alone won't catch these) | "kannst du mal", "musst du noch" |
| `titleReductionRules` | post-strip cleanup: leading particle trim, capitalization, verb-form normalization | drop leading "dass", normalize verb to infinitive |
| `sttPatterns` | recurring transcription error fixes | compound-split repairs |
| `ambiguityRules` | locale defaults for ambiguous phrases | bare weekday → next occurrence, confidence capped |

**Sizing rule:** packs start small (~50–150 entries per section) and grow **exclusively from corpus failures** — every entry must be traceable to a real missed case. No quota-driven lexicon building (explicitly rejected from the original multi-language prompt: entry counts were arbitrary there).

**Pack versioning:** each pack carries a version; the regression suite pins pack versions so accuracy numbers are reproducible.

---

## 4. Date extraction — the critical component

NSDataDetector is the base, not the solution. Its coverage of colloquial relative phrases varies sharply by locale (weakest known gap: German). Fantastical built a proprietary parser for exactly this reason.

**Design: two-layer date extraction, per language**
1. Custom `dateRules` from the language pack run **first** (they encode what the stock detector misses).
2. NSDataDetector runs second with the detected locale, catching standard formats.
3. Conflicts resolve in favor of the custom layer (it exists precisely because the detector is wrong there).

**Consequence for language rollout:** the custom date layer is the main per-language engineering cost. A language without a validated date layer does not ship (see §9 checklist).

Ambiguous dates (bare weekday, bare time-of-day, phrases spanning midnight) resolve by the pack's `ambiguityRules` with confidence capped below the gate threshold — they route to FM refinement or the low-confidence inline flag, never a silent guess.

---

## 5. Foundation Models fallback

- **On-device only.** Use `SystemLanguageModel` exclusively. The framework's 2026 cloud-provider options are never used — they would silently break the no-API constraint. Enforce with a lint rule / code review checklist item.
- **Specialized model:** `SystemLanguageModel(useCase: .contentTagging)` — purpose-built for extraction/tagging.
- **Guided generation only:** task schema as `@Generable` Swift struct, priority as enum via `@Guide(anyOf:)`, date as constrained string. Free-text output is never parsed.
- **Scope:** FM refines only the low-confidence candidate it receives, with the rules output passed as context. It never overrides a high-confidence rules result.
- **Double gate:** device availability AND language availability. Apple's on-device models support a fixed language set (16 as of the 2025 tech report; grows with OS updates). A supported UI language with unsupported FM coverage simply runs rules-only — identical features, quality delta only (unchanged principle).
- **Free upside:** AFM 3 (June 2026) ships a 20B sparse model on newest devices. The gate architecture means the fallback tier improves with every OS/hardware cycle with zero code changes, while the rules tier stays deterministic.

---

## 6. Accuracy strategy

**Two-tier targets, per language:**

| Tier | Path | Target |
|---|---|---|
| FM-capable device, FM-supported language | rules + gated FM refinement | 95% |
| Rules-only (older device or FM-unsupported language) | rules + entity memory | 85–88% |

A flat 95% across all devices is not achievable without dropping the iPhone 13/14 floor — standing tradeoff, revisit only if the floor decision changes.

**Threshold calibration (never guessed):** run the corpus rules-only, sweep the gate threshold, pick the lowest value where precision on above-threshold tasks ≥ 98%. Re-calibrate on every engine or pack change, per language, as part of the regression run.

**Per-field scoring:** the corpus scorer reports title / date / time / priority / category / segmentation separately. Segmentation split precision/recall tracked on its own (one bad split corrupts multiple tasks). Blended single numbers are never reported alone.

**Cold start:** entity memory starts empty; accuracy climbs with use. Documented as an expected curve (day 1: rules baseline → week 2+: rules + populated memory). Mitigation: optional Contacts seeding at onboarding (permission-gated) — names are the largest cold-start gap.

---

## 7. Entity memory

SwiftData `@Model` (SQLite-backed), consistent with the existing `TaskItem`/`NoteLine` persistence — language-agnostic (proper nouns don't belong to a language).

Schema (core fields on an `EntityMemory` model): `entity, type (PERSON|PLACE|THING), categoryHint, frequency, confidence, lastSeen, source (AUTO|CORRECTED|SEEDED)`.

Rules:
- Unknown proper noun → stored immediately, low confidence.
- Repeat appearances → frequency++ and confidence growth.
- **User correction → immediate overwrite at confidence 1.0** (corrections are ground truth; frequency is only a proxy).
- Feeds stage 0.5 (fuzzy STT repair, Levenshtein ≤ 2 on proper nouns — never silent below match confidence) and stage 3 (resolution + confidence adjustment).

No hardcoded global brand/place lists (rejected from the original prompt): per-user learned entities beat a static global list for accuracy and carry zero maintenance burden. Works identically for every future language.

---

## 8. Testing & corpus

- Per language: 50–100 hand-labeled lines as a permanent XCTest regression suite. Must include: multi-task lines, mixed-language lines (e.g. Denglisch), recurring entities (3+ mentions), priority keywords, ambiguous dates, dictation-style errors.
- Iteration loop unchanged: run → score per field → categorize failures → fix biggest category (usually a pack addition) → re-run.
- Corpus grows from real usage: stage 6 correction logs are the recruiting pool for new corpus lines.
- Accuracy numbers are always reported per language × per tier.

---

## 9. Language rollout checklist

Adding language X (no engine work):

1. Language pack authored (all §3 sections, seeded small).
2. **Custom date rule layer validated against locale-specific NSDataDetector gaps** — the gating engineering task per language.
3. 50–100 line corpus hand-labeled by a native/fluent speaker.
4. Regression suite ≥ 85% rules-only, per field.
5. FM language support checked → tier assignment (95% or rules-only target).
6. Threshold calibrated for X.
7. Ship behind the existing language routing: the onboarding-selected primary language remains the prior; per-line detection overrides it only on high-confidence signals, which is what makes mixed-language notes work without pack thrashing on short lines. Adding language X just makes X selectable at onboarding and detectable as an override target.

Batch 1 (already built, validated in TestFlight): EN, DE, FR, ES, IT, PT, NL, PL — carried forward into this architecture as-is via the migration in §3/§10, not re-run through the checklist below. DE was the reference implementation for the custom date rule layer (§4); the other seven already have validated packs and corpora under the prior structure and are migrated, not rebuilt.

The rollout checklist below governs language 9 onward.

---

## 10. Explicitly rejected (with reasons, for future reference)

- **Rust/KMP core + RN/Compose UI** — discards Swift-only accuracy levers (Foundation Models, App Intents); solves portability you don't need.
- **fastText/CRF custom ML** — no training data exists pre-launch; Apple ships a pretrained, OS-maintained extraction model for free. Strictly dominated.
- **Bundled small LLM (Core ML/MLX)** — breaks app-size constraint, poor on 4 GB devices.
- **Quota-based lexicons ("500+ verbs per language")** — arbitrary; packs grow from corpus failures only.
- **Hand-tuned weighted scoring formula** — replaced by calibrated confidence gate.
- **Hardcoded global entity lists** — replaced by learning entity memory.
- **FM cloud-provider options (WWDC 2026)** — would silently violate the no-API constraint.

---

## 11. Top risks

1. **DE date layer effort underestimated** — colloquial German relative dates are the known weak spot; Milestone 0 corpus will expose this first. Budget real iteration time here.
2. **Segmentation on messy dictation** — conjunction/verb splitting on run-on spoken sentences is the hardest rules problem; per-field scoring will show if it's the accuracy bottleneck.
3. **Rules-tier ceiling** — if real-world rules-only accuracy lands below ~85% after corpus iteration, the options are: expand FM tier reach, add inline confirmation UI for low-confidence tasks, or revisit the device floor. Decision point, not a silent failure.
