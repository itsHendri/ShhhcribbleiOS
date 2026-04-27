import Foundation
import UIKit

actor ClipboardService {
    static let shared = ClipboardService()

    private var priorClipboard: String?
    private var priorChangeCount: Int = 0

    private init() {}

    func snapshot() {
        priorClipboard = UIPasteboard.general.string
        priorChangeCount = UIPasteboard.general.changeCount
    }

    func writeTranscript(_ text: String) {
        UIPasteboard.general.string = text
    }

    func restoreImmediately() {
        UIPasteboard.general.string = priorClipboard ?? ""
    }

    func scheduleRestore(after delay: TimeInterval) {
        // Capture the changeCount at schedule time (after our final write).
        // Live-partial writes during the recording bumped the counter many
        // times, so we can't compare to the original snapshot count. What we
        // want is: only restore if NOTHING ELSE writes during the delay
        // window — so the user's manual copy mid-window survives.
        let countAtScheduleTime = UIPasteboard.general.changeCount
        let saved = priorClipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard UIPasteboard.general.changeCount == countAtScheduleTime else { return }
            UIPasteboard.general.string = saved ?? ""
        }
    }
}
