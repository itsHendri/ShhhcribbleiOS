import EventKit
import Foundation
import ShhhcribbleCore

/// Writes a confirmed spoken meeting to the default calendar. Only ever
/// called from Add to Calendar on a meeting's card in Tasks: nothing is
/// written, and nobody invited, before that tap. Asks for write-only access,
/// so the app never reads the calendar. The same event as the Mac's
/// `CalendarWriter`.
@MainActor
enum CalendarWriter {
    private static let eventStore = EKEventStore()

    /// Nil on success, else words to show.
    static func add(_ meeting: MeetingItem) async -> String? {
        guard let start = meeting.start else {
            return "This meeting has no day or time yet. Use Change to set one."
        }
        do {
            guard try await eventStore.requestWriteOnlyAccessToEvents() else {
                return "Shhhcribble is not allowed to add to your calendar. Turn it on in Settings, Apps, Shhhcribble, Calendars."
            }
        } catch {
            return "Calendar access could not be asked for: \(error.localizedDescription)"
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            return "There is no default calendar to add it to. Choose one in Settings, Apps, Calendar."
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = Note.preview(meeting.title)
        event.isAllDay = meeting.allDay
        event.startDate = start
        // An all-day event ends on its start day; an end at the next midnight
        // shows as two days.
        event.endDate = meeting.allDay ? start : (meeting.end ?? start.addingTimeInterval(SpokenIntent.defaultMeetingLength))
        if let raw = meeting.spokenText, !raw.isEmpty { event.notes = "Said: \u{201C}\(raw)\u{201D}" }
        do {
            try eventStore.save(event, span: .thisEvent)
            return nil
        } catch {
            return "The calendar did not accept it: \(error.localizedDescription)"
        }
    }
}
