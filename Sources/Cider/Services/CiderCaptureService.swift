import Foundation

struct CiderCaptureResult {
    struct Source {
        var kind: String
        var url: String?
        var file: String?
        var text: String?
        var itemID: UUID
        var itemType: String
    }

    struct Item {
        var id: UUID
        var type: String
        var title: String
        var relativePath: String?
        var folderID: UUID?
        var folderName: String
    }

    struct Enrichment {
        var status: String
        var isEnriching: Bool
        var titleState: String
        var lastEnrichedAt: Date?
    }

    struct Duplicate {
        var status: String
        var existingItemID: UUID?
    }

    struct Target {
        var kind: String
        var name: String
        var relativePath: String
        var folderID: UUID?
    }

    struct Routing {
        var decisionID: UUID?
        var candidateTarget: Target?
        var reviewNeeded: Bool
        var confidence: Double
        var reason: String
        var reviewState: String
    }

    var command: String
    var source: Source
    var item: Item
    var enrichment: Enrichment
    var duplicate: Duplicate
    var routing: Routing
    var nextSafeAction: String

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var sourceDict: [String: Any] = [
            "kind": source.kind,
            "itemID": source.itemID.uuidString,
            "itemType": source.itemType,
        ]
        if let url = source.url { sourceDict["url"] = url }
        if let file = source.file { sourceDict["file"] = file }
        if let text = source.text { sourceDict["text"] = text }

        var itemDict: [String: Any] = [
            "id": item.id.uuidString,
            "type": item.type,
            "title": item.title,
            "folderName": item.folderName,
        ]
        if let relativePath = item.relativePath { itemDict["relativePath"] = relativePath }
        if let folderID = item.folderID { itemDict["folderID"] = folderID.uuidString }

        var enrichmentDict: [String: Any] = [
            "status": enrichment.status,
            "isEnriching": enrichment.isEnriching,
            "titleState": enrichment.titleState,
        ]
        if let lastEnrichedAt = enrichment.lastEnrichedAt {
            enrichmentDict["lastEnrichedAt"] = formatter.string(from: lastEnrichedAt)
        }

        var duplicateDict: [String: Any] = [
            "status": duplicate.status,
        ]
        if let existingItemID = duplicate.existingItemID {
            duplicateDict["existingItemID"] = existingItemID.uuidString
        }

        var routingDict: [String: Any] = [
            "reviewNeeded": routing.reviewNeeded,
            "confidence": routing.confidence,
            "reason": routing.reason,
            "reviewState": routing.reviewState,
        ]
        if let decisionID = routing.decisionID { routingDict["decisionID"] = decisionID.uuidString }
        if let target = routing.candidateTarget {
            var targetDict: [String: Any] = [
                "kind": target.kind,
                "name": target.name,
                "relativePath": target.relativePath,
            ]
            if let folderID = target.folderID { targetDict["folderID"] = folderID.uuidString }
            routingDict["candidateTarget"] = targetDict
        }

        return [
            "command": command,
            "source": sourceDict,
            "item": itemDict,
            "enrichment": enrichmentDict,
            "duplicate": duplicateDict,
            "routing": routingDict,
            "nextSafeAction": nextSafeAction,
        ]
    }
}

enum CiderCaptureError: LocalizedError {
    case missingSource
    case unsupportedSource(String)
    case storeFailed(String)
    case fileNotFound(String)
    case fileCopyFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Capture source is required."
        case .unsupportedSource(let source):
            return "Unsupported capture source: \(source)"
        case .storeFailed(let source):
            return "Could not store capture source: \(source)"
        case .fileNotFound(let path):
            return "Capture file does not exist: \(path)"
        case .fileCopyFailed(let path):
            return "Could not copy capture file into the vault: \(path)"
        }
    }
}

@MainActor
final class CiderCaptureService {
    private let bookmarkService: VaultBookmarkService
    private let notesStorage: NotesStorage
    private let todoStorage: TodoCardStorage
    private let vaultFileStorage: VaultFileStorage
    private let routingDecisionService: CiderRoutingDecisionService?
    private let database: CiderDatabase?

    init(
        bookmarkService: VaultBookmarkService = .shared,
        notesStorage: NotesStorage = .shared,
        todoStorage: TodoCardStorage = .shared,
        vaultFileStorage: VaultFileStorage = .shared,
        database: CiderDatabase? = nil,
        routingDecisionService: CiderRoutingDecisionService? = CiderRoutingDecisionService()
    ) {
        self.bookmarkService = bookmarkService
        self.notesStorage = notesStorage
        self.todoStorage = todoStorage
        self.vaultFileStorage = vaultFileStorage
        self.database = database
        self.routingDecisionService = routingDecisionService
    }

