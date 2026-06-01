import Foundation
import Testing
@testable import Cider

@Suite("Chat Capture Intake Service Tests")
@MainActor
struct ChatCaptureIntakeServiceTests {
    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-chat-capture-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempDatabase(in vault: URL) throws -> CiderDatabase {
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: dbURL)
        return db
    }

    private func withIsolatedVault<T>(
        _ body: (CiderDatabase, NotesStorage, VaultFileStorage) throws -> T
    ) throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let db = try makeTempDatabase(in: vault)
        defer {
            db.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        return try body(db, NotesStorage(database: db), VaultFileStorage(database: db))
    }

    @Test("telegram runtime update maps explicit save intent into canonical chat capture input")
    func telegramRuntimeUpdateMapsExplicitSaveIntentIntoCanonicalChatCaptureInput() throws {
        let update = TelegramUpdateEnvelope(
            updateID: 42,
            chatID: 9001,
            senderID: 7007,
            senderDisplayName: "Erik",
            text: "save this https://example.com/cider-graph"
        )

        let input = ChatRuntimeCaptureAdapter.input(fromTelegram: update)

        #expect(input?.channel == .telegram)
        #expect(input?.channelID == "9001")
        #expect(input?.threadID == "9001")
        #expect(input?.messageID == "telegram:42")
        #expect(input?.senderID == "7007")
        #expect(input?.senderName == "Erik")
        #expect(input?.intent == .capture)
        #expect(input?.text == "https://example.com/cider-graph")
        #expect(input?.metadata["source_update_id"] == "42")
        #expect(input?.metadata["runtime"] == "telegram")
    }

    @Test("telegram runtime save intent captures through canonical intake")
    func telegramRuntimeSaveIntentCapturesThroughCanonicalIntake() throws {
        try withIsolatedVault { db, notes, _ in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(notesStorage: notes, database: db)
            )
            let update = TelegramUpdateEnvelope(
                updateID: 43,
                chatID: 9002,
                senderID: 7008,
                senderDisplayName: "Erik",
                text: "save this https://example.com/canonical-chat"
            )

            let result = try ChatRuntimeCaptureAdapter.captureIfNeeded(
                fromTelegram: update,
                intakeService: service
            )

            let capture = try #require(result?.captureResult)
            #expect(result?.status == .captured)
            #expect(capture.sourceContext?.channel == "telegram")
            #expect(capture.sourceContext?.messageID == "telegram:43")

            let eventID = try #require(capture.captureEventID)
            let stmt = try db.prepare("""
                SELECT surface, channel, channel_id, thread_id, message_id, sender_id
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "chat")
            #expect(stmt.string(at: 1) == "telegram")
            #expect(stmt.string(at: 2) == "9002")
            #expect(stmt.string(at: 3) == "9002")
            #expect(stmt.string(at: 4) == "telegram:43")
            #expect(stmt.string(at: 5) == "7008")
        }
    }

    @Test("telegram runtime image save intent preserves local attachment for canonical capture")
    func telegramRuntimeImageSaveIntentPreservesLocalAttachmentForCanonicalCapture() throws {
        let update = TelegramUpdateEnvelope(
            updateID: 44,
            chatID: 9003,
            senderID: 7009,
            senderDisplayName: "Erik",
            text: """
            The user sent an image on Telegram.
            Caption: save this
            Local image copy: /tmp/cider-image.png
            OCR text from image: graph note
            """
        )

        let input = ChatRuntimeCaptureAdapter.input(fromTelegram: update)

        #expect(input?.intent == .capture)
        #expect(input?.text == "")
        let attachment = try #require(input?.attachments.first)
        #expect(attachment.filename == "cider-image.png")
        #expect(attachment.localPath == "/tmp/cider-image.png")
    }

    @Test("telegram failed image download with save intent records unsupported attachment review")
    func telegramFailedImageDownloadWithSaveIntentRecordsUnsupportedAttachmentReview() throws {
        try withIsolatedVault { db, notes, files in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                ),
                database: db
            )
            let update = TelegramUpdateEnvelope(
                updateID: 46,
                chatID: 9005,
                senderID: 7011,
                senderDisplayName: "Erik",
                text: """
                The user sent an image on Telegram.
                Caption: save this
                Telegram image file_id: AgACAgQAAxkBAAIB
                Image download failed, so only caption/text context is available.
                """
            )

            let input = try #require(ChatRuntimeCaptureAdapter.input(fromTelegram: update))
            #expect(input.intent == .capture)
            #expect(input.text == "")
            #expect(input.metadata["attachment_failure_reason"] == "telegram_image_download_failed")
            let attachment = try #require(input.attachments.first)
            #expect(attachment.id == "AgACAgQAAxkBAAIB")
            #expect(attachment.filename == nil)
            #expect(attachment.mimeType == "image/jpeg")
            #expect(attachment.localPath == nil)

            let result = try ChatRuntimeCaptureAdapter.captureIfNeeded(
                fromTelegram: update,
                intakeService: service
            )

            #expect(result?.status == .needsReview)
            #expect(result?.captureResult == nil)
            let eventID = try #require(result?.captureEventID)
            #expect(result?.safeNextCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json") == true)
            #expect(try captureAttachmentCount(db, eventID: eventID) == 1)
            #expect(try captureAttachmentSourceIDs(db, eventID: eventID) == ["AgACAgQAAxkBAAIB"])
            #expect(try unsupportedAttachmentReviewOutputCount(db, eventID: eventID) == 1)

            let stmt = try db.prepare("""
                SELECT source_kind, surface, channel, channel_id, thread_id, message_id, sender_id,
                       sender_name, attachment_count, metadata
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "chat_unsupported_attachment")
            #expect(stmt.string(at: 1) == "chat")
            #expect(stmt.string(at: 2) == "telegram")
            #expect(stmt.string(at: 3) == "9005")
            #expect(stmt.string(at: 4) == "9005")
            #expect(stmt.string(at: 5) == "telegram:46")
            #expect(stmt.string(at: 6) == "7011")
            #expect(stmt.string(at: 7) == "Erik")
            #expect(stmt.int(at: 8) == 1)
            #expect(stmt.string(at: 9).contains("telegram_image_download_failed"))
        }
    }

    @Test("telegram runtime bare save intent is not captured as chat-history text")
    func telegramRuntimeBareSaveIntentIsNotCapturedAsChatHistoryText() throws {
        let update = TelegramUpdateEnvelope(
            updateID: 45,
            chatID: 9004,
            senderID: 7010,
            senderDisplayName: "Erik",
            text: "save this"
        )

        #expect(ChatRuntimeCaptureAdapter.input(fromTelegram: update) == nil)
    }

    @Test("telegram chat capture creates canonical capture event provenance")
    func telegramChatCaptureCreatesCanonicalCaptureEventProvenance() throws {
        try withIsolatedVault { db, notes, _ in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(notesStorage: notes, database: db)
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .telegram,
                channelID: "chat-42",
                threadID: "thread-42",
                messageID: "msg-100",
                senderID: "user-7",
                senderName: "Erik",
                text: "Remember that Cider needs graph-safe chat intake.",
                attachments: [
                    ChatAttachment(
                        id: "photo-1",
                        filename: "capture.png",
                        mimeType: "image/png",
                        localPath: "/tmp/capture.png",
                        remoteURL: nil
                    )
                ],
                intent: .capture
            ))

            let capture = try #require(result.captureResult)
            #expect(result.status == .captured)
            #expect(capture.item.type == "note")
            #expect(capture.sourceContext?.channel == "telegram")
            #expect(capture.sourceContext?.messageID == "msg-100")
            #expect(capture.sourceContext?.attachments.count == 1)

            let eventID = try #require(capture.captureEventID)
            let stmt = try db.prepare("""
                SELECT surface, channel, channel_id, thread_id, message_id, sender_id, sender_name, attachment_count
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "chat")
            #expect(stmt.string(at: 1) == "telegram")
            #expect(stmt.string(at: 2) == "chat-42")
            #expect(stmt.string(at: 3) == "thread-42")
            #expect(stmt.string(at: 4) == "msg-100")
            #expect(stmt.string(at: 5) == "user-7")
            #expect(stmt.string(at: 6) == "Erik")
            #expect(stmt.int(at: 7) == 1)
        }
    }

    @Test("empty chat capture returns review outcome without mutating")
    func emptyChatCaptureReturnsReviewOutcomeWithoutMutating() throws {
        try withIsolatedVault { db, notes, _ in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(notesStorage: notes, database: db)
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "channel-1",
                threadID: nil,
                messageID: "discord-msg-1",
                senderID: "discord-user-1",
                senderName: "Erik",
                text: "   ",
                attachments: [],
                intent: .capture
            ))

            #expect(result.status == .needsReview)
            #expect(result.captureResult == nil)
            #expect(result.reason.contains("No captureable"))

            let stmt = try db.prepare("SELECT count(*) FROM capture_events;")
            try stmt.step()
            #expect(stmt.int(at: 0) == 0)
        }
    }

    @Test("discord local attachment capture imports file through canonical capture service")
    func discordLocalAttachmentCaptureImportsFileThroughCanonicalCaptureService() throws {
        try withIsolatedVault { db, notes, files in
            let sourceFile = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent("discord-upload.txt")
            try "Graph-safe Discord attachment".write(to: sourceFile, atomically: true, encoding: .utf8)

            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                )
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "discord-channel-9",
                threadID: "discord-thread-3",
                messageID: "discord-msg-22",
                senderID: "discord-user-4",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "attachment-1",
                        filename: "discord-upload.txt",
                        mimeType: "text/plain",
                        localPath: sourceFile.path,
                        remoteURL: "https://cdn.discordapp.example/discord-upload.txt"
                    )
                ],
                intent: .capture
            ))

            let capture = try #require(result.captureResult)
            #expect(result.status == .captured)
            #expect(capture.source.kind == "file")
            #expect(capture.item.type == "vaultFile")
            #expect(capture.sourceContext?.channel == "discord")
            #expect(capture.sourceContext?.messageID == "discord-msg-22")
            #expect(capture.sourceContext?.attachments.count == 1)

            let eventID = try #require(capture.captureEventID)
            let stmt = try db.prepare("""
                SELECT source_kind, surface, channel, channel_id, thread_id, message_id, sender_id, attachment_count
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "file")
            #expect(stmt.string(at: 1) == "chat")
            #expect(stmt.string(at: 2) == "discord")
            #expect(stmt.string(at: 3) == "discord-channel-9")
            #expect(stmt.string(at: 4) == "discord-thread-3")
            #expect(stmt.string(at: 5) == "discord-msg-22")
            #expect(stmt.string(at: 6) == "discord-user-4")
            #expect(stmt.int(at: 7) == 1)
        }
    }

    @Test("discord multi local attachment capture imports each file and preserves full attachment context")
    func discordMultiLocalAttachmentCaptureImportsEachFileAndPreservesFullAttachmentContext() throws {
        try withIsolatedVault { db, notes, files in
            let firstFile = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("first-upload.txt")
            let secondFile = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("second-upload.txt")
            try "First Discord attachment".write(to: firstFile, atomically: true, encoding: .utf8)
            try "Second Discord attachment".write(to: secondFile, atomically: true, encoding: .utf8)

            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                )
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "discord-channel-multi",
                threadID: "discord-thread-multi",
                messageID: "discord-msg-multi",
                senderID: "discord-user-multi",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "attachment-first",
                        filename: "first-upload.txt",
                        mimeType: "text/plain",
                        localPath: firstFile.path,
                        remoteURL: "https://cdn.discordapp.example/first-upload.txt"
                    ),
                    ChatAttachment(
                        id: "attachment-second",
                        filename: "second-upload.txt",
                        mimeType: "text/plain",
                        localPath: secondFile.path,
                        remoteURL: "https://cdn.discordapp.example/second-upload.txt"
                    )
                ],
                intent: .capture
            ))

            #expect(result.status == .captured)
            #expect(result.captureResults.count == 2)
            #expect(result.captureResults.allSatisfy { $0.item.type == "vaultFile" })
            #expect(Set(result.captureResults.map(\.source.file)) == Set([firstFile.path, secondFile.path]))

            let eventIDs = result.captureResults.compactMap(\.captureEventID)
            #expect(eventIDs.count == 2)
            for eventID in eventIDs {
                #expect(try captureAttachmentCount(db, eventID: eventID) == 2)
            }
        }
    }

    @Test("mixed local and remote chat attachments preserve unsupported remote metadata")
    func mixedLocalAndRemoteChatAttachmentsPreserveUnsupportedRemoteMetadata() throws {
        try withIsolatedVault { db, notes, files in
            let localFile = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("local-upload.txt")
            try "Local attachment".write(to: localFile, atomically: true, encoding: .utf8)

            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                )
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "discord-channel-mixed",
                threadID: nil,
                messageID: "discord-msg-mixed",
                senderID: "discord-user-mixed",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "attachment-local",
                        filename: "local-upload.txt",
                        mimeType: "text/plain",
                        localPath: localFile.path,
                        remoteURL: nil
                    ),
                    ChatAttachment(
                        id: "attachment-remote",
                        filename: "remote-only.pdf",
                        mimeType: "application/pdf",
                        localPath: nil,
                        remoteURL: "https://cdn.discordapp.example/remote-only.pdf"
                    )
                ],
                intent: .capture
            ))

            let capture = try #require(result.captureResult)
            let eventID = try #require(capture.captureEventID)
            #expect(result.status == .captured)
            #expect(result.captureResults.count == 1)
            #expect(try captureAttachmentCount(db, eventID: eventID) == 2)
            #expect(try captureAttachmentRemoteURLs(db, eventID: eventID).contains("https://cdn.discordapp.example/remote-only.pdf"))
        }
    }

    @Test("chat capture persists attachment-level provenance and owner relations")
    func chatCapturePersistsAttachmentLevelProvenanceAndOwnerRelations() throws {
        try withIsolatedVault { db, notes, files in
            let sourceFile = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent("discord-image.png")
            try Data([0x89, 0x50, 0x4e, 0x47]).write(to: sourceFile)

            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                )
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "discord-channel-10",
                threadID: "discord-thread-4",
                messageID: "discord-msg-24",
                senderID: "discord-user-5",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "discord-attachment-24",
                        filename: "discord-image.png",
                        mimeType: "image/png",
                        localPath: sourceFile.path,
                        remoteURL: "https://cdn.discordapp.example/discord-image.png"
                    )
                ],
                intent: .capture
            ))

            let capture = try #require(result.captureResult)
            let eventID = try #require(capture.captureEventID)
            let attachmentStmt = try db.prepare("""
                SELECT id, capture_event_id, attachment_index, source_attachment_id,
                       filename, mime_type, local_path, remote_url, byte_size
                FROM capture_attachments
                WHERE capture_event_id = ?;
                """)
            attachmentStmt.bind(eventID.uuidString, at: 1)
            #expect(try attachmentStmt.step())
            let attachmentID = attachmentStmt.string(at: 0)
            #expect(attachmentStmt.string(at: 1) == eventID.uuidString)
            #expect(attachmentStmt.int(at: 2) == 0)
            #expect(attachmentStmt.string(at: 3) == "discord-attachment-24")
            #expect(attachmentStmt.string(at: 4) == "discord-image.png")
            #expect(attachmentStmt.string(at: 5) == "image/png")
            #expect(attachmentStmt.string(at: 6) == sourceFile.path)
            #expect(attachmentStmt.string(at: 7) == "https://cdn.discordapp.example/discord-image.png")
            #expect(attachmentStmt.int(at: 8) == 4)
            #expect(try !attachmentStmt.step())

            let store = SecondBrainStore(database: db)
            let eventRelations = try store.outgoingRelations(for: SecondBrainOwnerRef(
                ownerType: "capture_event",
                ownerID: eventID.uuidString
            ))
            #expect(eventRelations.contains { relation in
                relation.targetOwner.ownerType == "capture_attachment"
                    && relation.targetOwner.ownerID == attachmentID
                    && relation.relationType == "had_attachment"
            })

            let attachmentBackedItemRelations = try store.outgoingRelations(for: SecondBrainOwnerRef(
                ownerType: "capture_attachment",
                ownerID: attachmentID
            ))
            #expect(attachmentBackedItemRelations.contains { relation in
                relation.targetOwner.ownerID == capture.item.id.uuidString
                    && relation.relationType == "associated_item"
            })
        }
    }

    @Test("remote-only chat attachment records durable review state")
    func remoteOnlyChatAttachmentRecordsDurableReviewState() throws {
        try withIsolatedVault { db, notes, files in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                ),
                database: db
            )

            let result = try service.capture(ChatCaptureInput(
                channel: .discord,
                channelID: "discord-channel-9",
                threadID: nil,
                messageID: "discord-msg-23",
                senderID: "discord-user-4",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "attachment-remote",
                        filename: "remote.pdf",
                        mimeType: "application/pdf",
                        localPath: nil,
                        remoteURL: "https://cdn.discordapp.example/remote.pdf"
                    )
                ],
                intent: .capture
            ))

            #expect(result.status == .needsReview)
            #expect(result.captureResult == nil)
            #expect(result.reason.contains("unsupported attachment"))
            let eventID = try #require(result.captureEventID)
            #expect(result.safeNextCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json"))

            #expect(try captureAttachmentCount(db, eventID: eventID) == 1)
            #expect(try captureAttachmentRemoteURLs(db, eventID: eventID) == ["https://cdn.discordapp.example/remote.pdf"])
            #expect(try unsupportedAttachmentReviewOutputCount(db, eventID: eventID) == 1)
        }
    }

    private func captureAttachmentCount(_ db: CiderDatabase, eventID: UUID) throws -> Int {
        let stmt = try db.prepare("SELECT count(*) FROM capture_attachments WHERE capture_event_id = ?;")
        stmt.bind(eventID.uuidString, at: 1)
        try stmt.step()
        return stmt.int(at: 0)
    }

    private func captureAttachmentRemoteURLs(_ db: CiderDatabase, eventID: UUID) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT remote_url
            FROM capture_attachments
            WHERE capture_event_id = ?
            ORDER BY attachment_index ASC;
            """)
        stmt.bind(eventID.uuidString, at: 1)
        var urls: [String] = []
        while try stmt.step() {
            if let url = stmt.optionalString(at: 0) {
                urls.append(url)
            }
        }
        return urls
    }

    private func captureAttachmentSourceIDs(_ db: CiderDatabase, eventID: UUID) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT source_attachment_id
            FROM capture_attachments
            WHERE capture_event_id = ?
            ORDER BY attachment_index ASC;
            """)
        stmt.bind(eventID.uuidString, at: 1)
        var ids: [String] = []
        while try stmt.step() {
            if let id = stmt.optionalString(at: 0) {
                ids.append(id)
            }
        }
        return ids
    }

    private func unsupportedAttachmentReviewOutputCount(_ db: CiderDatabase, eventID: UUID) throws -> Int {
        let stmt = try db.prepare("""
            SELECT count(*)
            FROM enrichment_outputs
            WHERE owner_type = 'capture_event'
              AND owner_id = ?
              AND kind = 'unsupported_chat_attachment'
              AND review_state = 'needs_review';
            """)
        stmt.bind(eventID.uuidString, at: 1)
        try stmt.step()
        return stmt.int(at: 0)
    }
}
