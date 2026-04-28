import AppKit
import SwiftUI

@MainActor
final class CiderFloatingPanelManager: NSObject, NSWindowDelegate {
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

    nonisolated static let surfaceUserInfoKey = "surface"

    private var panelsByKey: [String: CiderFloatingPanel] = [:]
    private var surfacesByPanel: [ObjectIdentifier: CiderFloatableSurface] = [:]
    private var dropZoneContext: CiderDropZoneContext?

    private(set) var bookkeeping = Bookkeeping()

    override init() {
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

    @discardableResult
    func float(_ surface: CiderFloatableSurface) -> CiderFloatingPanel {
        if case .dropZone = surface, dropZoneContext == nil {
            dropZoneContext = .manualTesting()
        }

        let key = surface.stableKey
        if let panel = panelsByKey[key] {
            _ = bookkeeping.register(surface)
            panel.showNearMouse()
            return panel
        }

        let panel = CiderFloatingPanel(
            surface: surface,
            contentSize: defaultContentSize(for: surface)
        )
        panel.delegate = self
        panel.contentView = contentView(for: surface)

        panelsByKey[key] = panel
        surfacesByPanel[ObjectIdentifier(panel)] = surface
        _ = bookkeeping.register(surface)
        panel.showNearMouse()
        return panel
    }

    func dock(_ surface: CiderFloatableSurface) {
        let key = surface.stableKey
        guard let panel = panelsByKey.removeValue(forKey: key) else {
            bookkeeping.unregister(surface)
            return
        }

        surfacesByPanel.removeValue(forKey: ObjectIdentifier(panel))
        bookkeeping.unregister(surface)
        if case .dropZone = surface {
            dropZoneContext = nil
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

    func showDropZone(context: CiderDropZoneContext = .manualTesting()) {
        dropZoneContext = context
        _ = float(.dropZone)
    }

    func closeDropZone() {
        dock(.dropZone)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? CiderFloatingPanel else { return }
        let panelID = ObjectIdentifier(panel)
        guard let surface = surfacesByPanel.removeValue(forKey: panelID) else { return }

        panelsByKey.removeValue(forKey: surface.stableKey)
        bookkeeping.unregister(surface)
        if case .dropZone = surface {
            dropZoneContext = nil
        }
    }

    private func defaultContentSize(for surface: CiderFloatableSurface) -> NSSize {
        switch surface {
        case .dropZone:
            NSSize(width: 340, height: 300)
        default:
            NSSize(width: 420, height: 520)
        }
    }

    private func contentView(for surface: CiderFloatableSurface) -> NSView {
        if case .dropZone = surface {
            let context = dropZoneContext ?? .manualTesting()
            dropZoneContext = context
            return NSHostingView(rootView: CiderDropZoneView(context: context))
        }

        return NSHostingView(
            rootView: CiderFloatingSurfaceView(surface: surface) { [weak self] in
                self?.dock(surface)
            }
        )
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
    }

    @objc private func handleFloatSurfaceNotification(_ notification: Notification) {
        guard let surface = notification.userInfo?[Self.surfaceUserInfoKey] as? CiderFloatableSurface else {
            return
        }

        // These surfaces already have specialized panel controllers with their
        // own sizing, shadows, hotkeys, and persistence. AppDelegate observes
        // the same notification and opens those existing panels.
        guard surface != .aiAssistant, surface != .clipboard else {
            return
        }

        float(surface)
    }

    @objc private func handleShowDropZoneNotification(_ notification: Notification) {
        if let context = notification.userInfo?["context"] as? CiderDropZoneContext {
            showDropZone(context: context)
        } else {
            showDropZone()
        }
    }
}