    func add(
        _ rawSource: String,
        title: String? = nil,
        folderID: UUID? = nil
    ) throws -> CiderCaptureResult {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw CiderCaptureError.missingSource }

        switch inferredKind(for: source) {
        case .url:
            return try addURL(source, title: title, folderID: folderID)
        case .file:
            return try addFile(source, title: title, folderID: folderID)
        case .todo:
            return try addTodo(source, title: title, folderID: folderID)
        case .note:
            return try addNote(source, title: title, folderID: folderID)
        }
    }

    private func addURL(
        _ source: String,
        title: String?,
        folderID: UUID?
    ) throws -> CiderCaptureResult {
        guard bookmarkService.previewNormalizedURLString(from: source) != nil else {
            throw CiderCaptureError.unsupportedSource(source)
        }

        let existingIDs = Set(bookmarkService.bookmarks.map(\.id))
        guard let captured = bookmarkService.add(urlString: source, title: title, folderID: folderID) else {
            throw CiderCaptureError.storeFailed(source)
        }

        let bookmark = bookmarkService.bookmarks.first(where: { $0.id == captured.id }) ?? captured
        let isDuplicate = existingIDs.contains(bookmark.id)
        let target = routingTarget(for: bookmark)
        let reviewNeeded = bookmark.folderID == nil
        let reviewState = reviewNeeded ? "needs_review" : "accepted"
        let reason = reviewNeeded
            ? "No deterministic route was supplied, so Cider kept the capture in Inbox/Bookmarks for review."
            : "Capture used the supplied deterministic target."
        let routingDecision = try? routingDecisionService?.recordDecision(
            itemID: bookmark.id,
            itemType: "bookmark",
            target: target.routingDecisionTarget,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            actor: "agent",
            source: "capture.add",
            reviewState: reviewState
        )

        return CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "url",
                url: source,
                file: nil,
                text: nil,
                itemID: bookmark.id,
                itemType: "bookmark"
            ),
            item: .init(
                id: bookmark.id,
                type: "bookmark",
                title: bookmark.title,
                relativePath: bookmark.relativePath,
                folderID: bookmark.folderID,
                folderName: target.name
            ),
            enrichment: .init(
                status: enrichmentStatus(for: bookmark),
                isEnriching: bookmark.isEnriching,
                titleState: titleState(for: bookmark),
                lastEnrichedAt: bookmark.lastEnrichedAt
            ),
            duplicate: .init(
                status: isDuplicate ? "duplicate" : "new",
                existingItemID: isDuplicate ? bookmark.id : nil
            ),
            routing: .init(
                decisionID: routingDecision?.id,
                candidateTarget: target,
                reviewNeeded: reviewNeeded,
                confidence: reviewNeeded ? 0.0 : 1.0,
                reason: reason,
                reviewState: reviewState
            ),
            nextSafeAction: isDuplicate ? "inspect_existing_item" : "enrich"
        )
    }

    private func addNote(
        _ source: String,
        title: String?,
        folderID: UUID?
    ) throws -> CiderCaptureResult {
        let note = notesStorage.createNew(initialContent: source)
        if let title = normalizedTitle(title) ?? derivedTextTitle(from: source) {
            notesStorage.rename(note: note, to: title)
        }
        if let folderID {
            _ = notesStorage.assignNote(note.id, toFolder: folderID)
        }
        guard let stored = notesStorage.notes.first(where: { $0.id == note.id }) else {
            throw CiderCaptureError.storeFailed(source)
        }

        let target = routingTarget(
            itemType: "note",
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Notes"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "note",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured text as a note and kept it in Inbox/Notes for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: source,
            itemID: stored.id,
            itemType: "note",
            title: stored.title,
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: normalizedTitle(title) == nil ? "derived" : "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.reviewNeeded ? "review_route" : "inspect_item"
        )
    }

    private func addTodo(
        _ source: String,
        title: String?,
        folderID: UUID?
    ) throws -> CiderCaptureResult {
        let todoTitle = normalizedTitle(title) ?? derivedTodoTitle(from: source)
        var todo = todoStorage.createTodoCard(title: todoTitle)
        if let folderID {
            todo.folderID = folderID
            _ = todoStorage.updateTodoCard(todo)
        }
        guard let stored = todoStorage.todoCards.first(where: { $0.id == todo.id }) else {
            throw CiderCaptureError.storeFailed(source)
        }

        let relativePath = itemRelativePathFromDatabase(itemID: stored.id) ?? "Inbox/Todos"
        let target = routingTarget(
            itemType: "todo",
            relativePath: relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Todos"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "todo",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured task-like text as a todo and kept it in Inbox/Todos for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: source,
            itemID: stored.id,
            itemType: "todo",
            title: stored.title,
            relativePath: relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: normalizedTitle(title) == nil ? "derived" : "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.reviewNeeded ? "review_route" : "inspect_item"
        )
    }

    private func addFile(
        _ source: String,
        title: String?,
        folderID: UUID?
    ) throws -> CiderCaptureResult {
        let sourceURL = URL(fileURLWithPath: NSString(string: source).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw CiderCaptureError.fileNotFound(source)
        }

        let fileType = VaultFileType.from(extension: sourceURL.pathExtension)
        let destinationDirectory = fileDestinationDirectory(fileType: fileType, folderID: folderID)
        try FileManager.default.createDirectory(at: destinationDirectory.url, withIntermediateDirectories: true)
        let destinationURL = uniqueDestinationURL(for: sourceURL, in: destinationDirectory.url)
        do {
            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            throw CiderCaptureError.fileCopyFailed(source)
        }

        let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let file = VaultFile(
            id: UUID(),
            filename: destinationURL.lastPathComponent,
            relativePath: destinationDirectory.relativePathPrefix.isEmpty
                ? destinationURL.lastPathComponent
                : "\(destinationDirectory.relativePathPrefix)/\(destinationURL.lastPathComponent)",
            fileType: fileType,
            fileSize: Int64(values?.fileSize ?? 0),
            createdAt: values?.creationDate ?? Date(),
            modifiedAt: values?.contentModificationDate ?? Date(),
            folderID: destinationDirectory.folderID,
            title: normalizedTitle(title)
        )
        vaultFileStorage.persistVaultFileToDatabase(file)

        let target = routingTarget(
            itemType: "vaultFile",
            relativePath: file.relativePath,
            folderID: file.folderID,
            fallbackInboxPath: destinationDirectory.relativePathPrefix
        )
        let routing = try recordRouting(
            itemID: file.id,
            itemType: "vaultFile",
            target: target,
            reviewNeeded: file.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider imported the file and kept it in \(target.relativePath) for review."
        )

        return sharedResult(
            sourceKind: "file",
            sourceURL: nil,
            sourceFile: sourceURL.path,
            sourceText: nil,
            itemID: file.id,
            itemType: "vaultFile",
            title: file.displayTitle,
            relativePath: file.relativePath,
            folderID: file.folderID,
            folderName: target.name,
            enrichmentStatus: fileType == .image ? "pending" : "not_applicable",
            titleState: file.title == nil ? "filename_derived" : "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.reviewNeeded ? "review_route" : "inspect_item"
        )
    }

    private func enrichmentStatus(for bookmark: Bookmark) -> String {
        if let status = bookmark.enrichmentStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            return status
        }
        if bookmark.metadataUpdatedAt != nil {
            return "metadata_complete"
        }
        return "pending"
    }

    private func titleState(for bookmark: Bookmark) -> String {
        if bookmark.titleManuallySet { return "manual" }
        if bookmark.metadataUpdatedAt != nil { return "enriched" }
        return "host_derived"
    }

    private func routingTarget(for bookmark: Bookmark) -> CiderCaptureResult.Target {
        if let folderID = bookmark.folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return .init(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }

        return .init(
            kind: "inbox",
            name: "Inbox/Bookmarks",
            relativePath: "Inbox/Bookmarks",
            folderID: nil
        )
    }

    private enum CaptureKind {
        case url
        case note
        case todo
        case file
    }

    private func inferredKind(for source: String) -> CaptureKind {
        if bookmarkService.previewNormalizedURLString(from: source) != nil {
            return .url
        }

        let expandedPath = NSString(string: source).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            return .file
        }

        let lowercased = source.lowercased()
        let todoPrefixes = ["todo:", "task:", "reminder:", "remember to ", "remind me to "]
        if todoPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return .todo
        }

        return .note
    }

    private func sharedResult(
        sourceKind: String,
        sourceURL: String?,
        sourceFile: String?,
        sourceText: String?,
        itemID: UUID,
        itemType: String,
        title: String,
        relativePath: String?,
        folderID: UUID?,
        folderName: String,
        enrichmentStatus: String,
        titleState: String,
        duplicateStatus: String,
        routing: CiderCaptureResult.Routing,
        nextSafeAction: String
    ) -> CiderCaptureResult {
        CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: sourceKind,
                url: sourceURL,
                file: sourceFile,
                text: sourceText,
                itemID: itemID,
                itemType: itemType
            ),
            item: .init(
                id: itemID,
                type: itemType,
                title: title,
                relativePath: relativePath,
                folderID: folderID,
                folderName: folderName
            ),
            enrichment: .init(
                status: enrichmentStatus,
                isEnriching: false,
                titleState: titleState,
                lastEnrichedAt: nil
            ),
            duplicate: .init(
                status: duplicateStatus,
                existingItemID: nil
            ),
            routing: routing,
            nextSafeAction: nextSafeAction
        )
    }

    private func recordRouting(
        itemID: UUID,
        itemType: String,
        target: CiderCaptureResult.Target,
        reviewNeeded: Bool,
        acceptedReason: String,
        reviewReason: String
    ) throws -> CiderCaptureResult.Routing {
        let reviewState = reviewNeeded ? "needs_review" : "accepted"
        let reason = reviewNeeded ? reviewReason : acceptedReason
        let routingDecision = try? routingDecisionService?.recordDecision(
            itemID: itemID,
            itemType: itemType,
            target: target.routingDecisionTarget,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            actor: "agent",
            source: "capture.add",
            reviewState: reviewState
        )
        return .init(
            decisionID: routingDecision?.id,
            candidateTarget: target,
            reviewNeeded: reviewNeeded,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            reviewState: reviewState
        )
    }

    private func routingTarget(
        itemType: String,
        relativePath: String?,
        folderID: UUID?,
        fallbackInboxPath: String
    ) -> CiderCaptureResult.Target {
        if let folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return .init(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }

        let inboxPath: String
        if let relativePath, relativePath.hasPrefix("Inbox/") {
            let parts = relativePath.split(separator: "/").prefix(2).map(String.init)
            inboxPath = parts.count == 2 ? parts.joined(separator: "/") : fallbackInboxPath
        } else {
            inboxPath = fallbackInboxPath
        }

        return .init(
            kind: "inbox",
            name: inboxPath,
            relativePath: inboxPath,
            folderID: nil
        )
    }

    private func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func derivedTextTitle(from source: String) -> String? {
        let line = source
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(80))
    }

    private func derivedTodoTitle(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let prefixes = ["todo:", "task:", "reminder:", "remember to ", "remind me to "]
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let title = trimmed[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Untitled Todo" : title
        }
        return trimmed.isEmpty ? "Untitled Todo" : trimmed
    }

    private func itemRelativePathFromDatabase(itemID: UUID) -> String? {
        guard let database else { return nil }
        do {
            let stmt = try database.prepare("SELECT relative_path FROM items WHERE id = ?;")
            stmt.bind(itemID.uuidString, at: 1)
            guard try stmt.step() else { return nil }
            return stmt.optionalString(at: 0)
        } catch {
            return nil
        }
    }

    private func fileDestinationDirectory(
        fileType: VaultFileType,
        folderID: UUID?
    ) -> (url: URL, relativePathPrefix: String, folderID: UUID?) {
        if let folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return (
                StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(folder.relativePath),
                folder.relativePath,
                folder.id
            )
        }

        let inboxSubdirectory: String
        switch fileType {
        case .image:
            inboxSubdirectory = "Images"
        case .video:
            inboxSubdirectory = "Videos"
        default:
            inboxSubdirectory = "Files"
        }
        let relativePath = "\(StoragePaths.inboxDir)/\(inboxSubdirectory)"
        return (
            StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath),
            relativePath,
            nil
        )
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let base = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let ext = (sourceURL.lastPathComponent as NSString).pathExtension
        var candidate = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let filename = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directoryURL.appendingPathComponent(filename)
            counter += 1
        }
        return candidate
    }
}

