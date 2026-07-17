import Foundation

enum AIAgentRuntimeSelection: String, CaseIterable, Sendable {
    case appleIntelligence
    case localModel
    case hermes

    static let productionSelectable: [AIAgentRuntimeSelection] = [
        .appleIntelligence,
        .localModel,
        .hermes,
    ]
}

struct AIAgentRuntimeSelectionStore {
    static let defaultsKey = "cider.aiRuntimeSelection"
    static let legacyCodexRawValue = "codexCLI"
    static let legacyCodexFallback: AIAgentRuntimeSelection = .appleIntelligence

    let defaults: UserDefaults

    func load(localModelEnabled: Bool) -> AIAgentRuntimeSelection {
        guard let raw = defaults.string(forKey: Self.defaultsKey) else {
            return localModelEnabled ? .localModel : .appleIntelligence
        }

        if raw == Self.legacyCodexRawValue {
            defaults.set(Self.legacyCodexFallback.rawValue, forKey: Self.defaultsKey)
            return Self.legacyCodexFallback
        }

        guard let selection = AIAgentRuntimeSelection(rawValue: raw) else {
            return localModelEnabled ? .localModel : .appleIntelligence
        }
        return selection
    }

    func persist(_ selection: AIAgentRuntimeSelection) {
        defaults.set(selection.rawValue, forKey: Self.defaultsKey)
    }
}

enum LegacyCodexRuntimePolicy {
    static let runtimeID = "process.codex-cli"
    static let unavailableReason = "Codex CLI is unavailable until Cider has a separately reviewed bounded runtime authority contract."

    static func isDisabled(runtimeID: String) -> Bool {
        runtimeID == Self.runtimeID
    }
}
