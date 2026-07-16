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

struct CiderVaultFileDisplayTitleUpdateReceipt: Equatable {
    let receiptID: String
    let item: LibraryEntityRef
    let beforeTitle: String
    let afterTitle: String
    let changed: Bool
    let wasReused: Bool
    let actor: String
    let source: String
    let safeVerificationCommands: [String]

    var verificationCommand: String { safeVerificationCommands[0] }

    func toDictionary() -> [String: Any] {
        [
            "id": receiptID,
            "command": "item.update",
            "action": "update_vault_file_display_title",
            "item": ["type": item.type.rawValue, "id": item.entityID.uuidString],
            "before": ["title": beforeTitle],
            "after": ["title": afterTitle],
            "changed": changed,
            "wasReused": wasReused,
            "actor": actor,
            "source": source,
            "readOnly": false,
            "verificationCommand": verificationCommand,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

struct CiderVaultFileDisplayTitleUpdateError: Error, Equatable, LocalizedError {
    enum Code: String, Equatable {
        case databaseUnavailable
        case invalidInput
        case unsupportedTargetType
        case targetMissing
        case wrongTargetType
        case staleExpectedTitle
        case notCommitted
    }

    let code: Code
    let reason: String

    var errorDescription: String? { reason }
}

enum CiderItemMutationError: LocalizedError {
    case databaseUnavailable
    case folderNotFound(UUID)
    case unsupportedItemType(LibraryEntityType)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Canonical SQLite database is not open."
        case .folderNotFound(let id):
            return "Folder not found for item mutation: \(id.uuidString)."
        case .unsupportedItemType(let type):
            return "Item mutations are not supported for \(type.rawValue)."
        }
    }
}

@MainActor
final class CiderItemMutationService {
    typealias FolderAssignment = (LibraryEntityRef, UUID?) throws -> Bool

    struct Hooks {
        enum Stage: Equatable {
            case beforeTitlePersist
            case beforeSearchProjection
            case beforeReceiptPersist
        }

        var atStage: @MainActor (Stage) throws -> Void

        init(atStage: @escaping @MainActor (Stage) throws -> Void = { _ in }) {
            self.atStage = atStage
        }
    }

    private let database: CiderDatabase
    private let contextService: CiderItemContextService
    private let routingService: CiderRoutingDecisionService
    private let secondBrainStore: SecondBrainStore
    private let assignToFolder: FolderAssignment
    private let hooks: Hooks

    init(
        database: CiderDatabase = .shared,
        contextService: CiderItemContextService? = nil,
        routingService: CiderRoutingDecisionService? = nil,
        secondBrainStore: SecondBrainStore? = nil,
        assignToFolder: FolderAssignment? = nil,
        hooks: Hooks = .init()
    ) {
        self.database = database
        self.contextService = contextService ?? CiderItemContextService(database: database)
        self.routingService = routingService ?? CiderRoutingDecisionService(database: database)
        self.secondBrainStore = secondBrainStore ?? SecondBrainStore(database: database)
        self.assignToFolder = assignToFolder ?? Self.assignViaDomainStorage
        self.hooks = hooks
    }

