import AVFoundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("filterFillerWords") private var filterFillerWords = true
    @AppStorage("useANE") private var useANE = true
    @AppStorage("asrMode") private var asrModeRaw = AsrMode.streaming.rawValue
    @ObservedObject private var status = TranscriptionStatus.shared

    @State private var micPermission: AVAudioApplication.recordPermission = .undetermined

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
                    fillerWordsSection
                    performanceSection
                    permissionsSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { refreshPermissions() }
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

    private var fillerWordsSection: some View {
        Section {
            Toggle("Remove filler words", isOn: $filterFillerWords)
        } header: {
            Text("Filler words")
        } footer: {
            Text("Removes \"um\", \"uh\", \"hmm\" and similar filler words from transcriptions.")
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

    // MARK: - Helpers

    private func reload() {
        Task { await TranscriptionService.shared.reloadModel() }
    }

    private func refreshPermissions() {
        micPermission = AVAudioApplication.shared.recordPermission
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
