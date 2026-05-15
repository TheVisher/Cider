import AppKit
import SwiftUI

@MainActor
final class CiderFloatingPanelManager: NSObject, NSWindowDelegate {
    private static let dropZoneAutoDismissTickSeconds: TimeInterval = 1 / 60
    private static let dropZoneAutoDismissDuration: CGFloat = 6
    private static let dropZoneAutoDismissStep = CGFloat(dropZoneAutoDismissTickSeconds) / dropZoneAutoDismissDuration

    enum RegistrationResult: Equatable {
        case created
        case reused
    }

    struct Bookkeeping {
        private var activeKeys: Set<String> = []

        var activeCount: Int { activeKeys.count }

        mutating func register(_ surface: CiderFloatableSurface) -> RegistrationResult {
            let inserted = activeKeys.insert(surface.stableKey).inserted
            return inserted ? .created : .reused
        }

        mutating func unregister(_ surface: CiderFloatableSurface) {
            activeKeys.remove(surface.stableKey)
        }

        func contains(_ surface: CiderFloatableSurface) -> Bool {
            activeKeys.contains(surface.stableKey)
        }
    }

    enum SurfaceNotificationPayload {
        static func surface(from notification: Notification) -> CiderFloatableSurface? {
            if let surface = notification.object as? CiderFloatableSurface {
                return surface
            }

            if let surface = notification.userInfo?[surfaceUserInfoKey] as? CiderFloatableSurface {
                return surface
            }

            if let surface = notification.userInfo?["ciderSurface"] as? CiderFloatableSurface {
                return surface
            }

            if let surface = notification.userInfo?["floatableSurface"] as? CiderFloatableSurface {
                return surface
            }

            return nil
        }
    }

    nonisolated static let surfaceUserInfoKey = "surface"

    private var panelsByKey: [String: CiderFloatingPanel] = [:]
    private var surfacesByPanel: [ObjectIdentifier: CiderFloatableSurface] = [:]
    private var dropZoneContext: CiderDropZoneContext?
    private var dropZoneAutoDismissTimer: Timer?
    private let positionStore: CiderPanelPositionStore

    private(set) var bookkeeping = Bookkeeping()
    private(set) var recallCoordinator = CiderSurfaceRecallCoordinator()