    func updateVaultFileDisplayTitle(
        ref: LibraryEntityRef,
        expectedCurrentTitle: String,
        newTitle: String,
        reason: String,
        actor: String,
        source: String
    ) throws -> CiderVaultFileDisplayTitleUpdateReceipt {
        guard database.isOpen else {
            throw CiderVaultFileDisplayTitleUpdateError(
                code: .databaseUnavailable,
                reason: "Canonical SQLite database is not open; nothing was changed."
            )
        }
        guard ref.type == .vaultFile else {
            throw CiderVaultFileDisplayTitleUpdateError(
                code: .unsupportedTargetType,
                reason: "Display-title updates require a canonical vaultFile target; nothing was changed."
            )
        }

        let normalizedNewTitle: String
        let normalizedReason: String
        let normalizedActor: String
        let normalizedSource: String
        do {
            normalizedNewTitle = try CiderDisplayTitlePolicy.normalizedTitle(newTitle, field: "New title")
            normalizedReason = try CiderDisplayTitlePolicy.normalized(reason, field: "Reason", maximum: 500)
            normalizedActor = try CiderDisplayTitlePolicy.normalized(actor, field: "Actor", maximum: 120)
            normalizedSource = try CiderDisplayTitlePolicy.normalized(source, field: "Source", maximum: 160)
            _ = try CiderDisplayTitlePolicy.normalizedTitle(expectedCurrentTitle, field: "Expected current title")
        } catch {
            throw CiderVaultFileDisplayTitleUpdateError(code: .invalidInput, reason: error.localizedDescription)
        }

        let requestIdentity = [
            ref.entityID.uuidString,
            expectedCurrentTitle,
            normalizedNewTitle,
            normalizedReason,
            normalizedActor,
            normalizedSource,
        ].joined(separator: "\u{1f}")
        let receiptID = Self.stableRetitleReceiptID(requestIdentity)
        let commands = Self.vaultFileRetitleVerificationCommands(fileID: ref.entityID)
        let ledger = SecondBrainActionReceiptLedgerService(database: database)
        do {
            if let existing = try ledger.inspect(id: receiptID) {
                guard existing.command == "item.update",
                      existing.action == "update_vault_file_display_title",
                      existing.owner == Self.owner(for: ref) else {
                    throw CiderVaultFileDisplayTitleUpdateError(
                        code: .notCommitted,
                        reason: "The durable action identity is inconsistent; no new mutation was attempted."
                    )
                }
                let target = try vaultFileRetitleTarget(ref.entityID)
                guard target.type == "vaultFile", target.hasVaultFileRow else {
                    throw CiderVaultFileDisplayTitleUpdateError(
                        code: .targetMissing,
                        reason: "The receipt target is no longer a complete canonical vaultFile; no new mutation was attempted."
                    )
                }
                guard target.title == normalizedNewTitle else {
                    throw CiderVaultFileDisplayTitleUpdateError(
                        code: .staleExpectedTitle,
                        reason: "The vaultFile title changed after this receipt was committed; refresh and retry with current truth. Nothing was changed."
                    )
                }
                return CiderVaultFileDisplayTitleUpdateReceipt(
                    receiptID: receiptID,
                    item: ref,
                    beforeTitle: expectedCurrentTitle,
                    afterTitle: normalizedNewTitle,
                    changed: existing.changed,
                    wasReused: true,
                    actor: normalizedActor,
                    source: normalizedSource,
                    safeVerificationCommands: existing.safeVerificationCommands.isEmpty ? commands : existing.safeVerificationCommands
                )
            }

            let target = try vaultFileRetitleTarget(ref.entityID)
            guard target.type == "vaultFile" else {
                throw CiderVaultFileDisplayTitleUpdateError(
                    code: .wrongTargetType,
                    reason: "The target ID resolves to \(target.type), not a canonical vaultFile; nothing was changed."
                )
            }
            guard target.hasVaultFileRow else {
                throw CiderVaultFileDisplayTitleUpdateError(
                    code: .targetMissing,
                    reason: "The target does not resolve to a complete canonical vaultFile; nothing was changed."
                )
            }
            guard target.title == expectedCurrentTitle else {
                throw CiderVaultFileDisplayTitleUpdateError(
                    code: .staleExpectedTitle,
                    reason: "The expected current title is stale; refresh the vaultFile and retry. Nothing was changed."
                )
            }

            let changed = target.title != normalizedNewTitle
            let receipt = CiderVaultFileDisplayTitleUpdateReceipt(
                receiptID: receiptID,
                item: ref,
                beforeTitle: target.title,
                afterTitle: normalizedNewTitle,
                changed: changed,
                wasReused: false,
                actor: normalizedActor,
                source: normalizedSource,
                safeVerificationCommands: commands
            )
            try database.withTransaction {
                if changed {
                    try hooks.atStage(.beforeTitlePersist)
                    let updateItem = try database.prepare("""
                        UPDATE items SET title = ?
                        WHERE id = ? AND type = 'vaultFile' AND title = ?;
                        """)
                    updateItem.bind(normalizedNewTitle, at: 1)
                        .bind(ref.entityID.uuidString, at: 2)
                        .bind(expectedCurrentTitle, at: 3)
                    try updateItem.step()
                    guard try databaseChangeCount() == 1 else {
                        throw CiderVaultFileDisplayTitleUpdateError(
                            code: .staleExpectedTitle,
                            reason: "The vaultFile title changed concurrently; nothing was committed."
                        )
                    }

                    let markManual = try database.prepare("""
                        UPDATE vault_files SET title_manually_set = 1 WHERE item_id = ?;
                        """)
                    markManual.bind(ref.entityID.uuidString, at: 1)
                    try markManual.step()
                    guard try databaseChangeCount() == 1 else {
                        throw CiderVaultFileDisplayTitleUpdateError(
                            code: .targetMissing,
                            reason: "The canonical vaultFile metadata row is missing; nothing was committed."
                        )
                    }

                    try hooks.atStage(.beforeSearchProjection)
                    _ = try SecondBrainItemContentIndexingService(database: database).rebuild(
                        owner: Self.owner(for: ref)
                    )
                }

                try hooks.atStage(.beforeReceiptPersist)
                try ledger.record(Self.actionReceiptRecord(
                    receipt: receipt,
                    reason: normalizedReason,
                    correlationID: LocalFileIntakeValidator.sha256(Data(requestIdentity.utf8))
                ))
            }

            if changed, database === CiderDatabase.shared {
                VaultFileStorage.shared.publishCommittedDisplayTitle(fileID: ref.entityID, title: normalizedNewTitle)
                VaultFileService.shared.refreshMetadata()
            }
            return receipt
        } catch let error as CiderVaultFileDisplayTitleUpdateError {
            throw error
        } catch {
            throw CiderVaultFileDisplayTitleUpdateError(
                code: .notCommitted,
                reason: "The vaultFile display-title update failed; nothing was committed."
            )
        }
    }

