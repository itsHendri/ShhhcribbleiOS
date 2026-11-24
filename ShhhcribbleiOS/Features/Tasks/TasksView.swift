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
    @State private var changingMeeting: MeetingItem?
    @State private var addingMeeting: Set<UUID> = []
    @State private var calendarError: String?
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

                // A spoken meeting waits here for a yes (Hendri's pick A,
                // 2026-11-24, the Mac's card).
                if !tasks.meetings.isEmpty {
                    Section("To confirm") {
                        ForEach(tasks.meetings) { meeting in
                            MeetingCard(
                                meeting: meeting,
                                isAdding: addingMeeting.contains(meeting.id),
                                add: { addToCalendar(meeting) },
                                change: { changingMeeting = meeting },
                                dismiss: { tasks.notAMeeting(id: meeting.id) }
                            )
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

                if tasks.groups.isEmpty && tasks.meetings.isEmpty {
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
            .sheet(item: $changingMeeting) { MeetingEditView(meeting: $0) }
            .alert("Not added to the calendar", isPresented: Binding(
                get: { calendarError != nil },
                set: { if !$0 { calendarError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(calendarError ?? "")
            }
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
        let ids = offsets.map { items[$0].id }
        for id in ids { tasks.delete(id: id) }
        TasksView.offerUndo(ids: ids)
    }

    /// The same line as for notes: "Moved to Recently Deleted · Undo".
    static func offerUndo(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        ToastManager.shared.show(
            ids.count == 1 ? "Moved to Recently Deleted" : "\(ids.count) tasks moved to Recently Deleted",
            systemImage: "trash",
            actionLabel: "Undo"
        ) {
            for id in ids { TaskList.shared.restore(id: id) }
        }
    }

    private func addToCalendar(_ meeting: MeetingItem) {
        guard !addingMeeting.contains(meeting.id) else { return }
        addingMeeting.insert(meeting.id)
        Task {
            let error = await tasks.addMeetingToCalendar(id: meeting.id)
            addingMeeting.remove(meeting.id)
            if let error {
                calendarError = error
            } else {
                ToastManager.shared.show("Added to Calendar", systemImage: "calendar.badge.checkmark")
            }
        }
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
                    Button("Delete task", role: .destructive) {
                        TaskList.shared.delete(id: task.id)
                        TasksView.offerUndo(ids: [task.id])
                        dismiss()
                    }
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

/// A spoken meeting waiting for a yes: what, when, what was said, and Add to
/// Calendar / Change / Not a Meeting. The Mac's card, in the phone's list.
/// A dashed border and the "Meeting to confirm" line mark it, not colour.
private struct MeetingCard: View {
    let meeting: MeetingItem
    let isAdding: Bool
    let add: () -> Void
    let change: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(meeting.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
            Text(MeetingCard.whenWords(meeting))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let raw = meeting.spokenText, !raw.isEmpty {
                Text("\u{201C}\(raw)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.secondary).frame(width: 2)
                    }
            }
            Button(action: add) {
                Text(isAdding ? "Adding…" : "Add to Calendar")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(meeting.start == nil || isAdding)
            HStack(spacing: 8) {
                Button(action: change) {
                    Text("Change").frame(maxWidth: .infinity, minHeight: 44)
                }
                Button(action: dismiss) {
                    Text("Not a Meeting").frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting to confirm: \(meeting.title), \(MeetingCard.whenWords(meeting))")
    }

    private var kicker: String {
        let from = meeting.source == .recorder ? "from the recorder, " : (meeting.source == .iPhone ? "from the iPhone, " : "")
        return "Meeting to confirm · " + from + meeting.createdAt.formatted(date: .omitted, time: .shortened)
    }

    static func whenWords(_ meeting: MeetingItem) -> String {
        guard let start = meeting.start else { return "No day or time was heard. Use Change to set one." }
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if meeting.allDay { return day + ", all day" }
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = (meeting.end ?? start.addingTimeInterval(3600)).formatted(date: .omitted, time: .shortened)
        return "\(day), \(from) to \(to)"
    }
}

/// Change a waiting meeting's title and time before it goes to the calendar.
private struct MeetingEditView: View {
    let meeting: MeetingItem
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool

    init(meeting: MeetingItem) {
        self.meeting = meeting
        let start = meeting.start ?? Date()
        _title = State(initialValue: meeting.title)
        _start = State(initialValue: start)
        _end = State(initialValue: meeting.end ?? start.addingTimeInterval(3600))
        _allDay = State(initialValue: meeting.allDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting") {
                    TextField("Meeting", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle("All day", isOn: $allDay)
                    DatePicker("Starts", selection: $start,
                               displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        .onChange(of: start) { _, newStart in
                            if end <= newStart { end = newStart.addingTimeInterval(3600) }
                        }
                    if !allDay {
                        DatePicker("Ends", selection: $end, in: start...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Change Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        let s = allDay ? calendar.startOfDay(for: start) : start
        // An all-day event ends on its own day.
        let e = allDay ? s : end
        TaskList.shared.changeMeeting(id: meeting.id, title: title, start: s, end: e, allDay: allDay)
        dismiss()
    }
}
