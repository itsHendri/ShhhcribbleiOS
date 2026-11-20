import Combine
import SwiftUI

/// Tasks and reminders: what is overdue, due today, coming up, undated, and
/// done. Ticking works in place; tapping a row opens it for editing.
struct TasksView: View {
    @ObservedObject private var tasks = TaskList.shared
    @State private var newText = ""
    @State private var editing: TaskItem?
    @State private var showDone = false
    @State private var alertsAllowed = true
    @FocusState private var addFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("New task", text: $newText)
                            .focused($addFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button(action: add) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                        .disabled(!canAdd)
                        .accessibilityLabel("Add task")
                    }
                } footer: {
                    Text("Or say it: start a recording with \"Reminder\" or \"To-do\", then the task and when.")
                }

                if !alertsAllowed {
                    Section {
                        Label("Notifications are off for Shhhcribble, so reminders will not alert.",
                              systemImage: "bell.slash")
                            .font(.footnote)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                group("Overdue", tasks.groups.overdue, overdue: true)
                group("Today", tasks.groups.today)
                group("Upcoming", tasks.groups.upcoming)
                group("No date", tasks.groups.noDate)

                if !tasks.groups.done.isEmpty {
                    Section {
                        DisclosureGroup("Done (\(tasks.groups.done.count))", isExpanded: $showDone) {
                            ForEach(tasks.groups.done) { row($0, overdue: false) }
                                .onDelete { delete($0, from: tasks.groups.done) }
                        }
                    }
                }

                if tasks.groups.isEmpty {
                    Section {
                        Text("No tasks yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tasks")
            // Room for the floating tab bar and record button.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            .sheet(item: $editing) { TaskEditView(task: $0) }
        }
        .onReceive(minute) { _ in tasks.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAll() }
        }
        .onAppear(perform: refreshAll)
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TaskItem], overdue: Bool = false) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { row($0, overdue: overdue) }
                    .onDelete { delete($0, from: items) }
            }
        }
    }

    private func row(_ task: TaskItem, overdue: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                tasks.toggle(id: task.id)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.done ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark not done: \(task.text)" : "Mark done: \(task.text)")

            Button {
                editing = task
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.text)
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? .secondary : .primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if let due = task.dueAt, !task.done {
                            HStack(spacing: 6) {
                                if overdue {
                                    Label("Overdue", systemImage: "exclamationmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .labelStyle(.titleAndIcon)
                                }
                                Text(DueLabel.text(for: due, allDay: task.dueAllDay))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(overdue ? .primary : .secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the task")
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 16))
    }

    private var canAdd: Bool {
        !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tasks.add(text: text)
        newText = ""
        addFocused = true
    }

    private func delete(_ offsets: IndexSet, from items: [TaskItem]) {
        for index in offsets { tasks.delete(id: items[index].id) }
    }

    private func refreshAll() {
        tasks.refresh()
        Task { alertsAllowed = await ReminderScheduler.shared.alertsAllowed() }
    }
}

/// One task, opened: its text, when it is due, and what else can be done
/// with it. Changes are saved on Done.
struct TaskEditView: View {
    let task: TaskItem

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var allDay: Bool
    @State private var confirmDelete = false

    init(task: TaskItem) {
        self.task = task
        _text = State(initialValue: task.text)
        _hasDue = State(initialValue: task.dueAt != nil)
        _due = State(initialValue: task.dueAt ?? Self.nextHour())
        _allDay = State(initialValue: task.dueAllDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task", text: $text, axis: .vertical)
                        .lineLimit(1...6)
                }

                Section {
                    Toggle("Remind me", isOn: $hasDue)
                    if hasDue {
                        Toggle("All day", isOn: $allDay)
                        DatePicker(
                            "When",
                            selection: $due,
                            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }
                } footer: {
                    if hasDue && allDay {
                        Text("An all-day reminder alerts at 09:00 that day.")
                    }
                }

                Section {
                    Button("Make it a plain note") {
                        TaskList.shared.makePlainNote(id: task.id)
                        dismiss()
                    }
                    Button("Delete task", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("A plain note moves to Notes and loses its due time.")
                }
            }
            .navigationTitle(task.done ? "Done task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    TaskList.shared.delete(id: task.id)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let tasks = TaskList.shared
        tasks.rename(id: task.id, text: text)
        let newDue: Date? = hasDue
            ? (allDay ? Self.allDayAlert(on: due) : due)
            : nil
        if newDue != task.dueAt || (hasDue && allDay) != task.dueAllDay {
            tasks.setDue(id: task.id, dueAt: newDue, allDay: hasDue && allDay)
        }
        dismiss()
    }

    private static func nextHour() -> Date {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? Date()
    }

    private static func allDayAlert(on day: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }
}
