import Foundation
import Testing
@testable import Cider

@Suite("Local File Intake Tests")
@MainActor
struct LocalFileIntakeTests {
    @Test("validator returns stable bounded metadata without making caller policy global")
    func validatorReturnsStableMetadata() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("source.txt", Data("shared intake".utf8))

        let metadata = try LocalFileIntakeValidator().validate(source)

        #expect(metadata.identity.standardizedURL == source.standardizedFileURL)
        #expect(metadata.identity.resolvedURL == source.resolvingSymlinksInPath().standardizedFileURL)
        #expect(metadata.displayName == "source.txt")
        #expect(metadata.fileExtension == "txt")
        #expect(metadata.contentTypeIdentifier != nil)
        #expect(metadata.byteSize == 13)
        #expect(metadata.sha256.count == 64)
        #expect(metadata.identity.resourceIdentifier?.count ?? 0 <= 256)
        #expect(metadata.identity.volumeIdentifier?.count ?? 0 <= 256)
    }

    @Test("validator rejects directories symlinks aliases and traversal without exposing private paths")
    func validatorRejectsUnsafeLocalInputs() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let validator = LocalFileIntakeValidator()
        let source = try fixture.write("private-sentinel.txt", Data("safe".utf8))
        let symlink = fixture.root.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        let traversal = URL(fileURLWithPath: fixture.root.path + "/nested/../private-sentinel.txt")

        try expectFailure(.notRegularFile, from: { try validator.validate(fixture.root) }, privateRoot: fixture.root)
        try expectFailure(.symbolicLink, from: { try validator.validate(symlink) }, privateRoot: fixture.root)
        try expectFailure(.pathTraversal, from: { try validator.validate(traversal) }, privateRoot: fixture.root)

        let alias = fixture.root.appendingPathComponent("source alias")
        let bookmark = try source.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: alias)
        try expectFailure(.aliasFile, from: { try validator.validate(alias) }, privateRoot: fixture.root)

        let deterministicallyUnreadable = LocalFileIntakeValidator(
            hooks: .init(isReadableFile: { _ in false })
        )
        try expectFailure(
            .unreadable,
            from: { try deterministicallyUnreadable.validate(source) },
            privateRoot: fixture.root
        )
    }

    @Test("validator detects a deterministic change during hashing")
    func validatorDetectsChangeDuringValidation() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("changing.txt", Data("before".utf8))
        var changed = false
        let validator = LocalFileIntakeValidator(hooks: .init(afterInitialSnapshot: {
            guard !changed else { return }
            changed = true
            try Data("after-content".utf8).write(to: source, options: .atomic)
        }))

        try expectFailure(
            .changedDuringValidation,
            from: { try validator.validate(source) },
            privateRoot: fixture.root
        )
    }

    @Test("original caller URL security scope encloses reads and copy and balances success and failure")
    func originalCallerSecurityScopeIsBalanced() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let storedURL = try fixture.write("scoped.txt", Data("scoped source".utf8))
        let callerURL = URL(fileURLWithPath: fixture.root.path + "/./scoped.txt")
        #expect(callerURL != callerURL.standardizedFileURL)

        let tracker = IntakeScopeTracker()
        let validator = LocalFileIntakeValidator(hooks: .init(
            startAccessingSecurityScopedResource: { tracker.start($0) },
            stopAccessingSecurityScopedResource: { tracker.stop($0) },
            beforeFileRead: { accessURL, readURL in
                tracker.recordRead(accessURL: accessURL, readURL: readURL)
            }
        ))
        let metadata = try validator.validate(callerURL)
        #expect(metadata.identity.accessURL == callerURL)
        #expect(metadata.identity.standardizedURL == storedURL.standardizedFileURL)
        #expect(try validator.data(for: metadata) == Data("scoped source".utf8))

        let ingestion = fixture.makeIngestion(validator: validator, hooks: .init(
            beforeSourceCopy: { accessURL, sourceURL, _ in
                tracker.recordCopy(accessURL: accessURL, sourceURL: sourceURL)
            }
        ))
        _ = try ingestion.ingest(fixture.request(
            validated: metadata,
            fileID: UUID(),
            filename: "scoped.txt"
        ))

        #expect(!tracker.readScopes.isEmpty)
        #expect(tracker.readScopes.allSatisfy { $0.wasActive })
        #expect(tracker.copyScopes.count == 1)
        #expect(tracker.copyScopes.allSatisfy { $0.wasActive })
        #expect(tracker.copyScopes.first?.accessURL == callerURL)
        #expect(tracker.copyScopes.first?.sourceURL == storedURL.standardizedFileURL)
        #expect(tracker.isBalanced)
        #expect(tracker.activeURLs.isEmpty)

        let failingTracker = IntakeScopeTracker()
        let failingValidator = LocalFileIntakeValidator(hooks: .init(
            afterInitialSnapshot: { throw IntakeInjectedFailure.validation },
            startAccessingSecurityScopedResource: { failingTracker.start($0) },
            stopAccessingSecurityScopedResource: { failingTracker.stop($0) },
            beforeFileRead: { accessURL, readURL in
                failingTracker.recordRead(accessURL: accessURL, readURL: readURL)
            }
        ))
        #expect(throws: LocalFileIntakeError.self) {
            try failingValidator.validate(callerURL)
        }
        #expect(failingTracker.starts == [callerURL])
        #expect(failingTracker.stops == [callerURL])
        #expect(failingTracker.activeURLs.isEmpty)

        let copyFailureTracker = IntakeScopeTracker()
        let copyFailureValidator = LocalFileIntakeValidator(hooks: .init(
            startAccessingSecurityScopedResource: { copyFailureTracker.start($0) },
            stopAccessingSecurityScopedResource: { copyFailureTracker.stop($0) },
            beforeFileRead: { accessURL, readURL in
                copyFailureTracker.recordRead(accessURL: accessURL, readURL: readURL)
            }
        ))
        let copyFailureMetadata = try copyFailureValidator.validate(callerURL)
        let copyFailureIngestion = fixture.makeIngestion(validator: copyFailureValidator, hooks: .init(
            beforeSourceCopy: { accessURL, sourceURL, _ in
                copyFailureTracker.recordCopy(accessURL: accessURL, sourceURL: sourceURL)
                throw IntakeInjectedFailure.copy
            }
        ))
        #expect(throws: LocalFileIntakeError.self) {
            try copyFailureIngestion.ingest(fixture.request(
                validated: copyFailureMetadata,
                fileID: UUID(),
                filename: "copy-failure.txt"
            ))
        }
        #expect(copyFailureTracker.copyScopes.count == 1)
        #expect(copyFailureTracker.copyScopes.allSatisfy { $0.wasActive })
        #expect(copyFailureTracker.isBalanced)
        #expect(copyFailureTracker.activeURLs.isEmpty)

        var declinedStarts = 0
        var declinedStops = 0
        var declinedScopeReads = 0
        let ordinaryFileValidator = LocalFileIntakeValidator(hooks: .init(
            startAccessingSecurityScopedResource: { _ in
                declinedStarts += 1
                return false
            },
            stopAccessingSecurityScopedResource: { _ in declinedStops += 1 },
            beforeFileRead: { _, _ in declinedScopeReads += 1 }
        ))
        let ordinaryMetadata = try ordinaryFileValidator.validate(storedURL)
        #expect(try ordinaryFileValidator.data(for: ordinaryMetadata) == Data("scoped source".utf8))
        #expect(declinedStarts == 2)
        #expect(declinedStops == 0)
        #expect(declinedScopeReads > 0)
    }

    @Test("materializer rolls back a source change after copy")
    func materializerRollsBackSourceChange() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("changing.pdf", Data("original-pdf".utf8))
        let validator = LocalFileIntakeValidator()
        let metadata = try validator.validate(source)
        let before = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()
        var changed = false
        let ingestion = fixture.makeIngestion(validator: validator, hooks: .init(afterCopy: { _ in
            guard !changed else { return }
            changed = true
            try Data("changed-after-copy".utf8).write(to: source, options: .atomic)
        }))

        #expect(throws: LocalFileIntakeError.self) {
            try ingestion.ingest(fixture.request(validated: metadata, fileID: UUID(), filename: "changing.pdf"))
        }

        #expect(try fixture.vaultFileCount() == 0)
        #expect(try fixture.fingerprint() == before)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("materializer rolls back filesystem and database work when persistence fails")
    func materializerRollsBackPersistenceFailure() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("rollback.txt", Data("rollback".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let before = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()
        let ingestion = fixture.makeIngestion(hooks: .init(beforeDatabasePersist: { _ in
            throw IntakeInjectedFailure.persistence
        }))

        #expect(throws: LocalFileIntakeError.self) {
            try ingestion.ingest(fixture.request(validated: metadata, fileID: UUID(), filename: "rollback.txt"))
        }

        #expect(try fixture.vaultFileCount() == 0)
        #expect(try fixture.fingerprint() == before)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("Chat batch rows remain externally invisible and second persist failure rolls back exactly")
    func chatBatchIsAtomicAcrossSecondPersistFailure() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let observer = CiderDatabase()
        try observer.open(at: fixture.databaseURL)
        defer { observer.close() }
        let validator = LocalFileIntakeValidator()
        var persistCount = 0
        var externallyVisibleCounts: [Int] = []
        let ingestion = fixture.makeIngestion(validator: validator, hooks: .init(
            beforeDatabasePersist: { _ in
                persistCount += 1
                guard persistCount == 2 else { return }
                externallyVisibleCounts.append(try fixture.vaultFileCount(using: observer))
                throw IntakeInjectedFailure.persistence
            }
        ))
        let chat = AgentRoomsAttachmentService(
            database: fixture.database,
            vaultRoot: fixture.vaultRoot,
            validator: validator,
            ingestionService: ingestion
        )
        let first = try chat.stage(
            try fixture.write("first.txt", Data("first batch file".utf8)),
            source: .filePicker,
            existing: []
        )
        let second = try chat.stage(
            try fixture.write("second.txt", Data("second batch file".utf8)),
            source: .filePicker,
            existing: [first]
        )
        let filesystemBefore = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        #expect(throws: ConversationAttachmentInputError.self) {
            try chat.materialize([first, second], at: Date(timeIntervalSince1970: 1_827_000_000))
        }

        #expect(persistCount == 2)
        #expect(externallyVisibleCounts == [0])
        #expect(try fixture.fingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("batch success retry and failing mixed reuse preserve canonical rows and files")
    func batchSuccessRetryAndReuseAreStable() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let validator = LocalFileIntakeValidator()
        let firstMetadata = try validator.validate(try fixture.write("batch-a.txt", Data("batch a".utf8)))
        let secondMetadata = try validator.validate(try fixture.write("batch-b.txt", Data("batch b".utf8)))
        let firstRequest = fixture.request(
            validated: firstMetadata,
            fileID: UUID(),
            filename: "batch-a.txt",
            filenameStrategy: .prefixWithStableID
        )
        let secondRequest = fixture.request(
            validated: secondMetadata,
            fileID: UUID(),
            filename: "batch-b.txt",
            filenameStrategy: .prefixWithStableID
        )
        let ingestion = fixture.makeIngestion(validator: validator)

        let firstResults = try ingestion.ingestBatch([firstRequest, secondRequest]) { $0 }
        #expect(firstResults.count == 2)
        #expect(firstResults.allSatisfy { !$0.wasReused })
        #expect(try fixture.vaultFileCount() == 2)
        let stableFilesystem = try fixture.fingerprint()
        let stableDatabase = try fixture.databaseFingerprint()

        let retryResults = try ingestion.ingestBatch([firstRequest, secondRequest]) { $0 }
        #expect(retryResults.map(\.file) == firstResults.map(\.file))
        #expect(retryResults.allSatisfy { $0.wasReused })
        #expect(try fixture.fingerprint() == stableFilesystem)
        #expect(try fixture.databaseFingerprint() == stableDatabase)

        let thirdMetadata = try validator.validate(try fixture.write("batch-c.txt", Data("batch c".utf8)))
        let thirdRequest = fixture.request(
            validated: thirdMetadata,
            fileID: UUID(),
            filename: "batch-c.txt",
            filenameStrategy: .prefixWithStableID
        )
        #expect(throws: IntakeInjectedFailure.self) {
            try ingestion.ingestBatch([firstRequest, thirdRequest]) { _ in
                throw IntakeInjectedFailure.payload
            }
        }
        #expect(try fixture.fingerprint() == stableFilesystem)
        #expect(try fixture.databaseFingerprint() == stableDatabase)
        let canonicalFirst = fixture.vaultRoot.appendingPathComponent(firstResults[0].file.relativePath)
        #expect(try Data(contentsOf: canonicalFirst) == Data("batch a".utf8))
    }

    @Test("Chat payload failure rolls back all new batch rows and files")
    func chatPayloadFailureRollsBackBatch() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let validator = LocalFileIntakeValidator()
        var firstPersistedFile: VaultFile?
        let ingestion = fixture.makeIngestion(validator: validator, hooks: .init(
            beforeDatabasePersist: { file in
                if let firstPersistedFile {
                    try Data("corrupted before payload".utf8).write(
                        to: fixture.vaultRoot.appendingPathComponent(firstPersistedFile.relativePath),
                        options: .atomic
                    )
                } else {
                    firstPersistedFile = file
                }
            }
        ))
        let chat = AgentRoomsAttachmentService(
            database: fixture.database,
            vaultRoot: fixture.vaultRoot,
            validator: validator,
            ingestionService: ingestion
        )
        let first = try chat.stage(
            try fixture.write("payload-a.txt", Data("payload a".utf8)),
            source: .filePicker,
            existing: []
        )
        let second = try chat.stage(
            try fixture.write("payload-b.txt", Data("payload b".utf8)),
            source: .filePicker,
            existing: [first]
        )
        let filesystemBefore = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        #expect(throws: ConversationAttachmentInputError.self) {
            try chat.materialize([first, second], at: Date(timeIntervalSince1970: 1_827_000_000))
        }
        #expect(try fixture.fingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("canonical destination rejects in-vault symlink components")
    func materializerRejectsDestinationSymlinkComponent() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("symlink-destination.txt", Data("do not redirect".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let inbox = fixture.vaultRoot.appendingPathComponent("Inbox", isDirectory: true)
        let realDirectory = inbox.appendingPathComponent("Real", isDirectory: true)
        let linkedDirectory = inbox.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        let filesystemBefore = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        do {
            _ = try fixture.makeIngestion().ingest(fixture.request(
                validated: metadata,
                fileID: UUID(),
                filename: "symlink-destination.txt"
            ))
            Issue.record("Expected an in-vault destination symlink to fail closed")
        } catch let error as LocalFileIntakeError {
            #expect(error.code == .unsafeDestination)
        }

        #expect(try fixture.fingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("same stable request deduplicates and preserves identity through physical reopen")
    func materializerReusesStableIdentityAcrossReopen() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("retry.txt", Data("retry identity".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let fileID = UUID()
        let request = fixture.request(validated: metadata, fileID: fileID, filename: "retry.txt")

        let first = try fixture.makeIngestion().ingest(request)
        let retry = try fixture.makeIngestion().ingest(request)
        #expect(first.file.id == fileID)
        #expect(retry.file == first.file)
        #expect(retry.wasReused)
        #expect(try fixture.vaultFileCount() == 1)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedService = VaultFileIngestionService(
            database: reopened,
            vaultRoot: fixture.vaultRoot,
            storage: VaultFileStorage(database: reopened)
        )
        let reopenedResult = try reopenedService.ingest(request)
        #expect(reopenedResult.file.id == first.file.id)
        #expect(reopenedResult.file.relativePath == first.file.relativePath)
        #expect(reopenedResult.wasReused)
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(first.file.relativePath)) == Data("retry identity".utf8))
    }

    @Test("distinct capture identities preserve existing duplicate semantics for identical content")
    func distinctIdentitiesRemainDistinct() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("duplicate.txt", Data("same content".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let ingestion = fixture.makeIngestion()

        let first = try ingestion.ingest(fixture.request(validated: metadata, fileID: UUID(), filename: "duplicate.txt"))
        let second = try ingestion.ingest(fixture.request(validated: metadata, fileID: UUID(), filename: "duplicate.txt"))

        #expect(first.file.id != second.file.id)
        #expect(first.file.relativePath != second.file.relativePath)
        #expect(first.validatedMetadata.sha256 == second.validatedMetadata.sha256)
        #expect(try fixture.vaultFileCount() == 2)
    }

    @Test("materializer rejects a stable identity already owned by another item type")
    func materializerRejectsForeignIdentity() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("identity.txt", Data("identity conflict".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let fileID = UUID()
        try fixture.insertForeignItem(id: fileID)
        let before = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        do {
            _ = try fixture.makeIngestion().ingest(
                fixture.request(validated: metadata, fileID: fileID, filename: "identity.txt")
            )
            Issue.record("Expected the foreign stable identity to fail closed")
        } catch let error as LocalFileIntakeError {
            #expect(error.code == .identityConflict)
        }

        #expect(try fixture.vaultFileCount() == 0)
        #expect(try fixture.fingerprint() == before)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
    }

    @Test("same-content stable ID reuse rejects incompatible canonical contracts")
    func materializerRejectsIncompatibleStableReuseContracts() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("contract.txt", Data("same canonical content".utf8))
        let metadata = try LocalFileIntakeValidator().validate(source)
        let fileID = UUID()
        let ingestion = fixture.makeIngestion()
        let original = fixture.request(
            validated: metadata,
            fileID: fileID,
            filename: "contract.txt",
            filenameStrategy: .prefixWithStableID
        )
        let persisted = try ingestion.ingest(original)
        let filesystemBefore = try fixture.fingerprint()
        let databaseBefore = try fixture.databaseFingerprint()
        let incompatibleRequests = [
            fixture.request(
                validated: metadata,
                fileID: fileID,
                filename: "contract.txt",
                filenameStrategy: .prefixWithStableID,
                fileType: .image
            ),
            fixture.request(
                validated: metadata,
                fileID: fileID,
                filename: "contract.txt",
                filenameStrategy: .prefixWithStableID,
                folderID: UUID()
            ),
            fixture.request(
                validated: metadata,
                fileID: fileID,
                destinationRelativeDirectory: "Inbox/Images",
                filename: "contract.txt",
                filenameStrategy: .prefixWithStableID
            ),
            fixture.request(
                validated: metadata,
                fileID: fileID,
                filename: "contract.txt",
                filenameStrategy: .preserveWithUniqueSuffix
            ),
            fixture.request(
                validated: metadata,
                fileID: fileID,
                filename: "renamed.txt",
                filenameStrategy: .prefixWithStableID
            ),
        ]

        for request in incompatibleRequests {
            do {
                _ = try ingestion.ingest(request)
                Issue.record("Expected incompatible stable-ID reuse to fail closed")
            } catch let error as LocalFileIntakeError {
                #expect(error.code == .identityConflict)
            }
        }

        #expect(try fixture.fingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(persisted.file.relativePath)) == Data("same canonical content".utf8))
    }

    @Test("Chat and Capture share validation metadata while Chat policy stays local")
    func chatAndCaptureShareCoreWithoutSharingComposerPolicy() throws {
        let fixture = try IntakeFixture(overrideStoragePaths: true)
        defer { fixture.cleanup() }
        let source = try fixture.write("shared.txt", Data("same source through both surfaces".utf8))
        let validator = LocalFileIntakeValidator()
        let chat = AgentRoomsAttachmentService(
            database: fixture.database,
            vaultRoot: fixture.vaultRoot,
            validator: validator,
            ingestionService: fixture.makeIngestion(validator: validator)
        )
        let staged = try chat.stage(source, source: .filePicker, existing: [])
        let capture = CiderCaptureService(
            vaultFileStorage: VaultFileStorage(database: fixture.database),
            database: fixture.database,
            routingDecisionService: CiderRoutingDecisionService(database: fixture.database),
            localFileValidator: validator,
            vaultFileIngestionService: fixture.makeIngestion(validator: validator)
        )
        let captured = try capture.addFileCapture(sourcePath: source.path, title: nil, folderID: nil)
        let capturedRelativePath = try #require(captured.item.relativePath)
        let capturedMetadata = try validator.validate(
            fixture.vaultRoot.appendingPathComponent(capturedRelativePath)
        )

        #expect(staged.validatedMetadata.sha256 == capturedMetadata.sha256)
        #expect(staged.validatedMetadata.byteSize == capturedMetadata.byteSize)
        #expect(staged.validatedMetadata.contentTypeIdentifier == capturedMetadata.contentTypeIdentifier)
        #expect(captured.duplicate.status == "unsupported")

        let oversized = try fixture.write(
            "capture-only.txt",
            Data(repeating: 65, count: Int(AgentRoomsAttachmentService.maximumTextByteSize + 1))
        )
        #expect(throws: ConversationAttachmentInputError.self) {
            try chat.stage(oversized, source: .filePicker, existing: [])
        }
        let captureOnly = try capture.addFileCapture(sourcePath: oversized.path, title: nil, folderID: nil)
        #expect(captureOnly.item.type == "vaultFile")
        let captureOnlyPath = try #require(captureOnly.item.relativePath)
        let captureOnlyMetadata = try validator.validate(
            fixture.vaultRoot.appendingPathComponent(captureOnlyPath)
        )
        #expect(captureOnlyMetadata.byteSize == AgentRoomsAttachmentService.maximumTextByteSize + 1)
    }

    @Test("Journal originals and note-relative assets can validate without inheriting Chat limits")
    func adjacentAdapterCompatibility() throws {
        let fixture = try IntakeFixture()
        defer { fixture.cleanup() }
        let audioBytes = Data(repeating: 0x41, count: Int(AgentRoomsAttachmentService.maximumImageByteSize + 1))
        let audio = try fixture.write("journal-original.m4a", audioBytes)
        let image = try fixture.write("note-image.png", IntakeFixture.pngData)
        let text = try fixture.write("note-import.txt", Data("note import".utf8))
        let validator = LocalFileIntakeValidator()

        let audioMetadata = try validator.validate(audio)
        let imageMetadata = try validator.validate(image)
        let textMetadata = try validator.validate(text)
        let request = StoredAudioTranscriptionRequest(
            fileURL: audioMetadata.identity.standardizedURL,
            sourceID: "journal-original:test",
            displayName: audioMetadata.displayName
        )

        #expect(audioMetadata.byteSize == Int64(audioBytes.count))
        #expect(request.source.retention == .preserveOriginal)
        #expect(try Data(contentsOf: audio) == audioBytes)
        #expect(imageMetadata.fileExtension == "png")
        #expect(textMetadata.fileExtension == "txt")
        #expect(try validator.data(for: textMetadata) == Data("note import".utf8))
        #expect(NotesMarkdownPathCodec.markdownForPersistence(
            "![image](./.attachments/asset.png)",
            notesDirectoryURL: fixture.root
        ).contains("./.attachments/asset.png"))
    }

    private func expectFailure(
        _ expected: LocalFileIntakeError.Code,
        from operation: () throws -> Void,
        privateRoot: URL
    ) throws {
        do {
            try operation()
            Issue.record("Expected local-file intake failure \(expected.rawValue)")
        } catch let error as LocalFileIntakeError {
            #expect(error.code == expected)
            #expect(!error.localizedDescription.contains(privateRoot.path))
            #expect(error.localizedDescription.count <= 240)
        }
    }
}

