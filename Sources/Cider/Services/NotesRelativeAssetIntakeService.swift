import Foundation
import ImageIO

struct NotesRelativeAssetIntakeError: Error, Equatable, LocalizedError, Sendable {
    enum Code: String, Equatable, Sendable {
        case fileIntake
        case unsupportedType
        case invalidImage
        case invalidUTF8
        case payloadFailed
        case persistenceIndeterminate
    }

    let code: Code
    let intakeCode: LocalFileIntakeError.Code?

    init(_ code: Code, intakeCode: LocalFileIntakeError.Code? = nil) {
        self.code = code
        self.intakeCode = intakeCode
    }

    var errorDescription: String? {
        switch code {
        case .fileIntake:
            "Cider could not safely read or store the selected note asset."
        case .unsupportedType:
            "That local file type is not supported by the note editor."
        case .invalidImage:
            "The selected note image could not be decoded safely."
        case .invalidUTF8:
            "Imported note text must be valid UTF-8."
        case .payloadFailed:
            "Cider could not insert the prepared asset into the note editor."
        case .persistenceIndeterminate:
            "Cider could not confirm note recovery, so the prepared asset was retained for safe repair."
        }
    }
}

struct NotesRelativeAsset: Equatable, Sendable {
    let fileURL: URL
    let persistedReference: String
    let editorReference: String
    let metadata: LocalFileValidatedMetadata
    let wasReused: Bool
}

struct NotesLocalTextImport: Equatable, Sendable {
    let content: String
    let metadata: LocalFileValidatedMetadata
}

/// The production editor/file transaction boundary for prepared note images. The
/// ViewModel supplies its exact state snapshot and concrete WebKit/storage/sync
/// operations; tests can exercise the same ordering without constructing a WebView.
@MainActor
final class NotesEditorImageTransactionCoordinator {
    struct Operations {
        let captureSnapshot: () async throws -> NotesEditorImageTransactionSnapshot
        let prepareForMutation: (NotesEditorImageTransactionSnapshot) -> Void
        let validateCurrentState: (NotesEditorImageTransactionSnapshot) throws -> Void
        let insertImage: (NotesRelativeAsset, String) async throws -> Void
        let capturePostInsertMarkdown: () async throws -> String
        let portableMarkdown: (String, NotesEditorImageTransactionSnapshot) throws -> String
        let persist: (String, NotesEditorImageTransactionSnapshot) throws -> Void
        let applySuccess: (String, NotesEditorImageTransactionSnapshot) -> Void
        let pushAfterLocalChange: () -> Void
        let restoreEditor: (String, Bool) async -> Void
        let restoreState: (NotesEditorImageTransactionSnapshot) -> Void
        let refreshExternalChangeState: (NotesEditorImageTransactionSnapshot) throws -> Void
    }

    @discardableResult
    func perform(
        asset: NotesRelativeAsset,
        alt: String,
        operations: Operations
    ) async throws -> String {
        let snapshot = try await operations.captureSnapshot()
        operations.prepareForMutation(snapshot)
        var insertCompleted = false
        do {
            try operations.validateCurrentState(snapshot)
            try await operations.insertImage(asset, alt)
            insertCompleted = true
            try operations.validateCurrentState(snapshot)
            let editorMarkdown = try await operations.capturePostInsertMarkdown()
            try operations.validateCurrentState(snapshot)
            let persisted = try operations.portableMarkdown(editorMarkdown, snapshot)
            try operations.persist(persisted, snapshot)
            operations.applySuccess(persisted, snapshot)
            operations.pushAfterLocalChange()
            return persisted
        } catch {
            await operations.restoreEditor(snapshot.editorMarkdown, insertCompleted)
            operations.restoreState(snapshot)
            try? operations.refreshExternalChangeState(snapshot)
            if let intakeError = error as? NotesRelativeAssetIntakeError {
                throw intakeError
            }
            if let persistenceError = error as? NotesStorage.ImageTransactionPersistenceError,
               persistenceError.outcome == .indeterminate {
                throw NotesRelativeAssetIntakeError(.persistenceIndeterminate)
            }
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
    }
}

@MainActor
final class NotesRelativeAssetIntakeService {
    private struct FinalizationFailure: Error, LocalFileMaterializationFailureDisposition {
        let underlying: any Error

        var retainPreparedMaterialization: Bool {
            (underlying as? NotesRelativeAssetIntakeError)?.code == .persistenceIndeterminate
        }
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"
    ]
    private static let textExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    private let validator: LocalFileIntakeValidator
    private let materializer: LocalFileMaterializationService
    private let fileManager: FileManager

    init(
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        fileManager: FileManager = .default,
        materializer: LocalFileMaterializationService? = nil
    ) {
        self.validator = validator
        self.fileManager = fileManager
        self.materializer = materializer ?? LocalFileMaterializationService(
            validator: validator,
            fileManager: fileManager
        )
    }

