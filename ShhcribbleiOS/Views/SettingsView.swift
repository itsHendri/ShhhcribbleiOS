import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("filterFillerWords") private var filterFillerWords = true
    @AppStorage("useANE") private var useANE = true
    @AppStorage("asrMode") private var asrModeRaw = AsrMode.streaming.rawValue
    @ObservedObject private var status = TranscriptionStatus.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
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
                    if !status.lastEvent.isEmpty {
                        HStack {
                            Text("Last event")
                            Spacer()
                            Text(status.lastEvent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if status.isRecording {
                        HStack {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Recording…")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Button("Load model now") {
                        Task { try? await TranscriptionService.shared.ensureModelLoaded() }
                    }
                    .disabled(status.model == .loading || status.model == .ready)

                    Button("Test transcribe") {
                        Task { try? await TranscriptionService.shared.recordAndTranscribe() }
                    }
                    .disabled(status.model != .ready || status.isRecording)

                    if status.isRecording {
                        Button("Stop recording", role: .destructive) {
                            Task { await TranscriptionService.shared.stopRecording() }
                        }
                    }
                }

                Section {
                    Picker("Model", selection: $asrModeRaw) {
                        ForEach(AsrMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .onChange(of: asrModeRaw) { _, _ in reload() }
                    Toggle("Use Neural Engine", isOn: $useANE)
                        .onChange(of: useANE) { _, _ in reload() }
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Streaming: ultra-low latency, no punctuation. Parakeet TDT v3 (larger, ~200 MB first download): punctuated + capitalized output, re-transcribed every ~1.5s so the clipboard stays fresh for the Back Tap → paste flow. TDT uses more CPU/ANE.")
                }

                Section("Transcription") {
                    Toggle("Filter filler words", isOn: $filterFillerWords)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Back Tap setup")
                            .font(.headline)
                        Text("""
                        Settings → Accessibility → Touch → Back Tap → Triple Tap → Shortcuts → tap "Shhcribble: Record & Transcribe".

                        Triple-tap the back of your phone to transcribe.
                        """)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func reload() {
        Task { await TranscriptionService.shared.reloadModel() }
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
}
