import AppKit
import SwiftUI

// MARK: - Panel Mode Type

enum PanelModeType: Sendable, Equatable {
    case item
    case tool
}

// MARK: - Panel Header Action

struct PanelHeaderAction: Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String
    let action: @MainActor @Sendable () -> Void
}

// MARK: - Panel Keyboard Shortcut

struct PanelKeyboardShortcut: Sendable {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: @MainActor @Sendable () -> Void
}

// MARK: - Panel Mode Protocol

@MainActor
protocol PanelMode: ObservableObject, Identifiable {
    var id: String { get }
    var title: String { get }
    var modeType: PanelModeType { get }
    var headerActions: [PanelHeaderAction] { get }

    associatedtype ContentBody: View
    @ViewBuilder var contentView: ContentBody { get }

    // Lifecycle
    func onActivate()
    func onDeactivate()

    // Eviction (items only)
    var canEvict: Bool { get }

    // Layout
    var preferredWidth: CGFloat? { get }

    // Drag support
    var dragProviders: [NSItemProvider]? { get }

    // Keyboard
    var keyboardShortcuts: [PanelKeyboardShortcut]? { get }
}

// MARK: - Default Implementations

extension PanelMode {
    var headerActions: [PanelHeaderAction] { [] }
    func onActivate() {}
    func onDeactivate() {}
    var canEvict: Bool { true }
    var preferredWidth: CGFloat? { nil }
    var dragProviders: [NSItemProvider]? { nil }
    var keyboardShortcuts: [PanelKeyboardShortcut]? { nil }
}
