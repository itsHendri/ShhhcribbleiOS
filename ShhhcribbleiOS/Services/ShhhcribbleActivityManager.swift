import ActivityKit
import Foundation
import ShhhcribbleShared

@MainActor
final class ShhhcribbleActivityManager {
    static let shared = ShhhcribbleActivityManager()
    private var activity: Activity<ShhhcribbleActivityAttributes>?

    private init() {}

    var isRunning: Bool { activity != nil }

    @discardableResult
    func start() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[Shhhcribble] Live Activities disabled in system settings")
            return false
        }
        if activity != nil { return true }
        let attrs = ShhhcribbleActivityAttributes()
        let state = ShhhcribbleActivityAttributes.ContentState(status: .recording, snippet: "")
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            print("[Shhhcribble] Live Activity start failed: \(error)")
            return false
        }
    }

    func update(snippet: String) {
        guard let activity else { return }
        let state = ShhhcribbleActivityAttributes.ContentState(status: .recording, snippet: snippet)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        let state = ShhhcribbleActivityAttributes.ContentState(status: .stopping, snippet: "")
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
