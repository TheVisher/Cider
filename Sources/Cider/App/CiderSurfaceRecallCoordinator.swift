import Foundation

enum CiderSurfaceActivationAction: Equatable {
    case openMainWindow
    case show(CiderFloatableSurface)
    case hide(CiderFloatableSurface)
}

struct CiderSurfaceRecallCoordinator {
    private(set) var lastRecallableSurface: CiderFloatableSurface?

    static func isRecallable(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo, .vaultFile, .aiAssistant, .journalIntelligence, .kanbanTestingGuide:
            true
        case .clipboard, .dropZone:
            false
        }
    }

    mutating func record(_ surface: CiderFloatableSurface) {
        guard Self.isRecallable(surface) else { return }
        lastRecallableSurface = surface
    }

    mutating func recordClosed(_ surface: CiderFloatableSurface) {
        guard Self.isRecallable(surface) else { return }
        lastRecallableSurface = surface
    }

    func activationAction(isVisible: (CiderFloatableSurface) -> Bool) -> CiderSurfaceActivationAction {
        guard let surface = lastRecallableSurface else {
            return .openMainWindow
        }

        return isVisible(surface) ? .hide(surface) : .show(surface)
    }
}
