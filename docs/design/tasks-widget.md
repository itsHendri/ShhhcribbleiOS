# Tasks widget page

Canvas: [Shhhcribble iPhone](https://claude.ai/artifact/QiwDgUnpfz29rQK9GjegHN). The pick is on page "Approved · to build"; round 1 with all six options is on page "Explorations".

## Thesis
One home-screen page that holds only Shhhcribble: a large widget on top and a medium one below, read as one surface. Hendri's words: a full-screen widget where all reminders and items live. iOS has no full-screen widget on iPhone, so two stacked widgets is the closest form (decided 2026-11-19).

## Decided
- 2026-11-20: direction D, Tasks plus capture. Hendri picked it over the suggested B.
  - Large widget: the task list, sorted by due time, tick boxes, an "Overdue" badge with a label, times on the right, "+N more" on the last row.
  - Medium widget: a record button on the left (starts a recording, same path as the Control Center control) and the latest note on the right (time, length, up to four lines).
  - Accepted cost: three fewer task rows than a list in both widgets.

## Drafts round (2026-11-20), waiting for a pick
On the canvas page "? Review": D in three looks, each in light and dark, plus the empty states.
1. System (suggested): system type, the app's blue only on the record button.
2. Ink: no colour, rounded type, hairlines.
3. Next up: the next task large on top, a round record button, six tasks.
Colours checked for contrast: the record label is white on #1F5FD6 in light and dark navy on #6BA6FF in dark; the overdue badge always carries the word.

## Fixed by the platform
- Widgets cannot scroll. What fits is all there is: about 7 rows plus a header in the large one, 3 in the medium one, at a 44 px touch size.
- Tick boxes work without opening the app (an intent that writes to the shared store from the widget process).
- States are never told apart by colour alone: done is a filled mark plus strikethrough, overdue is a labelled badge.
- The record button opens the app to record. A widget cannot use the microphone.

## What the code must match
- The approved board `approved/D-capture.dc.html` for structure, until the drafts round replaces it.
- The medium widget reads the latest note through the shared store's light reader, never the full library.

## Open
- The look (drafts round above) and whether the empty-state wording is right.
- Lock screen and StandBy versions.

## Explicitly deferred
- A to C, E and F from round 1. Not picked; kept on the Explorations page as history.
