# Deleting notes

## Problem (2026-11-20)
"Clear All" sat in the Notes header next to the import button and deleted every note at once, for good, with no question. Hendri: it needs an "are you sure" prompt or better UX, maybe a trash. With sync on, a delete also reaches the Mac.

## Done
- 2026-11-20: Clear All asks first: "Delete all N notes?", "This can't be undone. Your tasks are kept." Commit `1bc5762`.

## References (Mobbin, 2026-11-20)
- [Messages: Recently Deleted](https://mobbin.com/screens/2045db8b-a2b7-4a30-aed7-38d897b851cd?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): days left on each row, Recover All and a delete button at the bottom, 30 to 40 days.
- [CapCut: Trash tab](https://mobbin.com/screens/fc2d7eac-f881-4b49-9270-1590a6bde4b1?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): "Items moved to Trash will appear here and be deleted after 7 days", Select to act on several.
- [Quo: "Voicemail deleted · Undo"](https://mobbin.com/screens/561695d8-e824-4ecf-85b1-90c21189aeef?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): one delete, no question, an Undo bar at the bottom.
- [GitHub: Select Items](https://mobbin.com/screens/5edb4b50-e0ce-4571-ac92-dc6af0f05cea?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): Select all lives inside a select mode, not as a standing button.
- [Oura: Delete all memories](https://mobbin.com/screens/f5728230-f84a-40ac-aa8e-48b9238e1ae5?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): delete-all at the bottom of a settings-like screen, with a line saying what goes.
- [corner: delete this list?](https://mobbin.com/screens/153c74ef-2d72-4406-bfb6-1a99238c012b?utm_source=claude&utm_medium=ai-assistant&utm_source_platform=mcp): the confirm says who else loses it ("collaborators") and that it cannot be undone.

What they agree on: a single delete gets an Undo, not a question; deleting many happens from a select mode or a settings screen, never a standing header button; the safe apps keep deleted items for a set time and show the days left. Nobody in the set puts delete-all beside an everyday button.

## Decided
- 2026-11-20, Hendri: Undo plus Recently Deleted (over Undo only).
  - Every delete shows "Note deleted · Undo" (or "N notes deleted") for six seconds. Built: the full row is kept in memory, so Undo restores everything, including the Mac's styling and the summary.
  - Deleted notes go to Recently Deleted for 30 days, then are removed for good. Days left on each row, Recover and Recover All.
  - Clear All leaves the Notes header.

## Open
- Where Recently Deleted and Clear All live (design round on the canvas).
- Recently Deleted needs a "deleted at" field in the shared library, so it is the Mac track's schema to change, and the Mac app would show the same bin.