    init(positionStore: CiderPanelPositionStore = .shared) {
        self.positionStore = positionStore
        super.init()
        installNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var activeSurfaceCount: Int { bookkeeping.activeCount }

    func contains(_ surface: CiderFloatableSurface) -> Bool {
        bookkeeping.contains(surface)
    }

    func recordRecallCandidate(_ surface: CiderFloatableSurface) {
        recallCoordinator.record(surface)
    }

    func recordClosedRecallCandidate(_ surface: CiderFloatableSurface) {
        recallCoordinator.recordClosed(surface)
    }

    func isVisible(_ surface: CiderFloatableSurface) -> Bool {
        panelsByKey[surface.stableKey]?.isVisible == true
    }

    func performSmartRecall(fallbackToMainWindow: () -> Void) {
        switch recallCoordinator.activationAction(isVisible: isVisible) {
        case .openMainWindow:
            fallbackToMainWindow()
        case .show(let surface):
            guard canRestore(surface) else {
                fallbackToMainWindow()
                return
            }
            float(surface)
        case .hide(let surface):
            dock(surface)
        }
    }

    @discardableResult
    func float(_ surface: CiderFloatableSurface) -> CiderFloatingPanel {
        if case .dropZone = surface, dropZoneContext == nil {
            dropZoneContext = .manualTesting()
        }

        let key = surface.stableKey
        if let panel = panelsByKey[key] {
            _ = bookkeeping.register(surface)
            recordRecallCandidate(surface)
            if case .dropZone = surface, dropZoneContext?.isPinned == true {
                panel.orderFrontRegardless()
            } else {
                show(panel, for: surface)
            }
            return panel
        }

        let panel = CiderFloatingPanel(
            surface: surface,
            contentSize: CiderFloatingPanelLayout.defaultContentSize(for: surface)
        )
        panel.delegate = self
        panel.contentView = contentView(for: surface)

        panelsByKey[key] = panel
        surfacesByPanel[ObjectIdentifier(panel)] = surface
        _ = bookkeeping.register(surface)
        recordRecallCandidate(surface)
        show(panel, for: surface)
        return panel
    }

    func dock(_ surface: CiderFloatableSurface) {
        let key = surface.stableKey
        guard let panel = panelsByKey.removeValue(forKey: key) else {
            recordClosedRecallCandidate(surface)
            bookkeeping.unregister(surface)
            return
        }

        surfacesByPanel.removeValue(forKey: ObjectIdentifier(panel))
        persistFrameIfNeeded(for: surface, panel: panel)
        recordClosedRecallCandidate(surface)
        bookkeeping.unregister(surface)
        if case .dropZone = surface {
            stopDropZoneAutoDismissTimer()
        }

        panel.orderOut(nil)
        NotificationCenter.default.post(
            name: .dockCiderSurface,
            object: self,
            userInfo: [Self.surfaceUserInfoKey: surface]
        )
    }

    func closeAll() {
        let surfaces = Array(panelsByKey.values.map(\.surface))
        surfaces.forEach(dock)
    }

    func showDropZone(context providedContext: CiderDropZoneContext? = nil) {
        let context = providedContext ?? dropZoneContext ?? .manualTesting()
        dropZoneContext = context
        context.resetDismissProgress()
        let panel = float(.dropZone)
        startDropZoneAutoDismissTimer(context: context, panel: panel)
    }

    func closeDropZone() {
        dock(.dropZone)
    }

    func dismissDropZoneIfUnpinned() {
        guard dropZoneContext?.isPinned != true else { return }
        closeDropZone()
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? CiderFloatingPanel else { return }
        let panelID = ObjectIdentifier(panel)
        guard let surface = surfacesByPanel.removeValue(forKey: panelID) else { return }

        panelsByKey.removeValue(forKey: surface.stableKey)
        persistFrameIfNeeded(for: surface, panel: panel)
        recordClosedRecallCandidate(surface)
        bookkeeping.unregister(surface)
        if case .dropZone = surface {
            stopDropZoneAutoDismissTimer()
        }
    }

    private func contentView(for surface: CiderFloatableSurface) -> NSView {
        if case .dropZone = surface {
            let context = dropZoneContext ?? .manualTesting()
            dropZoneContext = context
            return NSHostingView(
                rootView: CiderDropZoneView(context: context)
            )
        }

        return NSHostingView(
            rootView: CiderFloatingSurfaceView(surface: surface) { [weak self] in
                self?.dock(surface)
            }
        )
    }

    private func canRestore(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note(let id):
            NotesStorage.shared.notes.contains { $0.id == id }
        case .bookmark(let id), .bookmarkMetadata(let id):
            VaultBookmarkService.shared.bookmarks.contains { $0.id == id }
        case .contact(let id):
            ContactStorage.shared.contacts.contains { $0.id == id }
        case .dateCard(let id):
            DateCardStorage.shared.dateCards.contains { $0.id == id }
        case .todo(let id):
            TodoCardStorage.shared.todoCards.contains { $0.id == id }
        case .vaultFile(let id):
            VaultFileService.shared.file(for: id) != nil
        case .clipboard, .dropZone:
            false
        case .aiAssistant:
            true
        case .kanbanTestingGuide(let payload):
            KanbanStorage.shared.findCard(id: payload.cardID)?.board.id == payload.boardID
        }
    }

    private func show(_ panel: CiderFloatingPanel, for surface: CiderFloatableSurface) {
        guard surface != .dropZone else {
            panel.showNearMouse()
            return
        }

        let config = CiderConfig.load()
        guard config.rememberPanelPosition else {
            panel.showNearMouse()
            return
        }

        let key = surface.stableKey
        if config.openOnMouseScreen,
           let targetScreen = CiderFloatingPanelPlacement.mouseScreen() {
            if let savedFrame = positionStore.frame(forFloatingSurfaceKey: key) {
                let sourceScreen = CiderFloatingPanelPlacement.preferredScreen(for: savedFrame)
                let preferredFrame = CiderFloatingPanelPlacement.translatedFrame(
                    savedFrame,
                    from: sourceScreen?.visibleFrame ?? targetScreen.visibleFrame,
                    to: targetScreen.visibleFrame
                )
                panel.show(frame: CiderFloatingPanelLayout.restoredFrame(preferredFrame, for: surface))
                return
            }

            panel.showNearMouse()
            return
        }

        if let savedFrame = positionStore.frame(forFloatingSurfaceKey: key) {
            panel.show(frame: CiderFloatingPanelLayout.restoredFrame(savedFrame, for: surface))
        } else {
            panel.showNearMouse()
        }
    }

