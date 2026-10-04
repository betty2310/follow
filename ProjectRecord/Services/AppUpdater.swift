import Foundation
import Observation
import Sparkle

/// In-app updates via Sparkle (docs/DECISIONS.md D28). The feed is `appcast.xml` on the latest GitHub Release,
/// written by the release workflow; Sparkle verifies each update with the EdDSA key in Info.plist.
///
/// Checks at launch and then every day (`SUScheduledCheckInterval`). An update found at launch is shown in
/// Sparkle's update window right away (Install / Skip This Version / Remind Me Later); one found later only
/// turns the sidebar version label into a bubble, so it never interrupts a session. Clicking the bubble opens the window.
@MainActor
@Observable
final class AppUpdater: NSObject {
    private(set) var status = UpdateStatus()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    /// `start: false` gives an inert updater (SwiftUI previews, the environment default).
    init(start: Bool = true) {
        super.init()
        // Unit tests run inside the app (TEST_HOST): never check for updates there.
        guard start, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        // Sparkle skips its scheduled check on the very first launch; check now so every launch checks.
        controller?.updater.checkForUpdatesInBackground()
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { access(keyPath: \.automaticallyChecks); return controller?.updater.automaticallyChecksForUpdates ?? false }
        set { withMutation(keyPath: \.automaticallyChecks) { controller?.updater.automaticallyChecksForUpdates = newValue } }
    }

    /// Shows the update window (or "You're up to date").
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status.found(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status.notFound()
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip { status.skipped() }
    }

    #if DEBUG
    /// Debug builds share the bundle id with the installed app; only check when asked (menu or bubble).
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updatesInBackground { throw CocoaError(.userCancelled) }
    }
    #endif
}

extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Show the window only when Sparkle would bring it into focus (right after launch); otherwise just the bubble.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }
}

/// What the sidebar's version label shows. Pure, so the rules are testable without Sparkle.
struct UpdateStatus: Equatable {
    /// Display version of a newer release, or nil when up to date (or the user skipped it).
    private(set) var availableVersion: String?

    mutating func found(_ version: String) { availableVersion = version }
    mutating func notFound() { availableVersion = nil }
    /// "Skip This Version": the user doesn't care, drop the bubble. "Remind Me Later" keeps it.
    mutating func skipped() { availableVersion = nil }

    /// "v1.2.0" from Info.plist (`CFBundleShortVersionString`, set from the release tag).
    static func currentVersion(_ bundle: Bundle = .main) -> String {
        "v" + (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
    }
}
