import AppKit
import Foundation
import Sparkle

/// Manages Sparkle auto-update lifecycle.
/// Singleton — accessed directly from Settings views.
@MainActor
final class SparkleUpdaterService: NSObject, ObservableObject {
    static let shared = SparkleUpdaterService()

    let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate = SparkleUserDriverDelegate()
    private var temporarilyDemotedWindows: [(window: NSWindow, level: NSWindow.Level)] = []

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
            userDriverDelegate: userDriverDelegate
        )
        super.init()
        userDriverDelegate.service = self
    }

    /// Starts the updater (call once at launch after config is ready).
    func start() {
        updaterController.startUpdater()
    }

    /// Triggers an explicit user-initiated update check.
    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else { return }
        prepareForSparkleUserInterface()
        updaterController.checkForUpdates(nil)
    }

    func prepareForSparkleUserInterface() {
        NSApp.activate(ignoringOtherApps: true)

        let alreadyTracked = Set(temporarilyDemotedWindows.map { ObjectIdentifier($0.window) })
        let candidates = NSApp.windows.filter { window in
            guard window.isVisible,
                  window.level.rawValue >= NSWindow.Level.floating.rawValue,
                  alreadyTracked.contains(ObjectIdentifier(window)) == false else {
                return false
            }
            return window is CiderPanel
                || window is CiderShadowPanel
                || window is SettingsWindow
                || window is AIAssistantPanel
                || window is ClipboardPanel
                || window is BookmarkCaptureToastPanel
                || window is ScreenCaptureToastPanel
        }

        for window in candidates {
            temporarilyDemotedWindows.append((window, window.level))
            window.level = .normal
        }
    }

    func restoreWindowsAfterSparkleUserInterface() {
        let windowsToRestore = temporarilyDemotedWindows
        temporarilyDemotedWindows.removeAll()

        for entry in windowsToRestore {
            entry.window.level = entry.level
            if entry.window.isVisible {
                entry.window.orderFront(nil)
            }
        }
    }
}

private final class SparkleUserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var service: SparkleUpdaterService?

    @MainActor
    func standardUserDriverWillShowModalAlert() {
        service?.prepareForSparkleUserInterface()
    }

    @MainActor
    func standardUserDriverDidShowModalAlert() {
        service?.restoreWindowsAfterSparkleUserInterface()
    }

    @MainActor
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        service?.prepareForSparkleUserInterface()
    }

    @MainActor
    func standardUserDriverWillFinishUpdateSession() {
        service?.restoreWindowsAfterSparkleUserInterface()
    }
}
