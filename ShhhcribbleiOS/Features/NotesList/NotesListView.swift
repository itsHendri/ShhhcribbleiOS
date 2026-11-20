import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotesListView: View {
    @ObservedObject private var library = Library.shared
    @ObservedObject private var sync = SyncService.shared
    private var notes: [LibraryNote] { library.notes }
    @State private var searchText: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var showFileImporter = false
    /// Select mode: tapping a note picks it instead of opening it.
    @State private var selecting = false
    @State private var picked: Set<UUID> = []

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
                if selecting {
                    selectHeader
                } else {
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
                        // No delete-all in the header (Hendri, 2026-11-20): it
                        // sat beside an everyday button and wiped every note.
                        // Deleting several goes through Select.
                        if !notes.isEmpty {
                            Button("Select") {
                                picked = []
                                selecting = true
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                if case .needsConfirmation(let count) = sync.status {
                    HeldDeletesCard(count: count)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

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
                    if !library.trashed.isEmpty {
                        RecentlyDeletedLink(count: library.trashed.count)
                            .padding(.horizontal, 16)
                    }
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
                        // At the top, not the end: with a long list the end is
                        // never seen (Hendri, 2026-11-20). Only while the bin
                        // holds something.
                        if !library.trashed.isEmpty && !selecting {
                            Section {
                                RecentlyDeletedLink(count: library.trashed.count, inList: true)
                            }
                        }
                        Section {
                            ForEach(filteredNotes) { note in
                                if selecting {
                                    SelectableRow(note: note, picked: picked.contains(note.id)) {
                                        if picked.contains(note.id) { picked.remove(note.id) }
                                        else { picked.insert(note.id) }
                                    }
                                } else {
                                    NavigationLink(value: note.id) {
                                        NoteRow(note: note,
                                                onCopy: { copy(note) },
                                                onDelete: { delete(note) })
                                    }
                                }
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

    private var selectHeader: some View {
        let all = filteredNotes.map(\.id)
        let allPicked = !all.isEmpty && Set(all).isSubset(of: picked)
        return HStack {
            Button(allPicked ? "Select None" : "Select All") {
                picked = allPicked ? [] : Set(all)
            }
            .frame(minHeight: 44)
            Spacer()
            Button(role: .destructive) {
                let ids = Array(picked)
                library.delete(ids: ids)
                selecting = false
                picked = []
                Self.offerUndo(count: ids.count)
            } label: {
                Label(picked.isEmpty ? "Delete" : "Delete \(picked.count)", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .foregroundStyle(picked.isEmpty ? Color.secondary : Color(.systemRed))
            .disabled(picked.isEmpty)
            .frame(minHeight: 44)
            Spacer()
            Button("Done") {
                selecting = false
                picked = []
            }
            .fontWeight(.semibold)
            .frame(minHeight: 44)
        }
        .font(.system(size: 17))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
                ToastManager.shared.show(back == 1 ? "Note recovered" : "\(back) notes recovered",
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

/// Opens Recently Deleted. Sits at the top of the notes list while the bin
/// holds anything.
private struct RecentlyDeletedLink: View {
    let count: Int
    var inList = false

    var body: some View {
        let row = Button {
            AppRouter.shared.showingBin = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text("Recently Deleted")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recently Deleted, \(count) \(count == 1 ? "note" : "notes")")

        if inList {
            row
        } else {
            row
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// A note in Select mode: a tick circle and the text. Picked shows a filled
/// circle with a tick, never colour alone.
private struct SelectableRow: View {
    let note: LibraryNote
    let picked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.transcript)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
