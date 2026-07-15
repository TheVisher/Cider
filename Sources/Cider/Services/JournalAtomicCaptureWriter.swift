import Foundation

struct JournalAtomicMediaSource: Equatable, Sendable {
    let sourceURL: URL
    let sourceID: String
    let kind: JournalMediaKind
    let displayTitle: String?
    let mimeType: String?

    init(
        sourceURL: URL,
        sourceID: String,
        kind: JournalMediaKind,
        displayTitle: String? = nil,
        mimeType: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceID = sourceID
        self.kind = kind
        self.displayTitle = displayTitle
        self.mimeType = mimeType
    }
}

struct JournalAtomicCaptureRequest: Equatable {
    let journalDate: String
    let time: String
    let text: String
    let source: String
    let capturedAt: Date
    let idempotencyKey: String
    let sourceContext: CaptureSourceContext?
    let media: [JournalAtomicMediaSource]
}

struct JournalAtomicCaptureReceipt: Equatable, Sendable {
    struct ItemRef: Equatable, Sendable {
        let type: String
        let id: String
        let title: String
        let relativePath: String?

        var canonicalRef: String { "\(type):\(id)" }
    }

    struct SourceRef: Equatable, Sendable {
        let id: String
        let kind: String
        let capturedAt: Date
        let sourceID: String
        let displayTitle: String
        let rawFilename: String?
        let mediaItem: ItemRef?

        var canonicalRef: String { "journal_source:\(id)" }
    }

    let receiptID: String
    let journalDate: String
    let time: String
    let item: ItemRef
    let textSource: SourceRef
    let mediaSources: [SourceRef]
    let captureEventRef: String
    let wasReused: Bool
}

struct JournalAtomicCaptureError: Error, Equatable, LocalizedError, Sendable {
    enum Code: String, Equatable, Sendable {
        case validationFailed
        case idempotencyConflict
        case notCommitted
        case indeterminate
    }

    let code: Code
    let reason: String

    var errorDescription: String? { reason }
}

/// One logical Journal mutation across the day note, immutable originals,
/// source-card provenance, relations, and search projections. SQLite is the
/// commit coordinator; the Markdown file is snapshotted and compensated if the
/// transaction cannot commit.
@MainActor
final class JournalAtomicCaptureWriter {
    struct Hooks {
        enum Stage: Equatable {
            case afterNoteFileWrite
            case afterNotePersist
            case afterSourceCards
            case beforeSearchProjection
        }

        var atStage: @MainActor (Stage) throws -> Void

        init(atStage: @escaping @MainActor (Stage) throws -> Void = { _ in }) {
            self.atStage = atStage
        }
    }

    private enum PreviousFile {
        case missing(createdDirectories: [URL])
        case bytes(Data)
    }

    private let database: CiderDatabase
    private let notesStorage: NotesStorage
    private let mediaIntake: JournalMediaIntakeService
    private let vaultRoot: URL
    private let fileManager: FileManager
    private let hooks: Hooks

    init(
        database: CiderDatabase,
        notesStorage: NotesStorage,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        mediaIntake: JournalMediaIntakeService? = nil,
        fileManager: FileManager = .default,
        hooks: Hooks = .init()
    ) {
        self.database = database
        self.notesStorage = notesStorage
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.mediaIntake = mediaIntake ?? JournalMediaIntakeService(database: database, vaultRoot: vaultRoot)
        self.fileManager = fileManager
        self.hooks = hooks
    }

