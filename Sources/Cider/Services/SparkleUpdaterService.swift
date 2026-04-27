import AppKit
import Combine
import Foundation
import Sparkle

/// Manages Sparkle auto-update lifecycle.
/// Singleton — accessed directly from Settings views.
@MainActor
final class SparkleUpdaterService: NSObject, ObservableObject {
    static let shared = SparkleUpdaterService()

    private enum DefaultsKey {
        static let showSidebarUpdateReminders = "cider.showSidebarUpdateReminders"
        static let dismissedSidebarUpdateIdentifier = "cider.dismissedSidebarUpdateIdentifier"
    }

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = SparkleUpdaterDelegate()
    private let userDriverDelegate = SparkleUserDriverDelegate()
    private let defaults: UserDefaults
    private var temporarilyDemotedWindows: [(window: NSWindow, level: NSWindow.Level)] = []

    @Published private(set) var availableUpdateIdentifier: String?
    @Published private(set) var availableUpdateDisplayVersion: String?
    @Published private var dismissedSidebarUpdateIdentifier: String?
    @Published var showSidebarUpdateReminders: Bool {
        didSet {
            defaults.set(showSidebarUpdateReminders, forKey: DefaultsKey.showSidebarUpdateReminders)
        }
    }

    /// Last update check date (from Sparkle's defaults).
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    /// Whether automatic update checks are enabled.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var shouldShowSidebarUpdateReminder: Bool {
        SparkleUpdateReminderState(
            availableUpdateIdentifier: availableUpdateIdentifier,
            sidebarRemindersEnabled: showSidebarUpdateReminders,
            dismissedUpdateIdentifier: dismissedSidebarUpdateIdentifier
        )
        .shouldShowSidebarReminder
    }

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        dismissedSidebarUpdateIdentifier = defaults.string(forKey: DefaultsKey.dismissedSidebarUpdateIdentifier)
        showSidebarUpdateReminders = defaults.object(forKey: DefaultsKey.showSidebarUpdateReminders) as? Bool ?? true

        // startingUpdater: false — we start manually after config is loaded
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        super.init()
        updaterDelegate.service = self
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

    func dismissCurrentSidebarUpdateReminder() {
        guard let availableUpdateIdentifier else { return }
        dismissedSidebarUpdateIdentifier = availableUpdateIdentifier
        defaults.set(availableUpdateIdentifier, forKey: DefaultsKey.dismissedSidebarUpdateIdentifier)
    }

    func markUpdateAvailable(identifier: String, displayVersion: String?) {
        availableUpdateIdentifier = identifier
        availableUpdateDisplayVersion = displayVersion
    }

    func clearAvailableUpdate() {
        availableUpdateIdentifier = nil
        availableUpdateDisplayVersion = nil
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

private final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var service: SparkleUpdaterService?

    @MainActor
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        service?.markUpdateAvailable(
            identifier: "\(item.displayVersionString)-\(item.versionString)",
            displayVersion: item.displayVersionString
        )
    }

    @MainActor
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        service?.clearAvailableUpdate()
    }

    @MainActor
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        service?.clearAvailableUpdate()
    }

    @MainActor
    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if choice == .install {
            service?.clearAvailableUpdate()
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
