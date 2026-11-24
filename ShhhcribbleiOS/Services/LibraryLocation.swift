import Foundation

// Compiled into the app and the widget extension (see project.yml), so both
// agree on where the library is and how a due time reads.

/// Where the shared library lives on the phone.
///
/// The database sits in the App Group container so the widget (and later the
/// keyboard) can open the same file. SQLite keeps three files side by side
/// while it is open; they share this folder.
enum LibraryLocation {
    static let appGroup = "group.com.shhhcribble"

    static func databaseURL() -> URL {
        // Tests are hosted by the app. They must never open the real library.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("shhhcribble-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("library.sqlite")
        }
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Library/Shhhcribble", isDirectory: true)
        // Readable after the first unlock since boot, so the widget can show
        // tasks on a locked phone. New files in the folder inherit this.
        try? fm.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return dir.appendingPathComponent("library.sqlite")
    }
}

/// How a due time reads in a row and in a toast. Words, never colour.
enum DueLabel {
    static func text(for due: Date, allDay: Bool, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(due, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(due, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: due)).day ?? 0
            let format = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            day = (1..<7).contains(days)
                ? due.formatted(format.weekday(.abbreviated))
                : due.formatted(format.day().month(.abbreviated))
        }
        guard !allDay else { return day }
        let time = due.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(day) \(time)"
    }
}

#if canImport(SwiftUI)
import SwiftUI
import UIKit
import ShhhcribbleCore

extension Color {
    /// A dynamic colour from one of the core's shared `Look` values: its
    /// light value in light mode, its dark value in dark mode. Compiled into
    /// the app and the widget.
    init(look: LookColor) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? look.dark : look.light
            let c = LookColor.components(hex)
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
    }
}
#endif
