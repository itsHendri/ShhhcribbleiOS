import AppIntents
import ShhhcribbleCore
import SwiftUI
import WidgetKit

// The home-screen page Hendri picked (docs/design/tasks-widget.md, pick B):
// a large widget with the open tasks and a medium one with the latest note
// and a record button. Everything you tap sits in the right-hand column.
//
// Both read the shared library through the core's `LibraryReader`, never the
// full store: a widget has little memory and must not change the schema.

// MARK: - Look

enum WidgetLook {
    /// The violet of the app icon. Light and dark values keep text on it,
    /// and it on the card, above 4.5:1.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.663, green: 0.616, blue: 1.0, alpha: 1)   // #A99DFF
            : UIColor(red: 0.333, green: 0.282, blue: 0.878, alpha: 1) // #5548E0
    })
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.071, green: 0.047, blue: 0.227, alpha: 1) // #120C3A
            : UIColor(red: 0.984, green: 0.953, blue: 0.918, alpha: 1) // #FBF3EA
    })
    static let overdueFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.706, blue: 0.659, alpha: 1)   // #FFB4A8
            : UIColor(red: 0.541, green: 0.122, blue: 0.067, alpha: 1) // #8A1F11
    })
    static let overdueText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.231, green: 0.039, blue: 0.016, alpha: 1) // #3B0A04
            : .white
    })
}

/// The scribble from the app icon, redrawn as a line.
struct ScribbleMark: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (7, 7.2), (16.5, 4.6), (8, 10.4), (17.6, 9), (7.4, 14.6), (17, 14), (10.4, 19.4),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 / 24 * rect.width,
                            y: rect.minY + point.1 / 24 * rect.height)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

// MARK: - Data

/// One open task as the widget shows it.
struct WidgetTask: Identifiable, Hashable {
    let id: UUID
    let text: String
    /// "Today 15:00", "Fri", or nil when the task has no time.
    let due: String?
    let overdue: Bool
}

struct TasksEntry: TimelineEntry {
    let date: Date
    /// False before the app has run once on this build.
    let usable: Bool
    let openCount: Int
    let tasks: [WidgetTask]

    static let sample = TasksEntry(
        date: Date(), usable: true, openCount: 8,
        tasks: [
            WidgetTask(id: UUID(), text: "Send the invoice", due: nil, overdue: true),
            WidgetTask(id: UUID(), text: "Call the dentist", due: "Today 11:30", overdue: false),
            WidgetTask(id: UUID(), text: "Reply to Ana", due: "Today 15:00", overdue: false),
            WidgetTask(id: UUID(), text: "Order filament", due: "Tomorrow", overdue: false),
            WidgetTask(id: UUID(), text: "Book the car inspection", due: "Fri 09:00", overdue: false),
            WidgetTask(id: UUID(), text: "Buy milk", due: nil, overdue: false),
        ]
    )
}

struct NoteEntry: TimelineEntry {
    let date: Date
    let usable: Bool
    /// "10:52 · 0:34", or nil when there is no note.
    let caption: String?
    let text: String?

    static let sample = NoteEntry(
        date: Date(), usable: true, caption: "10:52 · 0:34",
        text: "The hinge needs two more millimetres of clearance or the lid binds when the case is closed."
    )
}

enum WidgetData {
    static let rows = 6

    static func reader() -> LibraryReader {
        LibraryReader(path: LibraryLocation.databaseURL().path)
    }

    static func tasks(now: Date = Date(), calendar: Calendar = .current) -> TasksEntry {
        let reader = reader()
        guard reader.isUsable else {
            return TasksEntry(date: now, usable: false, openCount: 0, tasks: [])
        }
        let startOfToday = calendar.startOfDay(for: now)
        // The same order as the Tasks tab and the Mac (the core's
        // TaskSections: overdue, today, upcoming by time, then undated newest
        // first). The reader's own order puts undated oldest first, so read
        // a generous batch and sort it here.
        let sections = TaskSections.sections(of: reader.openTasks(limit: 200), now: now, calendar: calendar)
        let ordered = sections.overdue + sections.today + sections.upcoming + sections.noDate
        let tasks = ordered.prefix(rows).map { note in
            let overdue = note.dueAt.map { $0 < startOfToday } ?? false
            return WidgetTask(
                id: note.id,
                text: note.text,
                due: overdue ? nil : note.dueAt.map {
                    DueLabel.text(for: $0, allDay: note.dueAllDay, now: now, calendar: calendar)
                },
                overdue: overdue
            )
        }
        return TasksEntry(date: now, usable: true, openCount: reader.openTaskCount(), tasks: tasks)
    }

