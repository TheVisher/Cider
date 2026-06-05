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

    @Test("discord runtime update maps explicit save intent into canonical chat capture input")
    func discordRuntimeUpdateMapsExplicitSaveIntentIntoCanonicalChatCaptureInput() throws {
        let update = DiscordUpdateEnvelope(
            messageID: "discord-msg-100",
            channelID: "discord-channel-100",
            threadID: "discord-thread-100",
            senderID: "discord-user-100",
            senderDisplayName: "Erik",
            text: "save this https://example.com/discord-capture",
            attachments: []
        )

        let input = ChatRuntimeCaptureAdapter.input(fromDiscord: update)

        #expect(input?.channel == .discord)
        #expect(input?.channelID == "discord-channel-100")
        #expect(input?.threadID == "discord-thread-100")
        #expect(input?.messageID == "discord:discord-msg-100")
        #expect(input?.senderID == "discord-user-100")
        #expect(input?.senderName == "Erik")
        #expect(input?.intent == .capture)
        #expect(input?.text == "https://example.com/discord-capture")
        #expect(input?.metadata["source_message_id"] == "discord-msg-100")
        #expect(input?.metadata["runtime"] == "discord")
    }

    @Test("discord runtime local attachment save intent preserves attachment metadata")
    func discordRuntimeLocalAttachmentSaveIntentPreservesAttachmentMetadata() throws {
        let update = DiscordUpdateEnvelope(
            messageID: "discord-msg-101",
            channelID: "discord-channel-101",
            threadID: nil,
            senderID: "discord-user-101",
            senderDisplayName: "Erik",
            text: "save this",
            attachments: [
                DiscordAttachmentEnvelope(
                    id: "discord-attachment-101",
                    filename: "receipt.png",
                    mimeType: "image/png",
                    localPath: "/tmp/discord-receipt.png",
                    remoteURL: "https://cdn.discordapp.example/receipt.png"
                )
            ]
        )

        let input = ChatRuntimeCaptureAdapter.input(fromDiscord: update)

        #expect(input?.intent == .capture)
        #expect(input?.text == "")
        let attachment = try #require(input?.attachments.first)
        #expect(attachment.id == "discord-attachment-101")
        #expect(attachment.filename == "receipt.png")
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.localPath == "/tmp/discord-receipt.png")
        #expect(attachment.remoteURL == "https://cdn.discordapp.example/receipt.png")
    }

    @Test("discord runtime remote attachment save intent records unsupported attachment review")
    func discordRuntimeRemoteAttachmentSaveIntentRecordsUnsupportedAttachmentReview() throws {
        try withIsolatedVault { db, notes, files in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                ),
                database: db
            )
            let update = DiscordUpdateEnvelope(
                messageID: "discord-msg-102",
                channelID: "discord-channel-102",
                threadID: nil,
                senderID: "discord-user-102",
                senderDisplayName: "Erik",
                text: "save this",
                attachments: [
                    DiscordAttachmentEnvelope(
                        id: "discord-attachment-102",
                        filename: "remote.pdf",
                        mimeType: "application/pdf",
                        localPath: nil,
                        remoteURL: "https://cdn.discordapp.example/remote.pdf",
                        downloadFailedReason: "discord_attachment_download_failed"
                    )
                ]
            )

            let input = try #require(ChatRuntimeCaptureAdapter.input(fromDiscord: update))
            #expect(input.metadata["attachment_failure_reason"] == "discord_attachment_download_failed")
            let result = try ChatRuntimeCaptureAdapter.captureIfNeeded(
                fromDiscord: update,
                intakeService: service
            )

            #expect(result?.status == .needsReview)
            let eventID = try #require(result?.captureEventID)
            #expect(result?.safeNextCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json") == true)
            #expect(try captureAttachmentSourceIDs(db, eventID: eventID) == ["discord-attachment-102"])
            #expect(try captureAttachmentRemoteURLs(db, eventID: eventID) == ["https://cdn.discordapp.example/remote.pdf"])
            #expect(try unsupportedAttachmentReviewOutputCount(db, eventID: eventID) == 1)
        }
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

    @Test("future chat channel text capture preserves raw channel identity")
    func futureChatChannelTextCapturePreservesRawChannelIdentity() throws {
        try withIsolatedVault { db, notes, _ in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(notesStorage: notes, database: db)
            )
            let channel = try #require(ChatCaptureChannel(rawValue: "matrix"))

            let result = try service.capture(ChatCaptureInput(
                channel: channel,
                channelID: "room-42",
                threadID: "thread-99",
                messageID: "matrix-event-123",
                senderID: "matrix-user-7",
                senderName: "Erik",
                text: "Remember future chat capture provenance.",
                intent: .capture,
                metadata: ["runtime": "matrix-test"]
            ))

            let capture = try #require(result.captureResult)
            let eventID = try #require(capture.captureEventID)
            #expect(capture.sourceContext?.channel == "matrix")

            let stmt = try db.prepare("""
                SELECT surface, channel, channel_id, thread_id, message_id, sender_id, metadata
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "chat")
            #expect(stmt.string(at: 1) == "matrix")
            #expect(stmt.string(at: 2) == "room-42")
            #expect(stmt.string(at: 3) == "thread-99")
            #expect(stmt.string(at: 4) == "matrix-event-123")
            #expect(stmt.string(at: 5) == "matrix-user-7")
            #expect(stmt.string(at: 6).contains("matrix-test"))
        }
    }

    @Test("future chat channel remote attachment review preserves raw channel identity")
    func futureChatChannelRemoteAttachmentReviewPreservesRawChannelIdentity() throws {
        try withIsolatedVault { db, notes, files in
            let service = ChatCaptureIntakeService(
                captureService: CiderCaptureService(
                    notesStorage: notes,
                    vaultFileStorage: files,
                    database: db
                ),
                database: db
            )
            let channel = try #require(ChatCaptureChannel(rawValue: "matrix"))

            let result = try service.capture(ChatCaptureInput(
                channel: channel,
                channelID: "room-attachments",
                threadID: nil,
                messageID: "matrix-event-remote",
                senderID: "matrix-user-8",
                senderName: "Erik",
                text: "   ",
                attachments: [
                    ChatAttachment(
                        id: "matrix-file-1",
                        filename: "future.pdf",
                        mimeType: "application/pdf",
                        localPath: nil,
                        remoteURL: "mxc://server/future"
                    )
                ],
                intent: .capture,
                metadata: ["runtime": "matrix-test"]
            ))

            #expect(result.status == .needsReview)
            let eventID = try #require(result.captureEventID)
            #expect(result.safeNextCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json"))
            #expect(try captureAttachmentSourceIDs(db, eventID: eventID) == ["matrix-file-1"])
            #expect(try captureAttachmentRemoteURLs(db, eventID: eventID) == ["mxc://server/future"])

            let stmt = try db.prepare("""
                SELECT source_kind, surface, channel, channel_id, message_id, metadata
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "chat_unsupported_attachment")
            #expect(stmt.string(at: 1) == "chat")
            #expect(stmt.string(at: 2) == "matrix")
            #expect(stmt.string(at: 3) == "room-attachments")
            #expect(stmt.string(at: 4) == "matrix-event-remote")
            #expect(stmt.string(at: 5).contains("matrix-test"))
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

    @Test("chat capture acknowledgement includes saved item type title and destination")
    func chatCaptureAcknowledgementIncludesSavedItemTypeTitleAndDestination() {
        let result = ChatCaptureIntakeResult(
            status: .captured,
            reason: "Captured through canonical capture service.",
            captureResult: makeCaptureResult(itemType: "note", title: "Graph-safe chat intake", relativePath: "Inbox/Notes/Graph-safe chat intake.md"),
            captureResults: [
                makeCaptureResult(itemType: "note", title: "Graph-safe chat intake", relativePath: "Inbox/Notes/Graph-safe chat intake.md")
            ]
        )

        #expect(result.compactAcknowledgement == "Saved note: Graph-safe chat intake. Inbox/Notes/Graph-safe chat intake.md.")
    }

    @Test("chat capture acknowledgement calls out duplicate and partial states")
    func chatCaptureAcknowledgementCallsOutDuplicateAndPartialStates() {
        let duplicate = ChatCaptureIntakeResult(
            status: .captured,
            reason: "Captured through canonical capture service.",
            captureResult: makeCaptureResult(
                itemType: "bookmark",
                title: "Cider",
                relativePath: "Inbox/Cider.md",
                duplicate: .init(status: "duplicate", existingItemID: UUID(), reason: "URL already exists", evidence: "normalized_url")
            ),
            captureResults: []
        )
        let partial = ChatCaptureIntakeResult(
            status: .captured,
            reason: "Captured through canonical capture service.",
            captureResult: makeCaptureResult(
                itemType: "vaultFile",
                title: "scan.pdf",
                relativePath: "Inbox/Files/scan.pdf",
                indexing: .init(status: "failed", reason: "Could not index PDF", ownerType: "vaultFile", ownerID: UUID().uuidString, captureEventID: UUID())
            ),
            captureResults: []
        )

        #expect(duplicate.compactAcknowledgement.contains("Duplicate bookmark: Cider."))
        #expect(partial.compactAcknowledgement.contains("Saved file: scan.pdf."))
        #expect(partial.compactAcknowledgement.contains("Partial save: Could not index PDF."))
    }

    @Test("chat capture acknowledgement summarizes multiple local attachments")
    func chatCaptureAcknowledgementSummarizesMultipleLocalAttachments() {
        let first = makeCaptureResult(itemType: "vaultFile", title: "first-upload.txt", relativePath: "Inbox/Files/first-upload.txt")
        let second = makeCaptureResult(itemType: "vaultFile", title: "second-upload.txt", relativePath: "Inbox/Files/second-upload.txt")
        let result = ChatCaptureIntakeResult(
            status: .captured,
            reason: "Captured 2 local chat attachments through canonical capture service.",
            captureResult: first,
            captureResults: [first, second]
        )

        #expect(result.compactAcknowledgement == "Saved 2 files. First: first-upload.txt. Review each receipt if routing looks off.")
    }

    @Test("chat capture acknowledgement includes review event context for unsupported attachments")
    func chatCaptureAcknowledgementIncludesReviewEventContextForUnsupportedAttachments() {
        let eventID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let result = ChatCaptureIntakeResult(
            status: .needsReview,
            reason: "Chat message contains unsupported attachment content without a local file path; Cider recorded it for review.",
            captureResult: nil,
            captureEventID: eventID,
            safeNextCommands: ["cider-cli item backlinks capture_event \(eventID.uuidString) --json"]
        )

        #expect(result.compactAcknowledgement.contains("Needs review: unsupported chat attachment recorded."))
        #expect(result.compactAcknowledgement.contains(eventID.uuidString))
        #expect(result.compactAcknowledgement.contains("cider-cli item backlinks capture_event"))
    }

    @Test("chat capture acknowledgement keeps no-capture review compact")
    func chatCaptureAcknowledgementKeepsNoCaptureReviewCompact() {
        let result = ChatCaptureIntakeResult(
            status: .needsReview,
            reason: "No captureable text or supported attachment content was provided.",
            captureResult: nil
        )

        #expect(result.compactAcknowledgement == "Needs review: No captureable text or supported attachment content was provided.")
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

    private func makeCaptureResult(
        itemType: String,
        title: String,
        relativePath: String,
        duplicate: CiderCaptureResult.Duplicate = .init(status: "new", existingItemID: nil),
        indexing: CiderCaptureResult.SideEffectStatus = .init(
            status: "indexed",
            reason: nil,
            ownerType: "note",
            ownerID: UUID().uuidString,
            captureEventID: UUID()
        )
    ) -> CiderCaptureResult {
        let itemID = UUID()
        return CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: itemType == "bookmark" ? "url" : itemType,
                url: itemType == "bookmark" ? "https://example.com" : nil,
                file: itemType == "vaultFile" ? "/tmp/\(title)" : nil,
                text: itemType == "note" ? title : nil,
                itemID: itemID,
                itemType: itemType
            ),
            item: .init(
                id: itemID,
                type: itemType,
                title: title,
                relativePath: relativePath,
                folderID: nil,
                folderName: "Inbox"
            ),
            enrichment: .init(
                status: "not_applicable",
                isEnriching: false,
                titleState: "manual",
                lastEnrichedAt: nil
            ),
            duplicate: duplicate,
            routing: .init(
                decisionID: nil,
                candidateTarget: nil,
                reviewNeeded: false,
                confidence: 1,
                reason: "Confident route.",
                reviewState: "not_needed",
                status: "not_applicable",
                statusReason: nil
            ),
            nextSafeAction: "inspect_item",
            captureEventID: UUID(),
            provenance: .init(
                status: "recorded",
                reason: nil,
                ownerType: itemType,
                ownerID: itemID.uuidString,
                captureEventID: UUID()
            ),
            indexing: indexing
        )
    }
}
