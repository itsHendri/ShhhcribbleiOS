# ShhhcribbleiOS — Claude Code context

Read this at the start of every session. It is the single source of truth for architecture decisions and hard constraints. Don't relitigate anything marked **load-bearing** without a strong reason and a note added here.

---

## What this app is

A native iOS voice-to-text note-taking app. An external trigger (Control Center widget, AirPods, Back Tap, Action Button, or keyboard extension) starts recording. The user speaks. Parakeet TDT v3 transcribes on-device via FluidAudio. The transcript is auto-saved as a Note and copied to the clipboard — or, in Phase 2, injected directly into the focused text field via the keyboard extension. Edits happen later from the note detail screen; there is no forced review step in the main flow.

**Everything runs on-device. No cloud. No API keys. No LLM post-processing.**

- **Platform:** iOS 18+ — iPhone only
- **Language:** Swift / SwiftUI
- **Transcription:** FluidAudio + NVIDIA Parakeet TDT v3 (CoreML, Apple Neural Engine)
- **Persistence:** SwiftData
- **Forked from:** OsamaBinBallZak/ShhhcribbleiOS (MIT)
- **Related:** itsHendri/Shhhcribble (Mac version — same FluidAudio stack, lessons learned documented below)

---

## Directory map

```
ShhhcribbleiOS/
├── App/
│   ├── ShhhcribbleApp.swift           # Entry point, ModelContainer, URL scheme handler
│   └── AppIntents.swift              # StartRecordingIntent, ShhhcribbleShortcuts (App Shortcuts)
├── Features/
│   ├── Recording/
│   │   ├── RecordingView.swift       # Waveform, timer, Stop + Cancel buttons
│   │   └── RecordingViewModel.swift  # @Observable, owns TranscriptionService session
│   ├── NotesList/
│   │   ├── NotesListView.swift       # Search bar, tag filter chips, note rows
│   │   └── NotesListViewModel.swift
│   ├── NoteDetail/
│   │   ├── NoteDetailView.swift      # Full note, inline editing, share
│   │   └── NoteDetailViewModel.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── CustomWordsView.swift     # Hotword biasing list
│   │   ├── SubstitutionsView.swift   # Find-replace rules
│   │   └── FillerWordsView.swift
│   └── Onboarding/
│       └── OnboardingView.swift      # 3 screens: what it is / add Control Center / AirPods setup
├── Models/
│   └── Note.swift                    # @Model SwiftData entity — see schema below
├── Services/
│   ├── TranscriptionService.swift    # FluidAudio actor — FRAGILE, read rules below
│   ├── AudioSessionService.swift     # AVAudioSession + route-change handling — FRAGILE
│   ├── VocabularyService.swift       # Hotwords + substitution rules, AppStorage-backed
│   └── ClipboardService.swift        # UIPasteboard snapshot/write/restore
├── Extensions/
│   ├── String+Filters.swift          # Filler word removal, substitution pass
│   └── String+TitleGeneration.swift  # First-sentence extraction for auto-title
ShhhcribbleShared/                     # Live Activity attributes + StopRecordingIntent — keep as-is from original
ShhhcribbleWidget/                     # Live Activity — extend waveform UI
ShhhcribbleKeyboard/                   # Phase 2 only — do not create until Sprint 5
```

---

## SwiftData Note model

```swift
@Model
class Note {
    var id: UUID = UUID()
    var transcript: String            // Parakeet output after filter + substitution pass
    var title: String                 // Auto: first sentence truncated to ~60 chars
    var createdAt: Date = Date()
    var duration: TimeInterval        // Recording length in seconds
    var trigger: TriggerSource        // How recording was started
    var tags: [String] = []           // Manual tags — empty by default
    var embedding: Data? = nil        // Reserved for v3 semantic search — always nil in v1/v2
}

enum TriggerSource: String, Codable {
    case controlCenter
    case airPods
    case backTap
    case actionButton
    case keyboard
    case manual
}
```

