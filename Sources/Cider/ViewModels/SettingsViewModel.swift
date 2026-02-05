import SwiftUI
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {
    // General settings
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }
    @Published var hotkeyEnabled: Bool = true
    @Published var hotkeyDoubleTapInterval: Double = 0.3

    // Appearance settings
    @Published var sidebarEnabled: Bool {
        didSet { saveConfig() }
    }
    @Published var sidebarEdge: SidebarEdge {
        didSet { saveConfig() }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { saveConfig() }
    }
    @Published var textSize: TextSize {
        didSet { saveConfig() }
    }
    @Published var paletteSize: PaletteSize {
        didSet { saveConfig() }
    }

    // Advanced settings
    @Published var autoHideApps: Bool {
        didSet { saveConfig() }
    }

    // Window cycling settings
    @Published var enableOptionTabCycling: Bool {
        didSet { saveConfig() }
    }
    @Published var optionTabCycleAllScreens: Bool {
        didSet { saveConfig() }
    }

    private var config: CiderConfig

    init() {
        // Load config
        self.config = CiderConfig.load()
        self.sidebarEnabled = config.sidebarEnabled
        self.sidebarEdge = config.sidebarEdge
        self.showMenuBarIcon = config.showMenuBarIcon
        self.textSize = config.textSize
        self.paletteSize = config.paletteSize
        self.autoHideApps = config.autoHideApps
        self.enableOptionTabCycling = config.enableOptionTabCycling
        self.optionTabCycleAllScreens = config.optionTabCycleAllScreens

        // Check current launch at login status
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    private func saveConfig() {
        config.sidebarEnabled = sidebarEnabled
        config.sidebarEdge = sidebarEdge
        config.showMenuBarIcon = showMenuBarIcon
        config.textSize = textSize
        config.paletteSize = paletteSize
        config.autoHideApps = autoHideApps
        config.enableOptionTabCycling = enableOptionTabCycling
        config.optionTabCycleAllScreens = optionTabCycleAllScreens
        config.save()

        // Post notification so AppDelegate can respond
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }

    func dismiss() {
        NotificationCenter.default.post(name: .dismissSettings, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let dismissSettings = Notification.Name("dismissSettings")
    static let ciderConfigChanged = Notification.Name("ciderConfigChanged")
}
