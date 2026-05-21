import Foundation

enum WorkspaceDomainContentScope: String, CaseIterable, Hashable {
    case domainOnly
    case allItems

    static func defaultScope(for domain: WorkspaceNavigationDomain?) -> WorkspaceDomainContentScope {
        guard let domain else { return .allItems }
        switch domain {
        case .bookmarks, .notes, .tasksEvents, .files, .people:
            return .domainOnly
        case .mainDashboard, .spaces, .media, .projects, .aiAssistant, .browse:
            return .allItems
        }
    }

    func entityTypes(for domain: WorkspaceNavigationDomain?) -> Set<LibraryEntityType> {
        guard self == .domainOnly, let domain else {
            return LibraryEntityType.activeCases
        }

        switch domain {
        case .bookmarks:
            return [.bookmark]
        case .notes:
            return [.note]
        case .tasksEvents:
            return [.todo, .dateCard]
        case .files:
            return [.vaultFile]
        case .people:
            return [.contact]
        case .mainDashboard, .spaces, .media, .projects, .aiAssistant, .browse:
            return LibraryEntityType.activeCases
        }
    }

    func focusedTitle(for domain: WorkspaceNavigationDomain?) -> String {
        guard let domain else { return "Domain Only" }
        switch domain {
        case .bookmarks:
            return "Bookmarks Only"
        case .notes:
            return "Notes Only"
        case .tasksEvents:
            return "Tasks Only"
        case .files:
            return "Files Only"
        case .people:
            return "People Only"
        case .mainDashboard, .spaces, .media, .projects, .aiAssistant, .browse:
            return "Domain Only"
        }
    }
}
