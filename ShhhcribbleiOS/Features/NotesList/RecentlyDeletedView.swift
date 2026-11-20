import SwiftUI

/// Notes deleted in the last 30 days, on this iPhone and the Mac. Each one
/// can be recovered; after 30 days the library removes it for good.
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title)
                                .lineLimit(2)
                            Text(caption(note))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                recover(note)
                            } label: {
                                Label("Recover", systemImage: "arrow.uturn.backward")
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
                            Button("Recover", systemImage: "arrow.uturn.backward") { recover(note) }
                            Button("Delete Now", systemImage: "trash", role: .destructive) {
                                library.deleteForever(ids: [note.id])
                            }
                        }
                        .accessibilityAction(named: "Recover") { recover(note) }
                    }
                } footer: {
                    if !library.trashed.isEmpty {
                        Text("Notes are removed for good after 30 days, on this iPhone and your Mac. Swipe right to recover one.")
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
                    Button("Recover All") {
                        let count = library.trashed.count
                        library.restoreAll()
                        ToastManager.shared.show(count == 1 ? "Note recovered" : "\(count) notes recovered",
                                                 systemImage: "arrow.uturn.backward")
                    }
                    .disabled(library.trashed.isEmpty)
                    Spacer()
                    Button("Delete All Now", role: .destructive) { confirmEmpty = true }
                        .foregroundStyle(library.trashed.isEmpty ? Color.secondary : Color(.systemRed))
                        .disabled(library.trashed.isEmpty)
                }
            }
            .confirmationDialog(
                library.trashed.count == 1 ? "Delete this note for good?" : "Delete these \(library.trashed.count) notes for good?",
                isPresented: $confirmEmpty,
                titleVisibility: .visible
            ) {
                Button("Delete for Good", role: .destructive) {
                    library.deleteForever(ids: library.trashed.map(\.id))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They can't be recovered after this, on this iPhone or your Mac.")
            }
        }
    }

    private func recover(_ note: LibraryNote) {
        library.restore(id: note.id)
        ToastManager.shared.show("Note recovered", systemImage: "arrow.uturn.backward")
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
