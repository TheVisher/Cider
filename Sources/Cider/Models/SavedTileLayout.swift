import Foundation
import CoreGraphics

// MARK: - Saved Tile Layout (persisted)

struct SavedTileLayout: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var root: SavedTileNode
    var targetScreenIndex: Int  // 0 = primary, 1 = secondary (screenIDs change across reboots)
    var gap: CGFloat

    init(id: UUID = UUID(), name: String = "", root: SavedTileNode, targetScreenIndex: Int = 0, gap: CGFloat = CiderDesign.tileGap) {
        self.id = id
        self.root = root
        self.targetScreenIndex = targetScreenIndex
        self.gap = gap
        // Auto-generate name from leaf apps if not provided
        self.name = name.isEmpty ? root.apps.map(\.appName).joined(separator: " + ") : name
    }
}

// MARK: - Saved Tile Node (Codable mirror of TileNode with bundle IDs)

indirect enum SavedTileNode: Codable, Hashable {
    case leaf(bundleIdentifier: String, appName: String, appPath: String)
    case split(orientation: SplitOrientation, ratio: CGFloat,
               left: SavedTileNode, right: SavedTileNode)

    /// Flattened leaf apps in tree order.
    var apps: [(bundleIdentifier: String, appName: String, appPath: String)] {
        switch self {
        case .leaf(let bundleID, let appName, let appPath):
            return [(bundleID, appName, appPath)]
        case .split(_, _, let left, let right):
            return left.apps + right.apps
        }
    }
}

// MARK: - Active Tile Group Display (transient, for palette rendering)

struct TileGroupDisplay: Identifiable {
    let id: UUID              // DynamicTileManager group UUID
    let windows: [WindowInfo] // All windows in the tile
    let groupID: UUID         // For context menu actions (same as id)
    let screenID: UInt32
    var displayName: String   // "Safari + Terminal"
}

// MARK: - Monitor Section Item (tile groups + saved layouts + regular app groups)

enum MonitorSectionItem: Identifiable {
    case tileGroup(TileGroupDisplay)
    case savedLayout(SavedTileLayout)
    case appGroup(WindowAppGroup)

    var id: String {
        switch self {
        case .tileGroup(let display): return "tile-\(display.id)"
        case .savedLayout(let layout): return "saved-\(layout.id)"
        case .appGroup(let group): return "app-\(group.id)"
        }
    }
}
