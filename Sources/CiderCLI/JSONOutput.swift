@testable import Cider
import Foundation

/// Checks if --json flag is present in command line args
let jsonOutput = CommandLine.arguments.contains("--json")

/// Outputs JSON-encoded data to stdout, or prints human-readable fallback
func outputJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
        print(string)
    }
}

// MARK: - Item Serializers (all @MainActor since they access shared singletons)

@MainActor func bookmarkToDict(_ bm: Bookmark) -> [String: Any] {
    var d: [String: Any] = [
        "id": bm.id.uuidString,
        "title": bm.title,
        "url": bm.urlString,
        "host": bm.hostDisplay,
        "notes": bm.notes,
        "tags": bm.tags,
        "labelIDs": bm.labelIDs.map(\.uuidString),
        "folder": bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "folderID": bm.folderID?.uuidString as Any,
        "created": ISO8601DateFormatter().string(from: bm.createdAt),
        "updated": ISO8601DateFormatter().string(from: bm.updatedAt),
        "titleManuallySet": bm.titleManuallySet,
        "notesManuallySet": bm.notesManuallySet,
    ]
    if let path = bm.relativePath { d["relativePath"] = path }
    if let ocr = bm.ocrText { d["ocrText"] = ocr }
    if let colors = bm.dominantColors { d["dominantColors"] = colors }
    if let summary = bm.aiSummary { d["aiSummary"] = summary }
    if let status = bm.enrichmentStatus { d["enrichmentStatus"] = status }
    if let enrichedAt = bm.lastEnrichedAt { d["lastEnrichedAt"] = ISO8601DateFormatter().string(from: enrichedAt) }
    if let thumb = bm.thumbnailRelativePath { d["thumbnailPath"] = thumb }
    if let media = bm.mediaType { d["mediaType"] = media.rawValue }
    return d
}

@MainActor func noteToDict(_ note: Note) -> [String: Any] {
    [
        "id": note.id.uuidString,
        "title": note.title,
        "folder": note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "folderID": note.folderID?.uuidString as Any,
        "labelIDs": note.labelIDs.map(\.uuidString),
        "tags": note.tags,
        "pinned": note.isPinned,
        "created": ISO8601DateFormatter().string(from: note.createdAt),
        "modified": ISO8601DateFormatter().string(from: note.modifiedAt),
        "relativePath": note.relativePath,
    ]
}

@MainActor func todoToDict(_ todo: TodoCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": todo.id.uuidString,
        "title": todo.title,
        "details": todo.details,
        "completed": todo.isCompleted,
        "created": ISO8601DateFormatter().string(from: todo.createdAt),
        "updated": ISO8601DateFormatter().string(from: todo.updatedAt),
        "labelIDs": todo.labelIDs.map(\.uuidString),
        "folder": todo.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if let due = todo.dueDate { d["dueDate"] = ISO8601DateFormatter().string(from: due) }
    if let priority = todo.priority { d["priority"] = priority.rawValue }
    if let completedAt = todo.completedAt { d["completedAt"] = ISO8601DateFormatter().string(from: completedAt) }
    d["checklist"] = todo.checklist.map { item -> [String: Any] in
        var cd: [String: Any] = [
            "id": item.id.uuidString,
            "title": item.title,
            "completed": item.isCompleted,
        ]
        if !item.subtasks.isEmpty {
            cd["subtasks"] = item.subtasks.map { [
                "id": $0.id.uuidString,
                "title": $0.title,
                "completed": $0.isCompleted,
            ] as [String: Any] }
        }
        return cd
    }
    return d
}

@MainActor func eventToDict(_ card: DateCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": card.id.uuidString,
        "title": card.title,
        "details": card.details,
        "startAt": ISO8601DateFormatter().string(from: card.startAt),
        "completed": card.isCompleted,
        "created": ISO8601DateFormatter().string(from: card.createdAt),
        "labelIDs": card.labelIDs.map(\.uuidString),
        "folder": card.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if let endAt = card.endAt { d["endAt"] = ISO8601DateFormatter().string(from: endAt) }
    if !card.location.isEmpty { d["location"] = card.location }
    if let amount = card.amount { d["amount"] = amount }
    return d
}

