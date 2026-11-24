import SwiftUI

/// Notes deleted in the last 30 days, on this iPhone and the Mac. Each one
/// can be restored; after 30 days the library removes it for good.
/// Design: docs/design/deleting.md, the bin board on the canvas.
struct RecentlyDeletedView: View {
    @ObservedObject private var library = Library.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEmpty = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if library.trashed.isEmpty {
                        Text("Nothing here. Deleted notes stay for 30 days.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.trashed) { note in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title)
                                    .lineLimit(2)
                                Text(caption(note))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Visible, not only a swipe (Hendri, 2026-11-21:
                            // "only had a recover all action though?"). Words
                            // as on the Mac: Restore, Delete Now, Empty
                            // Recently Deleted (Hendri, 2026-11-24).
                            Button("Restore") { restore(note) }
                                .buttonStyle(.bordered)
                                .foregroundStyle(Color.accentOnGrey)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Restore \(note.title)")
                        }
                        .frame(minHeight: 44)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                restore(note)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                library.deleteForever(ids: [note.id])
                            } label: {
                                Label("Delete Now", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Restore", systemImage: "arrow.uturn.backward") { restore(note) }
                            Button("Delete Now", systemImage: "trash", role: .destructive) {
                                library.deleteForever(ids: [note.id])
                            }
                        }
                        .accessibilityAction(named: "Restore") { restore(note) }
                    }
                } footer: {
                    if !library.trashed.isEmpty {
                        Text("Notes are removed for good after 30 days, on this iPhone and your Mac.")
                    }
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Restore All") {
                        let count = library.trashed.count
                        library.restoreAll()
                        ToastManager.shared.show(count == 1 ? "Note restored" : "\(count) notes restored",
                                                 systemImage: "arrow.uturn.backward")
                    }
                    .disabled(library.trashed.isEmpty)
                    Spacer()
                    Button("Empty Recently Deleted", role: .destructive) { confirmEmpty = true }
                        .foregroundStyle(library.trashed.isEmpty ? Color.secondary : Color(.systemRed))
                        .disabled(library.trashed.isEmpty)
                }
            }
            .confirmationDialog(
                "Empty Recently Deleted?",
                isPresented: $confirmEmpty,
                titleVisibility: .visible
            ) {
                Button(library.trashed.count == 1 ? "Delete 1 Note" : "Delete \(library.trashed.count) Notes",
                       role: .destructive) {
                    library.deleteForever(ids: library.trashed.map(\.id))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything in Recently Deleted is deleted for good, on this iPhone and your Mac. This can't be undone.")
            }
        }
    }

    private func restore(_ note: LibraryNote) {
        library.restore(id: note.id)
        ToastManager.shared.show("Note restored", systemImage: "arrow.uturn.backward")
    }

    private func caption(_ note: LibraryNote) -> String {
        let left = Library.daysLeft(note)
        let deleted = note.deletedAt.map { date -> String in
            Calendar.current.isDateInToday(date)
                ? "Deleted today"
                : "Deleted " + date.formatted(.dateTime.day().month(.abbreviated))
        } ?? "Deleted"
        let days = left == 0 ? "removed today" : (left == 1 ? "1 day left" : "\(left) days left")
        return "\(deleted) · \(days)"
    }
}