The `embedding: Data?` field must be present from the very first schema version. Populated in v3 when semantic search lands. Adding it later requires a migration.

---

## Capture flow

```
Trigger fires
    ↓
ClipboardService.snapshot()           ← save whatever is on clipboard RIGHT NOW
Recording starts (Live Activity)
    ↓
  [Cancel tap] → abort, no transcription, ClipboardService.restoreImmediately()
    ↓
[Stop tap]
    ↓
  → Empty audio → .noSpeech ("No speech detected", ~1 s neutral, dismiss) → ClipboardService.restoreImmediately()
  → Valid audio → Parakeet → substitution pass → filler filter
    ↓
Auto-save Note (auto-title from first sentence)
Write transcript to clipboard
ClipboardService.scheduleRestore(2.0)
Live Activity ends, app returns to .idle
```

Editing happens later via `NoteDetailView` (inline edit, share, delete). There is no forced review screen in the main flow — Save is automatic on Stop. If the user wants to discard, they delete the note from `NotesListView` or `NoteDetailView`.

**Never save a blank note. Never paste an empty string.**

---

## Load-bearing decisions

### Activation model — always tap-to-stop
The trigger (widget / AirPods / Back Tap) starts recording. The UI provides a Stop button. There is no push-to-talk mechanic and no toggle-mode setting. The launch IS the start. Don't add a hold-to-record gesture or a toggle preference.

### Clipboard restore — always
`ClipboardService` snapshots the clipboard before every recording. After paste, it restores the prior value with a 2-second delay, gated on `UIPasteboard.changeCount` so a manual copy during the window isn't clobbered. On Cancel or Discard, restore is immediate.

```swift
func scheduleRestore(after delay: TimeInterval) {
    let savedCount = UIPasteboard.general.changeCount
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard UIPasteboard.general.changeCount == savedCount + 1 else { return }
        UIPasteboard.general.string = self.priorClipboard ?? ""
    }
}
```

### "No speech detected" — named state
Empty transcription result is not an error and not a save. It is a distinct named state: brief neutral indicator (~1 s auto-dismiss), no clipboard write, no note created. Distinguish from `.error` (real failure: mic permission denied, model not loaded, FluidAudio threw).

### No LLM post-processing — ever
Parakeet output → deterministic substitution pass → deterministic filler filter → user receives exactly that. No AI reformatting. No contextual tone adjustment. No summarisation. What the user said is what they get.

### No input device picker
Route-change handlers manage the active input automatically. A manual device picker causes lifecycle bugs when users pin to a disconnected device — confirmed on Mac. Don't add one.

---

## AudioSessionService — AirPods rules (empirically verified on Mac 2026-04-23)

These are the most dangerous area of the codebase. The Mac version hit every one of these. Don't repeat them.

**Never call `setVoiceProcessingEnabled(true)` for Bluetooth.**
On iOS 17+ and macOS 14+, AirPods deliver clean audio via plain HAL I/O. Voice processing destroys output audio (music goes scratchy), forces HFP lock-in for 30+ seconds post-recording, and generates `AVAudioEngineConfigurationChange` notification storms. The guidance that AirPods need VP to deliver mic audio is iOS 16-era and is wrong today.

**Fresh `AVAudioEngine` per recording.**
Deallocate and recreate `engine = AVAudioEngine()` in `stop()`. This ensures the engine always binds to the current input device. AirPods reconnects, Continuity Mic swaps, sleep/wake all self-heal on the next trigger. Cost: ~100–200 ms cold-start. Worth every millisecond.

**Mid-recording route changes: rebuild, don't patch.**
Observe `AVAudioEngineConfigurationChange`. Tear down the tap. Reallocate the engine. Restart against the new format. Preserve any samples already captured.

