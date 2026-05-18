import Foundation

struct CiderItemMutationResult: Equatable {
    var ok: Bool
    var command: String
    var action: String
    var ref: LibraryEntityRef
    var before: CiderItemSummary
    var after: CiderItemSummary?
    var mutationAuditEntryID: UUID?
    var routingDecisionID: UUID?
    var agentActionID: String?
    var partialFailures: [String]
    var nextSafeAction: String

    @MainActor
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "ok": ok,
            "command": command,
            "action": action,
            "item": [
                "type": ref.type.rawValue,
                "id": ref.entityID.uuidString,
            ],
            "before": CiderItemMutationService.itemSummaryDictionary(before),
            "partialFailures": partialFailures,
            "nextSafeAction": nextSafeAction,
        ]
        if let after {
            dict["after"] = CiderItemMutationService.itemSummaryDictionary(after)
        } else {
            dict["after"] = NSNull()
        }
        if let mutationAuditEntryID {
            dict["mutationAuditEntryID"] = mutationAuditEntryID.uuidString
        }
        if let routingDecisionID {
            dict["routingDecisionID"] = routingDecisionID.uuidString
        }
        if let agentActionID {
            dict["agentActionID"] = agentActionID
        }
        return dict
    }
}

enum CiderItemMutationError: LocalizedError {
    case databaseUnavailable
    case unsupportedItemType(LibraryEntityType)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Canonical SQLite database is not open."
        case .unsupportedItemType(let type):
            return "Item mutations are not supported for \(type.rawValue)."
        }
    }
}

@MainActor
final class CiderItemMutationService {
    typealias FolderAssignment = (LibraryEntityRef, UUID?) throws -> Bool

    private let database: CiderDatabase
    private let contextService: CiderItemContextService
    private let routingService: CiderRoutingDecisionService
    private let secondBrainStore: SecondBrainStore
    private let assignToFolder: FolderAssignment

    init(
        database: CiderDatabase = .shared,
        contextService: CiderItemContextService? = nil,
        routingService: CiderRoutingDecisionService? = nil,
        secondBrainStore: SecondBrainStore? = nil,
        assignToFolder: FolderAssignment? = nil
    ) {
        self.database = database
        self.contextService = contextService ?? CiderItemContextService(database: database)
        self.routingService = routingService ?? CiderRoutingDecisionService(database: database)
        self.secondBrainStore = secondBrainStore ?? SecondBrainStore(database: database)
        self.assignToFolder = assignToFolder ?? Self.assignViaDomainStorage
    }

    func move(
        ref: LibraryEntityRef,
        toFolder folderID: UUID,
        targetRelativePath: String,
        actor: String,
        source: String,
        reason: String? = nil
    ) throws -> CiderItemMutationResult {
        try moveOrUnfile(
            command: "item.move",
            action: "move_to_folder",
            auditAction: "item_move",
            ref: ref,
            folderID: folderID,
            targetRelativePath: targetRelativePath,
            actor: actor,
            source: source,
            reason: reason ?? "Moved with item move."
        )
    }

    func unfile(
        ref: LibraryEntityRef,
        actor: String,
        source: String,
        reason: String? = nil
    ) throws -> CiderItemMutationResult {
        try moveOrUnfile(
            command: "item.unfile",
            action: "unfile",
            auditAction: "item_unfile",
            ref: ref,
            folderID: nil,
            targetRelativePath: inboxRelativePath(for: ref.type),
            actor: actor,
            source: source,
            reason: reason ?? "Unfiled with item unfile."
        )
    }