@MainActor func contactToDict(_ contact: ContactCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": contact.id.uuidString,
        "displayName": contact.displayName,
        "created": ISO8601DateFormatter().string(from: contact.createdAt),
        "labelIDs": contact.labelIDs.map(\.uuidString),
        "folder": contact.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if !contact.email.isEmpty { d["email"] = contact.email }
    if !contact.phone.isEmpty { d["phone"] = contact.phone }
    if !contact.address.isEmpty { d["address"] = contact.address }
    if !contact.notes.isEmpty { d["notes"] = contact.notes }
    if !contact.relationshipLabel.isEmpty { d["relationship"] = contact.relationshipLabel }
    if let birthday = contact.birthday { d["birthday"] = ISO8601DateFormatter().string(from: birthday) }
    return d
}

@MainActor func vaultFileToDict(_ file: VaultFile) -> [String: Any] {
    var d: [String: Any] = [
        "id": file.id.uuidString,
        "filename": file.filename,
        "displayTitle": file.displayTitle,
        "fileType": file.fileType.rawValue,
        "fileSize": file.fileSize,
        "relativePath": file.relativePath,
        "folder": file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "labelIDs": file.labelIDs.map(\.uuidString),
        "tags": file.tags,
        "notes": file.notes,
        "created": ISO8601DateFormatter().string(from: file.createdAt),
        "modified": ISO8601DateFormatter().string(from: file.modifiedAt),
    ]
    if let title = file.title { d["title"] = title }
    if let ocr = file.ocrText { d["ocrText"] = ocr }
    if let colors = file.dominantColors { d["dominantColors"] = colors }
    return d
}

@MainActor func folderToDict(_ folder: VaultFolder) -> [String: Any] {
    [
        "id": folder.id.uuidString,
        "name": folder.name,
        "relativePath": folder.relativePath,
        "created": ISO8601DateFormatter().string(from: folder.createdAt),
    ]
}

@MainActor func labelToDict(_ label: CardLabel) -> [String: Any] {
    [
        "id": label.id.uuidString,
        "name": label.name,
        "colorHex": label.colorHex,
        "created": ISO8601DateFormatter().string(from: label.createdAt),
    ]
}

@MainActor func boardToDict(_ board: KanbanBoard) -> [String: Any] {
    [
        "id": board.id,
        "name": board.name,
        "created": ISO8601DateFormatter().string(from: board.created),
        "columns": board.columns.map { col in
            [
                "id": col.id,
                "name": col.name,
                "isDoneColumn": col.isDoneColumn,
                "cards": col.cards.map { card in
                    var d: [String: Any] = [
                        "id": card.id,
                        "title": card.title,
                        "created": ISO8601DateFormatter().string(from: card.created),
                    ]
                    if let notes = card.notes { d["notes"] = notes }
                    if let color = card.color { d["color"] = color.rawValue }
                    if let priority = card.priority { d["priority"] = priority.rawValue }
                    if let agent = card.agent { d["agent"] = agent }
                    if !card.tags.isEmpty { d["tags"] = card.tags }
                    if let completed = card.completed { d["completed"] = ISO8601DateFormatter().string(from: completed) }
                    return d
                },
            ] as [String: Any]
        },
    ]
}

@MainActor func clipboardItemToDict(_ item: ClipboardItem) -> [String: Any] {
    var d: [String: Any] = [
        "id": item.id.uuidString,
        "type": item.type.rawValue,
        "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
        "isSaved": item.isSaved,
    ]
    if let text = item.textContent { d["textContent"] = text }
    if let app = item.sourceAppName { d["sourceApp"] = app }
    if let savedID = item.savedItemID { d["savedItemID"] = savedID.uuidString }
    return d
}

@MainActor func trashItemToDict(_ item: TrashItem) -> [String: Any] {
    [
        "id": item.id.uuidString,
        "itemID": item.itemID.uuidString,
        "type": item.itemType.rawValue,
        "title": item.title,
        "deletedAt": ISO8601DateFormatter().string(from: item.deletedAt),
        "folderID": item.originalFolderID?.uuidString as Any,
    ]
}

