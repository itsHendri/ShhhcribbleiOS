import SwiftUI
import UIKit

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = Library.shared

    let noteID: UUID

    /// The note as the library holds it right now. Edits write straight
    /// through, so text appended by a recording while this screen is open
    /// shows up here and is never overwritten by a stale copy.
    private var note: LibraryNote {
        library.note(id: noteID)
            ?? LibraryNote(id: noteID, transcript: "", duration: 0, trigger: .manual)
    }

    private func field<T>(_ keyPath: WritableKeyPath<LibraryNote, T>) -> Binding<T> {
        Binding(
            get: { note[keyPath: keyPath] },
            set: { newValue in
                guard var current = library.note(id: noteID) else { return }
                current[keyPath: keyPath] = newValue
                library.update(current)
            }
        )
    }
    @State private var isEditing: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(1...3)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 12) {
                    Label(formattedTimestamp, systemImage: "calendar")
                    Label(formattedDuration, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                TagEditor(
                    tags: field(\.tags),
                    suggestions: library.allTags
                )

                SummaryBlock(note: note)

                Divider()

                if isEditing {
                    TextEditor(text: field(\.transcript))
                        .font(.body)
                        .frame(minHeight: 240)
                        .scrollContentBackground(.hidden)
                } else {
                    Text(renderedMarkdown)
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                        .textSelection(.enabled)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditing = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.bottom, 80) // clearance for the floating play + continue buttons
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Copy lives here, not on the list's rows (Hendri, 2026-11-24).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = note.transcript
                    ToastManager.shared.show("Copied to clipboard", systemImage: "doc.on.doc.fill")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: note.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // No question first: the note goes to Recently Deleted with
                // an Undo line, as everywhere else (Hendri, 2026-11-24).
                Button(role: .destructive) {
                    library.delete(id: noteID)
                    NotesListView.offerUndo(count: 1)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            // Open in view mode when the transcript already looks markdown-y
            // (headings/bullets/links). Empty or plain transcripts open in
            // edit mode so the user can keep typing without an extra tap.
            isEditing = !note.transcript.containsMarkdownSyntax
            NoteFocus.shared.activeNoteId = note.id
        }
        .onDisappear {
            NoteFocus.shared.activeNoteId = nil
        }
    }

    private var formattedTimestamp: String {
        note.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedDuration: String {
        let seconds = Int(note.duration.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// `.inlineOnlyPreservingWhitespace` keeps newlines (full markdown mode
    /// collapses them, which makes a multi-line transcript unreadable). Falls
    /// back to plain text on parse failure.
    private var renderedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: note.transcript,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(note.transcript)
    }
}

// MARK: - Tag editor

private struct TagEditor: View {
    @Binding var tags: [String]
    let suggestions: [String]

    @State private var input: String = ""
    @FocusState private var focused: Bool

    private var filteredSuggestions: [String] {
        let needle = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = Set(tags)
        return suggestions
            .filter { !existing.contains($0) }
            .filter { needle.isEmpty || $0.lowercased().hasPrefix(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(label: tag, onRemove: { remove(tag) })
                }

                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Add tag", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { commit(input) }
                        .onChange(of: input) { _, newValue in
                            // Commit on space or comma — feels like a token field.
                            if let last = newValue.last, last == " " || last == "," {
                                let candidate = String(newValue.dropLast())
                                commit(candidate)
                            }
                        }
                        .frame(minWidth: 80)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }

            if focused, !filteredSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                commit(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(Color.accentColor.opacity(0.15))
                                    )
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private func commit(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        defer { input = "" }
        guard !cleaned.isEmpty else { return }
        guard !tags.contains(cleaned) else { return }
        tags.append(cleaned)
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

private struct TagChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove tag \(label)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.18))
        )
        .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Flow layout

/// Wraps subviews onto multiple lines like CSS flexbox / inline text.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The note's summary, or the button that makes one. Summaries are made on
/// the phone by Apple's on-device model, and only when asked for.
private struct SummaryBlock: View {
    let note: LibraryNote
    @ObservedObject private var summaries = Summaries.shared
    @ObservedObject private var tasks = TaskList.shared

    private var working: Bool { summaries.working.contains(note.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = note.summary, !summary.isEmpty {
                Label("Summary", systemImage: "text.badge.star")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.callout)
                    .textSelection(.enabled)
                if !note.actionItems.isEmpty {
                    Label("To do", systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(note.actionItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.callout)
                                if !item.quote.isEmpty {
                                    Text("\u{201C}" + item.quote + "\u{201D}")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            // Linked to this note, so a second tap (here or
                            // on the Mac) never makes a second task.
                            if tasks.isInTasks(noteID: note.id, item: item.text) {
                                Label("In Tasks", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(minHeight: 44)
                            } else {
                                Button {
                                    tasks.addFromSummary(noteID: note.id, item: item.text)
                                    ToastManager.shared.show("Added to Tasks", systemImage: "checklist")
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 20))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Add to Tasks: \(item.text)")
                            }
                        }
                    }
                }
            }

            if working {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Summarising on this iPhone…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            } else if summaries.available {
                Button {
                    Task { await summaries.generate(for: note.id) }
                } label: {
                    Label(note.summary == nil ? "Summarise" : "Summarise again", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(note.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if summaries.failed.contains(note.id) {
                    Label("No summary came back. Try again.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if note.summary == nil {
                Label("Summaries need Apple Intelligence turned on in Settings.", systemImage: "sparkles.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
