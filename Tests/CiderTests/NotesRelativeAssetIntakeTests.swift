import Foundation
import Testing
@testable import Cider

@Suite("Notes Relative Asset Intake Tests")
@MainActor
struct NotesRelativeAssetIntakeTests {
    @Test("local image import preserves bytes and exact portable relative Markdown")
    func imageRoundTrip() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("image.png", NotesAssetFixture.pngData)
        let result = try await fixture.service.importLocalImage(
            at: source,
            noteID: fixture.noteID,
            noteDirectoryURL: fixture.notesRoot
        ) { prepared in prepared }

        #expect(result.persistedReference.hasPrefix("./.attachments/"))
        #expect(!result.persistedReference.contains(fixture.root.path))
        #expect(!result.persistedReference.contains("file://"))
        #expect(try Data(contentsOf: result.fileURL) == NotesAssetFixture.pngData)
        let markdown = "![image](\(result.editorReference))"
        let persisted = NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: fixture.notesRoot)
        #expect(persisted == "![image](\(result.persistedReference))")
        #expect(NotesMarkdownPathCodec.markdownForEditor(persisted, notesDirectoryURL: fixture.notesRoot) == markdown)
        #expect(try fixture.databaseFingerprint().isEmpty)
    }

    @Test("local text and Markdown imports validate under balanced scope and preserve exact UTF-8")
    func textRoundTripAndScopeBalance() throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let content = "# Exact Markdown\n\nUnicode: café 🚗\n"
        let source = try fixture.write("entry.md", Data(content.utf8))
        let tracker = NotesAssetScopeTracker()
        let service = fixture.makeService(validator: LocalFileIntakeValidator(hooks: .init(
            startAccessingSecurityScopedResource: tracker.start,
            stopAccessingSecurityScopedResource: tracker.stop,
            beforeFileRead: tracker.read
        )))

        let loaded = try service.loadLocalText(at: source)
        #expect(loaded.content == content)
        #expect(loaded.metadata.sha256 == LocalFileIntakeValidator.sha256(Data(content.utf8)))
        #expect(tracker.isBalanced)
        #expect(tracker.active.isEmpty)
        #expect(tracker.reads.allSatisfy { $0.wasActive })
        #expect(try fixture.filesystemFingerprint() == ["file:Note.md:\(LocalFileIntakeValidator.sha256(Data("original note".utf8)))"])
        #expect(try fixture.databaseFingerprint().isEmpty)
    }

    @Test("payload and finalize failure roll back only the newly created asset")
    func payloadFailureRollsBack() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("image.png", NotesAssetFixture.pngData)
        let filesystemBefore = try fixture.filesystemFingerprint()
        let noteBefore = try Data(contentsOf: fixture.noteURL)
        let databaseBefore = try fixture.databaseFingerprint()

        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await fixture.service.importLocalImage(
                at: source,
                noteID: fixture.noteID,
                noteDirectoryURL: fixture.notesRoot
            ) { _ in throw NotesAssetInjectedFailure.payload }
        }
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try Data(contentsOf: fixture.noteURL) == noteBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("decode failure leaves filesystem note and database fingerprints unchanged")
    func decodeFailureIsNonMutating() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("broken.png", Data("not an image".utf8))
        let filesystemBefore = try fixture.filesystemFingerprint()
        let noteBefore = try Data(contentsOf: fixture.noteURL)
        let databaseBefore = try fixture.databaseFingerprint()

        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await fixture.service.importLocalImage(
                at: source,
                noteID: fixture.noteID,
                noteDirectoryURL: fixture.notesRoot
            ) { prepared in prepared }
        }
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try Data(contentsOf: fixture.noteURL) == noteBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("source mutation and destination redirect fail closed without partial directories")
    func sourceMutationAndDestinationRedirectFailClosed() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("image.png", NotesAssetFixture.pngData)
        let mutationService = fixture.makeService(validator: LocalFileIntakeValidator(hooks: .init(afterInitialSnapshot: {
            try Data("changed".utf8).write(to: source, options: .atomic)
        })))
        let before = try fixture.filesystemFingerprint()
        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await mutationService.importLocalImage(at: source, noteID: fixture.noteID, noteDirectoryURL: fixture.notesRoot) { $0 }
        }
        #expect(try fixture.filesystemFingerprint() == before)

        try NotesAssetFixture.pngData.write(to: source, options: .atomic)
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let attachments = fixture.notesRoot.appendingPathComponent(".attachments", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: outside)
        let redirectedBefore = try fixture.filesystemFingerprint()
        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await fixture.service.importLocalImage(at: source, noteID: fixture.noteID, noteDirectoryURL: fixture.notesRoot) { $0 }
        }
        #expect(try fixture.filesystemFingerprint() == redirectedBefore)
        #expect((try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty)
    }

    @Test("destination component replacement during materialization fails closed without redirected writes")
    func destinationComponentReplacementFailsClosed() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("image.png", NotesAssetFixture.pngData)
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let before = try fixture.filesystemFingerprint()
        let service = fixture.makeService(materializationHooks: .init(afterCopy: { _ in
            let attachments = fixture.notesRoot.appendingPathComponent(".attachments", isDirectory: true)
            try FileManager.default.removeItem(at: attachments)
            try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: outside)
        }))

        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await service.importLocalImage(
                at: source,
                noteID: fixture.noteID,
                noteDirectoryURL: fixture.notesRoot
            ) { $0 }
        }
        #expect(try fixture.filesystemFingerprint() == before)
        #expect((try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty)
    }

    @Test("collision retry and physical reopen preserve one exact asset identity")
    func retryAndReopenIdentity() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("same name.png", NotesAssetFixture.pngData)
        let first = try await fixture.service.importLocalImage(at: source, noteID: fixture.noteID, noteDirectoryURL: fixture.notesRoot) { $0 }
        let retry = try await fixture.makeService().importLocalImage(at: source, noteID: fixture.noteID, noteDirectoryURL: fixture.notesRoot) { $0 }
        #expect(retry.fileURL == first.fileURL)
        #expect(retry.persistedReference == first.persistedReference)
        #expect(retry.wasReused)

        let changed = try fixture.write("same name copy.png", Data(NotesAssetFixture.pngData + Data([0])))
        let collision = try await fixture.makeService().importLocalImage(at: changed, noteID: fixture.noteID, noteDirectoryURL: fixture.notesRoot, displayName: "same name.png") { $0 }
        #expect(collision.fileURL != first.fileURL)
        #expect(collision.fileURL.lastPathComponent.hasSuffix("same name.png"))
        let attachmentFiles = try FileManager.default.contentsOfDirectory(atPath: first.fileURL.deletingLastPathComponent().path)
        #expect(attachmentFiles.count == 2)
    }

    @Test("Notes does not create VaultFile rows or inherit Chat byte limits")
    func noVaultFileIdentityOrChatLimitLeakage() throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        let largeText = String(repeating: "N", count: Int(AgentRoomsAttachmentService.maximumTextByteSize + 1))
        let source = try fixture.write("large.md", Data(largeText.utf8))
        let loaded = try fixture.service.loadLocalText(at: source)
        #expect(loaded.content == largeText)
        #expect(try fixture.databaseFingerprint().isEmpty)
    }

    @Test("production editor transaction restores exact JS and VM state for every staged failure")
    func productionEditorTransactionRollsBackEveryStage() async throws {
        for failure in NotesTransactionFailure.allCases {
            let fixture = try NotesAssetFixture()
            defer { fixture.cleanup() }
            try Data("disk truth".utf8).write(to: fixture.noteURL, options: .atomic)
            let source = try fixture.write("image.png", NotesAssetFixture.pngData)
            let fake = try NotesTransactionFake(fixture: fixture, failure: failure)
            let snapshot = fake.state
            let filesystemBefore = try fixture.filesystemFingerprint()
            let databaseBefore = try fake.databaseFingerprint()

            await #expect(throws: NotesRelativeAssetIntakeError.self) {
                try await fixture.service.importLocalImage(
                    at: source,
                    noteID: fixture.noteID,
                    noteDirectoryURL: fixture.notesRoot
                ) { asset in
                    try await NotesEditorImageTransactionCoordinator().perform(
                        asset: asset,
                        alt: "image.png",
                        operations: fake.operations
                    )
                }
            }

            #expect(fake.editorMarkdown == snapshot.editorMarkdown)
            #expect(fake.syncPushCount == 0)
            #expect(try fake.databaseFingerprint() == databaseBefore)
            #expect(fake.state.selectedNote.id == snapshot.selectedNote.id)
            #expect(fake.state.editingContent == snapshot.editingContent)
            #expect(fake.state.lastSyncedDiskContent == snapshot.lastSyncedDiskContent)
            #expect(fake.state.hasPendingSave == snapshot.hasPendingSave)
            #expect(fake.state.isLoadingNote == snapshot.isLoadingNote)
            #expect(fake.state.hadScheduledSave == snapshot.hadScheduledSave)
            #expect(fake.scheduledSaveMarkdown == snapshot.editorMarkdown)
            if failure == .externalChange {
                #expect(try String(contentsOf: fixture.noteURL, encoding: .utf8) == NotesTransactionFake.externalDiskContent)
                #expect(fake.state.externalChangeState != nil)
                #expect(fake.state.pendingExternalDiskContent == NotesTransactionFake.externalDiskContent)
                #expect(try fixture.filesystemFingerprint().allSatisfy { !$0.contains(".attachments") })
            } else {
                #expect(fake.state == snapshot)
                #expect(try fixture.filesystemFingerprint() == filesystemBefore)
            }
        }
    }

    @Test("production editor transaction persists portable parity pushes sync once and leaves no delayed overwrite")
    func productionEditorTransactionSuccessAndSubsequentFlush() async throws {
        let fixture = try NotesAssetFixture()
        defer { fixture.cleanup() }
        try Data("disk truth".utf8).write(to: fixture.noteURL, options: .atomic)
        let source = try fixture.write("image.png", NotesAssetFixture.pngData)
        let fake = try NotesTransactionFake(fixture: fixture, failure: nil)

        let persisted = try await fixture.service.importLocalImage(
            at: source,
            noteID: fixture.noteID,
            noteDirectoryURL: fixture.notesRoot
        ) { asset in
            try await NotesEditorImageTransactionCoordinator().perform(
                asset: asset,
                alt: "image.png",
                operations: fake.operations
            )
        }

        #expect(persisted.contains("./.attachments/"))
        #expect(!persisted.contains("cider-vault://"))
        #expect(!persisted.contains(fixture.root.path))
        #expect(fake.state.selectedNote.content == persisted)
        #expect(fake.state.editingContent == persisted)
        #expect(fake.state.lastSyncedDiskContent == persisted)
        #expect(try String(contentsOf: fixture.noteURL, encoding: .utf8) == persisted)
        #expect(fake.syncPushCount == 1)
        #expect(fake.persistCount == 1)
        #expect(!fake.state.hadScheduledSave)
        #expect(fake.scheduledSaveMarkdown == nil)

        let afterNextEdit = persisted + "\nnext edit"
        try fake.simulateSubsequentEditAndFlush(afterNextEdit)
        let diskAfterFlush = try String(contentsOf: fixture.noteURL, encoding: .utf8)
        #expect(diskAfterFlush == afterNextEdit)
        #expect(diskAfterFlush.components(separatedBy: "![image.png]").count - 1 == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.notesRoot.appendingPathComponent(".attachments").path).count == 1)
    }

    @Test("NotesViewModel production call site uses the transaction coordinator")
    func productionViewModelUsesCoordinator() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("imageTransactionCoordinator.perform("))
        #expect(source.contains("insertAndPersistPreparedImage"))
        #expect(source.contains("scheduleRestoredImageTransactionSave(snapshot)"))
    }

    @Test("TipTap load normalization never becomes disk truth or hides a real local edit")
    func editorNormalizationStaysSeparateFromDiskTruth() {
        let disk = "<p style=\"text-align: center\">![image](./image.png)</p>"
        let normalized = "![image](./image.png)"
        #expect(!NotesEditorDiskTruthPolicy.hasUnsavedLocalChanges(
            editingContent: normalized,
            lastSyncedDiskContent: disk,
            lastLoadedEditorNormalizedContent: normalized
        ))
        #expect(NotesEditorDiskTruthPolicy.hasUnsavedLocalChanges(
            editingContent: normalized + "\nunsynced keystroke",
            lastSyncedDiskContent: disk,
            lastLoadedEditorNormalizedContent: normalized
        ))
    }

    @Test("real NotesStorage image persistence compensates every injected determinate failure")
    func realNotesStorageCompensatesDeterminateFailures() async throws {
        let stages: [NotesStorage.ImageTransactionStage] = [
            .beforeFileReplace,
            .afterFileReplaceBeforeDatabase,
            .insideCanonicalDatabasePersist,
            .insideContentIndexRebuild,
            .postPersistVerification,
        ]

        for stage in stages {
            let fixture = try NotesCanonicalPersistenceFixture(failingStages: [stage])
            defer { fixture.cleanup() }
            let before = try fixture.completeFingerprint()
            let memoryBefore = try #require(fixture.storage.notes.first { $0.id == fixture.note.id })
            let cacheBefore = fixture.storage.cachedContentForTesting(noteID: fixture.note.id)

            do {
                _ = try await fixture.performImageTransaction()
                Issue.record("Expected injected \(stage) failure")
            } catch let error as NotesRelativeAssetIntakeError {
                #expect(error.code == .payloadFailed)
            }

            #expect(try fixture.completeFingerprint() == before)
            let memoryAfter = fixture.storage.notes.first { $0.id == fixture.note.id }
            #expect(memoryAfter == memoryBefore)
            #expect(fixture.storage.cachedContentForTesting(noteID: fixture.note.id) == cacheBefore)
            #expect(fixture.harness.syncPushCount == 0)
            #expect(!fixture.storage.hasPendingAttachmentCleanupForTesting)
            #expect(!FileManager.default.fileExists(atPath: fixture.attachmentsURL.path))
        }
    }

    @Test("real NotesStorage fails closed when disk changes immediately before replacement")
    func realNotesStorageRejectsExternalDiskChangeBeforeReplace() async throws {
        let externalBytes = Data("external disk bytes win\n".utf8)
        let fixture = try NotesCanonicalPersistenceFixture(stageAction: { stage, fixtureNoteURL in
            if stage == .beforeFileReplace {
                try externalBytes.write(to: fixtureNoteURL, options: .atomic)
            }
        })
        defer { fixture.cleanup() }
        let databaseBefore = try fixture.databaseFingerprint()
        let memoryBefore = fixture.storage.notes.first { $0.id == fixture.note.id }
        let cacheBefore = fixture.storage.cachedContentForTesting(noteID: fixture.note.id)

        await #expect(throws: NotesRelativeAssetIntakeError.self) {
            try await fixture.performImageTransaction()
        }

        #expect(try Data(contentsOf: fixture.noteURL) == externalBytes)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(fixture.storage.notes.first { $0.id == fixture.note.id } == memoryBefore)
        #expect(fixture.storage.cachedContentForTesting(noteID: fixture.note.id) == cacheBefore)
        #expect(fixture.harness.syncPushCount == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.attachmentsURL.path))
    }

    @Test("indeterminate compensation retains a potentially referenced asset and never reports success")
    func indeterminateCompensationRetainsAsset() async throws {
        let fixture = try NotesCanonicalPersistenceFixture(
            failingStages: [.postPersistVerification, .beforeCompensationRestore]
        )
        defer { fixture.cleanup() }
        let databaseBefore = try fixture.databaseFingerprint()
        let memoryBefore = try #require(fixture.storage.notes.first { $0.id == fixture.note.id })
        let cacheBefore = fixture.storage.cachedContentForTesting(noteID: fixture.note.id)
        var receivedCode: NotesRelativeAssetIntakeError.Code?

        do {
            _ = try await fixture.performImageTransaction()
            Issue.record("Indeterminate compensation must not report success")
        } catch let error as NotesRelativeAssetIntakeError {
            receivedCode = error.code
        }

        #expect(receivedCode == .persistenceIndeterminate)
        let disk = try String(contentsOf: fixture.noteURL, encoding: .utf8)
        #expect(disk.contains("./.attachments/"))
        #expect(!disk.contains("cider-vault://"))
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        let memoryAfter = fixture.storage.notes.first { $0.id == fixture.note.id }
        #expect(memoryAfter == memoryBefore)
        #expect(fixture.storage.cachedContentForTesting(noteID: fixture.note.id) == cacheBefore)
        #expect(fixture.harness.syncPushCount == 0)
        #expect(!fixture.storage.hasPendingAttachmentCleanupForTesting)
        let retained = try FileManager.default.contentsOfDirectory(at: fixture.attachmentsURL, includingPropertiesForKeys: nil)
        #expect(retained.count == 1)
        #expect(disk.contains(retained[0].lastPathComponent))
        print(
            "CID836_NOTES_INDETERMINATE "
                + "diskSHA256=\(LocalFileIntakeValidator.sha256(Data(disk.utf8))) "
                + "sqliteProjectionSHA256=\(fixture.fingerprintDigest(databaseBefore)) "
                + "assetSHA256=\(LocalFileIntakeValidator.sha256(try Data(contentsOf: retained[0]))) "
                + "syncPushes=\(fixture.harness.syncPushCount) retainedAssets=\(retained.count)"
        )
    }

    @Test("real NotesStorage success publishes one file row chunk asset and survives physical reopen")
    func realNotesStorageSuccessAndPhysicalReopen() async throws {
        let fixture = try NotesCanonicalPersistenceFixture()
        defer { fixture.cleanup() }

        let persisted = try await fixture.performImageTransaction()
        let committed = try #require(fixture.storage.notes.first { $0.id == fixture.note.id })
        #expect(persisted.contains("./.attachments/"))
        #expect(!persisted.contains("cider-vault://"))
        #expect(!persisted.contains(fixture.root.path))
        #expect(try Data(contentsOf: fixture.noteURL) == Data(persisted.utf8))
        #expect(committed.content == persisted)
        #expect(fixture.storage.cachedContentForTesting(noteID: fixture.note.id) == persisted)
        #expect(fixture.harness.syncPushCount == 1)
        #expect(fixture.storage.hasPendingAttachmentCleanupForTesting)
        #expect(try fixture.canonicalRowCount() == 1)
        #expect(try fixture.chunkBodies().count == 1)
        #expect(try fixture.chunkBodies()[0].contains(persisted))
        let assets = try FileManager.default.contentsOfDirectory(at: fixture.attachmentsURL, includingPropertiesForKeys: nil)
        #expect(assets.count == 1)
        #expect(persisted.contains(assets[0].lastPathComponent))

        let successFingerprint = try fixture.completeFingerprint()
        fixture.database.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.databaseURL)
        defer { reopenedDatabase.close() }
        let reopened = NotesStorage(
            database: reopenedDatabase,
            notesDirectoryURL: fixture.notesRoot,
            vaultRootURL: fixture.vaultRoot
        )
        reopened.loadNotesFromDatabase(reopenedDatabase)
        let reopenedNote = try #require(reopened.notes.first { $0.id == fixture.note.id })
        #expect(reopenedNote.content == persisted)
        #expect(reopened.loadContent(for: reopenedNote) == persisted)
        let reopenedDatabaseFingerprint = try fixture.databaseFingerprint(reopenedDatabase)
        #expect(reopenedDatabaseFingerprint == fixture.databaseFingerprintSnapshot(from: successFingerprint))
        #expect(try Data(contentsOf: fixture.noteURL) == Data(persisted.utf8))
        #expect(try LocalFileIntakeValidator.sha256(Data(contentsOf: assets[0])) == fixture.assetHash)
        let chunkBodies = try fixture.chunkBodies(reopenedDatabase)
        print(
            "CID836_NOTES_SUCCESS "
                + "diskSHA256=\(LocalFileIntakeValidator.sha256(Data(persisted.utf8))) "
                + "sqliteProjectionSHA256=\(fixture.fingerprintDigest(reopenedDatabaseFingerprint)) "
                + "chunkSHA256=\(fixture.fingerprintDigest(chunkBodies)) "
                + "assetSHA256=\(fixture.assetHash) rows=1 chunks=\(chunkBodies.count) assets=\(assets.count) "
                + "syncPushes=\(fixture.harness.syncPushCount) reopenParity=true"
        )
    }
}