private enum IntakeInjectedFailure: Error {
    case validation
    case copy
    case persistence
    case payload
}

private final class IntakeScopeTracker {
    struct ReadScope {
        let accessURL: URL
        let readURL: URL
        let wasActive: Bool
    }

    struct CopyScope {
        let accessURL: URL
        let sourceURL: URL
        let wasActive: Bool
    }

    private(set) var activeURLs: [URL: Int] = [:]
    private(set) var starts: [URL] = []
    private(set) var stops: [URL] = []
    private(set) var readScopes: [ReadScope] = []
    private(set) var copyScopes: [CopyScope] = []

    var isBalanced: Bool {
        Dictionary(grouping: starts, by: { $0 }).mapValues(\.count)
            == Dictionary(grouping: stops, by: { $0 }).mapValues(\.count)
    }

    func start(_ url: URL) -> Bool {
        starts.append(url)
        activeURLs[url, default: 0] += 1
        return true
    }

    func stop(_ url: URL) {
        stops.append(url)
        let remaining = (activeURLs[url] ?? 0) - 1
        if remaining > 0 {
            activeURLs[url] = remaining
        } else {
            activeURLs.removeValue(forKey: url)
        }
    }

    func recordRead(accessURL: URL, readURL: URL) {
        readScopes.append(.init(
            accessURL: accessURL,
            readURL: readURL,
            wasActive: (activeURLs[accessURL] ?? 0) > 0
        ))
    }

