import Foundation

enum CiderSpacePresetKind: String, Codable, CaseIterable, Hashable {
    case blank
    case project
    case media
    case people
    case tasksEvents
    case custom
}

enum CiderSpaceDefaultView: String, Codable, CaseIterable, Hashable {
    case overview
    case inbox
    case recent
    case notes
    case files
    case tasks
    case events
    case boards
    case references
    case people
}

struct CiderSpacePreset: Equatable {
    let kind: CiderSpacePresetKind
    let title: String
    let systemImage: String
    let purpose: String
    let aiInstructions: String
    let routingHints: [String]
    let defaultViews: [CiderSpaceDefaultView]

    static func defaults(for kind: CiderSpacePresetKind) -> CiderSpacePreset {
        switch kind {
        case .blank:
            return CiderSpacePreset(
                kind: kind,
                title: "Blank Space",
                systemImage: "square.grid.2x2",
                purpose: "A flexible space for related notes, links, files, tasks, and ideas.",
                aiInstructions: "Use this space for items that clearly belong to its purpose. Ask before making broad routing assumptions.",
                routingHints: ["Prefer the space inbox until the user defines more structure."],
                defaultViews: [.overview, .inbox, .recent]
            )
        case .project:
            return CiderSpacePreset(
                kind: kind,
                title: "Project",
                systemImage: "shippingbox",
                purpose: "An active project space for planning, references, tasks, boards, and implementation notes.",
                aiInstructions: "Route project plans, implementation notes, references, tasks, and Kanban-related work here when they belong to this project.",
                routingHints: ["Prefer References for supporting links.", "Prefer Boards or Tasks for Kanban and next-action work."],
                defaultViews: [.overview, .boards, .references, .tasks, .notes]
            )
        case .media:
            return CiderSpacePreset(
                kind: kind,
                title: "Media",
                systemImage: "play.rectangle",
                purpose: "Movies, shows, games, books, music, and entertainment tracking.",
                aiInstructions: "Route movies, shows, games, books, trailers, reviews, watchlists, Steam pages, and entertainment notes here.",
                routingHints: ["Prefer Games for Steam and game pages.", "Prefer Movies or Shows for trailers and reviews.", "Use References for essays and criticism."],
                defaultViews: [.overview, .inbox, .recent, .notes, .files]
            )
        case .people:
            return CiderSpacePreset(
                kind: kind,
                title: "People",
                systemImage: "person.2",
                purpose: "Relationships, contacts, birthdays, notes, reminders, and follow-up context.",
                aiInstructions: "Route contact notes, relationship context, birthday reminders, and people-related follow-ups here.",
                routingHints: ["Prefer People for contact cards.", "Prefer Tasks for follow-ups and reminders."],
                defaultViews: [.overview, .people, .tasks, .notes]
            )
        case .tasksEvents:
            return CiderSpacePreset(
                kind: kind,
                title: "Planning",
                systemImage: "checklist",
                purpose: "Tasks, events, reminders, planning, and time-sensitive follow-up.",
                aiInstructions: "Route reminders, todos, date cards, calendar-like notes, and planning items here when they need attention or scheduling.",
                routingHints: ["Prefer Tasks for actionable todos.", "Prefer Events for date-specific cards."],
                defaultViews: [.overview, .inbox, .tasks, .events, .recent]
            )
        case .custom:
            return CiderSpacePreset(
                kind: kind,
                title: "Custom Space",
                systemImage: "sparkles.square.filled.on.square",
                purpose: "A custom space with user-defined purpose, routing, and views.",
                aiInstructions: "Follow this space's user-provided instructions when routing or summarizing items.",
                routingHints: ["Use the user-provided space purpose as the primary routing signal."],
                defaultViews: [.overview, .inbox, .recent]
            )
        }
    }
}

struct CiderSpace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var systemImage: String
    var purpose: String
    var preset: CiderSpacePresetKind
    var isPinned: Bool
    var aiInstructions: String
    var routingHints: [String]
    var defaultViews: [CiderSpaceDefaultView]
    var rootRelativePath: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        systemImage: String,
        purpose: String,
        preset: CiderSpacePresetKind,
        isPinned: Bool = true,
        aiInstructions: String,
        routingHints: [String],
        defaultViews: [CiderSpaceDefaultView],
        rootRelativePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.purpose = purpose
        self.preset = preset
        self.isPinned = isPinned
        self.aiInstructions = aiInstructions
        self.routingHints = routingHints
        self.defaultViews = defaultViews
        self.rootRelativePath = rootRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CiderSpaceRoutingContext: Equatable, Identifiable {
    let id: String
    let name: String
    let purpose: String
    let aiInstructions: String
    let routingHints: [String]
    let rootRelativePath: String

    init(space: CiderSpace) {
        id = space.id
        name = space.name
        purpose = space.purpose
        aiInstructions = space.aiInstructions
        routingHints = space.routingHints
        rootRelativePath = space.rootRelativePath
    }
}

enum CiderSpaceSidebarModel {
    static func pinnedSpaces(from spaces: [CiderSpace]) -> [CiderSpace] {
        spaces
            .filter(\.isPinned)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
