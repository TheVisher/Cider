import Foundation
import ImageIO

@MainActor
final class AgentRoomsAttachmentService {
    static let maximumCount = 4
    static let maximumTextByteSize: Int64 = 1_048_576
    static let maximumImageByteSize: Int64 = 5_242_880
    static let maximumTotalByteSize: Int64 = 12_582_912

    private let database: CiderDatabase
    private let vaultRoot: URL
    private let fileManager: FileManager
    private let validator: LocalFileIntakeValidator
    private let ingestionService: VaultFileIngestionService
    private let didMaterialize: @MainActor () -> Void

    init(
        database: CiderDatabase = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        fileManager: FileManager = .default,
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        ingestionService: VaultFileIngestionService? = nil,
        didMaterialize: @escaping @MainActor () -> Void = {}
    ) {
        self.database = database
        self.vaultRoot = vaultRoot
        self.fileManager = fileManager
        self.validator = validator
        self.ingestionService = ingestionService ?? VaultFileIngestionService(
            database: database,
            vaultRoot: vaultRoot,
            storage: VaultFileStorage(database: database),
            validator: validator,
            fileManager: fileManager
        )
        self.didMaterialize = didMaterialize
    }

    func stage(
        _ url: URL,
        source: ConversationAttachmentInputSource,
        existing: [ConversationStagedAttachment]
    ) throws -> ConversationStagedAttachment {
        guard existing.count < Self.maximumCount else {
            throw ConversationAttachmentInputError.rejected("Attach up to \(Self.maximumCount) files per message.")
        }
        guard let spec = Self.allowedSpecification(forExtension: url.pathExtension.lowercased()) else {
            throw ConversationAttachmentInputError.rejected("That file type is not supported. Choose a bounded text, PNG, JPEG, or GIF file.")
        }
        let validated: LocalFileValidatedMetadata
        do {
            validated = try validator.validate(url, policy: .init(maximumByteSize: spec.maximumBytes))
        } catch let error as LocalFileIntakeError {
            throw Self.conversationError(for: error)
        }
        let displayName = validated.displayName
        let byteSize = validated.byteSize
        guard byteSize > 0 else {
            throw ConversationAttachmentInputError.rejected("\(displayName) is empty or exceeds the \(spec.maximumBytes / 1_048_576) MB limit.")
        }
        guard existing.reduce(Int64(0), { $0 + $1.byteSize }) + byteSize <= Self.maximumTotalByteSize else {
            throw ConversationAttachmentInputError.rejected("The staged attachment total exceeds 12 MB.")
        }
        let preview: (text: String?, image: Data?)
        do {
            preview = try validator.withData(
                for: validated,
                maximumByteSize: spec.maximumBytes
            ) { data in
                switch spec.kind {
                case .text:
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw ConversationAttachmentInputError.rejected("Text attachments must be valid UTF-8.")
                    }
                    return (
                        String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(160) ?? "Text file"),
                        nil
                    )
                case .image:
                    guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                        throw ConversationAttachmentInputError.rejected("The selected image could not be decoded safely.")
                    }
                    return (nil, data)
                }
            }
        } catch let error as LocalFileIntakeError {
            throw Self.conversationError(for: error)
        }
        let hash = validated.sha256
        guard !existing.contains(where: { $0.sha256 == hash }) else {
            throw ConversationAttachmentInputError.rejected("That file is already staged.")
        }
        return .init(
            id: UUID(),
            vaultFileID: UUID(),
            displayName: displayName,
            kind: spec.kind,
            contentType: spec.contentType,
            byteSize: byteSize,
            sha256: hash,
            inputSource: source,
            provenance: "\(source.displayName) · Local draft only",
            textPreview: preview.text,
            imagePreviewData: preview.image,
            sourceURL: validated.identity.accessURL,
            validatedMetadata: validated
        )
    }

    func materialize(_ staged: [ConversationStagedAttachment], at date: Date) throws -> [ConversationAcceptedAttachment] {
        guard !staged.isEmpty, staged.count <= Self.maximumCount,
              Set(staged.map(\.sha256)).count == staged.count,
              staged.reduce(Int64(0), { $0 + $1.byteSize }) <= Self.maximumTotalByteSize
        else { throw ConversationAttachmentInputError.rejected("The staged attachments are no longer valid.") }

        do {
            let requests = try staged.map { item in
                guard let specification = Self.allowedSpecification(forExtension: item.validatedMetadata.fileExtension),
                      specification.kind == item.kind,
                      specification.contentType == item.contentType,
                      item.validatedMetadata.sha256 == item.sha256,
                      item.validatedMetadata.byteSize == item.byteSize else {
                    throw ConversationAttachmentInputError.rejected("An attachment changed before Send.")
                }
                let directoryName = item.kind == .image ? VaultFileService.inboxImagesDirName : VaultFileService.inboxFilesDirName
                return VaultFileIngestionService.Request(
                    validated: item.validatedMetadata,
                    fileID: item.vaultFileID,
                    destinationRelativeDirectory: "Inbox/\(directoryName)",
                    filename: item.displayName,
                    filenameStrategy: .prefixWithStableID,
                    fileType: item.kind == .image ? .image : .document,
                    folderID: nil,
                    title: item.displayName,
                    timestamp: date
                )
            }
            let accepted = try ingestionService.ingestBatch(requests) { results in
                guard results.count == staged.count else {
                    throw ConversationAttachmentInputError.rejected("Durable attachment identity is unavailable.")
                }
                return try zip(staged, results).map { item, ingestion in
                    guard let specification = Self.allowedSpecification(forExtension: item.validatedMetadata.fileExtension) else {
                        throw ConversationAttachmentInputError.rejected("An attachment changed before Send.")
                    }
                    let vaultFile = ingestion.file
                    let canonicalURL = vaultRoot.appendingPathComponent(vaultFile.relativePath)
                    let canonicalMetadata = try validator.validate(canonicalURL)
                    guard LocalFileIntakeValidator.matchesContent(canonicalMetadata, item.validatedMetadata) else {
                        throw ConversationAttachmentInputError.rejected("An attachment changed before Send.")
                    }
                    let factID = item.id
                    let fact = HermesCiderAttachment(
                        id: factID.uuidString,
                        target: .init(kind: "vault_file", id: vaultFile.id.uuidString, title: item.displayName, projectID: nil, artifactType: nil, source: "cider", sourceRef: "vaultFile:\(vaultFile.id.uuidString)"),
                        displayName: item.displayName,
                        contentType: item.contentType,
                        byteSize: item.byteSize,
                        provenance: "user_attachment",
                        source: "cider",
                        sourceRef: "attachment:\(factID.uuidString)",
                        sha256: item.sha256,
                        inputSource: item.inputSource.rawValue,
                        lifecycle: "accepted"
                    )
                    return try validator.withData(
                        for: canonicalMetadata,
                        maximumByteSize: specification.maximumBytes
                    ) { payloadData in
                        ConversationAcceptedAttachment(
                            fact: fact,
                            payload: .init(
                                id: factID,
                                displayName: item.displayName,
                                contentType: item.contentType,
                                byteSize: item.byteSize,
                                sha256: item.sha256,
                                data: payloadData
                            )
                        )
                    }
                }
            }
            didMaterialize()
            return accepted
        } catch {
            if let safe = error as? ConversationAttachmentInputError { throw safe }
            if let intake = error as? LocalFileIntakeError {
                throw Self.conversationError(for: intake)
            }
            throw ConversationAttachmentInputError.rejected(
                "Cider could not copy the validated attachments into canonical storage."
            )
        }
    }

    func payloads(for facts: [HermesCiderAttachment]) throws -> [ConversationAttachmentTransportPayload] {
        do { return try facts.map { fact in
            guard let expectedHash = fact.sha256,
                  expectedHash.count == 64,
                  let fileID = UUID(uuidString: fact.target.id)
            else { throw ConversationAttachmentInputError.rejected("Durable attachment identity is unavailable.") }
            let statement = try database.prepare("SELECT i.relative_path FROM items i JOIN vault_files vf ON vf.item_id = i.id WHERE i.id = ? AND i.type = 'vaultFile' LIMIT 1;")
            statement.bind(fileID.uuidString, at: 1)
            guard try statement.step(), let relativePath = statement.optionalString(at: 0),
                  !relativePath.hasPrefix("/"), !relativePath.contains("..")
            else { throw ConversationAttachmentInputError.rejected("A durable attachment file is unavailable.") }
            let url = vaultRoot.appendingPathComponent(relativePath)
            let metadata = try validator.validate(url)
            guard metadata.sha256 == expectedHash, metadata.byteSize == fact.byteSize else {
                throw ConversationAttachmentInputError.rejected("A durable attachment changed and cannot be retried safely.")
            }
            let data = try validator.data(for: metadata)
            return .init(id: UUID(uuidString: fact.id)!, displayName: fact.displayName, contentType: fact.contentType, byteSize: Int64(data.count), sha256: expectedHash, data: data)
        } } catch {
            if let safe = error as? ConversationAttachmentInputError { throw safe }
            throw ConversationAttachmentInputError.rejected("A durable attachment is unavailable for retry.")
        }
    }

    func discard(_ accepted: [ConversationAcceptedAttachment]) {
        for item in accepted {
            guard let fileID = UUID(uuidString: item.fact.target.id) else { continue }
            if let statement = try? database.prepare("SELECT relative_path FROM items WHERE id = ? LIMIT 1;") {
                statement.bind(fileID.uuidString, at: 1)
                if (try? statement.step()) == true,
                   let path = statement.optionalString(at: 0), !path.hasPrefix("/"), !path.contains("..") {
                    try? fileManager.removeItem(at: vaultRoot.appendingPathComponent(path))
                }
            }
            if let delete = try? database.prepare("DELETE FROM items WHERE id = ?;") {
                delete.bind(fileID.uuidString, at: 1)
                _ = try? delete.step()
            }
        }
        if !accepted.isEmpty { didMaterialize() }
    }

    private static func allowedSpecification(forExtension ext: String) -> (kind: ConversationAttachmentKind, contentType: String, maximumBytes: Int64)? {
        switch ext {
        case "txt": (.text, "text/plain", maximumTextByteSize)
        case "md": (.text, "text/markdown", maximumTextByteSize)
        case "csv": (.text, "text/csv", maximumTextByteSize)
        case "json": (.text, "application/json", maximumTextByteSize)
        case "png": (.image, "image/png", maximumImageByteSize)
        case "jpg", "jpeg": (.image, "image/jpeg", maximumImageByteSize)
        case "gif": (.image, "image/gif", maximumImageByteSize)
        default: nil
        }
    }

    private static func conversationError(for error: LocalFileIntakeError) -> ConversationAttachmentInputError {
        switch error.code {
        case .notLocalFile:
            .rejected("Only local files can be attached.")
        case .exceedsMaximumByteSize:
            .rejected("The selected file exceeds the attachment size limit.")
        case .changedDuringValidation, .identityConflict:
            .rejected("The selected file changed while Cider was validating it.")
        case .materializationFailed, .persistenceFailed, .unsafeDestination:
            .rejected("Cider could not copy the validated attachments into canonical storage.")
        case .unavailable, .unreadable:
            .rejected("The selected file is unavailable or unreadable.")
        case .notRegularFile, .symbolicLink, .aliasFile, .pathTraversal:
            .rejected("Directories, aliases, symlinks, and unreadable files cannot be attached.")
        }
    }
}
