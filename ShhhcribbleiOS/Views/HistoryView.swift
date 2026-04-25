import SwiftUI
import UIKit

struct HistoryView: View {
    @ObservedObject private var store = TranscriptionStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "No transcriptions yet",
                        systemImage: "waveform",
                        description: Text("Triple-tap the back of your phone to start.")
                    )
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            Button {
                                UIPasteboard.general.string = entry.text
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.text)
                                        .foregroundStyle(.primary)
                                        .lineLimit(4)
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) { store.clearAll() }
                    }
                }
            }
        }
    }
}
