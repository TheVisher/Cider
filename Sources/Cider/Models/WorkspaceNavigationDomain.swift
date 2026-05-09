import Foundation

enum WorkspaceNavigationDomain: String, CaseIterable, Codable, Hashable, Identifiable {
    case mainDashboard
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

    var title: String {
        switch self {
        case .mainDashboard: "Home"
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
        case .media: "Movies, TV, games, and references"
        case .bookmarks: "Saved links and web captures"
        case .notes: "Notes and writing"
        case .projects: "Kanban boards and active plans"
        case .tasksEvents: "Todos, reminders, and calendar cards"
        case .files: "Vault files and attachments"
        case .people: "Contacts and relationships"
        case .aiAssistant: "Ask questions and run agent workflows"
        case .browse: "All items, folders, tags, and saved views"
        }
    }

    var systemImage: String {
        switch self {
        case .mainDashboard: "house"
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
