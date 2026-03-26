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
    var onlyUnassigned: Bool

    init(
        entityTypes: Set<LibraryEntityType> = Set(LibraryEntityType.allCases),
        labelIDs: Set<UUID> = [],
        folderID: UUID? = nil,
        includeCompleted: Bool = true,
        textQuery: String = "",
        onlyUnassigned: Bool = false
    ) {
        self.entityTypes = entityTypes
        self.labelIDs = labelIDs
        self.folderID = folderID
        self.includeCompleted = includeCompleted
        self.textQuery = textQuery
        self.onlyUnassigned = onlyUnassigned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decodedTypes = try container.decodeIfPresent(Set<LibraryEntityType>.self, forKey: .entityTypes) ?? Set(LibraryEntityType.allCases)
        // Ensure new entity types are included in existing saved views
        decodedTypes.insert(.vaultFile)
        entityTypes = decodedTypes
        labelIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .labelIDs) ?? []
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        includeCompleted = try container.decodeIfPresent(Bool.self, forKey: .includeCompleted) ?? true
        textQuery = try container.decodeIfPresent(String.self, forKey: .textQuery) ?? ""
        onlyUnassigned = try container.decodeIfPresent(Bool.self, forKey: .onlyUnassigned) ?? false
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
    var showComingUpSection: Bool

    init(
        displayMode: LibraryDisplayMode = .list,
        cardSizeScale: Double = 1.0,
        showsGhostCells: Bool = true,
        showsCalendarProjection: Bool = false,
        showComingUpSection: Bool = true
    ) {
        self.displayMode = displayMode
        self.cardSizeScale = min(max(cardSizeScale, 0), 3)
        self.showsGhostCells = showsGhostCells
        self.showsCalendarProjection = showsCalendarProjection
        self.showComingUpSection = showComingUpSection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayMode = try container.decodeIfPresent(LibraryDisplayMode.self, forKey: .displayMode) ?? .list
        let rawScale = try container.decodeIfPresent(Double.self, forKey: .cardSizeScale) ?? 1.0
        cardSizeScale = min(max(rawScale, 0), 3)
        showsGhostCells = try container.decodeIfPresent(Bool.self, forKey: .showsGhostCells) ?? true
        showsCalendarProjection = try container.decodeIfPresent(Bool.self, forKey: .showsCalendarProjection) ?? false
        showComingUpSection = try container.decodeIfPresent(Bool.self, forKey: .showComingUpSection) ?? true
    }
}

struct SavedView: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var filterSpec: SavedViewFilterSpec
    var sortSpec: SavedViewSortSpec
    var layoutSpec: SavedViewLayoutSpec
    var isTabPinned: Bool
    var isBlank: Bool
    var isOnboarding: Bool
    var kind: SavedViewKind
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        filterSpec: SavedViewFilterSpec = SavedViewFilterSpec(),
        sortSpec: SavedViewSortSpec = SavedViewSortSpec(),
        layoutSpec: SavedViewLayoutSpec = SavedViewLayoutSpec(),
        isTabPinned: Bool = true,
        isBlank: Bool = false,
        isOnboarding: Bool = false,
        kind: SavedViewKind = .library,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.filterSpec = filterSpec
        self.sortSpec = sortSpec
        self.layoutSpec = layoutSpec
        self.isTabPinned = isTabPinned
        self.isBlank = isBlank
        self.isOnboarding = isOnboarding
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filterSpec = try container.decodeIfPresent(SavedViewFilterSpec.self, forKey: .filterSpec) ?? SavedViewFilterSpec()
        sortSpec = try container.decodeIfPresent(SavedViewSortSpec.self, forKey: .sortSpec) ?? SavedViewSortSpec()
        layoutSpec = try container.decodeIfPresent(SavedViewLayoutSpec.self, forKey: .layoutSpec) ?? SavedViewLayoutSpec()
        isTabPinned = try container.decodeIfPresent(Bool.self, forKey: .isTabPinned) ?? true
        isBlank = try container.decodeIfPresent(Bool.self, forKey: .isBlank) ?? false
        isOnboarding = try container.decodeIfPresent(Bool.self, forKey: .isOnboarding) ?? false
        kind = try container.decodeIfPresent(SavedViewKind.self, forKey: .kind) ?? .library
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