**Buffer allocation per-callback, not pre-sized.**
AirPods use variable-size stereo buffers. Pre-sizing from the input format at prepare-time silently truncates → trailing words are clipped from transcription. Allocate `AVAudioPCMBuffer` per-callback from `buffer.frameLength * ratio`.

**Never run two `AVAudioEngine` instances simultaneously.**
Sharing the VP lifecycle deadlocks the main thread on `AVAudioEngineConfigurationChange`. This broke the Mac v2 onboarding mic-test screen. If you're thinking of a mic preview in onboarding — don't.

---

## TranscriptionService

Swift `actor` — thread-safe audio buffer access. One `AsrManager` loaded with Parakeet TDT v3 (~494 MB, downloaded once). Final transcription runs on `stop()`. Live preview (if implemented) polls the growing sample buffer every 3 s — do not use a pre-sized reusable buffer (see AudioSessionService buffer rule above).

The streaming `StreamingEouAsrManager` (160 ms chunks) exists in FluidAudio but was authored against a voice-processing pipeline. If you want to add it later, verify it handles AirPods' 24 kHz stereo VP-free correctly before shipping.

---

## ClipboardService

```swift
actor ClipboardService {
    private var priorClipboard: String?
    private var priorChangeCount: Int = 0

    func snapshot() {
        priorClipboard = UIPasteboard.general.string
        priorChangeCount = UIPasteboard.general.changeCount
    }

    func writeTranscript(_ text: String) {
        UIPasteboard.general.string = text
    }

    func restoreImmediately() {
        UIPasteboard.general.string = priorClipboard ?? ""
    }

    func scheduleRestore(after delay: TimeInterval) {
        let savedCount = priorChangeCount
        let saved = priorClipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard UIPasteboard.general.changeCount == savedCount + 1 else { return }
            UIPasteboard.general.string = saved ?? ""
        }
    }
}
```

---

## App Group

App Group ID: `group.com.shhhcribble`
Set up from the very first build. Shared between:
- Main app target
- `ShhhcribbleWidget` (Live Activity)
- `ShhhcribbleKeyboard` (Phase 2 — keyboard extension)

If the group isn't set up from Sprint 1, adding the keyboard extension in Sprint 5 requires re-entitling every target simultaneously. Do it once, early.

---

## AppIntents

```swift
// StartRecordingIntent — invokable from Siri, Shortcuts, AirPods, Action Button, Control Center
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Shhhcribble Recording"
    static var description = IntentDescription("Start a voice recording in Shhhcribble")

    func perform() async throws -> some IntentResult {
        // Open app and begin recording via URL scheme or scene activation
        return .result()
    }
}

// Registered as an App Shortcut so it appears in Siri and Shortcuts automatically
// without any user setup
struct ShhhcribbleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: ["Start \(.applicationName)", "Record with \(.applicationName)"]
        )
    }
}
```

---

## Pref keys (UserDefaults / AppStorage)

| Key | Type | Default | What it does |
|---|---|---|---|
| `selectedParakeetModel` | String | `"parakeet-v3"` | TDT v3 or EOU streaming |
| `fillerFilterEnabled` | Bool | `true` | Strip um/uh/hmm etc. |
| `customHotwords` | [String] | `[]` | Hotword biasing passed to FluidAudio |
| `substitutionRules` | Data (JSON) | `{}` | Key-value find-replace dictionary |
| `customFillerWords` | [String] | `[]` | User-added filler words |
| `onboardingComplete` | Bool | `false` | Show onboarding on first launch |
| `cpuFallbackEnabled` | Bool | `false` | Debug: force CPU instead of ANE |

---

## UI state machine for recording

```
.idle
  → trigger fires → .recording
.recording
  → cancel tap   → .idle          (ClipboardService.restoreImmediately)
  → stop tap     → .transcribing
.transcribing
  → empty result → .noSpeech      (auto-dismiss ~1 s, ClipboardService.restoreImmediately)
  → error        → .error         (auto-dismiss ~1.6 s, ClipboardService.restoreImmediately)
  → valid text   → .saved         (persist Note, clipboard write, scheduleRestore(2.0))
.saved
  → ~1 s confirmation → .idle
```

