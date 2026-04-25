# ShhhcribbleiOS

Fast, one-gesture voice-to-clipboard transcription for iPhone. Triple-tap (or Double Back Tap) the back of your phone, speak, tap the iOS "← Back" pill to stop and return to whatever app you were in — your speech is already on the clipboard, ready to paste.

Runs fully on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet-based) on the Apple Neural Engine. No accounts, no network calls, no servers.

## Features

- **Back Tap → record → paste**: zero-friction dictation flow driven by a `shhhcribble://record` URL scheme opened from an iOS Shortcut.
- **Two transcription models:**
  - **Streaming** — ultra-low latency, live text on the clipboard as you speak, no punctuation.
  - **Parakeet TDT v3** — larger model (~200 MB first download), punctuated and capitalized output, re-transcribed every ~700 ms so the clipboard stays fresh for the paste flow.
- **Live Activity** keeps the recording visible while the app is minimized (iOS 18 requirement for background audio).
- **Neural Engine by default** with CPU fallback toggle.
- **Filler-word filter** (um, uh, like, you know…).
- **History** of recent transcriptions inside the app.

## Setup

1. Clone and open the generated project (xcodegen required for regeneration; pre-generated `.xcodeproj` is checked in).
2. In Xcode: select the `ShhhcribbleiOS` scheme, your iPhone as the destination, sign with your personal team, ▶.
3. On the iPhone, create a Shortcut:
   - Add action: **URL** → `shhhcribble://record`
   - Add action: **Open URLs**
   - Save as e.g. "Shhhcribble".
4. Settings → Accessibility → Touch → **Back Tap** → Double Tap → pick the Shortcut.

## Requirements

- iPhone on iOS 18+.
- Xcode 16+.
- Microphone permission; Live Activities enabled in Settings → Shhhcribble.

## Architecture

- `ShhhcribbleiOS` — SwiftUI app.
- `ShhhcribbleShared` — framework with `ShhhcribbleActivityAttributes` and `StopRecordingIntent`.
- `ShhhcribbleWidget` — Live Activity widget extension.

Project is defined in [project.yml](project.yml) and generated with [xcodegen](https://github.com/yonaskolb/XcodeGen).

## License

MIT.