private enum NotesAssetInjectedFailure: Error { case payload }

private enum NotesCanonicalPersistenceInjectedFailure: Error { case stage(NotesStorage.ImageTransactionStage) }

private enum NotesTransactionFailure: CaseIterable {
    case insert
    case getContent
    case save
    case selectionChange
    case externalChange
}

@MainActor
private final class NotesTransactionFake {
    static let externalDiskContent = "external disk divergence"
    let fixture: NotesAssetFixture
    let failure: NotesTransactionFailure?
    var state: NotesEditorImageTransactionSnapshot
    var editorMarkdown: String
    var syncPushCount = 0
    var persistCount = 0
    var scheduledSaveMarkdown: String?
    private var rows = ["note-row:disk truth", "chunk:disk truth"]

    init(fixture: NotesAssetFixture, failure: NotesTransactionFailure?) throws {
        self.fixture = fixture
        self.failure = failure
        let note = Note(
            id: fixture.noteID,
            title: "Note",
            content: "disk truth",
            modifiedAt: Date(timeIntervalSince1970: 10),
            relativePath: "Note.md"
        )
        let editor = "JS exact unsynced keystrokes"
        self.editorMarkdown = editor
        self.state = NotesEditorImageTransactionSnapshot(
            editorMarkdown: editor,
            persistedDiskContent: "disk truth",
            selectedNote: note,
            editingContent: "Swift bridge is one keystroke behind",
            charCount: 37,
            lastSyncedDiskContent: "disk truth",
            lastLoadedEditorNormalizedContent: nil,
            pendingExternalDiskContent: "previous pending external",
            ignoredExternalDiskContent: "previous ignored external",
            externalChangeState: nil,
            hasPendingSave: true,
            isLoadingNote: false,
            hadScheduledSave: true,
            lastRichEditorPushedMarkdown: "disk truth"
        )
        self.scheduledSaveMarkdown = editor
    }