There is no `.review` state in the main flow. Save is automatic on Stop. Edits happen later via `NoteDetailView`. Show a brief `.saved` confirmation (toast / haptic) so the user knows the note landed, then return to `.idle`.

---

## Phase 2 — keyboard extension (don't build until Sprint 5)

The keyboard extension (`ShhhcribbleKeyboard`) injects transcribed text directly into any focused text field via `UITextDocumentProxy`. It cannot access the microphone directly (Apple sandbox). Flow:

1. User switches to Shhhcribble keyboard (Globe key)
2. Taps mic button in keyboard UI
3. Keyboard signals main app via App Group shared container
4. Main app wakes (background audio session), records + transcribes
5. Main app writes transcript to App Group container
6. Keyboard reads transcript, calls `textDocumentProxy.insertText(transcript)`
7. Keyboard provides a Cancel button — tapping it writes a cancellation flag to the App Group and main app aborts

**Memory constraint:** keyboard extensions are capped at ~70 MB. Parakeet's working memory is ~66 MB on ANE. The model must run in the main app, not the keyboard extension. The keyboard only handles UI and proxy insertion.

**Known risk:** some apps (historically Electron on Mac — Claude.app, Slack, VS Code) drop `UITextDocumentProxy` writes silently. Test keyboard injection specifically against: Claude.app (iOS), WhatsApp, Apple Notes, Messages. If any app silently drops, log and surface a "copied to clipboard instead" fallback.

---

## What not to build (closed decisions)

- No push-to-talk / hold-to-record mechanic
- No toggle mode preference
- No input device picker
- No LLM post-processing of any kind
- No contextual formatting
- No cloud transcription
- No iCloud sync in v1
- No AI summaries / action items
- No speaker diarization
- No iPad / Mac (Mac version already exists)
- No Android
- No voice processing (`setVoiceProcessingEnabled`) for Bluetooth — ever

---

## Build sequence

**Sprint 1 — Foundation**
1. Re-sign all targets under your Apple Developer team
2. Set up App Group `group.com.shhhcribble` on all targets
3. Audit existing Swift files — refactor into feature folder structure above
4. Replace any UserDefaults note persistence with SwiftData `Note` model
5. Add `ControlCenterWidget` target (iOS 18 `ControlWidget`)

**Sprint 2 — Capture flow**
6. `RecordingView` + `RecordingViewModel` — waveform, timer, Stop + Cancel
7. `ClipboardService` — snapshot/write/restore
8. Auto-save on Stop + `.saved` confirmation toast (no Review screen — edits land in `NoteDetailView`)
9. `TranscriptionService` — FluidAudio actor, VP-free audio session
10. Share Sheet from `NoteDetailView`

**Sprint 3 — Notes layer**
11. SwiftData `Note` model + `ModelContainer` setup
12. `NotesListView` — search, tag filter chips, swipe actions
13. `NoteDetailView` — full note, edit, share

**Sprint 4 — Settings + polish**
14. `SettingsView` — filler words, custom vocabulary, substitution rules
15. `OnboardingView` — 3 screens + deep link to Control Center settings
16. Audio interruption handling (phone call, AirPods disconnect)
17. Error states (mic permission denied, model not loaded, no speech)
18. Visual polish — typography, waveform animation, dark mode

**Sprint 5 — Keyboard extension (Phase 2)**
19. `ShhhcribbleKeyboard` target + `UIInputViewController`
20. App Group microphone handoff flow
21. `UITextDocumentProxy` text injection
22. Cancel button in keyboard UI
23. Onboarding update for keyboard setup (Settings → General → Keyboards)

---

## When adding a feature

