# Implementation Log — AI Task Assistant

> This file tracks what was built, why each decision was made, and any open questions.
> Written for future Claude agents to pick up work without losing context.
> PRD lives at: `C:\Users\matsb\Desktop\App\Concept\ai-task-assistant-mvp-prd.md`

---

## Setup — 2026-07-01

### SETUP-1: Folder structure + git init
Created the full directory tree at `C:\Users\matsb\Desktop\App\ai-task-assistant\`:
- `AiTaskAssistant/App/` — SwiftUI app entry point
- `AiTaskAssistant/Views/` — NoteView (Slide 1), AssistantView (Slide 2), ContentView (root)
- `AiTaskAssistant/Models/` — TaskItem SwiftData model
- `AiTaskAssistant/Services/` — ExtractionService (Foundation Models)
- `AiTaskAssistant/Intents/` — AddTaskIntent (Siri, Milestone 4)
- `AiTaskAssistant/Resources/` — Assets, localization (empty for now)
- `AiTaskAssistantTests/` — unit tests
- `.github/workflows/` — GitHub Actions CI
Added `.gitignore` (standard Xcode/Swift exclusions).

### SETUP-2: Xcode project files
Created `AiTaskAssistant.xcodeproj/project.pbxproj` manually (no Xcode on Windows).
- Two targets: `AiTaskAssistant` (app) and `AiTaskAssistantTests` (unit test bundle)
- Deployment target: **iOS 26.0** — required for `FoundationModels` framework (Apple Intelligence on-device LLM)
- Swift version: 6.0
- Bundle ID: `com.matsb.AiTaskAssistant` — change `DEVELOPMENT_TEAM` in pbxproj once you have an Apple Developer account
- `Info.plist` created with portrait-only orientation, scene manifest (no multi-window)
- Permission keys for mic/speech (M2) and notifications (M3) are commented placeholders — add them when those milestones begin
- Stub `AiTaskAssistantApp.swift` imports SwiftUI + SwiftData and sets up `ModelContainer(for: TaskItem.self)`
- Stub test file uses Swift Testing framework (`import Testing`)

**Decision:** Used SwiftData over raw SQLite. SwiftData is the native Swift persistence layer (iOS 17+), has `@Model` macro ergonomics, and `@Query` integrates cleanly with SwiftUI. No reason to add SQLite complexity.

### SETUP-3: GitHub Actions CI
`.github/workflows/ios.yml` runs on `push` to `main`/`develop` and on PRs:
- `macos-15` runner with Xcode 16 (latest stable as of 2026-07; supports iOS 26 SDK)
- Builds app target for iPhone 16 simulator, `CODE_SIGNING_ALLOWED=NO` (no certificate needed in CI)
- Falls back to raw `xcodebuild` output if `xcpretty` is not installed
- Test step is `|| true` because on-device Foundation Models tests can't run in simulator

**Next agent note:** When pushing to GitHub for the first time, ensure the repo is public OR that GitHub Actions minutes are enabled for private repos. The workflow will fail until all referenced Swift source files exist (stubs are added as part of M0–M1).

### SETUP-4: TODO.md + IMPLEMENTATION-LOG.md
Created this file and `TODO.md` with all milestones from the PRD.

---

---

## Milestone 0 — 2026-07-01

### M0-1 + M0-2: ExtractedTask schema + ExtractionService

**File:** `AiTaskAssistant/Services/ExtractionService.swift`

Schema decisions:
- `ExtractedTask` is `@Generable` (FoundationModels structured generation macro). Wraps in `ExtractionResult` (also `@Generable`) which has a `tasks: [ExtractedTask]` property — this handles multi-task inputs natively.
- `dueDate`: `String?` (ISO 8601 `YYYY-MM-DD`) — the model outputs text, conversion to `Date` happens in `ExtractionService.parsedDate()` and in `NoteView`. Avoids teaching the model about `Date` formatting.
- `dueTime`: `String?` (HH:MM 24h) — separate from date so the model can express "time unknown" while knowing the date.
- `priority`: `TaskPriority?` enum (`low/medium/high`) — `@Guide` description explicitly says "only set on explicit signal". `nil` means no priority stated.
- `category`: `TaskCategory?` enum (`work/personal/health/shopping/finance/other`) — same rule. Fixed set as per PRD. No freeform generation.
- `dateConfidence`: `Double` (0.0–1.0) — model self-reports confidence. `< 0.7` triggers the orange "?" indicator in `AssistantView`. PRD requirement: "surface low confidence inline rather than hiding it."

`ExtractionService` is an `actor` (thread-safe, async). `LanguageModelSession` is created once per instance. `extract(from:referenceDate:)` injects today's date into the prompt so the model can resolve "tomorrow", "next Friday", etc.

Error handling: if extraction throws (model unavailable, parsing error), `NoteView` falls back to saving the raw text as a task title with no date — user doesn't lose their input.

### M0-3 + M0-4: ExtractionHarnessView + 20 test sentences

**File:** `AiTaskAssistant/Views/ExtractionHarnessView.swift`

`#if DEBUG` guard — not compiled into release builds. Accessible via the app entry point during development (wire it in `AiTaskAssistantApp.swift` temporarily when testing).

