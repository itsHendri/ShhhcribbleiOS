# ShhhcribbleiOS

Fast on-device voice-to-text for iPhone. Tap the play button (or trigger via Shortcuts / Back Tap), speak, and the transcript lands as a saved Note **and** on your clipboard. A Live Activity keeps the recording visible across apps and on the lock screen.

Runs fully on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet on the Apple Neural Engine). No accounts, no network calls, no servers.

> **Read [CLAUDE.md](CLAUDE.md) before extending the codebase.** It is the single source of truth for architecture decisions, audio-session rules (especially around AirPods), and Sprint sequencing. The "Working notes" section at the bottom captures gotchas around signing, logging, App Groups, and Live Activities under a free Personal Team.

## Features

- **One-tap recording** — brand-blue play button anchored to the right of the bottom navigation. Recording overlay shows live transcript with a real-time audio-reactive waveform; older words fade to grey, the latest two stay bright.
- **Two transcription engines** (pick in Settings):
  - **Streaming** — lowest latency, no punctuation.
  - **Parakeet TDT v3** — punctuated and capitalised, slightly more CPU.
- **Live Activity + Dynamic Island** — recording persists when you switch apps. Tap the card to return to the in-app overlay.
- **Notes list** with per-row Copy + swipe-to-delete; tap a row to copy.
- **Toast feedback** on every clipboard write.
- **App Intents** — `StartRecordingIntent` and `StopRecordingIntent` discoverable from Siri / Shortcuts / Back Tap.
- **Vocabulary settings** — auto-correct casing for proper nouns (Custom Words), apply find/replace rules to transcripts (Substitutions), and add personal filler words to strip (Filler Words).
- **Inline error UX** in the recording overlay — distinct surfaces for mic permission denied (with Open Settings), no speech detected, and model-load failure (with Retry).
- **Append-to-note** — a 44pt tinted mic FAB appears next to the play button while you're reading a note. Tapping it records a follow-up that's appended (separated by `\n\n`) to that specific note instead of creating a new one. The recording overlay surfaces an "Adding to: <title>" chip so you know what you're appending to.
- **Markdown auto-render** — notes whose transcript contains markdown syntax (headings, bullets, links) open in a rendered preview. Tap the text to switch back to the editor.
- **Light/dark recording overlay** — overlay follows the system colour scheme. Retry button shows a spinner while reloading the model. Model-load errors are mapped to short, action-oriented copy (offline, timeout, disk full) instead of dumping raw `NSError` userInfo. First-ever model download surfaces as an accent ring around the play button.

## Requirements

- iPhone on iOS 18+ (tested on iOS 26 / iPhone 17 Pro).
- Xcode 16+.
- Microphone permission. Live Activities permission (granted on first recording).
- For local development: `xcodegen` (`brew install xcodegen`).
- Optional but recommended for device debugging: `libimobiledevice` (`brew install libimobiledevice`).

## Project layout

```
ShhhcribbleiOS/
├── App/                   # ShhhcribbleApp + AppIntents
├── Features/
│   ├── Recording/         # RecordingOverlayView, SoundwaveBars, ScrollingLiveText
│   ├── NotesList/         # ContentView (root), NotesListView, ToastManager
│   └── Settings/          # SettingsView + CustomWordsView, SubstitutionsView, FillerWordsView
├── Models/                # Note (SwiftData), TriggerSource
├── Services/
│   ├── TranscriptionService    # FluidAudio actor — fragile, see CLAUDE.md
│   ├── AudioRecorder           # mic tap + RMS level publishing
│   ├── AudioSessionManager
│   ├── AudioInterruptionObserver
│   ├── ShhhcribbleActivityManager  # Live Activity start/update/end
│   └── NotesRepository         # SwiftData ModelContainer wrapper
└── Extensions/
    ├── String+Filters.swift           # filler-word removal (built-in + custom)
    ├── String+Substitutions.swift     # find/replace pass + auto-cased hotwords
    ├── String+TitleGeneration.swift
    └── String+Markdown.swift          # containsMarkdownSyntax heuristic for view/edit auto-toggle

ShhhcribbleShared/         # Framework — StartRecordingIntent, StopRecordingIntent,
                           # CancelRecordingIntent, ShhhcribbleActivityAttributes
ShhhcribbleWidget/         # Widget extension — Live Activity + ControlWidget
```

