# Swipe — Design Concept

*Direction: Lime · v4*

## 1. What this is

Swipe is a two-surface task app: a free-form **Notebook** for capturing tasks the way you'd jot them in Apple Notes, and a **Week** view where the same tasks live once they're structured — with dates, times, places, and categories. A task exists in exactly one of these two places at a time: raw and unresolved in the Notebook, or resolved and scheduled in Week. Nothing is duplicated, and nothing needs a separate "save" step — writing a line *is* creating a task.

This document captures the visual and interaction language we landed on after exploring three directions (Ink, Sorbet, Velvet) and iterating on the one you picked, Lime, through four rounds. It's meant as a reference for implementation, not a pixel spec — details like corner radii or exact spacing can flex once this is built in SwiftUI.

## 2. Design direction

**Lime** reads as a paper notebook with one deliberate accent, not a productivity dashboard. The palette is quiet — off-white paper, near-black ink, soft grey lines — until something needs attention, at which point a single lime-green shows up. It's the opposite of the "AI slop" gradient-and-emoji aesthetic we ruled out early: no decoration that isn't load-bearing.

The two earlier directions we didn't pick are worth naming because they inform what Lime deliberately avoids:
- **Ink** (dark, monospace metadata) was closest to Amy but felt more like a terminal than a notebook.
- **Velvet** (dark, serif, timeline rail) was the most editorial, but heavier than a quick-capture tool should feel.

Lime kept Sorbet's card-based task layout — it scans better than thin rows once tasks carry more metadata — while trading Sorbet's decorative pastel-per-row coding for something with actual rules.

## 3. Color system

Every color in the app now has exactly one job. Nothing is decorative-only, and nothing encodes two different things at once (an earlier draft accidentally used color for both category *and* random visual variety — that's gone).

| Color | Role | Where it appears |
|---|---|---|
| Paper `#F7F8EF` | Background | Every screen |
| Ink `#17170F` | Primary text, icons, borders on light buttons | Everywhere |
| Muted grey | Secondary text (metadata, labels) | Meta rows, field labels |
| Lime `#DCEB74` / Lime-deep `#C3D63F` | **Brand accent — state and action only** | Today's day-pill, open-task accent bar, checked checkboxes, primary CTA, typing caret |
| Sky-pale wash | Decorative header wash | Detail screen header only |

Categories are explicitly **not** colored — see §4. The one nuance worth calling out: the accent bar on a task card is lime when the task is open and fades to grey once it's done. That's a *state* signal (open vs. done), not a category or date signal, so it doesn't compete with anything else color is doing.

Buttons never invert to a dark fill — every button, everywhere, is a light surface with ink content. The primary "Als erledigt markieren" button is lime-filled with ink text rather than ink-filled with lime text, so it reads as an accent, not a mode switch.

## 4. Category system: icons, not color

Categories are told apart by **icon shape**, not hue:

| Category | Icon |
|---|---|
| Arbeit (Work) | Briefcase |
| Privat (Personal) | House |
| Fitness | Dumbbell |
| No category | No icon shown |

The same three icons appear consistently in four places: the Notebook's detection row, a task card's metadata line, the Week screen's legend, and the detail screen's category chip. A small legend under the week strip spells out what each icon means, so the system is self-documenting the first time someone sees it.

## 5. Typography

- **Bricolage Grotesque** (display) — screen titles, task titles, numbers in the stat bar, day numbers. Has enough personality to carry the brand without being loud.
- **Outfit** (body) — Notebook line text, field values, everything read at length.

Notebook text sits at 15px with generous line-height — deliberately smaller than a task-card title, because a raw note and a resolved task shouldn't look like the same kind of object.

## 6. Screens

### Notebook (home)
Just the notebook — no hero cards, no stats up front. Top bar: calendar and shopping-list icons grouped in the center, settings top-right, nothing else (no date label; the content below makes the date obvious enough). Each line shows the typed text on the left; on the right, small neutral icons appear *only* for fields the parser actually found — a calendar glyph for a detected date, a clock for time, a pin for place, a category icon, a list glyph for extra detail. A plain task with nothing detected shows nothing on the right. No dividers between lines — spacing alone separates entries, closer to how Notes actually looks.

Tapping a line marks it done, and it clears from the Notebook — it isn't deleted, it now lives on as a completed task in Week until it's explicitly removed. Below the caret, a one-line hint makes this discoverable.

A compact stat bar is pinned at the bottom: **Offen** (all open tasks), **Heute** (today's), **Woche** (this week's dated tasks). Each is tappable and actually filters Week rather than just linking to it.

### Week
Opens on the current week only — a 7-day strip (today filled lime), a category legend, then tasks grouped by day as rounded cards: checkbox top-right, category icon + time in the meta line, title below. A left accent bar (lime/grey) signals open vs. done at a glance. Below the dated groups sits **Ohne Datum** for tasks with no date at all, styled with a dashed border so it reads as "unanchored" rather than just another day.

Arriving via a stat filter swaps the header label ("Offene Aufgaben" / "Heute" / "Diese Woche") and shows a small "Alle anzeigen ✕" chip to clear back to the full view.

### Detail
Title, category chip, and four fields — date, time, place, category — each in its own tappable row for quick editing. One primary action (mark done) and one quiet destructive one (delete), visually de-emphasized so it's not accidentally hit.

### Shopping list
A second, simpler notebook — same capture-line pattern, same checkbox language, no dates or categories. Reuses the product's core idea (type it, it becomes a structured item) rather than being a bolted-on separate feature.

## 7. Open questions for implementation

A few things this concept intentionally leaves unresolved, worth deciding before or during the SwiftUI build:

- **Editing flow** — tapping a detail field currently implies inline edit, but the actual input mechanism (sheet, inline text field, date picker) isn't specified here.
- **Category assignment** — how a category gets set when it's not clearly stated in the text (manual picker on the note line? in detail only?).
- **Multi-day ranges** — the original design docs mention date ranges; Week's day-grouped layout doesn't yet show how a range task appears across multiple days without duplicating the card.
- **Swipe-to-delete** — referenced as a pattern goal early on, not yet represented in any screen here; currently delete only exists as a button in Detail.
- **Empty states** — no design yet for zero open tasks, zero tasks today, or an empty Notebook.
- **Settings** — icon exists, screen doesn't.

None of these block starting implementation of the two core screens, but they're worth a quick pass before they're needed.