    private func vaultFileRetitleTarget(_ id: UUID) throws -> (type: String, title: String, hasVaultFileRow: Bool) {
        let statement = try database.prepare("""
            SELECT i.type, i.title, EXISTS(SELECT 1 FROM vault_files vf WHERE vf.item_id = i.id)
            FROM items i WHERE i.id = ? LIMIT 1;
            """)
        statement.bind(id.uuidString, at: 1)
        guard try statement.step() else {
            throw CiderVaultFileDisplayTitleUpdateError(
                code: .targetMissing,
                reason: "No canonical item matches that vaultFile target; nothing was changed."
            )
        }
        return (statement.string(at: 0), statement.string(at: 1), statement.int(at: 2) == 1)
    }

    private func databaseChangeCount() throws -> Int {
        let statement = try database.prepare("SELECT changes();")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private static func stableRetitleReceiptID(_ identity: String) -> String {
        let digest = LocalFileIntakeValidator.sha256(Data("vaultfile-retitle|\(identity)".utf8))
        return "vaultfile-retitle-\(digest)"
    }

    private static func vaultFileRetitleVerificationCommands(fileID: UUID) -> [String] {
        [
            "cider-cli item get vaultFile \(fileID.uuidString) --json",
            "cider-cli item context vaultFile \(fileID.uuidString) --json",
            "cider-cli item action-ledger list --owner vaultFile:\(fileID.uuidString) --command item.update --json",
        ]
    }

    private static func actionReceiptRecord(
        receipt: CiderVaultFileDisplayTitleUpdateReceipt,
        reason: String,
        correlationID: String
    ) -> SecondBrainActionReceiptRecord {
        let owner = owner(for: receipt.item)
        let before: [String: Any] = ["title": receipt.beforeTitle]
        let after: [String: Any] = ["title": receipt.afterTitle]
        var receiptDictionary = receipt.toDictionary()
        receiptDictionary["reason"] = reason
        receiptDictionary["status"] = "succeeded"
        receiptDictionary["owner"] = [
            "ownerType": owner.ownerType,
            "ownerID": owner.ownerID,
            "ref": owner.canonicalRef,
        ]
        receiptDictionary["sourceRefs"] = [owner.canonicalRef]
        receiptDictionary["evidenceRefs"] = [owner.canonicalRef]
        receiptDictionary["safeNextCommands"] = receipt.safeVerificationCommands
        return SecondBrainActionReceiptRecord(
            id: receipt.receiptID,
            command: "item.update",
            action: "update_vault_file_display_title",
            actor: receipt.actor,
            status: "succeeded",
            owner: owner,
            sourceRefs: [owner.canonicalRef],
            evidenceRefs: [owner.canonicalRef],
            readOnly: false,
            changed: receipt.changed,
            beforeJSON: jsonString(before),
            afterJSON: jsonString(after),
            safeVerificationCommands: receipt.safeVerificationCommands,
            safeNextCommands: receipt.safeVerificationCommands,
            correlationID: correlationID,
            receiptJSON: jsonString(receiptDictionary)
        )
    }

    private static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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

    func move(
        ref: LibraryEntityRef,
        toFolder folderID: UUID?,
        actor: String,
        source: String,
        reason: String? = nil
    ) throws -> CiderItemMutationResult {
        guard let folderID else {
            return try unfile(ref: ref, actor: actor, source: source, reason: reason)
        }
        guard let folder = VaultFolderService.shared.folders.first(where: { $0.id == folderID }) else {
            throw CiderItemMutationError.folderNotFound(folderID)
        }
        return try move(
            ref: ref,
            toFolder: folderID,
            targetRelativePath: folder.relativePath,
            actor: actor,
            source: source,
            reason: reason
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
