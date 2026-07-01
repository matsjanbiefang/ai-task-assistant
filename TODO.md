# AI Task Assistant — TODO

> Workflow: Before starting any item, re-read the PRD at `../Concept/ai-task-assistant-mvp-prd.md`.
> Log every completed item in `IMPLEMENTATION-LOG.md`.

---

## Setup
- [x] **SETUP-1** Create project folder structure + git init
- [x] **SETUP-2** Create Xcode project files (`.xcodeproj`, `Info.plist`, `App` entry point)
- [x] **SETUP-3** Set up GitHub Actions CI (macOS runner, build check on push)
- [x] **SETUP-4** Create `TODO.md` and `IMPLEMENTATION-LOG.md` in project root

---

## Milestone 0 — PoC: Extraction Accuracy

- [x] **M0-1** Define Swift schema for structured task output (`ExtractedTask` struct with `@Generable`)
- [x] **M0-2** Write `ExtractionService.swift` using Foundation Models (`LanguageModelSession`, structured generation)
- [x] **M0-3** Create `ExtractionHarness` debug screen to run test sentences and print JSON output
- [x] **M0-4** Author 20 realistic test sentences (single tasks, multi-task, relative dates, no-date, priority, messy dictation)
- [ ] **M0-5** Run harness on device; document accuracy results in `IMPLEMENTATION-LOG.md`

---

## Milestone 1 — Core Capture + Organize Loop

- [x] **M1-1** Build `ContentView.swift` with `TabView` + `.page` style for two-screen swipe navigation
- [x] **M1-2** Build `NoteView.swift` (Slide 1): auto-focused text field + submit; clears and switches to Slide 2
- [x] **M1-3** Build `AssistantView.swift` (Slide 2): grouped task list (Today / Upcoming / No date)
- [x] **M1-4** Build `TaskItem.swift` model + SwiftData persistence (`@Model`, container)
- [x] **M1-5** Wire: NoteView submit → ExtractionService → save via SwiftData → refresh AssistantView
- [x] **M1-6** Implement inline task editing on AssistantView (tap row → editable fields)
- [x] **M1-7** Add low-confidence date indicator on extracted tasks

---

## Milestone 2 — Voice Input

- [x] **M2-1** Add mic button to NoteView using `SFSpeechRecognizer` / `AVAudioEngine`
- [x] **M2-2** Add permission keys to Info.plist + runtime prompts
- [ ] **M2-3** Validate multi-task splitting with real voice input; tune extraction prompt if needed *(requires device)*

---

## Milestone 3 — Reminders

- [x] **M3-1** Request `UNUserNotificationCenter` permission on first launch
- [x] **M3-2** Schedule local notifications from extracted due date/time
- [x] **M3-3** Handle notification tap → deep-link to Slide 2
- [x] **M3-4** Set app icon badge to count of tasks due today

---

## Milestone 4 — Siri Integration

- [x] **M4-1** Create `AddTaskIntent.swift` (`AppIntent`) — opens app and activates dictation on Slide 1
- [x] **M4-2** Wire Siri phrase "add a task to my assistant" → intent
- [x] **M4-3** Return brief voice confirmation from intent
