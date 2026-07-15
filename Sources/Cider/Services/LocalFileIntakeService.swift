import CommonCrypto
import Darwin
import Foundation
import UniformTypeIdentifiers

struct LocalFileIntakeIdentity: Equatable, Sendable {
    let accessURL: URL
    let standardizedURL: URL
    let resolvedURL: URL
    let resourceIdentifier: String?
    let volumeIdentifier: String?
}

struct LocalFileValidatedMetadata: Equatable, Sendable {
    let identity: LocalFileIntakeIdentity
    let displayName: String
    let fileExtension: String
    let contentTypeIdentifier: String?
    let byteSize: Int64
    let sha256: String
    let creationDate: Date?
    let modificationDate: Date?
}

struct LocalFileIntakeError: Error, Equatable, LocalizedError, Sendable {
    enum Code: String, Equatable, Sendable {
        case notLocalFile
        case unavailable
        case notRegularFile
        case unreadable
        case symbolicLink
        case aliasFile
        case pathTraversal
        case exceedsMaximumByteSize
        case changedDuringValidation
        case unsafeDestination
        case identityConflict
        case materializationFailed
        case persistenceFailed
    }

    let code: Code
    let maximumByteSize: Int64?

    init(_ code: Code, maximumByteSize: Int64? = nil) {
        self.code = code
        self.maximumByteSize = maximumByteSize
    }

    var errorDescription: String? {
        switch code {
        case .notLocalFile:
            "Only caller-supplied local files are supported."
        case .unavailable:
            "The selected file is unavailable."
        case .notRegularFile:
            "The selected item must be a regular file."
        case .unreadable:
            "The selected file is unreadable."
        case .symbolicLink:
            "Symbolic links and files reached through symbolic links are not supported."
        case .aliasFile:
            "Finder aliases are not supported."
        case .pathTraversal:
            "The selected file path contains unsafe traversal."
        case .exceedsMaximumByteSize:
            if let maximumByteSize {
                "The selected file exceeds the caller's \(maximumByteSize)-byte limit."
            } else {
                "The selected file exceeds the caller's size limit."
            }
        case .changedDuringValidation:
            "The selected file changed while Cider was validating or copying it."
        case .unsafeDestination:
            "The canonical storage destination is unsafe."
        case .identityConflict:
            "The stable file identity conflicts with different canonical content."
        case .materializationFailed:
            "Cider could not copy the validated file into canonical storage."
        case .persistenceFailed:
            "Cider could not persist the canonical file identity."
        }
    }
}

final class LocalFileIntakeValidator {
    struct Policy: Equatable, Sendable {
        var maximumByteSize: Int64?

        init(maximumByteSize: Int64? = nil) {
            self.maximumByteSize = maximumByteSize
        }
    }

    struct Hooks {
        var afterInitialSnapshot: (() throws -> Void)?
        var isReadableFile: ((String) -> Bool)?
        var startAccessingSecurityScopedResource: ((URL) -> Bool)?
        var stopAccessingSecurityScopedResource: ((URL) -> Void)?
        var beforeFileRead: ((_ accessURL: URL, _ readURL: URL) throws -> Void)?

        init(
            afterInitialSnapshot: (() throws -> Void)? = nil,
            isReadableFile: ((String) -> Bool)? = nil,
            startAccessingSecurityScopedResource: ((URL) -> Bool)? = nil,
            stopAccessingSecurityScopedResource: ((URL) -> Void)? = nil,
            beforeFileRead: ((_ accessURL: URL, _ readURL: URL) throws -> Void)? = nil
        ) {
            self.afterInitialSnapshot = afterInitialSnapshot
            self.isReadableFile = isReadableFile
            self.startAccessingSecurityScopedResource = startAccessingSecurityScopedResource
            self.stopAccessingSecurityScopedResource = stopAccessingSecurityScopedResource
            self.beforeFileRead = beforeFileRead
        }
    }

