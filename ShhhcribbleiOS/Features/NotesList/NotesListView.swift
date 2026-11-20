import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotesListView: View {
    @ObservedObject private var library = Library.shared
    private var notes: [LibraryNote] { library.notes }
    @State private var searchText: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var showFileImporter = false

    private var allTags: [String] { library.allTags }

    private var filteredNotes: [LibraryNote] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        return notes.filter { note in
            if !selectedTags.isEmpty {
                guard selectedTags.isSubset(of: Set(note.tags)) else { return false }
            }
            if !needle.isEmpty {
                guard
                    note.transcript.lowercased().contains(needle)
                        || note.title.lowercased().contains(needle)
                else { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Import audio file")
                    // No delete-all in the header (Hendri, 2026-11-20): it sat
                    // beside an everyday button and wiped every note. Deleting
                    // several comes back through Select, with Recently Deleted.
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if !notes.isEmpty {
                    SearchBar(text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if !allTags.isEmpty {
                    TagFilterBar(
                        tags: allTags,
                        selected: $selectedTags
                    )
                    .padding(.bottom, 8)
                }

                if notes.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "waveform",
                        description: Text("Tap the play button to start a transcription.")
                    )
                    Spacer()
                } else if filteredNotes.isEmpty {
                    Spacer()
                    ContentUnavailableView.search(text: searchText)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            NavigationLink(value: note.id) {
                                NoteRow(note: note,
                                        onCopy: { copy(note) },
                                        onDelete: { delete(note) })
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
                guard case .success(let url) = result else { return }
                Task { await TranscriptionService.shared.importAudioFile(url) }
            }
            .navigationDestination(for: UUID.self) { id in
                NoteDetailView(noteID: id)
            }
        }
    }

    private func copy(_ note: LibraryNote) {
        UIPasteboard.general.string = note.transcript
        ToastManager.shared.show("Copied to clipboard", systemImage: "doc.on.doc.fill")
    }

    private func delete(_ note: LibraryNote) {
        library.delete(id: note.id)
        Self.offerUndo(count: 1)
    }

    /// The bar that follows any delete. Six seconds to take it back.
    static func offerUndo(count: Int) {
        ToastManager.shared.show(
            count == 1 ? "Note deleted" : "\(count) notes deleted",
            systemImage: "trash",
            actionLabel: "Undo"
        ) {
            let back = Library.shared.undoLastDelete()
            if back > 0 {
                ToastManager.shared.show(back == 1 ? "Note restored" : "\(back) notes restored",
                                         systemImage: "arrow.uturn.backward")
            }
        }
    }

}

private struct TagFilterBar: View {
    let tags: [String]
    @Binding var selected: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selected.contains(tag)
                    Button {
                        if isOn { selected.remove(tag) } else { selected.insert(tag) }
                    } label: {
                        HStack(spacing: 4) {
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(tag)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                isOn ? Color.accentColor.opacity(0.25)
                                     : Color(.tertiarySystemFill)
                            )
                        )
                        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }

                if !selected.isEmpty {
                    Button("Clear filters") {
                        selected.removeAll()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct SearchBar: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}

private struct NoteRow: View {
    let note: LibraryNote
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
            .buttonStyle(.borderless)
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
