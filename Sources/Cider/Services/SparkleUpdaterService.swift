import Foundation
import Sparkle

/// Manages Sparkle auto-update lifecycle.
/// Singleton — accessed directly from Settings views.
@MainActor
final class SparkleUpdaterService: NSObject, ObservableObject {
    static let shared = SparkleUpdaterService()

    let updaterController: SPUStandardUpdaterController

    /// Last update check date (from Sparkle's defaults).
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    /// Whether automatic update checks are enabled.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    override init() {
        // startingUpdater: false — we start manually after config is loaded
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Starts the updater (call once at launch after config is ready).
    func start() {
        updaterController.startUpdater()
    }

    /// Triggers an explicit user-initiated update check.
    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
}
