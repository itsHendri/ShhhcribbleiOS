# Tasks widget page

Canvas: [Shhhcribble iPhone](https://claude.ai/artifact/QiwDgUnpfz29rQK9GjegHN). The pick is on page "Approved · to build"; round 1 with all six options is on page "Explorations".

## Thesis
One home-screen page that holds only Shhhcribble: a large widget on top and a medium one below, read as one surface. Hendri's words: a full-screen widget where all reminders and items live. iOS has no full-screen widget on iPhone, so two stacked widgets is the closest form (decided 2026-11-19).

## Decided
- 2026-11-20: direction D, Tasks plus capture. Hendri picked it over the suggested B.
  - Large widget: the task list, sorted by due time, tick boxes, an "Overdue" badge with a label, times on the right, "+N more" on the last row.
  - Medium widget: a record button on the left (starts a recording, same path as the Control Center control) and the latest note on the right (time, length, up to four lines).
  - Accepted cost: three fewer task rows than a list in both widgets.

## Drafts 1 (2026-11-20), feedback taken
Three looks of D. Not picked whole. Hendri's feedback, from two canvas comments and a screenshot of Apple's Reminders widget:
- The task card style of look 1 (System).
- A header like Reminders: a big count with "To do" under it, and a round button top right that opens the app, carrying the logo.
- The round record button of look 3, with no label under it, on the right for reach.

## Drafts 2 (2026-11-20): B picked
Hendri picked B, ticks on the right, over the suggested A. On the canvas page "Approved · to build"; the whole round is on "Explorations". All three carry the feedback above and use the logo's violet (#5548E0 light, #A99DFF dark) in place of the app's old blue.
- A. As asked (suggested): ticks on the left. 6 task rows under the tall header.
- B. Ticks on the right, in one tap column with the logo and record buttons.
- C. Compact header, count and label on one line. 7 rows.

## Built (2026-11-20), simulator only
`ShhhcribbleWidget/HomeWidgets.swift`. Checked in the iOS 27 simulator in light mode: both widgets on a home-screen page with real data, a tick from the widget (count 4 to 3, the row written with its done time), the record button opening the app into a recording. Not checked: dark mode, the tinted and clear home-screen styles, a locked phone, a real device.

## References (Mobbin, 2026-11-20)
- Perplexity's widgets: logo on top, a short list, actions at the bottom.
- Structured's widgets: the tick circle on the right of each row.
- TikTok and BitePal: one large round action in a widget, no label needed when the glyph is clear.
- Nobody in the set pairs a task list with a record button; that pairing is ours.

## Fixed by the platform
- Widgets cannot scroll. What fits is all there is: about 7 rows plus a header in the large one, 3 in the medium one, at a 44 px touch size.
- Tick boxes work without opening the app (an intent that writes to the shared store from the widget process).
- States are never told apart by colour alone: done is a filled mark plus strikethrough, overdue is a labelled badge.
- The record button opens the app to record. A widget cannot use the microphone.

## What the code must match
- The approved boards `approved/B-ticks-right-light.dc.html` and `-dark`: header with count, "To do" and the logo button; six rows, tick on the right; latest note left, 64 pt round record button right, no label.
- The medium widget reads the latest note through the shared store's light reader, never the full library.

## Open
- The empty states in the look of B (drawn in code first, shown to Hendri in the simulator).
- The logo in the button is a redrawn scribble. No vector of the real logo exists in `brands/shhhcribble/assets/logo` yet.
- The app itself still uses blue as its accent; the logo is violet. Moving the app to violet is a separate, small change.
- Lock screen and StandBy versions.

## Explicitly deferred
- A to C, E and F from round 1. Not picked; kept on the Explorations page as history.

## Tick position (2026-11-24)
Kept as is, on purpose: the tick is on the right in the widget and on the left in the app's Tasks tab. Hendri: "we can keep as is, on mobile is so we are closer to thumb" (the widget's taps all sit in the right-hand column, near the thumb).