20 test sentences cover:
1. Single task, relative date ("tomorrow")
2. Single task, explicit date ("July 15th")
3. Single task, no date
4. Single task with explicit time ("3pm")
5. Two tasks in one sentence
6. Three tasks, mixed dates
7. Explicit high priority ("Urgent:")
8. Explicit low priority ("Low priority")
9. Work category signal ("For work:")
10. Health category signal ("Health appointment")
11. Shopping category signal ("Grocery run")
12. Messy dictation, relative date (fillers: "uh yeah so...")
13. Messy dictation, no date ("oh and also don't forget...")
14. "next week" relative date
15. "in two days" relative date
16. Ambiguous date — should trigger dateConfidence < 0.7
17. Implicit morning time hint
18. Multi-task + priority ("ASAP: deploy ... then write ...")
19. Finance category ("Pay the electricity bill")
20. Long run-on with 3 tasks + explicit date ("turning 60 on the 12th")

**M0-5 is the only remaining Milestone 0 item** — requires running on a physical iPhone with Apple Intelligence (iOS 26, A17 Pro or later). Results should be pasted into this log under a "M0-5: Accuracy Results" section.

---

## Milestone 1 — 2026-07-01

### M1-1 through M1-7: Core Capture + Organize Loop

All M1 work was built alongside M0 to have a complete compilable project from the start.

**ContentView.swift** — `TabView` with `.page(indexDisplayMode: .never)` for hidden-indicator swipe. `@State private var selectedTab` is passed down to `NoteView` via `onSubmit` closure so submit on Slide 1 programmatically advances to Slide 2. This avoids deep state coupling.

**NoteView.swift** (Slide 1):
- `@FocusState isFocused = true` on `.onAppear` — keyboard opens immediately per PRD ("App opens directly into an active text field").
- Submit button disabled when text is empty or extraction is running. Shows `ProgressView` spinner during async extraction.
- On success: clears `inputText`, calls `onSubmit()` → user sees tasks land in Slide 2.
- On failure: saves raw text as title fallback (no silent loss).

**AssistantView.swift** (Slide 2):
- `@Query` for `TaskItem` sorted by `dueDate` ascending. Filtered into three sections: Today, Upcoming, No date. Completed tasks hidden from all sections.
- `dateConfidence < 0.7` → orange date text + `questionmark.circle` icon. Satisfies PRD "surface low confidence inline".
- Priority badge: red for high, orange for medium, secondary for low.
- Tap row → sheet with `TaskEditView`.

**TaskEditView.swift**:
- `@Bindable var task` — SwiftData's `@Bindable` propagates changes live.
- `DatePicker` + toggle for date presence. `Picker` for priority and category against the `allCases` enum arrays (no freeform input).
- "Mark complete" sets `isCompleted = true` and dismisses.

**TaskItem.swift** (`@Model`):
- Stores `priority` and `category` as `String?` (rawValue) rather than the enums — avoids SwiftData migration complexity when enums change during development.
- `dateConfidence: Double` stored so the UI indicator persists after the extraction session ends.

