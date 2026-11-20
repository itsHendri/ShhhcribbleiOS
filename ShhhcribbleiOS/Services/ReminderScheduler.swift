import Foundation
import ShhhcribbleCore
import UserNotifications
import os

private let reminderLog = Logger(subsystem: "com.shhhcribble.diag", category: "reminders")

/// Which alerts should be waiting, worked out from the tasks alone. Pure, so
/// it is tested without the notification centre.
enum ReminderPlan {
    struct Alert: Equatable {
        let id: UUID
        let fireAt: Date
        let body: String
    }

    /// iOS keeps at most 64 pending alerts per app. Leave a little room.
    static let limit = 60

    /// One alert per open task with a due time still ahead, soonest first.
    /// A task that is done, has no time, or is already past due gets none:
    /// iOS cannot fire in the past, and the task shows as overdue instead.
    static func alerts(for notes: [Note], now: Date) -> [Alert] {
        notes
            .filter { $0.isTask && !$0.done && ($0.dueAt ?? .distantPast) > now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(limit)
            .map { Alert(id: $0.id, fireAt: $0.dueAt ?? now, body: $0.text) }
    }

    /// What to change so the pending alerts match the wanted ones.
    /// `pending` maps an alert id to the fire time and text it was set with.
    static func changes(
        wanted: [Alert],
        pending: [UUID: Alert]
    ) -> (add: [Alert], remove: [UUID]) {
        let wantedIDs = Set(wanted.map(\.id))
        let remove = pending.keys.filter { !wantedIDs.contains($0) }
        let add = wanted.filter { pending[$0.id] != $0 }
        return (add, Array(remove))
    }
}

/// Keeps the phone's local alerts in step with the tasks. One alert per task,
/// with the task's id as the alert's id, so a change is always a replace.
///
/// Alerts are local to each device: the Mac sets its own from the same due
/// time. Nothing here is synced.
@MainActor
final class ReminderScheduler: NSObject {
    static let shared = ReminderScheduler()

    nonisolated static let category = "TASK_DUE"
    nonisolated static let doneAction = "TASK_DONE"
    nonisolated static let snoozeAction = "TASK_SNOOZE"
    private static let fireAtKey = "fireAt"

    private var center: UNUserNotificationCenter { .current() }
    private var askedThisLaunch = false

    /// Call once at launch, before the app finishes starting, so a tap on an
    /// alert that launched the app is delivered.
    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 10 minutes", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done, snooze], intentIdentifiers: [])
        ])
    }

    func reconcile(with notes: [Note], now: Date = Date()) {
        let wanted = ReminderPlan.alerts(for: notes, now: now)
        let doneIDs = notes.filter { $0.isTask && $0.done }.map(\.id.uuidString)
        Task { await apply(wanted: wanted, clearDelivered: doneIDs) }
    }

    private func apply(wanted: [ReminderPlan.Alert], clearDelivered: [String]) async {
        if !wanted.isEmpty { await askIfNeeded() }

        var pending: [UUID: ReminderPlan.Alert] = [:]
        for request in await center.pendingNotificationRequests()
        where request.content.categoryIdentifier == Self.category {
            guard let id = UUID(uuidString: request.identifier),
                  let stamp = request.content.userInfo[Self.fireAtKey] as? Double else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                continue
            }
            pending[id] = .init(id: id, fireAt: Date(timeIntervalSince1970: stamp), body: request.content.body)
        }

        let (add, remove) = ReminderPlan.changes(wanted: wanted, pending: pending)
        if !remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: remove.map(\.uuidString))
        }
        // A task ticked on the phone should not leave its alert on the lock screen.
        if !clearDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: clearDelivered)
        }
        for alert in add {
            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = alert.body
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.interruptionLevel = .timeSensitive
            content.userInfo = [Self.fireAtKey: alert.fireAt.timeIntervalSince1970]
            let parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: alert.fireAt)
            let request = UNNotificationRequest(
                identifier: alert.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                reminderLog.error("could not set alert: \(error.localizedDescription, privacy: .public)")
            }
        }
        if !add.isEmpty || !remove.isEmpty {
            reminderLog.notice("alerts: set \(add.count, privacy: .public), removed \(remove.count, privacy: .public), wanted \(wanted.count, privacy: .public)")
        }
    }

    /// Asks for permission the first time a task has a due time, not at
    /// first launch: the question makes sense only then.
    private func askIfNeeded() async {
        guard !askedThisLaunch else { return }
        askedThisLaunch = true
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Whether alerts can show. The Tasks screen says so in words when not.
    func alertsAllowed() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .notDetermined
    }
}

extension ReminderScheduler: UNUserNotificationCenterDelegate {
    // The completion-handler forms, on purpose. With the `async` forms the
    // system's completion runs off the main thread, and UIKit then aborts
    // the app the moment an alert's button is tapped (seen 2026-11-20).

    /// Show the alert even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let id = content.categoryIdentifier == Self.category
            ? UUID(uuidString: response.notification.request.identifier) : nil
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if let id {
                switch action {
                case Self.doneAction:
                    TaskList.shared.complete(id: id)
                case Self.snoozeAction:
                    TaskList.shared.snooze(id: id)
                case UNNotificationDefaultActionIdentifier:
                    AppRouter.shared.tab = .tasks
                default:
                    break
                }
            }
            completionHandler()
        }
    }
}
