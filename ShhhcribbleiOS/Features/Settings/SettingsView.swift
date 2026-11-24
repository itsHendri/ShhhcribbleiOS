import AVFoundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("filterFillerWords") private var filterFillerWords = true
    @AppStorage(TextFinisher.cleanupKey) private var cleanupEnabled = true
    @AppStorage("useANE") private var useANE = true
    @AppStorage("asrMode") private var asrModeRaw = AsrMode.streaming.rawValue
    // TODO: remove after onboarding QA — see plan silly-karp
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false
    @ObservedObject private var status = TranscriptionStatus.shared

    @State private var micPermission: AVAudioApplication.recordPermission = .undetermined

    // Counts for inline detail labels — refreshed on appear.
    @State private var hotwordCount: Int = 0
    @State private var substitutionCount: Int = 0
    @State private var customFillerCount: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Settings")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Form {
                    transcriptionStyleSection
                    SyncSection()
                    cleanupSection
                    vocabularySection
                    performanceSection
                    permissionsSection
                    aboutSection
                    debugSection // TODO: remove after onboarding QA — see plan silly-karp
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                refreshPermissions()
                refreshCounts()
            }
        }
    }

    // MARK: - Sections

    private var transcriptionStyleSection: some View {
        Section {
            Picker("Style", selection: $asrModeRaw) {
                ForEach(AsrMode.allCases, id: \.rawValue) { mode in
                    Text(modeLabel(mode)).tag(mode.rawValue)
                }
            }
            .onChange(of: asrModeRaw) { _, _ in reload() }

            HStack {
                Text("Status")
                Spacer()
                statusLabel
            }
            if case .error(let msg) = status.model {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Transcription style")
        } footer: {
            Text("Streaming shows transcribed text live with the lowest latency, but without punctuation. Parakeet TDT v3 produces punctuated, capitalised text and is more CPU-intensive. Both run fully on-device.")
        }
    }

    private var cleanupSection: some View {
        Section {
            Toggle("Clean up after recording", isOn: $cleanupEnabled)
        } header: {
            Text("Cleanup")
        } footer: {
            if TextFinisher.cleanupAvailable {
                Text("After you stop, Apple's on-device model tidies the text: punctuation, false starts, repeated words. It runs on this iPhone, and a result that adds or drops content is thrown away. The words as heard are kept with the note.")
            } else {
                Label("Not available right now. Cleanup needs Apple Intelligence turned on in the Settings app. Until then only filler words are removed.", systemImage: "sparkles.slash")
            }
        }
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                CustomWordsView()
                    .onDisappear { refreshCounts() }
            } label: {
                detailRow(
                    title: "Custom Words",
                    detail: hotwordCount == 0 ? "None" : "\(hotwordCount)"
                )
            }

            NavigationLink {
                SubstitutionsView()
                    .onDisappear { refreshCounts() }
            } label: {
                detailRow(
                    title: "Substitutions",
                    detail: substitutionCount == 0 ? "None" : "\(substitutionCount)"
                )
            }

            NavigationLink {
                FillerWordsView()
                    .onDisappear { refreshCounts() }
            } label: {
                detailRow(
                    title: "Filler Words",
                    detail: filterFillerWords
                        ? (customFillerCount == 0 ? "On" : "On · +\(customFillerCount)")
                        : "Off"
                )
            }
        } header: {
            Text("Vocabulary")
        } footer: {
            Text("Auto-correct casing for proper nouns, replace recurring phrases, and remove filler words from your transcripts.")
        }
    }

    private func detailRow(title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private var performanceSection: some View {
        Section {
            Toggle("Use Neural Engine", isOn: $useANE)
                .onChange(of: useANE) { _, _ in reload() }
        } header: {
            Text("Performance")
        } footer: {
            Text("Runs the transcription model on Apple's Neural Engine for faster performance and lower battery use. Disable only if you experience issues.")
        }
    }

    private var permissionsSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone")
                        .font(.body)
                    Text("Required to record your voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                permissionLabel(for: micPermission)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if micPermission == .denied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Permissions")
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Shhhcribble")
                        .font(.headline)
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(alignment: .top) {
                    Text("this app was crafted by a human named Hendri with chief vibes officer Tiuri whispering ideas in his ear. both humans. probably.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("(◡‿◡)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("About")
        }
    }

    // TODO: remove after onboarding QA — see plan silly-karp
    private var debugSection: some View {
        Section {
            Button {
                onboardingComplete = false
            } label: {
                HStack {
                    Text("Replay onboarding")
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Temporary — re-shows the onboarding flow on next return to this view's parent. Remove before TestFlight.")
        }
    }

    // MARK: - Helpers

    private func reload() {
        Task { await TranscriptionService.shared.reloadModel() }
    }

    private func refreshPermissions() {
        micPermission = AVAudioApplication.shared.recordPermission
    }

    private func refreshCounts() {
        hotwordCount = VocabularyEdit.customWords().count
        substitutionCount = VocabularyEdit.substitutions().count
        customFillerCount = (UserDefaults.standard.array(forKey: "customFillerWords") as? [String])?.count ?? 0
    }

    private func modeLabel(_ mode: AsrMode) -> String {
        switch mode {
        case .streaming: return "Streaming (live, no punctuation)"
        case .tdt:       return "Parakeet TDT v3 (punctuated)"
        }
    }

    @ViewBuilder
    private func permissionLabel(for permission: AVAudioApplication.recordPermission) -> some View {
        switch permission {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(.subheadline)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
                .font(.subheadline)
        case .undetermined:
            Text("Not asked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        @unknown default:
            Text("Unknown")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status.model {
        case .notLoaded:
            Text("Not loaded").foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Loading…").foregroundStyle(.secondary)
            }
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return short
    }
}

/// Settings › Sync. Off by default. Turning it on goes through one sheet that
/// says in plain words what leaves the phone; the same words stay here.
private struct SyncSection: View {
    @ObservedObject private var sync = SyncService.shared
    @AppStorage(SyncService.enabledKey) private var enabled = false
    @State private var showingDisclosure = false
    @State private var showingWords = false

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { enabled },
                set: { wantOn in
                    if wantOn { showingDisclosure = true } else { sync.turnOff() }
                }))
                .disabled(!SyncService.buildCanSync)
            statusRow
            Button("What sync does with your words") { showingWords = true }
                .font(.footnote)
                .frame(minHeight: 44)
        } header: {
            Text("Sync")
        } footer: {
            Text("Keeps your notes, tasks and dictionary the same on this iPhone and your Mac, through your own iCloud.")
        }
        .sheet(isPresented: $showingDisclosure) { disclosure(turningOn: true) }
        .sheet(isPresented: $showingWords) { disclosure(turningOn: false) }
    }

    @ViewBuilder
    private var statusRow: some View {
        if !SyncService.buildCanSync {
            Label("Sync is not available in this build.", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        } else {
            switch sync.status {
            case .off:
                Label("Off. Nothing leaves this iPhone.", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            case .syncing:
                Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
            case .upToDate(let date):
                Label("Up to date as of \(date.formatted(date: .omitted, time: .shortened))",
                      systemImage: "checkmark.icloud")
            case .needsConfirmation(let count):
                HeldDeletesCard(count: count)
            case .unavailable(let why):
                Label(why, systemImage: "exclamationmark.icloud")
            case .failed(let why):
                Label("Sync could not finish. \(why)", systemImage: "exclamationmark.icloud")
            }
        }
    }

    private func disclosure(turningOn: Bool) -> some View {
        NavigationStack {
            ScrollView {
                Text(SyncService.disclosure)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(turningOn ? "Turn on sync?" : "Sync and your words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if turningOn {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not Now") { showingDisclosure = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Turn On Sync") {
                            showingDisclosure = false
                            enabled = true
                            Task { await sync.turnOn() }
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingWords = false }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Sync noticed that many notes are gone from this iPhone and is holding the
/// deletes instead of sending them everywhere. The user decides.
struct HeldDeletesCard: View {
    let count: Int
    @ObservedObject private var sync = SyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(count) notes are no longer on this iPhone", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text("Deleting them here would delete them from iCloud and your Mac too. Nothing has been deleted yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Bring Them Back") { sync.restoreHeldRows() }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentFill)
                Spacer()
                Button("Delete Everywhere", role: .destructive) { sync.confirmHeldDeletes() }
                    .buttonStyle(.bordered)
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
    }
}