    var operations: NotesEditorImageTransactionCoordinator.Operations {
        .init(
            captureSnapshot: { [self] in state },
            prepareForMutation: { [self] _ in
                state = state.replacing(hadScheduledSave: false)
                scheduledSaveMarkdown = nil
            },
            validateCurrentState: { [self] snapshot in
                guard state.selectedNote.id == snapshot.selectedNote.id,
                      state.externalChangeState == nil,
                      try String(contentsOf: fixture.noteURL, encoding: .utf8) == snapshot.persistedDiskContent else {
                    throw NotesRelativeAssetIntakeError(.payloadFailed)
                }
            },
            insertImage: { [self] asset, alt in
                editorMarkdown += "\n![\(alt)](\(asset.editorReference))"
                switch failure {
                case .insert:
                    throw NotesRelativeAssetIntakeError(.payloadFailed)
                case .selectionChange:
                    state = state.replacing(selectedNote: Note(title: "Other", content: "other"))
                case .externalChange:
                    try Self.externalDiskContent.write(to: fixture.noteURL, atomically: true, encoding: .utf8)
                    state = state.replacing(
                        pendingExternalDiskContent: Self.externalDiskContent,
                        externalChangeState: NotesExternalChangeState(modifiedAt: Date(timeIntervalSince1970: 20))
                    )
                default:
                    break
                }
            },
            capturePostInsertMarkdown: { [self] in
                if failure == .getContent { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                return editorMarkdown
            },
            portableMarkdown: { [self] markdown, _ in
                NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: fixture.notesRoot)
            },
            persist: { [self] persisted, _ in
                if failure == .save { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                persistCount += 1
                try persisted.write(to: fixture.noteURL, atomically: true, encoding: .utf8)
                rows = ["note-row:\(persisted)", "chunk:\(persisted)"]
            },
            applySuccess: { [self] persisted, snapshot in
                var note = snapshot.selectedNote
                note.content = persisted
                state = snapshot.replacing(
                    editorMarkdown: editorMarkdown,
                    persistedDiskContent: persisted,
                    selectedNote: note,
                    editingContent: persisted,
                    charCount: persisted.count,
                    lastSyncedDiskContent: persisted,
                    pendingExternalDiskContent: .some(nil),
                    ignoredExternalDiskContent: .some(nil),
                    externalChangeState: .some(nil),
                    hasPendingSave: false,
                    isLoadingNote: false,
                    hadScheduledSave: false
                )
                scheduledSaveMarkdown = nil
            },
            pushAfterLocalChange: { [self] in syncPushCount += 1 },
            restoreEditor: { [self] markdown, _ in editorMarkdown = markdown },
            restoreState: { [self] snapshot in
                state = snapshot
                scheduledSaveMarkdown = snapshot.hadScheduledSave ? snapshot.editorMarkdown : nil
            },
            refreshExternalChangeState: { [self] snapshot in
                let disk = try String(contentsOf: fixture.noteURL, encoding: .utf8)
                if disk != snapshot.persistedDiskContent {
                    state = state.replacing(
                        pendingExternalDiskContent: disk,
                        externalChangeState: NotesExternalChangeState(modifiedAt: Date(timeIntervalSince1970: 20))
                    )
                }
            }
        )
    }

    func databaseFingerprint() throws -> [String] { rows }

    func simulateSubsequentEditAndFlush(_ markdown: String) throws {
        editorMarkdown = NotesMarkdownPathCodec.markdownForEditor(markdown, notesDirectoryURL: fixture.notesRoot)
        try markdown.write(to: fixture.noteURL, atomically: true, encoding: .utf8)
        rows = ["note-row:\(markdown)", "chunk:\(markdown)"]
        var note = state.selectedNote
        note.content = markdown
        state = state.replacing(
            selectedNote: note,
            editingContent: markdown,
            charCount: markdown.count,
            lastSyncedDiskContent: markdown,
            hasPendingSave: false,
            hadScheduledSave: false
        )
    }
}

private final class NotesAssetScopeTracker {
    struct Read { let wasActive: Bool }
    var active: [URL: Int] = [:]
    var starts: [URL] = []
    var stops: [URL] = []
    var reads: [Read] = []
    var isBalanced: Bool { Dictionary(grouping: starts, by: { $0 }).mapValues(\.count) == Dictionary(grouping: stops, by: { $0 }).mapValues(\.count) }
    func start(_ url: URL) -> Bool { starts.append(url); active[url, default: 0] += 1; return true }
    func stop(_ url: URL) { stops.append(url); active[url, default: 0] -= 1; if active[url] == 0 { active.removeValue(forKey: url) } }
    func read(_ accessURL: URL, _: URL) { reads.append(.init(wasActive: (active[accessURL] ?? 0) > 0)) }
}

@MainActor
private final class NotesCanonicalTransactionHarness {
    let storage: NotesStorage
    let noteURL: URL
    let notesRoot: URL
    var state: NotesEditorImageTransactionSnapshot
    var editorMarkdown: String
    var syncPushCount = 0

