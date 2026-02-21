import Foundation
import Combine

private struct ProjectsSnapshot: Codable {
    var projects: [Project]
    var items: [ProjectItem]
}

@MainActor
final class ProjectStorage: ObservableObject {
    static let shared = ProjectStorage()

    @Published private(set) var projects: [Project] = []
    @Published private(set) var items: [ProjectItem] = []

    private let fileName = "_cider_projects.json"
    private var fileURL: URL {
        let dir = StoragePaths.ciderDataDirectoryURL()
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(name: String, searchQuery: String? = nil) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Project" : trimmed
        let project = Project(name: finalName, searchQuery: searchQuery)
        projects.append(project)
        persist()
        return project
    }

    func renameProject(_ projectID: UUID, to newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        projects[idx].updatedAt = Date()
        persist()
    }

    func deleteProject(_ projectID: UUID) {
        items.removeAll { $0.projectID == projectID }
        projects.removeAll { $0.id == projectID }
        persist()
    }

    func archiveProject(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].isArchived = true
        projects[idx].updatedAt = Date()
        persist()
    }

    func unarchiveProject(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].isArchived = false
        projects[idx].updatedAt = Date()
        persist()
    }

    // MARK: - Project Items

    @discardableResult
    func addBookmark(_ bookmarkID: UUID, toProject projectID: UUID) -> ProjectItem? {
        guard projects.contains(where: { $0.id == projectID }) else { return nil }
        guard !items.contains(where: { $0.projectID == projectID && $0.bookmarkID == bookmarkID }) else {
            return nil
        }
        let maxOrder = items.filter { $0.projectID == projectID }.map(\.sortOrder).max() ?? -1
        let item = ProjectItem(
            projectID: projectID,
            bookmarkID: bookmarkID,
            sortOrder: maxOrder + 1
        )
        items.append(item)
        touchProject(projectID)
        persist()
        return item
    }

    @discardableResult
    func addNote(_ noteID: UUID, toProject projectID: UUID) -> ProjectItem? {
        guard projects.contains(where: { $0.id == projectID }) else { return nil }
        guard !items.contains(where: { $0.projectID == projectID && $0.noteID == noteID }) else {
            return nil
        }
        let maxOrder = items.filter { $0.projectID == projectID }.map(\.sortOrder).max() ?? -1
        let item = ProjectItem(
            projectID: projectID,
            noteID: noteID,
            sortOrder: maxOrder + 1
        )
        items.append(item)
        touchProject(projectID)
        persist()
        return item
    }

    func removeItem(_ itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let projectID = item.projectID
        items.removeAll { $0.id == itemID }
        touchProject(projectID)
        persist()
    }

    func itemsForProject(_ projectID: UUID) -> [ProjectItem] {
        items
            .filter { $0.projectID == projectID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func itemCount(for projectID: UUID) -> Int {
        items.filter { $0.projectID == projectID }.count
    }

    func activeProjects() -> [Project] {
        projects.filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(for id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Bulk Add (for Save as Project)

    func addSearchResults(_ results: [SearchResult], toProject projectID: UUID) {
        var order = (items.filter { $0.projectID == projectID }.map(\.sortOrder).max() ?? -1) + 1
        for result in results {
            switch result.type {
            case .bookmark:
                if let bookmark = result.bookmark,
                   !items.contains(where: { $0.projectID == projectID && $0.bookmarkID == bookmark.id }) {
                    let item = ProjectItem(
                        projectID: projectID,
                        bookmarkID: bookmark.id,
                        sortOrder: order
                    )
                    items.append(item)
                    order += 1
                }
            case .note:
                if let note = result.note,
                   !items.contains(where: { $0.projectID == projectID && $0.noteID == note.id }) {
                    let item = ProjectItem(
                        projectID: projectID,
                        noteID: note.id,
                        sortOrder: order
                    )
                    items.append(item)
                    order += 1
                }
            case .dateCard, .contact:
                break
            }
        }
        touchProject(projectID)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ProjectsSnapshot.self, from: data)
            projects = snapshot.projects
            items = snapshot.items
        } catch {
            projects = []
            items = []
        }
    }

    private func persist() {
        let snapshot = ProjectsSnapshot(projects: projects, items: items)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent fail — storage is best-effort
        }
    }

    private func touchProject(_ projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].updatedAt = Date()
    }
}
