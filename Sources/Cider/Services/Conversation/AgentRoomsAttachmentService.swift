import CommonCrypto
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
    private let storage: VaultFileStorage
    private let fileManager: FileManager
    private let didMaterialize: @MainActor () -> Void

    init(
        database: CiderDatabase = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        fileManager: FileManager = .default,
        didMaterialize: @escaping @MainActor () -> Void = {}
    ) {
        self.database = database
        self.vaultRoot = vaultRoot
        self.storage = VaultFileStorage(database: database)
        self.fileManager = fileManager
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
        guard url.isFileURL else {
            throw ConversationAttachmentInputError.rejected("Only local files can be attached.")
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey,
                .fileSizeKey, .nameKey,
            ])
        } catch {
            throw ConversationAttachmentInputError.rejected("The selected file is unavailable or unreadable.")
        }
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path)
        else {
            throw ConversationAttachmentInputError.rejected("Directories, aliases, symlinks, and unreadable files cannot be attached.")
        }

        let displayName = sanitizedFilename(values.name ?? url.lastPathComponent)
        guard let spec = Self.allowedSpecification(forExtension: url.pathExtension.lowercased()) else {
            throw ConversationAttachmentInputError.rejected("That file type is not supported. Choose a bounded text, PNG, JPEG, or GIF file.")
        }
        let byteSize = Int64(values.fileSize ?? -1)
        guard byteSize > 0, byteSize <= spec.maximumBytes else {
            throw ConversationAttachmentInputError.rejected("\(displayName) is empty or exceeds the \(spec.maximumBytes / 1_048_576) MB limit.")
        }
        guard existing.reduce(Int64(0), { $0 + $1.byteSize }) + byteSize <= Self.maximumTotalByteSize else {
            throw ConversationAttachmentInputError.rejected("The staged attachment total exceeds 12 MB.")
        }
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw ConversationAttachmentInputError.rejected("The selected file became unavailable or unreadable.") }
        guard Int64(data.count) == byteSize else {
            throw ConversationAttachmentInputError.rejected("The selected file changed while Cider was validating it.")
        }
        let textPreview: String?
        let imagePreviewData: Data?
        switch spec.kind {
        case .text:
            guard let text = String(data: data, encoding: .utf8) else {
                throw ConversationAttachmentInputError.rejected("Text attachments must be valid UTF-8.")
            }
            textPreview = String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(160) ?? "Text file")
            imagePreviewData = nil
        case .image:
            guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                throw ConversationAttachmentInputError.rejected("The selected image could not be decoded safely.")
            }
            textPreview = nil
            imagePreviewData = data
        }
        let hash = Self.sha256(data)
        guard !existing.contains(where: { $0.sha256 == hash }) else {
            throw ConversationAttachmentInputError.rejected("That file is already staged.")
        }
        return .init(
            id: UUID(),
            displayName: displayName,
            kind: spec.kind,
            contentType: spec.contentType,
            byteSize: byteSize,
            sha256: hash,
            inputSource: source,
            provenance: "\(source.displayName) · Local draft only",
            textPreview: textPreview,
            imagePreviewData: imagePreviewData,
            sourceURL: url
        )
    }

    func materialize(_ staged: [ConversationStagedAttachment], at date: Date) throws -> [ConversationAcceptedAttachment] {
        guard !staged.isEmpty, staged.count <= Self.maximumCount,
              Set(staged.map(\.sha256)).count == staged.count,
              staged.reduce(Int64(0), { $0 + $1.byteSize }) <= Self.maximumTotalByteSize
        else { throw ConversationAttachmentInputError.rejected("The staged attachments are no longer valid.") }

        var createdURLs: [URL] = []
        var files: [VaultFile] = []
        var accepted: [ConversationAcceptedAttachment] = []
        do {
            for item in staged {
                let revalidated = try stage(item.sourceURL, source: item.inputSource, existing: staged.filter { $0.id != item.id })
                guard revalidated.sha256 == item.sha256,
                      revalidated.byteSize == item.byteSize,
                      revalidated.contentType == item.contentType
                else { throw ConversationAttachmentInputError.rejected("An attachment changed before Send.") }
                let directoryName = item.kind == .image ? VaultFileService.inboxImagesDirName : VaultFileService.inboxFilesDirName
                let directory = vaultRoot.appendingPathComponent("Inbox/\(directoryName)", isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let vaultFileID = UUID()
                let destinationName = "\(vaultFileID.uuidString)-\(item.displayName)"
                let destination = directory.appendingPathComponent(destinationName)
                try fileManager.copyItem(at: item.sourceURL, to: destination)
                createdURLs.append(destination)
                let relativePath = "Inbox/\(directoryName)/\(destinationName)"
                let vaultFile = VaultFile(
                    id: vaultFileID,
                    filename: destinationName,
                    relativePath: relativePath,
                    fileType: item.kind == .image ? .image : .document,
                    fileSize: item.byteSize,
                    createdAt: date,
                    modifiedAt: date,
                    folderID: nil,
                    title: item.displayName
                )
                files.append(vaultFile)
                let factID = item.id
                let fact = HermesCiderAttachment(
                    id: factID.uuidString,
                    target: .init(kind: "vault_file", id: vaultFileID.uuidString, title: item.displayName, projectID: nil, artifactType: nil, source: "cider", sourceRef: "vaultFile:\(vaultFileID.uuidString)"),
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
                accepted.append(.init(
                    fact: fact,
                    payload: .init(id: factID, displayName: item.displayName, contentType: item.contentType, byteSize: item.byteSize, sha256: item.sha256, data: try Data(contentsOf: destination))
                ))
            }
            try database.withTransaction {
                for file in files { try storage.persistVaultFileToDatabaseInner(database, file: file) }
            }
            didMaterialize()
            return accepted
        } catch {
            for url in createdURLs { try? fileManager.removeItem(at: url) }
            if let safe = error as? ConversationAttachmentInputError { throw safe }
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
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard Self.sha256(data) == expectedHash, Int64(data.count) == fact.byteSize else {
                throw ConversationAttachmentInputError.rejected("A durable attachment changed and cannot be retried safely.")
            }
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

    private func sanitizedFilename(_ raw: String) -> String {
        let value = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(value)).replacingOccurrences(of: "/", with: "-")
        return String(name.prefix(160))
    }

    private static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