    func loadLocalText(at sourceURL: URL) throws -> NotesLocalTextImport {
        let validated = try validate(sourceURL)
        guard Self.textExtensions.contains(validated.fileExtension) else {
            throw NotesRelativeAssetIntakeError(.unsupportedType)
        }
        do {
            return try validator.withData(for: validated) { data in
                guard let content = String(data: data, encoding: .utf8) else {
                    throw NotesRelativeAssetIntakeError(.invalidUTF8)
                }
                return NotesLocalTextImport(content: content, metadata: validated)
            }
        } catch let error as NotesRelativeAssetIntakeError {
            throw error
        } catch let error as LocalFileIntakeError {
            throw NotesRelativeAssetIntakeError(.fileIntake, intakeCode: error.code)
        } catch {
            throw NotesRelativeAssetIntakeError(.invalidUTF8)
        }
    }

    func importLocalImage<T>(
        at sourceURL: URL,
        noteID: UUID,
        noteDirectoryURL: URL,
        displayName: String? = nil,
        finalize: (NotesRelativeAsset) async throws -> T
    ) async throws -> T {
        let validated = try validate(sourceURL)
        guard Self.imageExtensions.contains(validated.fileExtension) else {
            throw NotesRelativeAssetIntakeError(.unsupportedType)
        }
        do {
            try validator.withData(for: validated) { data in
                guard Self.isDecodableImage(data) else {
                    throw NotesRelativeAssetIntakeError(.invalidImage)
                }
            }
        } catch let error as NotesRelativeAssetIntakeError {
            throw error
        } catch let error as LocalFileIntakeError {
            throw NotesRelativeAssetIntakeError(.fileIntake, intakeCode: error.code)
        }

        let safeName = LocalFileIntakeValidator.sanitizedFilename(displayName ?? validated.displayName)
        let stableID = Self.stableAssetID(noteID: noteID, metadata: validated, filename: safeName)
        let request = LocalFileMaterializationService.Request(
            validated: validated,
            rootURL: noteDirectoryURL,
            destinationRelativeDirectory: ".attachments",
            filename: safeName,
            stableID: stableID
        )
        do {
            return try await materializer.materialize(request) { materialized in
                let persistedReference = "./.attachments/\(materialized.fileURL.lastPathComponent)"
                let portableMarkdown = "![asset](\(persistedReference))"
                let editorMarkdown = NotesMarkdownPathCodec.markdownForEditor(
                    portableMarkdown,
                    notesDirectoryURL: noteDirectoryURL
                )
                guard let editorReference = Self.markdownDestination(in: editorMarkdown) else {
                    throw FinalizationFailure(underlying: NotesRelativeAssetIntakeError(.payloadFailed))
                }
                let asset = NotesRelativeAsset(
                    fileURL: materialized.fileURL,
                    persistedReference: persistedReference,
                    editorReference: editorReference,
                    metadata: validated,
                    wasReused: materialized.wasReused
                )
                do {
                    return try await finalize(asset)
                } catch {
                    throw FinalizationFailure(underlying: error)
                }
            }
        } catch let failure as FinalizationFailure {
            if let error = failure.underlying as? NotesRelativeAssetIntakeError { throw error }
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        } catch let error as NotesRelativeAssetIntakeError {
            throw error
        } catch let error as LocalFileIntakeError {
            throw NotesRelativeAssetIntakeError(.fileIntake, intakeCode: error.code)
        } catch {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
    }

    func importImageData<T>(
        _ data: Data,
        filename: String,
        noteID: UUID,
        noteDirectoryURL: URL,
        finalize: (NotesRelativeAsset) async throws -> T
    ) async throws -> T {
        guard Self.isDecodableImage(data) else {
            throw NotesRelativeAssetIntakeError(.invalidImage)
        }
        let safeName = LocalFileIntakeValidator.sanitizedFilename(filename)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("cider-note-asset-\(UUID().uuidString)", isDirectory: true)
        let temporary = temporaryRoot.appendingPathComponent(safeName)
        do {
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            try data.write(to: temporary, options: .atomic)
            defer { try? fileManager.removeItem(at: temporaryRoot) }
            return try await importLocalImage(
                at: temporary,
                noteID: noteID,
                noteDirectoryURL: noteDirectoryURL,
                displayName: safeName,
                finalize: finalize
            )
        } catch let error as NotesRelativeAssetIntakeError {
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw NotesRelativeAssetIntakeError(.fileIntake)
        }
    }

    private func validate(_ url: URL) throws -> LocalFileValidatedMetadata {
        do {
            return try validator.validate(url)
        } catch let error as LocalFileIntakeError {
            throw NotesRelativeAssetIntakeError(.fileIntake, intakeCode: error.code)
        } catch {
            throw NotesRelativeAssetIntakeError(.fileIntake)
        }
    }

    private static func stableAssetID(
        noteID: UUID,
        metadata: LocalFileValidatedMetadata,
        filename: String
    ) -> UUID {
        let seed = Data("notes|\(noteID.uuidString)|\(metadata.sha256)|\(filename)".utf8)
        let digest = LocalFileIntakeValidator.sha256(seed)
        let raw = String(digest.prefix(32))
        let formatted = "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }

    private static func markdownDestination(in markdown: String) -> String? {
        guard let open = markdown.firstIndex(of: "("),
              let close = markdown[markdown.index(after: open)...].firstIndex(of: ")") else {
            return nil
        }
        return String(markdown[markdown.index(after: open)..<close])
    }

    private static func isDecodableImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