    static func note(now: Date = Date()) -> NoteEntry {
        let reader = reader()
        guard reader.isUsable else {
            return NoteEntry(date: now, usable: false, caption: nil, text: nil)
        }
        guard let note = reader.recentNotes(limit: 1).first else {
            return NoteEntry(date: now, usable: true, caption: nil, text: nil)
        }
        var caption = Calendar.current.isDateInToday(note.createdAt)
            ? note.createdAt.formatted(date: .omitted, time: .shortened)
            : note.createdAt.formatted(.dateTime.day().month(.abbreviated))
        if let seconds = note.durationSec, seconds >= 1 {
            let total = Int(seconds.rounded())
            caption += " · \(total / 60):" + String(format: "%02d", total % 60)
        }
        return NoteEntry(date: now, usable: true, caption: caption, text: String(note.text.prefix(240)))
    }

    /// Entries are rebuilt when the app or a tick changes the library. This
    /// is only the fallback, and it moves "Today" to "Overdue" at midnight.
    static func nextRefresh(after now: Date) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return min(midnight.addingTimeInterval(5), now.addingTimeInterval(30 * 60))
    }
}

// MARK: - Ticking a task

/// Marks a task done from the widget. Runs in the widget's process, writes
/// through `LibraryReader`, which signals the app so it drops the alert.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Task Done"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(id: UUID) { taskID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            _ = WidgetData.reader().setTaskDone(id: id, done: true)
        }
        return .result()
    }
}

// MARK: - Tasks widget

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(context.isPreview ? .sample : WidgetData.tasks())
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<TasksEntry>) -> Void) {
        let now = Date()
        completion(WidgetKit.Timeline(entries: [WidgetData.tasks(now: now)],
                            policy: .after(WidgetData.nextRefresh(after: now))))
    }
}

struct TasksWidgetView: View {
    let entry: TasksEntry

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !entry.usable {
                message("Open Shhhcribble", "Open the app once and your tasks show here.")
            } else if entry.tasks.isEmpty {
                message("Nothing to do", "Start a recording with \u{201C}Reminder\u{201D} or \u{201C}To-do\u{201D} and it lands here.")
            } else {
                ForEach(entry.tasks) { row($0) }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "shhhcribble://tasks"))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.openCount)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("To do")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetLook.accent)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.openCount) to do")
            Spacer()
            Link(destination: URL(string: "shhhcribble://tasks")!) {
                ZStack {
                    Circle().fill(WidgetLook.accent).widgetAccentable()
                    ScribbleMark()
                        .stroke(WidgetLook.onAccent,
                                style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 31, height: 31)
                }
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Open Shhhcribble")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func row(_ task: WidgetTask) -> some View {
        HStack(spacing: 8) {
            Text(task.text)
                .font(.system(size: 15))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if task.overdue {
                Label("Overdue", systemImage: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(WidgetLook.overdueText)
                    .background(WidgetLook.overdueFill, in: RoundedRectangle(cornerRadius: 4))
            } else if let due = task.due {
                Text(due)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(intent: CompleteTaskIntent(id: task.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done: \(task.text)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 2)
        .frame(height: 44)
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TasksWidget: Widget {
    static let kind = "com.shhhcribble.ios.tasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("To do")
        .description("Your open tasks and reminders. Tick them off here.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Capture widget

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        completion(context.isPreview ? .sample : WidgetData.note())
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<NoteEntry>) -> Void) {
        let now = Date()
        completion(WidgetKit.Timeline(entries: [WidgetData.note(now: now)],
                            policy: .after(WidgetData.nextRefresh(after: now))))
    }
}

struct CaptureWidgetView: View {
    let entry: NoteEntry

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                if let text = entry.text {
                    Text("Latest note" + (entry.caption.map { " · " + $0 } ?? ""))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(size: 14))
                        .lineLimit(4)
                } else {
                    Text(entry.usable ? "No notes yet" : "Open Shhhcribble")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.usable
                         ? "Tap the microphone and talk. Your latest note shows here."
                         : "Open the app once and your latest note shows here.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link(destination: URL(string: "shhhcribble://widget-record")!) {
                ZStack {
                    Circle().fill(WidgetLook.accent).widgetAccentable()
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WidgetLook.onAccent)
                }
                .frame(width: 64, height: 64)
            }
            .accessibilityLabel("Start recording")
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .widgetURL(URL(string: "shhhcribble://notes"))
    }
}

struct CaptureWidget: Widget {
    static let kind = "com.shhhcribble.ios.capture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NoteProvider()) { entry in
            CaptureWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Record")
        .description("Start talking, and see your latest note.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview("Tasks", as: .systemLarge) {
    TasksWidget()
} timeline: {
    TasksEntry.sample
    TasksEntry(date: Date(), usable: true, openCount: 0, tasks: [])
}

#Preview("Capture", as: .systemMedium) {
    CaptureWidget()
} timeline: {
    NoteEntry.sample
    NoteEntry(date: Date(), usable: true, caption: nil, text: nil)
}
