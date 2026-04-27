import SwiftData
import SwiftUI

struct NoteDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    @State private var showDeleteConfirm = false

    // All notes (sorted by recency) — used to source the tag autocomplete
    // suggestion list. SwiftData @Query auto-updates as notes change.
    @Query(sort: \Note.createdAt, order: .reverse) private var allNotes: [Note]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(1...3)

                HStack(spacing: 12) {
                    Label(formattedTimestamp, systemImage: "calendar")
                    Label(formattedDuration, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                TagEditor(
                    tags: Binding(
                        get: { note.tags },
                        set: { note.tags = $0 }
                    ),
                    suggestions: distinctTagsAcrossAllNotes
                )

                Divider()

                TextEditor(text: $note.transcript)
                    .font(.body)
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: note.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onDisappear { try? context.save() }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(note)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
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

    private var distinctTagsAcrossAllNotes: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for n in allNotes {
            for tag in n.tags where !seen.contains(tag) {
                seen.insert(tag)
                out.append(tag)
            }
        }
        return out.sorted()
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
