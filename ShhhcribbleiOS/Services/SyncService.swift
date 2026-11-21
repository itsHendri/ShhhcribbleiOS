import Combine
import Foundation
import ShhhcribbleCore
import UIKit
import WidgetKit

/// The phone's side of iCloud sync: one `LibrarySync` from the shared core
/// over the app's store. Off by default; the user turns it on in Settings,
/// after one sheet that says plainly what then leaves the phone.
///
/// The same switch name as the Mac (`syncEnabled`), so both read the same way
/// in a support conversation. Settings themselves never sync.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    static let enabledKey = "syncEnabled"
    static let containerID = "iCloud.com.shhhcribble.library"

    /// Whether this build carries the iCloud entitlement. Creating a CloudKit
    /// container without it crashes, and iOS cannot read its own
    /// entitlements at run time, so the flag is set in Info.plist in the same
    /// change that adds the entitlement (project.yml).
    static var buildCanSync: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ShhhCloudKitEnabled") as? Bool ?? false
    }

    @Published private(set) var status: LibrarySync.Status = .off

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private lazy var sync: LibrarySync = {
        // The core will not touch CloudKit on iOS unless told the build
        // carries the entitlement.
        LibrarySync.appDeclaresCloudKit = Self.buildCanSync
        let sync = LibrarySync(store: SharedLibrary.store, containerID: Self.containerID)
        sync.onRemoteChange = { _ in
            // The store has already reloaded; the notes and tasks screens and
            // the alert plan follow it. The widgets read the file themselves.
            WidgetCenter.shared.reloadAllTimelines()
        }
        watch = sync.$status.sink { [weak self] in self?.status = $0 }
        return sync
    }()
    private var watch: AnyCancellable?

    private init() {}

    /// At launch: pick up where it left off if the user had it on.
    func start() {
        guard Self.buildCanSync, isEnabled else { return }
        Task { await sync.enable() }
    }

    func turnOn() async {
        guard Self.buildCanSync else {
            status = .unavailable("Sync is not available in this build of Shhhcribble.")
            return
        }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await sync.enable()
    }

    /// Stops syncing and forgets what synced. Nothing on this iPhone or in
    /// iCloud is deleted.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        guard Self.buildCanSync else { return }
        sync.disable()
    }

    /// When the app comes to the front, and when iCloud says something moved.
    func syncNow() {
        guard Self.buildCanSync, isEnabled else { return }
        Task { await sync.syncNow() }
    }

    /// iCloud's change pushes did not always reach the phone in testing
    /// (2026-11-21: a tick on the Mac waited until the app came to the
    /// front). While the app is open, fetch once a minute as well, so a
    /// change from the Mac never waits on a push that does not come.
    private var foregroundTimer: Timer?

    func appBecameActive() {
        syncNow()
        foregroundTimer?.invalidate()
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in SyncService.shared.syncNow() }
        }
    }

    func appLeftForeground() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }

    func confirmHeldDeletes() { sync.confirmHeldDeletes() }
    func restoreHeldRows() { Task { await sync.restoreHeldRows() } }

    /// The words on the switch's sheet and under it in Settings, so what was
    /// agreed to can be read again later.
    static let disclosure = """
    With sync on, the text of your notes, tasks and dictionary is stored in your iCloud account, in a private database only you can open, and kept the same on your iPhone and your Mac.

    Apple stores it. Apple can read it unless you have turned on Advanced Data Protection for iCloud, in which case only your devices can.

    Shhhcribble has no server. Nobody at Shhhcribble can see any of it, with sync on or off.

    Audio never syncs. Settings never sync. Turning sync off stops it and leaves the notes on this iPhone exactly as they are.
    """
}
