import SwiftData
import SwiftUI
import UIKit

struct NotesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    if !notes.isEmpty {
                        Button("Clear All", role: .destructive, action: clearAll)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if notes.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "waveform",
                        description: Text("Tap the play button to start a transcription.")
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(notes) { note in
                            NoteRow(note: note,
                                    onCopy: { copy(note) },
                                    onDelete: { delete(note) })
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func copy(_ note: Note) {
        UIPasteboard.general.string = note.transcript
        ToastManager.shared.show("Copied to clipboard", systemImage: "doc.on.doc.fill")
    }

    private func delete(_ note: Note) {
        context.delete(note)
        try? context.save()
    }

    private func clearAll() {
        for note in notes {
            context.delete(note)
        }
        try? context.save()
    }
}

private struct NoteRow: View {
    let note: Note
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.transcript)
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.55, blue: 1.0))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy transcript")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
