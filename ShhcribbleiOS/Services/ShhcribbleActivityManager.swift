import ActivityKit
import Foundation
import ShhcribbleShared

@MainActor
final class ShhcribbleActivityManager {
    static let shared = ShhcribbleActivityManager()
    private var activity: Activity<ShhcribbleActivityAttributes>?

    private init() {}

    var isRunning: Bool { activity != nil }

    @discardableResult
    func start() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[Shhcribble] Live Activities disabled in system settings")
            return false
        }
        if activity != nil { return true }
        let attrs = ShhcribbleActivityAttributes()
        let state = ShhcribbleActivityAttributes.ContentState(status: .recording, snippet: "")
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            print("[Shhcribble] Live Activity start failed: \(error)")
            return false
        }
    }

    func update(snippet: String) {
        guard let activity else { return }
        let state = ShhcribbleActivityAttributes.ContentState(status: .recording, snippet: snippet)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        let state = ShhcribbleActivityAttributes.ContentState(status: .stopping, snippet: "")
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