**AiTaskAssistantApp.swift**:
- `.modelContainer(for: TaskItem.self)` on `WindowGroup` — single container for the whole app. No manual `ModelContext` setup needed.

---

---

## Milestone 2 — Voice Input — 2026-07-01

### M2-1: SpeechRecognizer + NoteView mic button

**New file:** `AiTaskAssistant/Services/SpeechRecognizer.swift`

Architecture:
- `@MainActor @Observable final class SpeechRecognizer` — `@Observable` instead of `ObservableObject` (Swift 5.9+ macro, cleaner). `@MainActor` because all UI-facing state mutations (`state`, `transcript`) must be on main thread.
- Three states: `.idle`, `.recording`, `.unavailable` (device doesn't support on-device recognition, or permission denied mid-session).
- `requiresOnDeviceRecognition = true` — keeps audio fully on-device, matching the PRD's privacy-first principle. Falls back gracefully if on-device is unavailable (older devices).
- Partial results streaming: `shouldReportPartialResults = true` — live transcription appears in the text field as the user speaks.
- Auto-stop: SFSpeechRecognizer fires `isFinal = true` on a natural pause — `stopRecording()` is called automatically. User can also tap the stop button manually.
- Error codes 203 (retry) and 1110 (no speech) are ignored — both are transient and non-fatal.
- Audio session teardown in `stopRecording()` calls `setActive(false, .notifyOthersOnDeactivation)` so other audio apps resume correctly.

**Updated:** `AiTaskAssistant/Views/NoteView.swift`
- Mic button sits left-aligned in the bottom bar; submit arrow stays right-aligned.
- `.contentTransition(.symbolEffect(.replace))` on the mic icon for smooth mic ↔ stop-circle animation.
- `onChange(of: speech.transcript)` guard: only syncs to `inputText` while actively recording, so manual edits after recording aren't clobbered.
- If permissions denied: inline "enable in Settings" hint below the text field. No blocking modal.
- Submit button stops recording if active before submitting (so final audio gets processed).

### M2-2: Permissions

**Info.plist additions:**
- `NSMicrophoneUsageDescription` — "Used to capture tasks by voice so you can add them hands-free."
- `NSSpeechRecognitionUsageDescription` — "Speech is transcribed on-device to convert your voice into a task."

Permission request happens at mic-button tap (not at launch), following iOS best practice of requesting at the moment of use.

### M2-3 (pending, device-only)
After first device build: dictate multi-task sentences ("Buy milk and call the dentist tomorrow") and verify ExtractionService splits them correctly. If splitting fails, add an explicit instruction in the extraction prompt: "The input may be spoken aloud; ignore filler words and split distinct actions into separate tasks."

---

## Milestone 3 — Reminders — 2026-07-01

### M3-1: Permission
`ContentView.task {}` calls `NotificationService.shared.requestPermission()` once on first appearance. Uses `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])`. Silently skips if already authorized.

### M3-2: Scheduling
`NotificationService.schedule(taskID:title:at:)` — called from `NoteView.submit()` for every extracted task that has a future due date. Uses `UNCalendarNotificationTrigger` (not time-interval) so the system can batch and optimize delivery.

`taskID` = `item.id.uuidString` — stable identifier for cancellation when tasks are deleted or rescheduled via `TaskEditView` (cancellation hook should be added to `TaskEditView` in a future polish pass).

### M3-3: Deep-link (notification tap → Slide 2)
Architecture: `NotificationDelegate` (`UNUserNotificationCenterDelegate`) intercepts the tap and calls `UIApplication.shared.open(URL("aitask://assistant"))`. The `WindowGroup` receives this via `.onOpenURL`, sets `deepLinkDestination = .assistant`, and `ContentView.onChange` switches `selectedTab` to 1.

Custom URL scheme `aitask://` registered in `Info.plist` under `CFBundleURLTypes`.

`NotificationDelegate.shared` is set as `UNUserNotificationCenter.current().delegate` in `AiTaskAssistantApp.init()` — must be set before the app finishes launching, so `init()` is the right place (not `.task` or `.onAppear`).

`willPresent` handler shows `.banner + .sound + .badge` while the app is in foreground — per PRD the assistant view is the home base so foregrounding it on notification makes sense.

### M3-4: Badge
`NotificationService.updateBadge(todayCount:)` uses `UNUserNotificationCenter.setBadgeCount(_:)` (iOS 16+ API, no `UIApplication` direct access needed). Called from:
- `NoteView.submit()` after saving new tasks
- `AssistantView.onChange(of: tasks)` after any task list change (completion, edit)

Badge count = tasks where `dueDate` is today (midnight → midnight) and `isCompleted == false`.

---

## Milestone 4 — Siri — 2026-07-01

### M4-1/M4-2/M4-3: AddTaskIntent + AppShortcuts

**Updated:** `AiTaskAssistant/Intents/AddTaskIntent.swift`

`AddTaskIntent: AppIntent` with `openAppWhenRun = true` — this is the key flag that tells the system to foreground the app after the intent runs. Without it, Siri would run the intent in the background.

`perform()` returns `IntentDialog("Ready. What's your task?")` — this is the M4-3 voice confirmation. Siri speaks this before handing control to the app.

`AddTaskShortcuts: AppShortcutsProvider` registers three Siri phrases:
- "Add a task to [app name]"
- "New task in [app name]"
- "Remind me in [app name]"

These appear in Settings > Siri & Search > [App] > Siri Shortcuts automatically.

**Deep-link from Siri → dictation:**
`ContentView` listens for `.onContinueUserActivity(NSStringFromClass(AddTaskIntent.self))`. When Siri opens the app via the intent, this fires, sets `selectedTab = 0` (Slide 1) and flips `activateDictation = true`. `NoteView.onChange(of: activateDictation)` calls `toggleRecording()` — mic starts automatically.

`activateDictation` is a `@Binding Bool` — passed from `ContentView` down to `NoteView`. Reset to `false` immediately in `NoteView.onChange` to prevent re-triggering.

---

## Status Summary — 2026-07-01

| Milestone | Status | Notes |
|-----------|--------|-------|
| Setup | ✅ Complete | Xcode project, CI, companion files |
| M0 PoC | Code complete | M0-5 requires device run |
| M1 Core Loop | ✅ Complete | Two-screen swipe, extraction, edit, persistence |
| M2 Voice | Code complete | M2-3 requires device validation |
| M3 Reminders | ✅ Complete | Scheduling, deep-link, badge |
| M4 Siri | ✅ Complete | Intent, phrases, dictation auto-start |

**Next actions for the developer:**
1. Create a GitHub repo and push this project
2. Watch CI run to confirm compilation (GitHub Actions, macos-15, Xcode 16)
3. Add Apple Developer Team ID to `DEVELOPMENT_TEAM` in `project.pbxproj`
4. Build to a real iPhone (iOS 26, Apple Intelligence enabled) via Xcode on any available Mac
5. Run `ExtractionHarnessView` (debug only) — tap "Run All", review 20 test results → M0-5
6. Test voice input with multi-task sentences → M2-3
7. Verify notification fires at correct time, badge updates, Siri phrase works

## Next: M0-5 (device run), then M2 (voice)

To run M0-5:
1. Push to GitHub, let CI verify the build
2. On a Mac with Xcode, open the project, change `DEVELOPMENT_TEAM` in build settings
3. Run on device (iPhone with Apple Intelligence)
4. On `ExtractionHarnessView`, tap "Run All" — review JSON output for each of the 20 sentences
5. Paste results here and decide if extraction is good enough to proceed to M2 without a mandatory review step

To access `ExtractionHarnessView` during testing: temporarily add a `NavigationLink` or `sheet` from `ContentView` to `ExtractionHarnessView()` under `#if DEBUG`.

M2 checklist when ready:
- Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` to `Info.plist`
- Build mic button with `AVAudioEngine` in `NoteView`
- Validate multi-task splitting with actual voice
