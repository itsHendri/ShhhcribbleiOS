import ActivityKit
import Foundation
import ShhhcribbleShared

@MainActor
final class ShhhcribbleActivityManager {
    static let shared = ShhhcribbleActivityManager()
    private var activity: Activity<ShhhcribbleActivityAttributes>?
    private var startedAt: Date = Date()

    // Throttle Live Activity updates. Apple recommends a maximum of a few
    // updates per second; pushing every transcript partial (which can fire
    // tens of times per second under streaming ASR) would burn the budget
    // and cause the system to drop or stall later updates. ~250 ms feels
    // smooth in tandem with the snippet's `.contentTransition(.opacity)`.
    private var lastSnippetPushAt: Date?
    private var pendingSnippet: String?
    private var pendingTask: Task<Void, Never>?
    private let snippetThrottle: TimeInterval = 0.25

    private init() {}

    var isRunning: Bool { activity != nil }

    @discardableResult
    func start() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[Shhhcribble] Live Activities disabled in system settings")
            return false
        }
        if activity != nil { return true }
        startedAt = Date()
        let attrs = ShhhcribbleActivityAttributes(startedAt: startedAt)
        let state = ShhhcribbleActivityAttributes.ContentState(
            status: .recording,
            snippet: "",
            startedAt: startedAt
        )
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
        guard activity != nil else { return }
        pendingSnippet = snippet

        let now = Date()
        let elapsed = lastSnippetPushAt.map { now.timeIntervalSince($0) } ?? .infinity
        if elapsed >= snippetThrottle {
            pushPendingSnippet()
        } else if pendingTask == nil {
            // Schedule a single trailing push so the very last character a
            // user speaks always lands in the Live Activity even if it comes
            // inside the throttle window.
            let delay = snippetThrottle - elapsed
            pendingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run { self?.pushPendingSnippet() }
            }
        }
    }

    private func pushPendingSnippet() {
        pendingTask?.cancel()
        pendingTask = nil
        guard let activity, let snippet = pendingSnippet else { return }
        pendingSnippet = nil
        lastSnippetPushAt = Date()
        let state = ShhhcribbleActivityAttributes.ContentState(
            status: .recording,
            snippet: snippet,
            startedAt: startedAt
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingSnippet = nil
        lastSnippetPushAt = nil
        guard let activity else { return }
        let state = ShhhcribbleActivityAttributes.ContentState(
            status: .stopping,
            snippet: "",
            startedAt: startedAt
        )
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
