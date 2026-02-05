import Foundation
import CoreGraphics

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bundleIdentifier: String
    let bounds: CGRect
    var screenID: UInt32?  // Mutable to allow updating when window moves
    var isMinimized: Bool  // Whether window is minimized to dock

    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    init(id: CGWindowID, ownerPID: pid_t, ownerName: String, title: String, bundleIdentifier: String, bounds: CGRect = .zero, screenID: UInt32? = nil, isMinimized: Bool = false) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.bounds = bounds
        self.screenID = screenID
        self.isMinimized = isMinimized
    }
}

struct WindowAppGroup: Identifiable, Hashable {
    let id: String
    let appName: String
    let bundleIdentifier: String
    var windows: [WindowInfo]
}
