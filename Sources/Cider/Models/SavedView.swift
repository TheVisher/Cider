import Foundation

enum LibrarySortMode: String, Codable, CaseIterable, Hashable {
    case createdDescending
    case createdAscending
    case updatedDescending
    case updatedAscending
    case titleAscending
    case titleDescending
    /// Items with a dateAnchor sort nearest first; others fall back to createdDate.
    case dateUpcoming
    /// Items with a dateAnchor sort farthest first; others fall back to createdDate.
    case dateFarthest
}

struct SavedViewFilterSpec: Codable, Hashable {
    var entityTypes: Set<LibraryEntityType>
    var labelIDs: Set<UUID>
    var folderID: UUID?
    var includeCompleted: Bool
    var textQuery: String

    init(
        entityTypes: Set<LibraryEntityType> = Set(LibraryEntityType.allCases),
        labelIDs: Set<UUID> = [],
        folderID: UUID? = nil,
        includeCompleted: Bool = true,
        textQuery: String = ""
    ) {
        self.entityTypes = entityTypes
        self.labelIDs = labelIDs
        self.folderID = folderID
        self.includeCompleted = includeCompleted
        self.textQuery = textQuery
    }
}

struct SavedViewSortSpec: Codable, Hashable {
    var mode: LibrarySortMode

    init(mode: LibrarySortMode = .createdDescending) {
        self.mode = mode
    }
}

struct SavedViewLayoutSpec: Codable, Hashable {
    var displayMode: LibraryDisplayMode
    var cardSizeScale: Double
    var showsGhostCells: Bool
    var showsCalendarProjection: Bool

    init(
        displayMode: LibraryDisplayMode = .list,
        cardSizeScale: Double = 1.0,
        showsGhostCells: Bool = true,
        showsCalendarProjection: Bool = false
    ) {
        self.displayMode = displayMode
        self.cardSizeScale = min(max(cardSizeScale, 0), 3)
        self.showsGhostCells = showsGhostCells
        self.showsCalendarProjection = showsCalendarProjection
    }
}

struct SavedView: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var filterSpec: SavedViewFilterSpec
    var sortSpec: SavedViewSortSpec
    var layoutSpec: SavedViewLayoutSpec
    var isTabPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        filterSpec: SavedViewFilterSpec = SavedViewFilterSpec(),
        sortSpec: SavedViewSortSpec = SavedViewSortSpec(),
        layoutSpec: SavedViewLayoutSpec = SavedViewLayoutSpec(),
        isTabPinned: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.filterSpec = filterSpec
        self.sortSpec = sortSpec
        self.layoutSpec = layoutSpec
        self.isTabPinned = isTabPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