@MainActor func searchResultToDict(_ result: SearchResult) -> [String: Any] {
    var d: [String: Any] = [
        "id": result.id.uuidString,
        "type": "\(result.type)",
        "title": result.title,
        "date": ISO8601DateFormatter().string(from: result.date),
    ]
    if let subtitle = result.subtitle { d["subtitle"] = subtitle }
    return d
}

@MainActor func doctorReportToDict(_ report: VaultDoctor.Report) -> [String: Any] {
    let iso = ISO8601DateFormatter()
    let countsByKey: [String: Int] = Dictionary(uniqueKeysWithValues: report.counts.map { ($0.key.rawValue, $0.value) })
    return [
        "startedAt": iso.string(from: report.startedAt),
        "finishedAt": iso.string(from: report.finishedAt),
        "counts": countsByKey,
        "fixableCount": report.fixableCount,
        "findings": report.findings.map(doctorFindingToDict),
    ]
}

@MainActor func doctorFindingToDict(_ f: VaultDoctor.Finding) -> [String: Any] {
    var d: [String: Any] = [
        "id": f.id,
        "kind": f.kind.rawValue,
        "severity": f.severity.rawValue,
        "summary": f.summary,
        "detail": f.detail,
        "isFixable": f.isFixable,
    ]
    if let label = f.fixLabel { d["fixLabel"] = label }
    if let fid = f.payload.folderID { d["folderID"] = fid.uuidString }
    if let iid = f.payload.itemID { d["itemID"] = iid.uuidString }
    if let sid = f.payload.sessionID { d["sessionID"] = sid.uuidString }
    if let rp = f.payload.relativePath { d["relativePath"] = rp }
    if let bc = f.payload.breadcrumbFile { d["breadcrumbFile"] = bc }
    return d
}

@MainActor func savedViewToDict(_ view: SavedView) -> [String: Any] {
    var d: [String: Any] = [
        "id": view.id.uuidString,
        "name": view.name,
        "isTabPinned": view.isTabPinned,
        "createdAt": ISO8601DateFormatter().string(from: view.createdAt),
        "updatedAt": ISO8601DateFormatter().string(from: view.updatedAt),
    ]
    switch view.kind {
    case .dashboard:
        d["kind"] = "dashboard"
    case .library:
        d["kind"] = "library"
    case .kanban(let boardID):
        d["kind"] = "kanban"
        d["boardID"] = boardID
    }
    // Filter spec
    var filter: [String: Any] = [:]
    if !view.filterSpec.entityTypes.isEmpty {
        filter["entityTypes"] = view.filterSpec.entityTypes.map(\.rawValue)
    }
    if !view.filterSpec.labelIDs.isEmpty {
        filter["labelIDs"] = view.filterSpec.labelIDs.map(\.uuidString)
    }
    if let folderID = view.filterSpec.folderID {
        filter["folderID"] = folderID.uuidString
    }
    if view.filterSpec.includeCompleted { filter["includeCompleted"] = true }
    if !view.filterSpec.textQuery.isEmpty { filter["textQuery"] = view.filterSpec.textQuery }
    if view.filterSpec.onlyUnassigned { filter["onlyUnassigned"] = true }
    if !filter.isEmpty { d["filter"] = filter }
    return d
}

@MainActor func statusToDict() -> [String: Any] {
    [
        "bookmarks": VaultBookmarkService.shared.bookmarks.count,
        "notes": NotesStorage.shared.notes.count,
        "todos": TodoCardStorage.shared.todoCards.count,
        "todosActive": TodoCardStorage.shared.todoCards.filter { !$0.isCompleted }.count,
        "events": DateCardStorage.shared.dateCards.count,
        "contacts": ContactStorage.shared.contacts.count,
        "vaultFiles": VaultFileService.shared.files.count,
        "vaultFilesImages": VaultFileService.shared.files.filter { $0.fileType == .image }.count,
        "folders": VaultFolderService.shared.folders.count,
        "labels": CardLabelStorage.shared.labels.count,
        "boards": KanbanStorage.shared.boards.count,
        "boardCards": KanbanStorage.shared.boards.flatMap(\.columns).flatMap(\.cards).count,
        "trash": TrashStorage.shared.allTrashItems().count,
        "vaultRoot": StoragePaths.cachedVaultDirectoryURL.path,
    ]
}
