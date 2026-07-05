import Foundation

enum WorkspaceNavigationDomain: String, CaseIterable, Codable, Hashable, Identifiable {
    case mainDashboard
    case spaces
    case review
    case media
    case bookmarks
    case notes
    case projects
    case tasksEvents
    case files
    case people
    case aiAssistant
    case browse

    var id: String { rawValue }

    static let primaryRoots: [WorkspaceNavigationDomain] = [
        .mainDashboard,
        .browse,
        .spaces,
        .aiAssistant
    ]

    var isPrimaryRoot: Bool {
        Self.primaryRoots.contains(self)
    }

    var isDomainSpaceSurface: Bool {
        switch self {
        case .review, .media, .bookmarks, .notes, .projects, .tasksEvents, .files, .people:
            return true
        case .mainDashboard, .spaces, .aiAssistant, .browse:
            return false
        }
    }

    var title: String {
        switch self {
        case .mainDashboard: "Home"
        case .spaces: "Spaces"
        case .review: "Review"
        case .media: "Media"
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        case .projects: "Projects"
        case .tasksEvents: "Tasks & Events"
        case .files: "Files"
        case .people: "People"
        case .aiAssistant: "AI Assistant"
        case .browse: "Library"
        }
    }

    var subtitle: String {
        switch self {
        case .mainDashboard: "Command center, inbox, and active work"
        case .spaces: "Domain contexts and pinned spaces"
        case .review: "Trust boundary and review queue"
        case .media: "Movies, TV, games, and references"
        case .bookmarks: "Saved links and web captures"
        case .notes: "Notes and writing"
        case .projects: "Kanban boards and active plans"
        case .tasksEvents: "Todos, reminders, and calendar cards"
        case .files: "Vault files and attachments"
        case .people: "Contacts and relationships"
        case .aiAssistant: "Ask questions and run agent workflows"
        case .browse: "All items, folders, and tags"
        }
    }

    var systemImage: String {
        switch self {
        case .mainDashboard: "house"
        case .spaces: "square.grid.2x2"
        case .review: "checklist.checked"
        case .media: "play.rectangle"
        case .bookmarks: "bookmark"
        case .notes: "note.text"
        case .projects: "square.split.2x1"
        case .tasksEvents: "checklist"
        case .files: "doc.text"
        case .people: "person.2"
        case .aiAssistant: "sparkles"
        case .browse: "books.vertical"
        }
    }

    var breadcrumbPath: [String] {
        ["Cider", title]
    }

    var opensDomainSidebar: Bool {
        true
    }
}

struct WorkspaceNavigationState: Equatable {
    private(set) var selectedDomain: WorkspaceNavigationDomain?

    var isShowingGlobalDomains: Bool {
        selectedDomain == nil
    }

    var breadcrumbPath: [String] {
        selectedDomain?.breadcrumbPath ?? ["Cider"]
    }

    mutating func select(_ domain: WorkspaceNavigationDomain) {
        selectedDomain = domain
    }

    mutating func goBackToGlobalDomains() {
        selectedDomain = nil
    }
}