    init(storage: NotesStorage, note: Note, noteURL: URL, notesRoot: URL, diskContent: String) {
        self.storage = storage
        self.noteURL = noteURL
        self.notesRoot = notesRoot
        self.editorMarkdown = diskContent
        self.state = .init(
            editorMarkdown: diskContent,
            persistedDiskContent: diskContent,
            selectedNote: note,
            editingContent: diskContent,
            charCount: diskContent.count,
            lastSyncedDiskContent: diskContent,
            lastLoadedEditorNormalizedContent: nil,
            pendingExternalDiskContent: nil,
            ignoredExternalDiskContent: nil,
            externalChangeState: nil,
            hasPendingSave: false,
            isLoadingNote: false,
            hadScheduledSave: false,
            lastRichEditorPushedMarkdown: diskContent
        )
    }

    var operations: NotesEditorImageTransactionCoordinator.Operations {
        .init(
            captureSnapshot: { [self] in state },
            prepareForMutation: { _ in },
            validateCurrentState: { [self] snapshot in
                guard state.selectedNote.id == snapshot.selectedNote.id,
                      try Data(contentsOf: noteURL) == Data(snapshot.persistedDiskContent.utf8) else {
                    throw NotesRelativeAssetIntakeError(.payloadFailed)
                }
            },
            insertImage: { [self] asset, alt in
                editorMarkdown += "\n![\(alt)](\(asset.editorReference))"
            },
            capturePostInsertMarkdown: { [self] in editorMarkdown },
            portableMarkdown: { [self] markdown, _ in
                NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: notesRoot)
            },
            persist: { [self] persisted, snapshot in
                var updated = snapshot.selectedNote
                updated.content = persisted
                _ = try storage.persistImageTransaction(
                    note: updated,
                    expected: .init(
                        noteID: snapshot.selectedNote.id,
                        fileURL: noteURL,
                        previousFile: .bytes(Data(snapshot.persistedDiskContent.utf8))
                    )
                )
            },
            applySuccess: { [self] persisted, snapshot in
                let committed = storage.notes.first { $0.id == snapshot.selectedNote.id } ?? snapshot.selectedNote
                state = snapshot.replacing(
                    editorMarkdown: editorMarkdown,
                    persistedDiskContent: persisted,
                    selectedNote: committed,
                    editingContent: persisted,
                    charCount: persisted.count,
                    lastSyncedDiskContent: persisted,
                    hasPendingSave: false,
                    hadScheduledSave: false
                )
            },
            pushAfterLocalChange: { [self] in syncPushCount += 1 },
            restoreEditor: { [self] markdown, _ in editorMarkdown = markdown },
            restoreState: { [self] snapshot in state = snapshot },
            refreshExternalChangeState: { _ in }
        )
    }
}