    private func persistFrameIfNeeded(for surface: CiderFloatableSurface, panel: CiderFloatingPanel) {
        guard CiderSurfaceRecallCoordinator.isRecallable(surface) else { return }
        positionStore.setFrame(panel.frame, forFloatingSurfaceKey: surface.stableKey)
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(handleFloatSurfaceNotification(_:)),
            name: .floatCiderSurface,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleShowDropZoneNotification(_:)),
            name: .showCiderDropZone,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleDockSurfaceNotification(_:)),
            name: .dockCiderSurface,
            object: nil
        )
    }

    @objc private func handleFloatSurfaceNotification(_ notification: Notification) {
        guard let surface = SurfaceNotificationPayload.surface(from: notification) else {
            return
        }

        // Clipboard still has its own specialized panel controller.
        guard surface != .clipboard else {
            return
        }

        float(surface)
    }

    @objc private func handleDockSurfaceNotification(_ notification: Notification) {
        guard let surface = SurfaceNotificationPayload.surface(from: notification),
              contains(surface) else {
            return
        }

        dock(surface)
    }

    @objc private func handleShowDropZoneNotification(_ notification: Notification) {
        if let context = notification.userInfo?["context"] as? CiderDropZoneContext {
            showDropZone(context: context)
        } else {
            showDropZone()
        }
    }

    private func startDropZoneAutoDismissTimer(
        context: CiderDropZoneContext,
        panel: CiderFloatingPanel
    ) {
        stopDropZoneAutoDismissTimer()

        let timer = Timer(timeInterval: Self.dropZoneAutoDismissTickSeconds, repeats: true) { [weak self, weak context, weak panel] _ in
            Task { @MainActor in
                guard let self, let context, let panel else { return }
                self.tickDropZoneAutoDismiss(context: context, panel: panel)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dropZoneAutoDismissTimer = timer
    }

    private func stopDropZoneAutoDismissTimer() {
        dropZoneAutoDismissTimer?.invalidate()
        dropZoneAutoDismissTimer = nil
    }

    private func tickDropZoneAutoDismiss(
        context: CiderDropZoneContext,
        panel: CiderFloatingPanel
    ) {
        guard panelsByKey[CiderFloatableSurface.dropZone.stableKey] === panel,
              panel.isVisible else {
            stopDropZoneAutoDismissTimer()
            context.setHoverPaused(false)
            return
        }

        let mouseInsidePanel = NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
        if context.tickAutoDismiss(
            by: Self.dropZoneAutoDismissStep,
            isMouseInsideWindow: mouseInsidePanel
        ) {
            dismissDropZoneIfUnpinned()
        }
    }
}

enum CiderFloatingPanelLayout {
    static func defaultContentSize(for surface: CiderFloatableSurface) -> NSSize {
        switch surface {
        case .dropZone:
            NSSize(width: 340, height: 360)
        case .note:
            NSSize(width: 820, height: 620)
        case .aiAssistant:
            NSSize(width: AIAssistantPanelDesign.defaultWidth, height: AIAssistantPanelDesign.defaultHeight)
        case .kanbanTestingGuide:
            NSSize(width: 420, height: 560)
        case .contact, .dateCard, .todo, .vaultFile:
            NSSize(width: 760, height: 560)
        default:
            NSSize(width: 420, height: 520)
        }
    }

    static func restoredFrame(_ frame: NSRect, for surface: CiderFloatableSurface) -> NSRect {
        let defaultSize = defaultContentSize(for: surface)
        guard defaultSize.width > frame.width || defaultSize.height > frame.height else {
            return frame
        }

        return NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(frame.width, defaultSize.width),
            height: max(frame.height, defaultSize.height)
        )
    }
}