    private func moveOrUnfile(
        command: String,
        action: String,
        auditAction: String,
        ref: LibraryEntityRef,
        folderID: UUID?,
        targetRelativePath: String,
        actor: String,
        source: String,
        reason: String
    ) throws -> CiderItemMutationResult {
        guard database.isOpen else { throw CiderItemMutationError.databaseUnavailable }
        let before = try contextService.context(for: ref).item
        let assigned = try assignToFolder(ref, folderID)
        guard assigned else {
            return failureResult(
                command: command,
                action: action,
                ref: ref,
                before: before,
                failure: "assignment_failed"
            )
        }

        let after = try contextService.context(for: ref).item
        guard after.folderID == folderID else {
            return CiderItemMutationResult(
                ok: false,
                command: command,
                action: action,
                ref: ref,
                before: before,
                after: after,
                mutationAuditEntryID: nil,
                routingDecisionID: nil,
                agentActionID: nil,
                partialFailures: ["assignment_not_confirmed"],
                nextSafeAction: "inspect_item"
            )
        }

        let auditEntry = MutationAuditService(database: database).record(
            action: auditAction,
            itemType: ref.type.rawValue,
            itemID: ref.entityID,
            before: Self.itemSummarySnapshot(before),
            after: Self.itemSummarySnapshot(after),
            metadata: [
                "command": command,
                "actor": actor,
                "source": source,
                "targetRelativePath": targetRelativePath,
            ],
            source: source == "cli" || source.hasPrefix("cli.") ? .cli : .agent
        )

        let target = CiderRoutingDecisionTarget(
            kind: folderID == nil ? "inbox" : "folder",
            name: targetRelativePath.split(separator: "/").last.map(String.init) ?? targetRelativePath,
            relativePath: targetRelativePath,
            folderID: folderID
        )
        let explanation = try routingService.recordManualMove(
            itemID: ref.entityID,
            target: target,
            reason: reason,
            actor: actor,
            source: source
        )

        let actionID = UUID().uuidString
        try secondBrainStore.recordAgentAction(
            SecondBrainAgentAction(
                id: actionID,
                owner: Self.owner(for: ref),
                itemID: ref.entityID.uuidString,
                toolName: command,
                actionType: command,
                source: source,
                status: "succeeded",
                summary: "\(command) confirmed for \(ref.type.rawValue):\(ref.entityID.uuidString).",
                argumentsJSON: DatabaseHelpers.encodeJSON([
                    "folderID": folderID?.uuidString ?? "",
                    "targetRelativePath": targetRelativePath,
                    "actor": actor,
                ]),
                resultJSON: DatabaseHelpers.encodeJSON([
                    "mutationAuditEntryID": auditEntry?.id.uuidString ?? "",
                    "routingDecisionID": explanation.latestDecision?.id.uuidString ?? "",
                    "afterFolderID": after.folderID?.uuidString ?? "",
                    "afterRelativePath": after.relativePath ?? "",
                ])
            )
        )

        return CiderItemMutationResult(
            ok: true,
            command: command,
            action: action,
            ref: ref,
            before: before,
            after: after,
            mutationAuditEntryID: auditEntry?.id,
            routingDecisionID: explanation.latestDecision?.id,
            agentActionID: actionID,
            partialFailures: [],
            nextSafeAction: explanation.nextSafeAction
        )
    }

    private func failureResult(
        command: String,
        action: String,
        ref: LibraryEntityRef,
        before: CiderItemSummary,
        failure: String
    ) -> CiderItemMutationResult {
        CiderItemMutationResult(
            ok: false,
            command: command,
            action: action,
            ref: ref,
            before: before,
            after: nil,
            mutationAuditEntryID: nil,
            routingDecisionID: nil,
            agentActionID: nil,
            partialFailures: [failure],
            nextSafeAction: "inspect_item"
        )
    }

    private static func assignViaDomainStorage(ref: LibraryEntityRef, folderID: UUID?) throws -> Bool {
        switch ref.type {
        case .bookmark:
            return VaultBookmarkService.shared.assignBookmark(
                ref.entityID,
                toFolder: folderID,
                auditMetadata: ["classification": "item_mutation_service"]
            )
        case .note:
            return NotesStorage.shared.assignNote(ref.entityID, toFolder: folderID)
        case .todo:
            return TodoCardStorage.shared.assignTodoCard(ref.entityID, toFolder: folderID)
        case .dateCard:
            return DateCardStorage.shared.assignDateCard(ref.entityID, toFolder: folderID)
        case .contact:
            return ContactStorage.shared.assignContact(ref.entityID, toFolder: folderID)
        case .vaultFile:
            let assigned = VaultFileService.shared.assignFile(ref.entityID, toFolder: folderID)
            return assigned
        case .externalFile, .session:
            throw CiderItemMutationError.unsupportedItemType(ref.type)
        }
    }

    private static func owner(for ref: LibraryEntityRef) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
    }

    private static func itemSummarySnapshot(_ item: CiderItemSummary) -> [String: String] {
        [
            "id": item.id.uuidString,
            "type": item.type.rawValue,
            "title": item.title,
            "folderID": item.folderID?.uuidString ?? "",
            "relativePath": item.relativePath ?? "",
        ]
    }

    static func itemSummaryDictionary(_ item: CiderItemSummary) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id.uuidString,
            "type": item.type.rawValue,
            "title": item.title,
            "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
        ]
        if let folderID = item.folderID {
            dict["folderID"] = folderID.uuidString
        }
        if let relativePath = item.relativePath {
            dict["relativePath"] = relativePath
        }
        return dict
    }

    private func inboxRelativePath(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark:
            return "Inbox/Bookmarks"
        case .note:
            return "Inbox/Notes"
        case .todo:
            return "Inbox/Todos"
        case .dateCard:
            return "Inbox/Dates"
        case .contact:
            return "Inbox/Contacts"
        case .vaultFile:
            return "Inbox/Files"
        case .externalFile, .session:
            return "Inbox"
        }
    }
}