1. One feature per branch, locally
2. Verify with AirPods connected + music playing before committing
3. Update this CLAUDE.md if the change adds a new load-bearing decision or pref key
4. Merge to main, delete the branch

---

## Working notes — Sprint 1 + iteration learnings

These are gotchas and conventions discovered while building Sprint 1 + the recording UX. Read before extending.

### Build & install on a physical iPhone (CLI)

Xcode UI is fine, but Cmd-R from Xcode silently fails when the App Group entitlement is in play under a free Personal Team. Direct `devicectl` install is the reliable path during development:

```bash
xcodebuild -project ShhhcribbleiOS.xcodeproj -scheme ShhhcribbleiOS \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath /tmp/sb_build build

xcrun devicectl device install app \
  --device <iPhone UDID> \
  /tmp/sb_build/Build/Products/Debug-iphoneos/ShhhcribbleiOS.app
```

Get the device UDID with `xcrun devicectl list devices`. The `Failed to load provisioning paramter list...code=1002 "No provider was found"` warning that `devicectl` always emits is harmless — installation completes anyway.

### Personal Team signing — pin the team ID in `project.yml`

`xcodegen` regenerates the project on every run and **blanks out** the development team selection from the pbxproj. To stop the manual "set team in Xcode every time" loop, the Personal Team ID is pinned in [project.yml](project.yml) under each target's `settings.base`:

```yaml
DEVELOPMENT_TEAM: L9T3PX7HVH
```

That's the user's personal team. Do not commit a paid program team ID here — Personal Team is intentional for development.

### App Group + Personal Team don't mix

Personal Team accounts cannot include the `com.apple.security.application-groups` entitlement in their auto-generated provisioning profiles. With it set, Xcode "Build Succeeded" but install silently fails (no error in the navigator). The App Group entries in [ShhhcribbleiOS.entitlements](ShhhcribbleiOS/ShhhcribbleiOS.entitlements) and [ShhhcribbleWidget.entitlements](ShhhcribbleWidget/ShhhcribbleWidget.entitlements) are intentionally **stripped** for now, with a marker comment in `project.yml` so we restore them when the app moves to a paid Apple Developer Program account.

**Restore App Group when:**
1. User enrols in paid Apple Developer Program
2. Sprint 5 begins (keyboard extension needs the App Group container to coordinate with main app)

### LiveActivityIntent + Personal Team

`LiveActivityIntent.perform()` is meant to run in the main app's process when the user taps a button on a Live Activity. With a free Personal Team and **no App Group entitlement**, the cross-process routing from widget extension → main app silently fails (intent never fires). Workaround currently in place:

```swift
public static var openAppWhenRun: Bool = true
```

Both `StopRecordingIntent` and `CancelRecordingIntent` use `openAppWhenRun: true` so tapping them from the lock screen forces unlock + foreground. Comment markers in both files note when to flip back to `false` (after paid program + App Group restored).

The Cancel/Stop buttons on the lock-screen Live Activity card are now **decorative only**. The whole card is tappable via `.widgetURL(URL(string: "shhhcribble://open")!)` which deep-links into the app — user stops via the in-app overlay. This avoids relying on intent routing entirely. Restore the per-button intents in Sprint 5 when the App Group comes back.

### Diagnostic logging on physical devices

`print(...)` does **not** show up in `idevicesyslog` output — iOS forwards `print` to stdout, which only Xcode's debug console captures. For diagnostic logs that need to survive launch from `devicectl` and be readable from `idevicesyslog`, use `os.Logger`:

```swift
import os
private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "lifecycle")
diagLog.notice("StopRecordingIntent.perform invoked, performer=\(Self.performer == nil ? "nil" : "set", privacy: .public)")
```

Mark interpolated values `privacy: .public` so they appear in the log instead of being redacted to `<private>`.

To stream from a connected iPhone:

```bash
brew install libimobiledevice    # one-time
idevicesyslog -u <iPhone UDID> --no-colors -o /tmp/sb_syslog.log
# (or) grep 'shhhcribble.diag' /tmp/sb_syslog.log
```

`--no-colors` matters: ANSI escape codes corrupt the file otherwise. Only run **one** `idevicesyslog` instance writing to the file at a time — multiple instances writing to the same file produce binary garbage.

### Live Activity widget animations

`.symbolEffect(.variableColor.iterative.reversing, …)` is unreliable in widget context on iOS 26. The fallback used in [ShhhcribbleLiveActivity.swift](ShhhcribbleWidget/ShhhcribbleLiveActivity.swift) is a **`TimelineView(.animation)`-driven custom waveform** built from primitive `Capsule` shapes. SwiftUI redraws on every timeline tick (~80 ms) and we drive bar heights from a sin wave evaluated at the timestamp. This is the documented way to get continuous animation in a widget without state churn.

Don't push high-frequency state updates to a Live Activity to drive animations. ActivityKit throttles aggressively (~2 updates/sec sustained) and the system will silently drop later updates.

### Live transcript pipeline pitfall

The Mac version computed a 60-character tail for the floating pill (`String(text.suffix(60))`). This was copied into iOS without realising the iOS overlay is full-screen and wants the **full** transcript. The sliding 60-char window broke the in-app `TypingViewModel` because `newText.hasPrefix(displayed)` failed on every partial — the typer rewound and retyped continuously. Symptom: jittery, never-settling text.

Fix in [TranscriptionService.swift](ShhhcribbleiOS/Services/TranscriptionService.swift):
- `TranscriptionStatus.partialSnippet` now receives the **full** filtered transcript.
- Live Activity gets a bounded `String(text.suffix(200))` because widget render space is tight.

The `TypingViewModel`'s rewind logic is still correct for genuine ASR revisions; it just shouldn't be triggered by our own truncation.

### Audio reactivity

[AudioRecorder.swift](ShhhcribbleiOS/Services/AudioRecorder.swift) computes RMS per buffer (~20 Hz on iPhone), scales by 12× to map normal speech to ~1.0, and runs an envelope follower (`max(scaled, smoothed * 0.78)`) for instant attack + smooth release. Published to `TranscriptionStatus.audioLevel` (0…1) which the in-app `SoundwaveBars` reads.

`SoundwaveBars` keeps an 11-slot history and shifts left on a 60 ms tick — so the bars literally show the shape of your voice over the last ~660 ms, not a stylised pulse.

The Live Activity waveform stays self-driven (sin wave via TimelineView) — pushing audio level updates through ActivityKit isn't viable.

### Streaming vs Parakeet TDT v3

Two different FluidAudio engines, **not** simultaneously loaded. The `AsrMode` AppStorage choice swaps which one `TranscriptionService` instantiates:

- **Streaming** (`StreamingEouAsrManager`): live partials at low latency, no punctuation/capitalisation.
- **Parakeet TDT v3** (`AsrManager`): live partials AND a final clean transcribe on stop, punctuated + capitalised. Higher CPU.

Both run fully on-device on the ANE. The picker in Settings is the only user-facing knob.

### Scene-phase observer — only auto-stop on URL-scheme launches

`ShhhcribbleApp.scenePhase` observer used to call `stopRecording()` whenever the app went background. This broke the in-app flow: starting via the play button then switching apps would terminate the recording the moment the Live Activity appeared. Auto-stop is now gated:

```swift
if phase == .background && status.isRecording && status.launchedViaURL {
    Task { await TranscriptionService.shared.stopRecording() }
}
```

So URL-scheme triggers (Back Tap → Shortcut → app launch) still get the "tap iOS Back pill = commit" behaviour, but in-app starts continue across app switches.

---

*Last updated: April 2026 — based on planning sessions and Mac version lessons (itsHendri/Shhhcribble v1.3.0)*