    private struct Snapshot: Equatable {
        let identity: LocalFileIntakeIdentity
        let displayName: String
        let fileExtension: String
        let contentTypeIdentifier: String?
        let byteSize: Int64
        let creationDate: Date?
        let modificationDate: Date?
    }

    private let fileManager: FileManager
    private let hooks: Hooks

    init(fileManager: FileManager = .default, hooks: Hooks = .init()) {
        self.fileManager = fileManager
        self.hooks = hooks
    }

    @discardableResult
    func validate(
        _ url: URL,
        policy: Policy = .init()
    ) throws -> LocalFileValidatedMetadata {
        try withSecurityScopedAccess(to: url) {
            try validateWithinActiveScope(accessURL: url, locationURL: url, policy: policy)
        }
    }

    private func validateWithinActiveScope(
        accessURL: URL,
        locationURL: URL,
        policy: Policy
    ) throws -> LocalFileValidatedMetadata {
        let before = try snapshot(locationURL, accessURL: accessURL, policy: policy)
        do {
            try hooks.afterInitialSnapshot?()
        } catch let error as LocalFileIntakeError {
            throw error
        } catch {
            throw LocalFileIntakeError(.changedDuringValidation)
        }

        let digest: String
        do {
            try notifyBeforeFileRead(accessURL: accessURL, readURL: before.identity.standardizedURL)
            digest = try Self.sha256(of: before.identity.standardizedURL)
        } catch {
            throw LocalFileIntakeError(.unreadable)
        }
        let after = try snapshot(locationURL, accessURL: accessURL, policy: policy)
        guard before == after else {
            throw LocalFileIntakeError(.changedDuringValidation)
        }

        return LocalFileValidatedMetadata(
            identity: after.identity,
            displayName: after.displayName,
            fileExtension: after.fileExtension,
            contentTypeIdentifier: after.contentTypeIdentifier,
            byteSize: after.byteSize,
            sha256: digest,
            creationDate: after.creationDate,
            modificationDate: after.modificationDate
        )
    }

    @discardableResult
    func revalidate(
        _ validated: LocalFileValidatedMetadata,
        policy: Policy = .init()
    ) throws -> LocalFileValidatedMetadata {
        try withSecurityScopedAccess(to: validated.identity.accessURL) {
            try revalidateWithinActiveScope(validated, policy: policy)
        }
    }

    func revalidateWithinActiveScope(
        _ validated: LocalFileValidatedMetadata,
        policy: Policy = .init()
    ) throws -> LocalFileValidatedMetadata {
        let current = try validateWithinActiveScope(
            accessURL: validated.identity.accessURL,
            locationURL: validated.identity.standardizedURL,
            policy: policy
        )
        guard Self.matchesValidatedContent(current, validated) else {
            throw LocalFileIntakeError(.changedDuringValidation)
        }
        return current
    }

    func data(
        for validated: LocalFileValidatedMetadata,
        maximumByteSize: Int64? = nil
    ) throws -> Data {
        try withData(for: validated, maximumByteSize: maximumByteSize) { $0 }
    }

    func withData<T>(
        for validated: LocalFileValidatedMetadata,
        maximumByteSize: Int64? = nil,
        _ body: (Data) throws -> T
    ) throws -> T {
        let policy = Policy(maximumByteSize: maximumByteSize)
        return try withSecurityScopedAccess(to: validated.identity.accessURL) {
            _ = try revalidateWithinActiveScope(validated, policy: policy)
            let data: Data
            do {
                try notifyBeforeFileRead(
                    accessURL: validated.identity.accessURL,
                    readURL: validated.identity.standardizedURL
                )
                data = try Data(contentsOf: validated.identity.standardizedURL, options: .mappedIfSafe)
            } catch let error as LocalFileIntakeError {
                throw error
            } catch {
                throw LocalFileIntakeError(.unreadable)
            }
            guard Int64(data.count) == validated.byteSize,
                  Self.sha256(data) == validated.sha256 else {
                throw LocalFileIntakeError(.changedDuringValidation)
            }
            let result = try body(data)
            _ = try revalidateWithinActiveScope(validated, policy: policy)
            return result
        }
    }

