# ShhhcribbleiOS — Claude Code context

Read this at the start of every session. It is the single source of truth for architecture decisions and hard constraints. Don't relitigate anything marked **load-bearing** without a strong reason and a note added here.

---

## What this app is

A native iOS voice-to-text note-taking app. An external trigger (Control Center widget, AirPods, Back Tap, Action Button, or keyboard extension) starts recording. The user speaks. Parakeet TDT v3 transcribes on-device via FluidAudio. The user reviews, edits if needed, and saves to a local note store — or pastes directly into another app via the keyboard extension.

**Everything runs on-device. No cloud. No API keys. No LLM post-processing.**

- **Platform:** iOS 18+ — iPhone only
- **Language:** Swift / SwiftUI
- **Transcription:** FluidAudio + NVIDIA Parakeet TDT v3 (CoreML, Apple Neural Engine)
- **Persistence:** SwiftData
- **Forked from:** OsamaBinBallZak/ShhcribbleiOS (MIT)
- **Related:** itsHendri/Shhhcribble (Mac version — same FluidAudio stack, lessons learned documented below)

---

## Naming

The product is spelled **Shhhcribble** (three H's) in every context: code identifiers, filenames, folders, target names, bundle IDs, URL schemes, App Group IDs, user-facing strings, and prose. The two-H variant `Shhcribble` is wrong. The only exception is the upstream fork attribution `OsamaBinBallZak/ShhcribbleiOS`, which references an externally-owned GitHub repo and must stay as the original spelling.

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
│   ├── Review/
│   │   ├── ReviewView.swift          # Transcript, inline edit, title, tags, Save/Share/Discard
│   │   └── ReviewViewModel.swift
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
  → Empty audio → "No speech detected" (neutral, ~1 s, dismiss) → ClipboardService.restoreImmediately()
  → Valid audio → Parakeet → substitution pass → filler filter
    ↓
ReviewView
  → [Discard] → ClipboardService.restoreImmediately()
  → [Save]    → persist Note, write transcript to clipboard, ClipboardService.scheduleRestore(2.0)
  → [Share]   → iOS share sheet, write transcript to clipboard, ClipboardService.scheduleRestore(2.0)
```

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
  → valid text   → .review
.review
  → save         → .idle          (persist Note, clipboard write, schedule restore)
  → share        → .idle          (share sheet, clipboard write, schedule restore)
  → discard      → .idle          (ClipboardService.restoreImmediately)
```

Flip to `.review` optimistically on stop — don't show a "Transcribing…" spinner in the main flow. If transcription takes longer than expected, the review screen loads while it completes.

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
8. `ReviewView` + `ReviewViewModel` — transcript, inline edit, title, tags
9. `TranscriptionService` — FluidAudio actor, VP-free audio session
10. Share Sheet from ReviewView

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

*Last updated: April 2026 — based on planning sessions and Mac version lessons (itsHendri/Shhhcribble v1.3.0)*
