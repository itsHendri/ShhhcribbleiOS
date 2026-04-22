import ActivityKit
import Foundation

public struct ShhcribbleActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: Status
        public var snippet: String

        public enum Status: String, Codable, Hashable, Sendable {
            case recording
            case stopping
        }

        public init(status: Status, snippet: String) {
            self.status = status
            self.snippet = snippet
        }
    }

    public var sessionId: String
    public var startedAt: Date

    public init(sessionId: String = UUID().uuidString, startedAt: Date = Date()) {
        self.sessionId = sessionId
        self.startedAt = startedAt
    }
}