@MainActor
private final class NotesCanonicalPersistenceFixture {
    let root: URL
    let vaultRoot: URL
    let notesRoot: URL
    let noteURL: URL
    let attachmentsURL: URL
    let databaseURL: URL
    let database: CiderDatabase
    let note: Note
    let storage: NotesStorage
    let harness: NotesCanonicalTransactionHarness
    let intake: NotesRelativeAssetIntakeService
    let sourceURL: URL
    let assetHash = LocalFileIntakeValidator.sha256(NotesAssetFixture.pngData)
    private static let priorContent = "exact prior disk bytes\n"

    init(
        failingStages: Set<NotesStorage.ImageTransactionStage> = [],
        stageAction: ((NotesStorage.ImageTransactionStage, URL) throws -> Void)? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-notes-canonical-\(UUID().uuidString)", isDirectory: true)
        let vaultRoot = root.appendingPathComponent("Vault", isDirectory: true)
        let notesRoot = vaultRoot.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = notesRoot.appendingPathComponent("Atomic Note.md")
        let attachmentsURL = notesRoot.appendingPathComponent(".attachments", isDirectory: true)
        let databaseURL = root.appendingPathComponent("cider.sqlite")
        let database = CiderDatabase()
        self.root = root
        self.vaultRoot = vaultRoot
        self.notesRoot = notesRoot
        self.noteURL = noteURL
        self.attachmentsURL = attachmentsURL
        self.databaseURL = databaseURL
        self.database = database
        try FileManager.default.createDirectory(at: notesRoot, withIntermediateDirectories: true)
        try database.open(at: databaseURL)
        let label = CardLabelStorage(database: database).createLabel(name: "Atomic Label")
        let folder = VaultFolder(relativePath: "Atomic Folder")
        VaultFolderService(database: database).persistToDatabase(database, folder: folder)
        note = Note(
            id: UUID(),
            title: "Atomic Note",
            content: Self.priorContent,
            summary: "Exact prior summary",
            createdAt: Date(timeIntervalSince1970: 1_830_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_830_000_100),
            relativePath: "Atomic Note.md",
            labelIDs: [label.id],
            folderID: folder.id,
            isPinned: true,
            tags: ["atomic-tag"],
            projectID: "cider",
            artifactType: "note"
        )
        try Data(Self.priorContent.utf8).write(to: noteURL, options: .atomic)
        let seeder = NotesStorage(database: database, notesDirectoryURL: notesRoot, vaultRootURL: vaultRoot)
        seeder.persistNoteToDatabase(database, note: note)
        _ = try SecondBrainItemContentIndexingService(database: database).rebuild(
            owner: .init(ownerType: "note", ownerID: note.id.uuidString)
        )
        storage = NotesStorage(
            database: database,
            notesDirectoryURL: notesRoot,
            vaultRootURL: vaultRoot,
            imageTransactionHooks: .init { stage in
                try stageAction?(stage, noteURL)
                if failingStages.contains(stage) {
                    throw NotesCanonicalPersistenceInjectedFailure.stage(stage)
                }
            }
        )
        storage.loadNotesFromDatabase(database)
        let loaded = try storage.notes.first.map { $0 } ?? { throw NotesAssetInjectedFailure.payload }()
        _ = storage.loadContent(for: loaded)
        harness = NotesCanonicalTransactionHarness(
            storage: storage,
            note: loaded,
            noteURL: noteURL,
            notesRoot: notesRoot,
            diskContent: Self.priorContent
        )
        intake = NotesRelativeAssetIntakeService()
        sourceURL = root.appendingPathComponent("input.png")
        try NotesAssetFixture.pngData.write(to: sourceURL, options: .atomic)
    }