struct CiderBookmarkCaptureAdapterResult {
    var bookmark: Bookmark
    var captureResult: CiderCaptureResult
}

@MainActor
final class CiderBookmarkCaptureAdapter {
    private let bookmarkService: VaultBookmarkService
    private let database: CiderDatabase?

    init(
        bookmarkService: VaultBookmarkService = .shared,
        database: CiderDatabase? = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
    ) {
        self.bookmarkService = bookmarkService
        self.database = database
    }

    func addURLBookmark(
        urlString: String,
        title: String? = nil,
        folderID: UUID? = nil
    ) throws -> CiderBookmarkCaptureAdapterResult {
        let captureResult = try CiderCaptureService(
            bookmarkService: bookmarkService,
            database: database
        ).add(
            urlString,
            title: title,
            folderID: folderID
        )
        guard captureResult.item.type == "bookmark",
              let bookmark = bookmarkService.bookmarks.first(where: { $0.id == captureResult.item.id })
        else {
            throw CiderCaptureError.storeFailed(urlString)
        }
        return CiderBookmarkCaptureAdapterResult(bookmark: bookmark, captureResult: captureResult)
    }
}

private extension CiderCaptureResult.Target {
    var routingDecisionTarget: CiderRoutingDecisionTarget {
        CiderRoutingDecisionTarget(
            kind: kind,
            name: name,
            relativePath: relativePath,
            folderID: folderID
        )
    }
}