Project is generated from [project.yml](project.yml) with [xcodegen](https://github.com/yonaskolb/XcodeGen).

## Local setup

1. Clone and open in Xcode:
   ```bash
   git clone https://github.com/itsHendri/ShhhcribbleiOS.git
   cd ShhhcribbleiOS
   xcodegen generate    # if you change project.yml or add files
   open ShhhcribbleiOS.xcodeproj
   ```
2. In Xcode, select your iPhone as destination, then **Cmd-R**. Personal Team `L9T3PX7HVH` is pinned in `project.yml`; you may need to override to your own team.
3. First launch on device:
   - **Untrusted Developer** popup → Settings → General → VPN & Device Management → trust your Apple ID.
   - Allow microphone permission.
   - Allow Live Activities permission on first recording.

## Build + install via CLI

When Xcode's Cmd-R is unreliable (common with App Group entitlements + Personal Team), `devicectl` is the dependable fallback. Get the device ID and install:

```bash
xcrun devicectl list devices

xcodebuild -project ShhhcribbleiOS.xcodeproj -scheme ShhhcribbleiOS \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath /tmp/sb_build build

xcrun devicectl device install app \
  --device <device-id> \
  /tmp/sb_build/Build/Products/Debug-iphoneos/ShhhcribbleiOS.app
```

## Streaming logs from a connected iPhone

`print(...)` does **not** appear in `idevicesyslog`. Use `os.Logger` with subsystem `com.shhhcribble.diag` for anything you want to see in syslog. Existing diagnostic logs are tagged that way.

```bash
brew install libimobiledevice
idevicesyslog -u <device-udid> --no-colors -o /tmp/sb_syslog.log

# In another terminal:
grep 'shhhcribble.diag' /tmp/sb_syslog.log
```

`--no-colors` is required — ANSI escapes in the output file corrupt it.

## Architecture highlights

- **No LLM, no cloud.** Pure on-device transcription via FluidAudio.
- **No `setVoiceProcessingEnabled(true)` for Bluetooth — ever.** AirPods deliver clean audio without it on iOS 17+. See CLAUDE.md for full justification.
- **Fresh `AVAudioEngine` per recording.** Self-heals on AirPods reconnect, Continuity Mic swaps, etc.
- **SwiftData** for the `Note` store. The `embedding: Data?` field lands in v1 to avoid a migration when semantic search ships in v3.
- **Filler-word filter and `TypingViewModel`** are deterministic; the live transcript you see is exactly what gets saved + copied.

## Working with Claude Code

This project is set up to be extended with [Claude Code](https://claude.com/claude-code). The core context lives in [CLAUDE.md](CLAUDE.md) — read it (or have Claude read it) at the start of every session. It documents architecture, hard constraints (especially around AirPods + audio sessions), the SwiftData schema, the build sequence, and known minor issues.

### Starting a new session

When you open Claude Code in this repo, two opening prompts cover most cases:

**1. Onboarding prompt — get Claude up to speed:**
```
Read CLAUDE.md fully, including the "Working notes" section at the bottom and
the "Known minor issues / future polish" list. Then walk through the
Features/, Services/, and Models/ directories so you understand the current
shape of the recording flow, the SwiftData Note model, and the recording
overlay state machine. Don't make any changes yet — just confirm you've
loaded the context.
```

This forces Claude to internalise the load-bearing decisions (no voice processing for Bluetooth, fresh `AVAudioEngine` per recording, App Group deferred until paid Developer Program, etc.) before it starts proposing changes.

**2. Planning prompt — pick the next sprint:**
```
Based on CLAUDE.md (especially the "Build sequence" section and "Known minor
issues / future polish" list), what's the most valuable next sprint to ship?
Consider:
  - what's already in flight or partially done,
  - the explicit "Sprint 5 — Keyboard extension" prerequisites (paid
    Developer Program, App Group restoration),
  - the deferred image-attachments feature flagged as next-PR in
    Sprint 4.5+1,
  - and any small polish items that could ship as a quick win first.

Propose one to three sprint options, ranked by impact-vs-effort, and explain
the trade-offs. Don't write code yet — I want to choose first.
```

Claude should respond with options, not a single forced answer. Pick one, then run it through plan mode (`shift+tab`) before letting it touch code — every load-bearing area in CLAUDE.md was learned the hard way.

### Working rules for Claude in this codebase

These are baked into CLAUDE.md but worth surfacing here:
- **Never relitigate a load-bearing decision** without a strong reason — if Claude proposes one, push back.
- **One feature per branch.** Verify on a real iPhone with AirPods + music playing before committing.
- **Update CLAUDE.md** whenever a change adds a new load-bearing decision or pref key.
- **Never connect to production** systems or use production credentials (this repo is personal, but the global SwissBorg guidance applies regardless).
- **Plan mode first** for anything non-trivial. The cost of an incorrect audio-session change is hours of debugging on-device.

## Forked from

[OsamaBinBallZak/ShhhcribbleiOS](https://github.com/OsamaBinBallZak/ShhhcribbleiOS) (MIT). Sibling Mac project: [itsHendri/Shhhcribble](https://github.com/itsHendri/Shhhcribble) — same FluidAudio stack; lessons from that codebase live in CLAUDE.md.

## License

MIT.
