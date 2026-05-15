import Foundation

struct CiderCaptureResult {
    struct Source {
        var kind: String
        var url: String?
        var file: String?
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
        var candidateTarget: Target?
        var reviewNeeded: Bool
        var confidence: Double
        var reason: String
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
        ]
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

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Capture source is required."
        case .unsupportedSource(let source):
            return "Unsupported capture source: \(source)"
        case .storeFailed(let source):
            return "Could not store capture source: \(source)"
        }
    }
}

@MainActor
final class CiderCaptureService {
    private let bookmarkService: VaultBookmarkService

    init(bookmarkService: VaultBookmarkService = .shared) {
        self.bookmarkService = bookmarkService
    }

    func add(
        _ rawSource: String,
        title: String? = nil,
        folderID: UUID? = nil
    ) throws -> CiderCaptureResult {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw CiderCaptureError.missingSource }
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

        return CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "url",
                url: source,
                file: nil,
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
                candidateTarget: target,
                reviewNeeded: reviewNeeded,
                confidence: reviewNeeded ? 0.0 : 1.0,
                reason: reviewNeeded
                    ? "No deterministic route was supplied, so Cider kept the capture in Inbox/Bookmarks for review."
                    : "Capture used the supplied deterministic target."
            ),
            nextSafeAction: isDuplicate ? "inspect_existing_item" : "enrich"
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
}
