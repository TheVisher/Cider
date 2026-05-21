import Foundation

enum WorkspaceDomainFolderPolicy {
    static func folders(_ folders: [Folder], for domain: WorkspaceNavigationDomain?) -> [Folder] {
        guard let domain else { return folders }
        guard domain != .browse else { return folders }
        guard let rootNames = rootFolderNames(for: domain), !rootNames.isEmpty else {
            return folders
        }

        let normalizedRootNames = Set(rootNames.map(normalize))
        let roots = folders.filter { folder in
            folder.parentID == nil && normalizedRootNames.contains(normalize(folder.name))
        }
        guard !roots.isEmpty else { return folders }

        var includedIDs = Set(roots.map(\.id))
        var changed = true
        while changed {
            changed = false
            for folder in folders where !includedIDs.contains(folder.id) {
                if let parentID = folder.parentID, includedIDs.contains(parentID) {
                    includedIDs.insert(folder.id)
                    changed = true
                }
            }
        }

        return folders.filter { includedIDs.contains($0.id) }
    }

    private static func rootFolderNames(for domain: WorkspaceNavigationDomain) -> [String]? {
        switch domain {
        case .mainDashboard, .spaces, .browse, .aiAssistant:
            nil
        case .media:
            ["Media", "Movies", "TV Shows", "Games", "Books", "Music"]
        case .bookmarks:
            ["Bookmarks", "Inbox/Bookmarks", "Reading", "Links"]
        case .notes:
            ["Notes", "Inbox/Notes"]
        case .projects:
            ["Projects", "Kanban", "Work"]
        case .tasksEvents:
            ["Tasks", "Todos", "Events", "Calendar", "Reminders"]
        case .files:
            ["Files", "Documents", "Archive"]
        case .people:
            ["People", "Contacts"]
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
    }
}