    func withSecurityScopedAccess<T>(
        to accessURL: URL,
        _ body: () throws -> T
    ) rethrows -> T {
        let didAccess = hooks.startAccessingSecurityScopedResource?(accessURL)
            ?? accessURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                if let stop = hooks.stopAccessingSecurityScopedResource {
                    stop(accessURL)
                } else {
                    accessURL.stopAccessingSecurityScopedResource()
                }
            }
        }
        return try body()
    }

    static func matchesValidatedContent(
        _ lhs: LocalFileValidatedMetadata,
        _ rhs: LocalFileValidatedMetadata
    ) -> Bool {
        lhs.identity == rhs.identity
            && lhs.byteSize == rhs.byteSize
            && lhs.sha256 == rhs.sha256
            && lhs.creationDate == rhs.creationDate
            && lhs.modificationDate == rhs.modificationDate
    }

    static func matchesContent(
        _ lhs: LocalFileValidatedMetadata,
        _ rhs: LocalFileValidatedMetadata
    ) -> Bool {
        lhs.byteSize == rhs.byteSize && lhs.sha256 == rhs.sha256
    }

    private func snapshot(_ url: URL, accessURL: URL, policy: Policy) throws -> Snapshot {
        guard url.isFileURL else {
            throw LocalFileIntakeError(.notLocalFile)
        }
        guard !Self.hasTraversalComponent(url) else {
            throw LocalFileIntakeError(.pathTraversal)
        }

        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.path == resolved.path else {
            throw LocalFileIntakeError(.symbolicLink)
        }

        let values: URLResourceValues
        do {
            try notifyBeforeFileRead(accessURL: accessURL, readURL: standardized)
            values = try standardized.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
                .fileSizeKey,
                .nameKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey,
                .volumeIdentifierKey,
                .contentTypeKey,
            ])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw LocalFileIntakeError(.unavailable)
        } catch {
            throw LocalFileIntakeError(.unreadable)
        }

        if values.isSymbolicLink == true {
            throw LocalFileIntakeError(.symbolicLink)
        }
        if values.isAliasFile == true {
            throw LocalFileIntakeError(.aliasFile)
        }
        guard values.isRegularFile == true, values.isDirectory != true else {
            throw LocalFileIntakeError(.notRegularFile)
        }
        guard fileManager.fileExists(atPath: standardized.path) else {
            throw LocalFileIntakeError(.unavailable)
        }
        let isReadable = hooks.isReadableFile?(standardized.path)
            ?? fileManager.isReadableFile(atPath: standardized.path)
        guard isReadable else {
            throw LocalFileIntakeError(.unreadable)
        }

        let byteSize = Int64(values.fileSize ?? -1)
        guard byteSize >= 0 else {
            throw LocalFileIntakeError(.unreadable)
        }
        if let maximum = policy.maximumByteSize, byteSize > maximum {
            throw LocalFileIntakeError(.exceedsMaximumByteSize, maximumByteSize: maximum)
        }

        let displayName = Self.sanitizedFilename(values.name ?? standardized.lastPathComponent)
        let fileExtension = standardized.pathExtension.lowercased()
        let contentType = values.contentType?.identifier
            ?? UTType(filenameExtension: fileExtension)?.identifier
        return Snapshot(
            identity: LocalFileIntakeIdentity(
                accessURL: accessURL,
                standardizedURL: standardized,
                resolvedURL: resolved,
                resourceIdentifier: Self.boundedIdentifier(values.fileResourceIdentifier),
                volumeIdentifier: Self.boundedIdentifier(values.volumeIdentifier)
            ),
            displayName: displayName,
            fileExtension: fileExtension,
            contentTypeIdentifier: contentType,
            byteSize: byteSize,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
    }

    private func notifyBeforeFileRead(accessURL: URL, readURL: URL) throws {
        do {
            try hooks.beforeFileRead?(accessURL, readURL)
        } catch let error as LocalFileIntakeError {
            throw error
        } catch {
            throw LocalFileIntakeError(.unreadable)
        }
    }

    private static func hasTraversalComponent(_ url: URL) -> Bool {
        url.path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    static func sanitizedFilename(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && scalar != "/" && scalar != ":"
        }
        let value = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeValue = value.isEmpty || value == "." || value == ".." ? "File" : value
        return String(safeValue.prefix(160))
    }

    private static func boundedIdentifier(_ value: Any?) -> String? {
        guard let value else { return nil }
        return String(String(describing: value).prefix(256))
    }

    static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        while true {
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            data.withUnsafeBytes { buffer in
                _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(data.count))
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class VaultFileIngestionService {
    enum FilenameStrategy: Equatable, Sendable {
        case preserveWithUniqueSuffix
        case prefixWithStableID
    }

    struct Request: Sendable {
        let validated: LocalFileValidatedMetadata
        let fileID: UUID
        let destinationRelativeDirectory: String
        let filename: String
        let filenameStrategy: FilenameStrategy
        let fileType: VaultFileType
        let folderID: UUID?
        let title: String?
        let timestamp: Date?
    }

    struct Result: Equatable, Sendable {
        let file: VaultFile
        let validatedMetadata: LocalFileValidatedMetadata
        let wasReused: Bool
    }

    struct Hooks {
        var beforeSourceCopy: (@MainActor (_ accessURL: URL, _ sourceURL: URL, _ destinationURL: URL) throws -> Void)?
        var afterCopy: (@MainActor (URL) throws -> Void)?
        var beforeDatabasePersist: (@MainActor (VaultFile) throws -> Void)?

        init(
            beforeSourceCopy: (@MainActor (_ accessURL: URL, _ sourceURL: URL, _ destinationURL: URL) throws -> Void)? = nil,
            afterCopy: (@MainActor (URL) throws -> Void)? = nil,
            beforeDatabasePersist: (@MainActor (VaultFile) throws -> Void)? = nil
        ) {
            self.beforeSourceCopy = beforeSourceCopy
            self.afterCopy = afterCopy
            self.beforeDatabasePersist = beforeDatabasePersist
        }
    }

    private enum Phase {
        case validation
        case filesystem
        case persistence
    }

    private enum PreparedRequest {
        case reused(Result)
        case created(file: VaultFile, validated: LocalFileValidatedMetadata)
    }

    private struct FinalizationFailure: Error {
        let underlying: any Error
    }

    private let database: CiderDatabase
    private let vaultRoot: URL
    private let storage: VaultFileStorage
    private let validator: LocalFileIntakeValidator
    private let fileManager: FileManager
    private let hooks: Hooks

    init(
        database: CiderDatabase,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        storage: VaultFileStorage? = nil,
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        fileManager: FileManager = .default,
        hooks: Hooks = .init()
    ) {
        self.database = database
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.storage = storage ?? VaultFileStorage(database: database)
        self.validator = validator
        self.fileManager = fileManager
        self.hooks = hooks
    }

    func ingest(_ request: Request) throws -> Result {
        try ingestBatch([request]) { results in
            guard let result = results.first else {
                throw LocalFileIntakeError(.persistenceFailed)
            }
            return result
        }
    }

    func ingestBatch<T>(
        _ requests: [Request],
        finalize: @MainActor ([Result]) throws -> T
    ) throws -> T {
        guard Set(requests.map(\.fileID)).count == requests.count else {
            throw LocalFileIntakeError(.identityConflict)
        }
        var phase = Phase.validation
        var materializedURLs: [URL] = []
        var createdDirectories: [URL] = []
        do {
            var prepared: [PreparedRequest] = []
            prepared.reserveCapacity(requests.count)
            for request in requests {
                if let reused = try reusableResult(for: request) {
                    prepared.append(.reused(reused))
                    continue
                }
                phase = .filesystem
                prepared.append(try prepareNewFile(
                    for: request,
                    materializedURLs: &materializedURLs,
                    createdDirectories: &createdDirectories
                ))
                phase = .validation
            }

            phase = .persistence
            return try database.withTransaction {
                var results: [Result] = []
                results.reserveCapacity(prepared.count)
                for item in prepared {
                    switch item {
                    case .reused(let result):
                        results.append(result)
                    case .created(let file, let validated):
                        try hooks.beforeDatabasePersist?(file)
                        try storage.persistVaultFileToDatabaseInner(database, file: file)
                        guard let persisted = try existingFile(id: file.id),
                              persisted.filename == file.filename,
                              persisted.relativePath == file.relativePath,
                              persisted.fileType == file.fileType,
                              persisted.folderID == file.folderID else {
                            throw LocalFileIntakeError(.persistenceFailed)
                        }
                        results.append(.init(
                            file: persisted,
                            validatedMetadata: validated,
                            wasReused: false
                        ))
                    }
                }
                do {
                    return try finalize(results)
                } catch {
                    throw FinalizationFailure(underlying: error)
                }
            }
        } catch {
            for url in materializedURLs.reversed() {
                try? fileManager.removeItem(at: url)
            }
            for directory in createdDirectories {
                if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                    try? fileManager.removeItem(at: directory)
                }
            }
            if let finalization = error as? FinalizationFailure {
                throw finalization.underlying
            }
            if let intakeError = error as? LocalFileIntakeError {
                throw intakeError
            }
            switch phase {
            case .validation:
                throw LocalFileIntakeError(.changedDuringValidation)
            case .filesystem:
                throw LocalFileIntakeError(.materializationFailed)
            case .persistence:
                throw LocalFileIntakeError(.persistenceFailed)
            }
        }
    }

    private func reusableResult(for request: Request) throws -> Result? {
        guard let existingType = try existingItemType(id: request.fileID) else { return nil }
        guard existingType == "vaultFile",
              let existing = try existingFile(id: request.fileID),
              matchesCanonicalContract(existing, request: request) else {
            throw LocalFileIntakeError(.identityConflict)
        }
        let canonicalURL: URL
        let canonicalMetadata: LocalFileValidatedMetadata
        do {
            canonicalURL = try containedURL(relativePath: existing.relativePath)
            canonicalMetadata = try validator.validate(canonicalURL)
        } catch {
            throw LocalFileIntakeError(.identityConflict)
        }
        guard LocalFileIntakeValidator.matchesContent(canonicalMetadata, request.validated) else {
            throw LocalFileIntakeError(.identityConflict)
        }
        return Result(file: existing, validatedMetadata: request.validated, wasReused: true)
    }

    private func prepareNewFile(
        for request: Request,
        materializedURLs: inout [URL],
        createdDirectories: inout [URL]
    ) throws -> PreparedRequest {
        let sourceURL = request.validated.identity.standardizedURL
        return try validator.withSecurityScopedAccess(to: request.validated.identity.accessURL) {
            _ = try validator.revalidateWithinActiveScope(request.validated)
            let directory = try createDestinationDirectory(
                request.destinationRelativeDirectory,
                createdDirectories: &createdDirectories
            )
            let destination = try uniqueDestinationURL(
                filename: request.filename,
                fileID: request.fileID,
                strategy: request.filenameStrategy,
                directory: directory
            )
            let temporary = directory.appendingPathComponent(".cider-intake-\(UUID().uuidString).partial")
            materializedURLs.append(temporary)
            try hooks.beforeSourceCopy?(request.validated.identity.accessURL, sourceURL, temporary)
            try fileManager.copyItem(at: sourceURL, to: temporary)
            try hooks.afterCopy?(temporary)

            let copied = try validator.validate(temporary)
            guard LocalFileIntakeValidator.matchesContent(copied, request.validated) else {
                throw LocalFileIntakeError(.changedDuringValidation)
            }
            _ = try validator.revalidateWithinActiveScope(request.validated)
            try validateDestinationDirectory(directory, relativePath: request.destinationRelativeDirectory)
            guard !entryExists(at: destination) else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            materializedURLs.append(destination)
            try validateExistingComponent(destination, requiresDirectory: false)

            let values = try? destination.resourceValues(forKeys: [
                .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            ])
            let timestamp = request.timestamp
            let relativePath = try vaultRelativePath(destination)
            let file = VaultFile(
                id: request.fileID,
                filename: destination.lastPathComponent,
                relativePath: relativePath,
                fileType: request.fileType,
                fileSize: Int64(values?.fileSize ?? Int(request.validated.byteSize)),
                createdAt: timestamp ?? values?.creationDate ?? request.validated.creationDate ?? Date(),
                modifiedAt: timestamp ?? values?.contentModificationDate ?? request.validated.modificationDate ?? Date(),
                folderID: request.folderID,
                title: request.title
            )
            return .created(file: file, validated: request.validated)
        }
    }

    private func existingItemType(id: UUID) throws -> String? {
        let statement = try database.prepare("SELECT type FROM items WHERE id = ? LIMIT 1;")
        statement.bind(id.uuidString, at: 1)
        guard try statement.step() else { return nil }
        return statement.string(at: 0)
    }

    private func existingFile(id: UUID) throws -> VaultFile? {
        let statement = try database.prepare("""
            SELECT i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                   vf.filename, vf.file_type, vf.file_size, vf.notes, vf.ocr_text, vf.dominant_colors,
                   vf.title_manually_set
            FROM items i
            JOIN vault_files vf ON vf.item_id = i.id
            WHERE i.id = ? AND i.type = 'vaultFile'
            LIMIT 1;
            """)
        statement.bind(id.uuidString, at: 1)
        guard try statement.step(),
              let relativePath = statement.optionalString(at: 4),
              let fileType = VaultFileType(rawValue: statement.string(at: 6)) else {
            return nil
        }
        let filename = statement.string(at: 5)
        let titleManuallySet = statement.int(at: 11) != 0
        let storedTitle = statement.string(at: 0)
        let filenameStem = (filename as NSString).deletingPathExtension
        let title = titleManuallySet || storedTitle != filenameStem ? storedTitle : nil
        return VaultFile(
            id: id,
            filename: filename,
            relativePath: relativePath,
            fileType: fileType,
            fileSize: Int64(statement.int(at: 7)),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 1)),
            modifiedAt: DatabaseHelpers.decodeDate(statement.double(at: 2)),
            folderID: statement.optionalString(at: 3).flatMap(UUID.init(uuidString:)),
            title: title,
            notes: statement.string(at: 8),
            ocrText: statement.optionalString(at: 9),
            dominantColors: statement.optionalString(at: 10).map(DatabaseHelpers.decodeStringArray)
        )
    }

    private func destinationDirectory(_ relativePath: String) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        let directory = vaultRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        try validateDestinationDirectory(directory, relativePath: relativePath)
        return directory
    }

    private func createDestinationDirectory(
        _ relativePath: String,
        createdDirectories: inout [URL]
    ) throws -> URL {
        let directory = try destinationDirectory(relativePath)
        if !entryExists(at: directory) {
            var candidate = directory
            while candidate.path != vaultRoot.path, !entryExists(at: candidate) {
                if !createdDirectories.contains(candidate) {
                    createdDirectories.append(candidate)
                }
                candidate = candidate.deletingLastPathComponent()
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try validateDestinationDirectory(directory, relativePath: relativePath)
        return directory
    }

    private func containedURL(relativePath: String) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        let url = vaultRoot.appendingPathComponent(relativePath).standardizedFileURL
        let components = relativePath.split(separator: "/").map(String.init)
        try validateExistingComponent(vaultRoot, requiresDirectory: true)
        var candidate = vaultRoot
        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(component, isDirectory: index < components.count - 1)
            guard entryExists(at: candidate) else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
            try validateExistingComponent(candidate, requiresDirectory: index < components.count - 1)
        }
        guard candidate.standardizedFileURL == url else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        return url
    }

    private func vaultRelativePath(_ url: URL) throws -> String {
        let rootPath = vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private func uniqueDestinationURL(
        filename: String,
        fileID: UUID,
        strategy: FilenameStrategy,
        directory: URL
    ) throws -> URL {
        let initialName = initialFilename(filename: filename, fileID: fileID, strategy: strategy)
        let base = (initialName as NSString).deletingPathExtension
        let ext = (initialName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(initialName)
        var counter = 2
        while entryExists(at: candidate) {
            try validateExistingEntryIsNotRedirect(candidate)
            let candidateName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(candidateName)
            counter += 1
        }
        return candidate
    }

    private func initialFilename(
        filename: String,
        fileID: UUID,
        strategy: FilenameStrategy
    ) -> String {
        let safeName = LocalFileIntakeValidator.sanitizedFilename(filename)
        switch strategy {
        case .preserveWithUniqueSuffix:
            return safeName
        case .prefixWithStableID:
            return "\(fileID.uuidString)-\(safeName)"
        }
    }

    private func matchesCanonicalContract(_ existing: VaultFile, request: Request) -> Bool {
        guard existing.fileType == request.fileType,
              existing.folderID == request.folderID,
              existing.filename == URL(fileURLWithPath: existing.relativePath).lastPathComponent else {
            return false
        }
        let existingDirectory = (existing.relativePath as NSString).deletingLastPathComponent
        guard existingDirectory == request.destinationRelativeDirectory else { return false }
        let initialName = initialFilename(
            filename: request.filename,
            fileID: request.fileID,
            strategy: request.filenameStrategy
        )
        if request.filenameStrategy == .preserveWithUniqueSuffix,
           existing.filename.hasPrefix("\(request.fileID.uuidString)-") {
            return false
        }
        return Self.matchesUniqueFilename(existing.filename, initialName: initialName)
    }

    private static func matchesUniqueFilename(_ filename: String, initialName: String) -> Bool {
        guard filename != initialName else { return true }
        let base = (initialName as NSString).deletingPathExtension
        let ext = (initialName as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        guard filename.hasPrefix("\(base) ("), filename.hasSuffix(")\(suffix)") else {
            return false
        }
        let start = filename.index(filename.startIndex, offsetBy: base.count + 2)
        let end = filename.index(filename.endIndex, offsetBy: -(suffix.count + 1))
        guard start < end, let value = Int(filename[start..<end]) else { return false }
        return value >= 2
    }

    private func validateDestinationDirectory(_ directory: URL, relativePath: String) throws {
        let expected = vaultRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        guard directory.standardizedFileURL == expected else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        try validateExistingComponent(vaultRoot, requiresDirectory: true)
        var candidate = vaultRoot
        for component in relativePath.split(separator: "/").map(String.init) {
            candidate.appendPathComponent(component, isDirectory: true)
            if entryExists(at: candidate) {
                try validateExistingComponent(candidate, requiresDirectory: true)
            }
        }
    }

    private func validateExistingComponent(_ url: URL, requiresDirectory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw LocalFileIntakeError(.unsafeDestination)
        }
        let fileKind = info.st_mode & S_IFMT
        guard fileKind != S_IFLNK else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isAliasFileKey, .isDirectoryKey, .isRegularFileKey])
        } catch {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        guard values.isAliasFile != true else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        if requiresDirectory {
            guard fileKind == S_IFDIR, values.isDirectory == true else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
        } else {
            guard fileKind == S_IFREG, values.isRegularFile == true else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
        }
    }

    private func validateExistingEntryIsNotRedirect(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        guard info.st_mode & S_IFMT != S_IFLNK else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        do {
            let values = try url.resourceValues(forKeys: [.isAliasFileKey])
            guard values.isAliasFile != true else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
        } catch let error as LocalFileIntakeError {
            throw error
        } catch {
            throw LocalFileIntakeError(.unsafeDestination)
        }
    }

    private func entryExists(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}