    func capture(_ request: JournalAtomicCaptureRequest) throws -> JournalAtomicCaptureReceipt {
        try validate(request)
        guard database.isOpen else {
            throw JournalAtomicCaptureError(
                code: .notCommitted,
                reason: "Journal capture requires a writable Cider database; nothing was changed."
            )
        }

        let mediaRequests = request.media.map {
            JournalMediaIntakeRequest(
                sourceURL: $0.sourceURL,
                sourceID: $0.sourceID,
                kind: $0.kind,
                capturedAt: request.capturedAt,
                displayName: Self.friendlyTitle($0.displayTitle, rawFilename: $0.sourceURL.lastPathComponent)
            )
        }
        let validatedMedia: JournalValidatedMediaBatch
        do {
            validatedMedia = try mediaIntake.validateBatch(mediaRequests)
        } catch {
            throw JournalAtomicCaptureError(
                code: .notCommitted,
                reason: "Journal capture validation or persistence failed; nothing was committed."
            )
        }
        let requestDigest = Self.requestDigest(request, mediaContentHashes: validatedMedia.contentHashes)
        let eventID = Self.stableUUID(seed: "journal-capture|\(request.idempotencyKey)")
        if let existing = try loadReceipt(eventID: eventID, requestDigest: requestDigest) {
            return existing
        }

        let prepared = try prepareNote(for: request)
        let fileURL = notesStorage.noteFileURL(for: prepared.note)
        let previousFile = try snapshot(fileURL)
        var didWriteNote = false

        do {
            let receipt = try mediaIntake.ingestBatch(validatedMedia) { originals in
                for original in originals where original.wasReused && original.file.createdAt != request.capturedAt {
                    throw LocalFileIntakeError(.identityConflict)
                }
                try self.writeAndVerify(prepared.note.content, to: fileURL)
                didWriteNote = true
                try self.hooks.atStage(.afterNoteFileWrite)

                try self.notesStorage.persistJournalNoteInCurrentTransaction(self.database, note: prepared.note)
                try self.hooks.atStage(.afterNotePersist)
                let receipt = try self.persistSourceCards(
                    request: request,
                    requestDigest: requestDigest,
                    eventID: eventID,
                    note: prepared.note,
                    originals: originals
                )
                try self.hooks.atStage(.afterSourceCards)
                try self.hooks.atStage(.beforeSearchProjection)
                _ = try SecondBrainItemContentIndexingService(database: self.database).rebuild(
                    owner: SecondBrainOwnerRef(ownerType: "note", ownerID: prepared.note.id.uuidString)
                )
                for original in originals {
                    _ = try SecondBrainItemContentIndexingService(database: self.database).rebuild(
                        owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: original.file.id.uuidString)
                    )
                }
                return receipt
            }
            notesStorage.publishCommittedJournalNote(prepared.note)
            return receipt
        } catch {
            guard didWriteNote else {
                throw JournalAtomicCaptureError(
                    code: .notCommitted,
                    reason: "Journal capture validation or persistence failed; nothing was committed."
                )
            }
            do {
                try restore(previousFile, at: fileURL)
                throw JournalAtomicCaptureError(
                    code: .notCommitted,
                    reason: "Journal capture failed and the prior day note was restored; nothing was committed."
                )
            } catch let recovery as JournalAtomicCaptureError {
                throw recovery
            } catch {
                throw JournalAtomicCaptureError(
                    code: .indeterminate,
                    reason: "Journal capture failed and Cider could not verify Markdown recovery. No success is claimed; inspect the day note and database before retrying."
                )
            }
        }
    }

    private func validate(_ request: JournalAtomicCaptureRequest) throws {
        guard JournalTitle.isValidISODate(request.journalDate),
              Self.isValidTime(request.time),
              !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(request.media.map(\.sourceID)).count == request.media.count,
              request.media.allSatisfy({ !$0.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw JournalAtomicCaptureError(
                code: .validationFailed,
                reason: "Journal date, time, text, idempotency key, and media source identities must be valid and distinct."
            )
        }
    }

    private func prepareNote(for request: JournalAtomicCaptureRequest) throws -> (note: Note, created: Bool) {
        let title = JournalTitle.canonicalTitle(forISODate: request.journalDate)
        let existing = notesStorage.notes.first { $0.dailyJournalDateLabel == request.journalDate }
        let baseContent: String
        var note: Note
        if let existing {
            note = existing
            baseContent = notesStorage.loadContent(for: existing)
        } else {
            let relativePath = "\(StoragePaths.inboxDir)/Notes/\(title).md"
            let url = vaultRoot.appendingPathComponent(relativePath).standardizedFileURL
            guard Self.isContained(url, in: vaultRoot), !fileManager.fileExists(atPath: url.path) else {
                throw JournalAtomicCaptureError(
                    code: .idempotencyConflict,
                    reason: "A Journal file exists without a matching canonical item; nothing was changed."
                )
            }
            note = Note(
                id: Self.stableUUID(seed: "journal-day|\(request.journalDate)"),
                title: title,
                content: "",
                createdAt: request.capturedAt,
                modifiedAt: request.capturedAt,
                relativePath: relativePath
            )
            baseContent = ""
        }
        let entry = JournalTitle.appendSection(time: request.time, source: request.source, body: request.text)
        if baseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.content = "# \(title)\n\n## Entries\n\(entry)"
        } else {
            // Existing user-owned bytes remain an exact prefix. The writer may
            // append a separator, but never trims, normalizes, or rewrites them.
            let separator = baseContent.hasSuffix("\n") ? "" : "\n"
            note.content = baseContent + separator + entry
        }
        note.modifiedAt = request.capturedAt
        return (note, existing == nil)
    }

    private func persistSourceCards(
        request: JournalAtomicCaptureRequest,
        requestDigest: String,
        eventID: UUID,
        note: Note,
        originals: [JournalStoredOriginal]
    ) throws -> JournalAtomicCaptureReceipt {
        let context = request.sourceContext
        var eventMetadata = context?.metadata ?? [:]
        eventMetadata["command"] = "capture.add"
        eventMetadata["kind"] = "journal"
        eventMetadata["date"] = request.journalDate
        eventMetadata["time"] = request.time
        eventMetadata["appendSource"] = request.source
        eventMetadata["journal_receipt_id"] = eventID.uuidString
        eventMetadata["journal_request_digest"] = requestDigest
        eventMetadata["journal_writer"] = "atomic_media_v1"
        eventMetadata["attachment_count"] = String(originals.count)
        eventMetadata = CaptureEventProvenanceContract.metadata(merging: eventMetadata, outcome: .completed)

        let event = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, 'journal', ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?);
            """)
        event.bind(eventID.uuidString, at: 1)
            .bind(context?.surface, at: 2)
            .bind(context?.channel, at: 3)
            .bind(context?.channelID, at: 4)
            .bind(context?.threadID, at: 5)
            .bind(context?.messageID, at: 6)
            .bind(context?.senderID, at: 7)
            .bind(context?.senderName, at: 8)
            .bind(context?.originalText ?? request.text, at: 9)
            .bind(originals.count, at: 10)
            .bind(DatabaseHelpers.encodeJSON(eventMetadata) ?? "{}", at: 11)
            .bind(DatabaseHelpers.encode(request.capturedAt), at: 12)
        try event.step()

        let store = SecondBrainStore(database: database)
        let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
        try store.recordRelation(.init(
            sourceOwner: captureOwner,
            targetOwner: noteOwner,
            relationType: "produced_item",
            evidence: "Journal capture appended to \(note.title).",
            source: "capture.add",
            actor: "system",
            confidence: 1,
            metadata: eventMetadata
        ))

        var sourceRefs: [JournalAtomicCaptureReceipt.SourceRef] = []
        for (index, pair) in zip(originals.indices, zip(originals, request.media)) {
            let (original, media) = pair
            let displayTitle = Self.friendlyTitle(media.displayTitle, rawFilename: media.sourceURL.lastPathComponent)
            let metadata: [String: String] = [
                "journal_note_id": note.id.uuidString,
                "journal_date": request.journalDate,
                "journal_time": request.time,
                "source_card_id": original.sourceCardID,
                "source_id": original.sourceID,
                "vault_file_id": original.file.id.uuidString,
                "display_title": displayTitle,
                "raw_filename": media.sourceURL.lastPathComponent,
                "sha256": original.sha256,
                "media_kind": original.kind.rawValue,
                "retention": "preserve_original",
            ]
            let attachment = try database.prepare("""
                INSERT INTO capture_attachments (
                    id, capture_event_id, attachment_index, source_attachment_id,
                    filename, mime_type, local_path, remote_url, byte_size,
                    metadata, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?);
                """)
            attachment.bind(original.sourceCardID, at: 1)
                .bind(eventID.uuidString, at: 2)
                .bind(index, at: 3)
                .bind(original.sourceID, at: 4)
                .bind(media.sourceURL.lastPathComponent, at: 5)
                .bind(media.mimeType, at: 6)
                .bind(original.file.relativePath, at: 7)
                .bind(original.byteSize, at: 8)
                .bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 9)
                .bind(DatabaseHelpers.encode(request.capturedAt), at: 10)
            try attachment.step()

            let attachmentOwner = SecondBrainOwnerRef(ownerType: "capture_attachment", ownerID: original.sourceCardID)
            let fileOwner = SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: original.file.id.uuidString)
            try store.recordRelation(.init(
                sourceOwner: captureOwner,
                targetOwner: attachmentOwner,
                relationType: "had_attachment",
                evidence: "Journal capture included \(displayTitle).",
                source: "capture.add",
                actor: "system",
                confidence: 1,
                metadata: metadata
            ))
            try store.recordRelation(.init(
                sourceOwner: attachmentOwner,
                targetOwner: fileOwner,
                relationType: "materialized_as",
                evidence: "Journal source retained its immutable original.",
                source: "journal.atomic_capture",
                actor: "system",
                confidence: 1,
                metadata: metadata
            ))
            try store.recordRelation(.init(
                sourceOwner: attachmentOwner,
                targetOwner: noteOwner,
                relationType: "journal_source_for",
                evidence: "Journal media source belongs to \(note.title).",
                source: "journal.atomic_capture",
                actor: "system",
                confidence: 1,
                metadata: metadata
            ))
            sourceRefs.append(Self.sourceRef(
                original: original,
                displayTitle: displayTitle,
                rawFilename: media.sourceURL.lastPathComponent
            ))
        }

        return Self.receipt(
            eventID: eventID,
            request: request,
            note: note,
            mediaSources: sourceRefs,
            wasReused: false
        )
    }

    private func loadReceipt(eventID: UUID, requestDigest: String) throws -> JournalAtomicCaptureReceipt? {
        let event = try database.prepare("""
            SELECT source_text, metadata, created_at
            FROM capture_events WHERE id = ? AND source_kind = 'journal' LIMIT 1;
            """)
        event.bind(eventID.uuidString, at: 1)
        guard try event.step() else { return nil }
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: event.optionalString(at: 1)) ?? [:]
        guard metadata["journal_request_digest"] == requestDigest else {
            throw JournalAtomicCaptureError(
                code: .idempotencyConflict,
                reason: "That Journal idempotency key already belongs to a different logical capture."
            )
        }
        guard let noteID = try relatedNoteID(eventID: eventID),
              let note = notesStorage.notes.first(where: { $0.id.uuidString == noteID })
                ?? loadNote(id: noteID) else {
            throw JournalAtomicCaptureError(
                code: .indeterminate,
                reason: "A durable Journal receipt exists but its canonical day cannot be resolved. No new mutation was attempted."
            )
        }
        let attachments = try loadMediaSourceRefs(eventID: eventID)
        guard attachments.count == (Int(metadata["attachment_count"] ?? "") ?? attachments.count) else {
            throw JournalAtomicCaptureError(code: .indeterminate, reason: "The durable Journal receipt is incomplete.")
        }
        try verifyDurableReceipt(note: note, attachments: attachments)
        let request = JournalAtomicCaptureRequest(
            journalDate: metadata["date"] ?? note.dailyJournalDateLabel ?? "",
            time: metadata["time"] ?? "",
            text: event.optionalString(at: 0) ?? "",
            source: metadata["appendSource"] ?? "capture.add",
            capturedAt: DatabaseHelpers.decodeDate(event.double(at: 2)),
            idempotencyKey: eventID.uuidString,
            sourceContext: nil,
            media: []
        )
        return Self.receipt(eventID: eventID, request: request, note: note, mediaSources: attachments, wasReused: true)
    }

    private func verifyDurableReceipt(
        note: Note,
        attachments: [JournalAtomicCaptureReceipt.SourceRef]
    ) throws {
        let noteURL = notesStorage.noteFileURL(for: note)
        guard let noteBytes = try? Data(contentsOf: noteURL),
              String(data: noteBytes, encoding: .utf8) == note.content else {
            throw JournalAtomicCaptureError(
                code: .indeterminate,
                reason: "The durable Journal receipt exists, but its day Markdown is missing or differs from canonical storage. No success is claimed."
            )
        }
        let validator = LocalFileIntakeValidator(fileManager: fileManager)
        for source in attachments {
            guard let item = source.mediaItem,
                  let relativePath = item.relativePath,
                  Self.isSafeRelativePath(relativePath) else {
                throw JournalAtomicCaptureError(code: .indeterminate, reason: "The durable Journal receipt has an unresolved media source.")
            }
            let metadataStatement = try database.prepare("SELECT metadata FROM capture_attachments WHERE id = ? LIMIT 1;")
            metadataStatement.bind(source.id, at: 1)
            guard try metadataStatement.step() else {
                throw JournalAtomicCaptureError(code: .indeterminate, reason: "The durable Journal source card is missing.")
            }
            let metadata = DatabaseHelpers.decodeJSON(
                [String: String].self,
                from: metadataStatement.optionalString(at: 0)
            ) ?? [:]
            let url = vaultRoot.appendingPathComponent(relativePath).standardizedFileURL
            guard Self.isContained(url, in: vaultRoot),
                  let validated = try? validator.validate(url),
                  validated.sha256 == metadata["sha256"] else {
                throw JournalAtomicCaptureError(
                    code: .indeterminate,
                    reason: "The durable Journal receipt exists, but an immutable original is missing or changed. No success is claimed."
                )
            }
        }
        let owners = ["note:\(note.id.uuidString)"] + attachments.compactMap { source in
            source.mediaItem.map { "vaultFile:\($0.id)" }
        }
        for owner in owners {
            let parts = owner.split(separator: ":", maxSplits: 1).map(String.init)
            let chunks = try database.prepare("SELECT COUNT(*) FROM content_chunks WHERE owner_type = ? AND owner_id = ?;")
            chunks.bind(parts[0], at: 1).bind(parts[1], at: 2)
            guard try chunks.step(), chunks.int(at: 0) > 0 else {
                throw JournalAtomicCaptureError(
                    code: .indeterminate,
                    reason: "The durable Journal receipt exists, but its search projection is incomplete. No success is claimed."
                )
            }
        }
    }

    private func relatedNoteID(eventID: UUID) throws -> String? {
        let statement = try database.prepare("""
            SELECT target_owner_id FROM owner_relations
            WHERE source_owner_type = 'capture_event' AND source_owner_id = ?
              AND target_owner_type = 'note' AND relation_type = 'produced_item'
            LIMIT 1;
            """)
        statement.bind(eventID.uuidString, at: 1)
        return try statement.step() ? statement.string(at: 0) : nil
    }

    private func loadMediaSourceRefs(eventID: UUID) throws -> [JournalAtomicCaptureReceipt.SourceRef] {
        let statement = try database.prepare("""
            SELECT a.id, a.source_attachment_id, a.filename, a.metadata, a.created_at,
                   i.id, i.title, i.relative_path, i.created_at, i.updated_at,
                   vf.filename, vf.file_type, vf.file_size
            FROM capture_attachments a
            LEFT JOIN items i ON i.id = json_extract(a.metadata, '$.vault_file_id') AND i.type = 'vaultFile'
            LEFT JOIN vault_files vf ON vf.item_id = i.id
            WHERE a.capture_event_id = ? ORDER BY a.attachment_index ASC;
            """)
        statement.bind(eventID.uuidString, at: 1)
        var refs: [JournalAtomicCaptureReceipt.SourceRef] = []
        while try statement.step() {
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 3)) ?? [:]
            var item: JournalAtomicCaptureReceipt.ItemRef?
            if let id = statement.optionalString(at: 5),
               let relativePath = statement.optionalString(at: 7) {
                item = .init(type: "vaultFile", id: id, title: statement.string(at: 6), relativePath: relativePath)
            }
            refs.append(.init(
                id: statement.string(at: 0),
                kind: metadata["media_kind"] ?? "media",
                capturedAt: DatabaseHelpers.decodeDate(statement.double(at: 4)),
                sourceID: metadata["source_id"] ?? statement.optionalString(at: 1) ?? "",
                displayTitle: metadata["display_title"] ?? statement.optionalString(at: 2) ?? "Media",
                rawFilename: metadata["raw_filename"] ?? statement.optionalString(at: 2),
                mediaItem: item
            ))
        }
        return refs
    }

    private func loadNote(id: String) -> Note? {
        guard let uuid = UUID(uuidString: id),
              let statement = try? database.prepare("""
                SELECT i.title, n.content, i.created_at, i.updated_at, i.relative_path
                FROM items i JOIN notes n ON n.item_id = i.id
                WHERE i.id = ? AND i.type = 'note' LIMIT 1;
                """) else { return nil }
        statement.bind(id, at: 1)
        guard (try? statement.step()) == true else { return nil }
        return Note(
            id: uuid,
            title: statement.string(at: 0),
            content: statement.string(at: 1),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 2)),
            modifiedAt: DatabaseHelpers.decodeDate(statement.double(at: 3)),
            relativePath: statement.optionalString(at: 4) ?? ""
        )
    }

    private func snapshot(_ url: URL) throws -> PreviousFile {
        guard fileManager.fileExists(atPath: url.path) else {
            var createdDirectories: [URL] = []
            var candidate = url.deletingLastPathComponent()
            while candidate.path != vaultRoot.path,
                  Self.isContained(candidate, in: vaultRoot),
                  !fileManager.fileExists(atPath: candidate.path) {
                createdDirectories.append(candidate)
                candidate = candidate.deletingLastPathComponent()
            }
            return .missing(createdDirectories: createdDirectories)
        }
        return .bytes(try Data(contentsOf: url))
    }

    private func writeAndVerify(_ content: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(content.utf8)
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else { throw LocalFileIntakeError(.materializationFailed) }
    }

    private func restore(_ previous: PreviousFile, at url: URL) throws {
        switch previous {
        case .missing(let createdDirectories):
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            guard !fileManager.fileExists(atPath: url.path) else { throw LocalFileIntakeError(.materializationFailed) }
            for directory in createdDirectories where (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try fileManager.removeItem(at: directory)
            }
        case .bytes(let data):
            try data.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == data else { throw LocalFileIntakeError(.materializationFailed) }
        }
    }

    private static func receipt(
        eventID: UUID,
        request: JournalAtomicCaptureRequest,
        note: Note,
        mediaSources: [JournalAtomicCaptureReceipt.SourceRef],
        wasReused: Bool
    ) -> JournalAtomicCaptureReceipt {
        let item = JournalAtomicCaptureReceipt.ItemRef(
            type: "note",
            id: note.id.uuidString,
            title: note.title,
            relativePath: note.relativePath
        )
        let textSource = JournalAtomicCaptureReceipt.SourceRef(
            id: "journal-text-\(eventID.uuidString)",
            kind: "text",
            capturedAt: request.capturedAt,
            sourceID: "journal-text-\(eventID.uuidString)",
            displayTitle: "Journal text",
            rawFilename: nil,
            mediaItem: nil
        )
        return .init(
            receiptID: eventID.uuidString,
            journalDate: request.journalDate,
            time: request.time,
            item: item,
            textSource: textSource,
            mediaSources: mediaSources,
            captureEventRef: "capture_event:\(eventID.uuidString)",
            wasReused: wasReused
        )
    }

    private static func sourceRef(
        original: JournalStoredOriginal,
        displayTitle: String,
        rawFilename: String
    ) -> JournalAtomicCaptureReceipt.SourceRef {
        .init(
            id: original.sourceCardID,
            kind: original.kind.rawValue,
            capturedAt: original.capturedAt,
            sourceID: original.sourceID,
            displayTitle: displayTitle,
            rawFilename: rawFilename,
            mediaItem: .init(
                type: "vaultFile",
                id: original.file.id.uuidString,
                title: original.file.displayTitle,
                relativePath: original.file.relativePath
            )
        )
    }

    private static func requestDigest(
        _ request: JournalAtomicCaptureRequest,
        mediaContentHashes: [String]
    ) -> String {
        precondition(request.media.count == mediaContentHashes.count)
        let media = zip(request.media, mediaContentHashes).map { source, contentHash in
            "\(source.sourceID)|\(source.kind.rawValue)|\(source.displayTitle ?? "")|\(source.sourceURL.lastPathComponent)|\(contentHash)"
        }.joined(separator: "\u{1e}")
        let source = request.sourceContext.map {
            "\($0.surface ?? "")|\($0.channel ?? "")|\($0.channelID ?? "")|\($0.threadID ?? "")|\($0.messageID ?? "")|\($0.senderID ?? "")"
        } ?? ""
        return LocalFileIntakeValidator.sha256(Data(
            "\(request.journalDate)|\(request.time)|\(request.text)|\(request.source)|\(source)|\(media)".utf8
        ))
    }

    static func stableUUID(seed: String) -> UUID {
        let raw = String(LocalFileIntakeValidator.sha256(Data(seed.utf8)).prefix(32))
        let formatted = "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted)!
    }

    private static func friendlyTitle(_ supplied: String?, rawFilename: String) -> String {
        let value = supplied?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return String(value.prefix(160)) }
        let stem = (rawFilename as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Journal media" : String(stem.prefix(160))
    }

    private static func isValidTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}
