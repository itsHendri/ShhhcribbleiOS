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
    └── String+TitleGeneration.swift

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

## Forked from

[OsamaBinBallZak/ShhhcribbleiOS](https://github.com/OsamaBinBallZak/ShhhcribbleiOS) (MIT). Sibling Mac project: [itsHendri/Shhhcribble](https://github.com/itsHendri/Shhhcribble) — same FluidAudio stack; lessons from that codebase live in CLAUDE.md.

## License

MIT.
