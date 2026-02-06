import Foundation

enum ActivationMode: String, Codable, CaseIterable {
    case doubleTap
    case singleTap

    var displayName: String {
        switch self {
        case .doubleTap: return "Double tap"
        case .singleTap: return "Single tap"
        }
    }
}

enum TextSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        rawValue.capitalized
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.18
        }
    }

    var bodySize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }

    var headlineSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
}

enum PaletteSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        rawValue.capitalized
    }

    var width: CGFloat {
        switch self {
        case .small: return 480
        case .medium: return 600
        case .large: return 760
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .small: return 320
        case .medium: return 400
        case .large: return 480
        }
    }

    var maxHeight: CGFloat {
        switch self {
        case .small: return 480
        case .medium: return 600
        case .large: return 720
        }
    }
}

struct CiderConfig: Codable {
    var autoHideApps: Bool  // Hide other apps when switching, like Stage Manager
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var paletteSize: PaletteSize
    var activationMode: ActivationMode
    var enableOptionTabCycling: Bool  // Enable Option+Tab window cycling
    var optionTabCycleAllScreens: Bool  // Cycle windows on all screens vs current only
    var rememberPaletteState: Bool  // Keep folders open between palette sessions

    static let storageKey = "CiderConfig"

    static var `default`: CiderConfig {
        CiderConfig(
            autoHideApps: false,
            showMenuBarIcon: true,
            textSize: .medium,
            paletteSize: .medium,
            activationMode: .doubleTap,
            enableOptionTabCycling: true,
            optionTabCycleAllScreens: true,
            rememberPaletteState: false
        )
    }

    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .default
        }

        // Try to decode, handling missing fields gracefully
        do {
            return try JSONDecoder().decode(CiderConfig.self, from: data)
        } catch {
            NSLog("[Cider] Config decode error: \(error). Resetting to defaults.")
            UserDefaults.standard.removeObject(forKey: storageKey)
            let defaults = CiderConfig.default
            defaults.save()
            return defaults
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
            UserDefaults.standard.synchronize() // Force immediate write
            NSLog("[Cider] Config saved: textSize=\(textSize), paletteSize=\(paletteSize)")
        }
    }

    // Custom decoding to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHideApps = try container.decodeIfPresent(Bool.self, forKey: .autoHideApps) ?? false
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        paletteSize = try container.decodeIfPresent(PaletteSize.self, forKey: .paletteSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        enableOptionTabCycling = try container.decodeIfPresent(Bool.self, forKey: .enableOptionTabCycling) ?? true
        optionTabCycleAllScreens = try container.decodeIfPresent(Bool.self, forKey: .optionTabCycleAllScreens) ?? true
        rememberPaletteState = try container.decodeIfPresent(Bool.self, forKey: .rememberPaletteState) ?? false
    }

    init(autoHideApps: Bool, showMenuBarIcon: Bool, textSize: TextSize, paletteSize: PaletteSize, activationMode: ActivationMode = .doubleTap, enableOptionTabCycling: Bool = true, optionTabCycleAllScreens: Bool = true, rememberPaletteState: Bool = false) {
        self.autoHideApps = autoHideApps
        self.showMenuBarIcon = showMenuBarIcon
        self.textSize = textSize
        self.paletteSize = paletteSize
        self.activationMode = activationMode
        self.enableOptionTabCycling = enableOptionTabCycling
        self.optionTabCycleAllScreens = optionTabCycleAllScreens
        self.rememberPaletteState = rememberPaletteState
    }
}
