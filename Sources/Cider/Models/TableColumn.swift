import Foundation

// MARK: - Table Column Definition

enum TableColumnID: String, Codable, CaseIterable, Hashable {
    case name
    case type
    case tags
    case folder
    case created
    case modified
    case url
    case wordCount
    case priority

    var displayName: String {
        switch self {
        case .name: "Name"
        case .type: "Type"
        case .tags: "Tags"
        case .folder: "Folder"
        case .created: "Created"
        case .modified: "Modified"
        case .url: "URL"
        case .wordCount: "Words"
        case .priority: "Priority"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: 0 // Flexible — fills remaining space
        case .type: 100
        case .tags: 150
        case .folder: 120
        case .created: 120
        case .modified: 120
        case .url: 180
        case .wordCount: 80
        case .priority: 80
        }
    }

    static let minWidth: CGFloat = 60

    /// Whether this column can be hidden (Name is always visible)
    var canHide: Bool {
        self != .name
    }

    /// Whether this column expands to fill remaining space
    var isFlexible: Bool {
        self == .name
    }

    /// Default columns shown on first use
    static let defaultVisible: [TableColumnID] = [.name, .type, .tags, .created, .modified]

    /// Columns hidden by default (shown via the + picker)
    static var defaultHidden: Set<TableColumnID> {
        Set(allCases).subtracting(defaultVisible)
    }
}

// MARK: - Table Column Config (persisted)

struct TableColumnConfig: Codable, Equatable {
    var columnOrder: [TableColumnID]
    var columnWidths: [TableColumnID: CGFloat]
    var hiddenColumns: Set<TableColumnID>

    static var `default`: TableColumnConfig {
        TableColumnConfig(
            columnOrder: TableColumnID.allCases,
            columnWidths: [:],
            hiddenColumns: TableColumnID.defaultHidden
        )
    }

    func width(for column: TableColumnID) -> CGFloat {
        columnWidths[column] ?? column.defaultWidth
    }

    var visibleColumns: [TableColumnID] {
        // Include columns in persisted order, plus any new columns not yet in the order
        let ordered = columnOrder.filter { !hiddenColumns.contains($0) }
        let missing = TableColumnID.allCases.filter { !columnOrder.contains($0) && !hiddenColumns.contains($0) }
        return ordered + missing
    }

    /// Total fixed width of all visible non-flexible columns
    var fixedColumnsWidth: CGFloat {
        visibleColumns
            .filter { !$0.isFlexible }
            .reduce(0) { $0 + width(for: $1) }
    }

    mutating func setWidth(_ width: CGFloat, for column: TableColumnID) {
        columnWidths[column] = max(width, TableColumnID.minWidth)
    }

    mutating func toggleVisibility(of column: TableColumnID) {
        guard column.canHide else { return }
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
            // Ensure column is in the order array
            if !columnOrder.contains(column) {
                columnOrder.append(column)
            }
        } else {
            hiddenColumns.insert(column)
        }
    }
}