    func recordCopy(accessURL: URL, sourceURL: URL) {
        copyScopes.append(.init(
            accessURL: accessURL,
            sourceURL: sourceURL,
            wasActive: (activeURLs[accessURL] ?? 0) > 0
        ))
    }
}

@MainActor
private final class IntakeFixture {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    let root: URL
    let vaultRoot: URL
    let databaseURL: URL
    let database: CiderDatabase
    private let previousVaultOverride: URL?
    private let overridesStoragePaths: Bool

    init(overrideStoragePaths: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-local-file-intake-\(UUID().uuidString)", isDirectory: true)
        vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
        databaseURL = root.appendingPathComponent("intake.sqlite")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        previousVaultOverride = StoragePaths.vaultOverride
        overridesStoragePaths = overrideStoragePaths
        if overrideStoragePaths {
            StoragePaths.vaultOverride = vaultRoot
            StoragePaths.invalidateCachedDirectory()
            StoragePaths.ensureVaultStructure()
        }
        database = CiderDatabase()
        try database.open(at: databaseURL)
    }

    func write(_ name: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    func makeIngestion(
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        hooks: VaultFileIngestionService.Hooks = .init()
    ) -> VaultFileIngestionService {
        VaultFileIngestionService(
            database: database,
            vaultRoot: vaultRoot,
            storage: VaultFileStorage(database: database),
            validator: validator,
            hooks: hooks
        )
    }

    func request(
        validated: LocalFileValidatedMetadata,
        fileID: UUID,
        destinationRelativeDirectory: String = "Inbox/Files",
        filename: String,
        filenameStrategy: VaultFileIngestionService.FilenameStrategy = .preserveWithUniqueSuffix,
        fileType: VaultFileType = .document,
        folderID: UUID? = nil
    ) -> VaultFileIngestionService.Request {
        .init(
            validated: validated,
            fileID: fileID,
            destinationRelativeDirectory: destinationRelativeDirectory,
            filename: filename,
            filenameStrategy: filenameStrategy,
            fileType: fileType,
            folderID: folderID,
            title: nil,
            timestamp: Date(timeIntervalSince1970: 1_827_000_000)
        )
    }

    func vaultFileCount() throws -> Int {
        try vaultFileCount(using: database)
    }

    func vaultFileCount(using database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM items WHERE type = 'vaultFile';")
        try statement.step()
        return statement.int(at: 0)
    }

    func insertForeignItem(id: UUID) throws {
        let statement = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at)
            VALUES (?, 'note', 'Foreign identity', ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
        statement.bind(1_827_000_000.0, at: 2)
        statement.bind(1_827_000_000.0, at: 3)
        try statement.step()
    }

    func fingerprint() throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: vaultRoot.path).sorted().map { path in
            let url = vaultRoot.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return "directory:\(path)" }
            let data = try Data(contentsOf: url)
            return "file:\(path):\(data.count):\(LocalFileIntakeValidator.sha256(data))"
        }
    }

    func databaseFingerprint() throws -> [String] {
        let statement = try database.prepare("""
            SELECT i.id, i.type, COALESCE(i.relative_path, ''), COALESCE(vf.filename, '')
            FROM items i
            LEFT JOIN vault_files vf ON vf.item_id = i.id
            ORDER BY i.id;
            """)
        var rows: [String] = []
        while try statement.step() {
            rows.append([
                statement.string(at: 0),
                statement.string(at: 1),
                statement.string(at: 2),
                statement.string(at: 3),
            ].joined(separator: "|"))
        }
        return rows
    }

    func cleanup() {
        database.close()
        if overridesStoragePaths {
            StoragePaths.vaultOverride = previousVaultOverride
            StoragePaths.invalidateCachedDirectory()
        }
        try? FileManager.default.removeItem(at: root)
    }
}