    func performImageTransaction() async throws -> String {
        try await intake.importLocalImage(
            at: sourceURL,
            noteID: note.id,
            noteDirectoryURL: notesRoot
        ) { asset in
            try await NotesEditorImageTransactionCoordinator().perform(
                asset: asset,
                alt: "input.png",
                operations: self.harness.operations
            )
        }
    }

    func completeFingerprint() throws -> [String] {
        let filesystem = try filesystemFingerprint().map { "fs:\($0)" }
        let database = try databaseFingerprint().map { "db:\($0)" }
        return ["disk:\(fileFingerprint(noteURL))"] + filesystem + database
    }

    func filesystemFingerprint() throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: notesRoot.path).sorted().map { path in
            let url = notesRoot.appendingPathComponent(path)
            let regular = (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true
            return regular ? "file:\(path):\(fileFingerprint(url))" : "directory:\(path)"
        }
    }

    func databaseFingerprint(_ db: CiderDatabase? = nil) throws -> [String] {
        let db = db ?? database
        let queries: [(String, String, Int)] = [
            ("item", "SELECT id, type, title, COALESCE(folder_id, ''), COALESCE(relative_path, ''), created_at, updated_at FROM items WHERE id = ? ORDER BY id;", 7),
            ("note", "SELECT item_id, content, COALESCE(summary, ''), is_pinned FROM notes WHERE item_id = ?;", 4),
            ("label", "SELECT item_id, label_id FROM item_labels WHERE item_id = ? ORDER BY label_id;", 2),
            ("tag", "SELECT it.item_id, t.name FROM item_tags it JOIN tags t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name;", 2),
            ("relation", "SELECT source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, source, COALESCE(metadata, '') FROM owner_relations WHERE source_owner_type = 'note' AND source_owner_id = ? ORDER BY id;", 7),
            ("chunk", "SELECT owner_type, owner_id, source, title, body, chunk_index, COALESCE(metadata, '') FROM content_chunks WHERE owner_type = 'note' AND owner_id = ? ORDER BY chunk_index;", 7),
        ]
        var rows: [String] = []
        for (prefix, sql, columns) in queries {
            let statement = try db.prepare(sql)
            statement.bind(note.id.uuidString, at: 1)
            while try statement.step() {
                rows.append(prefix + ":" + (0..<columns).map { statement.optionalString(at: Int32($0)) ?? String(statement.double(at: Int32($0))) }.joined(separator: "|"))
            }
        }
        return rows.sorted()
    }

    func canonicalRowCount(_ db: CiderDatabase? = nil) throws -> Int {
        let statement = try (db ?? database).prepare("SELECT COUNT(*) FROM items i JOIN notes n ON n.item_id = i.id WHERE i.id = ? AND i.type = 'note';")
        statement.bind(note.id.uuidString, at: 1)
        try statement.step()
        return statement.int(at: 0)
    }

    func chunkBodies(_ db: CiderDatabase? = nil) throws -> [String] {
        let statement = try (db ?? database).prepare("SELECT body FROM content_chunks WHERE owner_type = 'note' AND owner_id = ? ORDER BY chunk_index;")
        statement.bind(note.id.uuidString, at: 1)
        var bodies: [String] = []
        while try statement.step() { bodies.append(statement.string(at: 0)) }
        return bodies
    }

    func databaseFingerprintSnapshot(from complete: [String]) -> [String] {
        complete.compactMap { $0.hasPrefix("db:") ? String($0.dropFirst(3)) : nil }
    }

    func fingerprintDigest(_ values: [String]) -> String {
        LocalFileIntakeValidator.sha256(Data(values.joined(separator: "\n").utf8))
    }

    private func fileFingerprint(_ url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return "missing" }
        return "exists:\(data.count):\(LocalFileIntakeValidator.sha256(data))"
    }

    func cleanup() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class NotesAssetFixture {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cider-notes-assets-\(UUID().uuidString)", isDirectory: true)
    lazy var notesRoot = root.appendingPathComponent("Notes", isDirectory: true)
    lazy var noteURL = notesRoot.appendingPathComponent("Note.md")
    let noteID = UUID()
    let database = CiderDatabase()
    lazy var databaseURL = root.appendingPathComponent("notes.sqlite")
    lazy var service = makeService()
    init() throws { try FileManager.default.createDirectory(at: notesRoot, withIntermediateDirectories: true); try Data("original note".utf8).write(to: noteURL); try database.open(at: databaseURL) }
    func makeService(
        validator: LocalFileIntakeValidator = .init(),
        materializationHooks: LocalFileMaterializationService.Hooks = .init()
    ) -> NotesRelativeAssetIntakeService {
        NotesRelativeAssetIntakeService(
            validator: validator,
            materializer: LocalFileMaterializationService(
                validator: validator,
                hooks: materializationHooks
            )
        )
    }
    func write(_ name: String, _ data: Data) throws -> URL { let url = root.appendingPathComponent("inputs/\(name)"); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url, options: .atomic); return url }
    func filesystemFingerprint() throws -> [String] { try FileManager.default.subpathsOfDirectory(atPath: notesRoot.path).sorted().map { path in let url = notesRoot.appendingPathComponent(path); let regular = (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true; return regular ? "file:\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))" : "directory:\(path)" } }
    func databaseFingerprint() throws -> [String] { let s = try database.prepare("SELECT id, type, COALESCE(relative_path, '') FROM items ORDER BY id;"); var rows: [String] = []; while try s.step() { rows.append("\(s.string(at: 0))|\(s.string(at: 1))|\(s.string(at: 2))") }; return rows }
    func cleanup() { database.close(); try? FileManager.default.removeItem(at: root) }
}
