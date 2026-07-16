import Darwin
import Foundation
import ImageIO

enum JournalMediaKind: String, Equatable, Sendable {
    case audio
    case photo
    case media
}

struct JournalMediaIntakePolicy: Equatable, Sendable {
    static let defaultMaximumByteSize: Int64 = 512 * 1024 * 1024

    var maximumByteSize: Int64?
    var maximumAudioDuration: TimeInterval?

    init(maximumByteSize: Int64? = defaultMaximumByteSize, maximumAudioDuration: TimeInterval? = nil) {
        self.maximumByteSize = maximumByteSize
        self.maximumAudioDuration = maximumAudioDuration
    }
}

struct JournalMediaIntakeRequest: Equatable, Sendable {
    let sourceURL: URL
    let sourceID: String
    let kind: JournalMediaKind
    let capturedAt: Date
    let displayName: String?
    fileprivate let stableSourceDigest: String

    init(
        sourceURL: URL,
        sourceID: String,
        kind: JournalMediaKind,
        capturedAt: Date,
        displayName: String? = nil
    ) {
        self.sourceURL = sourceURL
        let completeDigest = LocalFileIntakeValidator.sha256(Data(sourceID.utf8))
        let normalizedSourceID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedSourceID = normalizedSourceID.localizedLowercase
        let looksLikePrivatePath = normalizedSourceID.hasPrefix("/")
            || normalizedSourceID.hasPrefix("~/")
            || lowercasedSourceID.hasPrefix("file://")
            || normalizedSourceID.contains("/Users/")
            || normalizedSourceID.contains("/private/")
        self.sourceID = sourceID.count <= 256 && !looksLikePrivatePath
            ? sourceID
            : "journal-\(kind.rawValue)-sha256-\(completeDigest)"
        self.stableSourceDigest = completeDigest
        self.kind = kind
        self.capturedAt = capturedAt
        self.displayName = displayName.map { String($0.prefix(160)) }
    }
}

struct JournalMediaIntakeError: Error, Equatable, LocalizedError, Sendable {
    enum Code: String, Equatable, Sendable {
        case fileIntake
        case unsupportedType
        case durationUnavailable
        case durationExceeded
        case transcriptionUnavailable
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
            "Cider could not safely retain the selected Journal original."
        case .unsupportedType:
            "That file type is not supported for this Journal media source."
        case .durationUnavailable:
            "Cider could not verify the Journal audio duration."
        case .durationExceeded:
            "The Journal audio exceeds the configured duration limit."
        case .transcriptionUnavailable:
            "The retained Journal audio is unavailable for transcription."
        }
    }
}

struct JournalStoredOriginal: Equatable, Sendable, Comparable {
    let file: VaultFile
    let sourceID: String
    let sourceCardID: String
    let capturedAt: Date
    let kind: JournalMediaKind
    let byteSize: Int64
    let sha256: String
    let retention: TranscriptionSourceRetention
    let wasReused: Bool

    var previewPresentation: VaultFileMediaPreviewPresentation {
        VaultFileMediaPreviewPolicy.presentation(for: file)
    }

    static func < (lhs: JournalStoredOriginal, rhs: JournalStoredOriginal) -> Bool {
        if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
        return lhs.sourceCardID < rhs.sourceCardID
    }
}

struct JournalValidatedMediaBatch: Equatable, Sendable {
    fileprivate let requests: [JournalMediaIntakeRequest]
    fileprivate let validated: [LocalFileValidatedMetadata]

    /// Ordered, path-free identities for exact-retry comparison.
    var contentHashes: [String] { validated.map(\.sha256) }
}

/// Journal-owned adapter that retains an immutable original before any source-card
/// or transcription work. It deliberately composes VaultFile storage without
/// inheriting Chat composer policy.
@MainActor
final class JournalMediaIntakeService {
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "alac", "caf", "flac", "m4a", "mp3", "ogg", "wav", "wma"
    ]
    private static let photoExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]
    private static let mediaExtensions = audioExtensions.union(photoExtensions).union([
        "avi", "m4v", "mkv", "mov", "mp4", "webm", "wmv"
    ])

    private let vaultRoot: URL
    private let validator: LocalFileIntakeValidator
    private let ingestionService: VaultFileIngestionService
    private let transcriptionService: any CiderTranscriptionServicing
    private let policy: JournalMediaIntakePolicy
    private let audioDuration: (URL) throws -> TimeInterval?
    private let fileManager: FileManager
    private let transcriptionWorkingRoot: URL

    init(
        database: CiderDatabase,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        ingestionService: VaultFileIngestionService? = nil,
        transcriptionService: (any CiderTranscriptionServicing)? = nil,
        policy: JournalMediaIntakePolicy = .init(),
        audioDuration: @escaping (URL) throws -> TimeInterval? = { _ in nil },
        fileManager: FileManager = .default,
        transcriptionWorkingRoot: URL? = nil
    ) {
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.validator = validator
        self.ingestionService = ingestionService ?? VaultFileIngestionService(
            database: database,
            vaultRoot: vaultRoot,
            storage: VaultFileStorage(database: database),
            validator: validator
        )
        self.transcriptionService = transcriptionService ?? CiderTranscriptionProviderSelection.makeDefault()
        self.policy = policy
        self.audioDuration = audioDuration
        self.fileManager = fileManager
        self.transcriptionWorkingRoot = (transcriptionWorkingRoot ?? fileManager.temporaryDirectory
            .appendingPathComponent("cider-journal-transcription", isDirectory: true)).standardizedFileURL
    }

    func ingest(_ request: JournalMediaIntakeRequest) throws -> JournalStoredOriginal {
        try ingest(request) { $0 }
    }

    func ingest<T>(
        _ request: JournalMediaIntakeRequest,
        createSourceCard: @MainActor (JournalStoredOriginal) throws -> T
    ) throws -> T {
        try ingestBatch([request]) { originals in
            guard let original = originals.first else {
                throw LocalFileIntakeError(.persistenceFailed)
            }
            return try createSourceCard(original)
        }
    }

    /// Validates every source before materializing any of them, then commits all
    /// originals and caller-owned source-card state in one SQLite transaction.
    /// This is the Journal writer seam for one logical capture with many media
    /// sources; callers must not loop over the single-file API when atomicity is
    /// required.
    func ingestBatch<T>(
        _ requests: [JournalMediaIntakeRequest],
        createSourceCards: @MainActor ([JournalStoredOriginal]) throws -> T
    ) throws -> T {
        try ingestBatch(try validateBatch(requests), createSourceCards: createSourceCards)
    }

    /// Produces the exact validated source identities used by ingestion. Callers
    /// may persist the ordered content hashes as part of a durable request receipt.
    func validateBatch(_ requests: [JournalMediaIntakeRequest]) throws -> JournalValidatedMediaBatch {
        guard !requests.isEmpty else {
            return JournalValidatedMediaBatch(requests: [], validated: [])
        }
        let validated: [LocalFileValidatedMetadata]
        do {
            validated = try requests.map { request in
                try validator.validate(
                    request.sourceURL,
                    policy: .init(maximumByteSize: effectiveMaximumByteSize)
                )
            }
        } catch let error as LocalFileIntakeError {
            throw JournalMediaIntakeError(.fileIntake, intakeCode: error.code)
        } catch {
            throw JournalMediaIntakeError(.fileIntake)
        }

        do {
            for (metadata, request) in zip(validated, requests) {
                try validate(metadata, for: request)
            }
            return JournalValidatedMediaBatch(requests: requests, validated: validated)
        } catch let error as LocalFileIntakeError {
            throw JournalMediaIntakeError(.fileIntake, intakeCode: error.code)
        } catch let error as JournalMediaIntakeError {
            throw error
        } catch {
            throw JournalMediaIntakeError(.fileIntake)
        }
    }

    func ingestBatch<T>(
        _ batch: JournalValidatedMediaBatch,
        createSourceCards: @MainActor ([JournalStoredOriginal]) throws -> T
    ) throws -> T {
        let requests = batch.requests
        let validated = batch.validated
        guard !requests.isEmpty else { return try createSourceCards([]) }
        do {
            let ingestionRequests = zip(validated, requests).map { metadata, request in
                let stableID = Self.stableFileID(sourceDigest: request.stableSourceDigest, kind: request.kind)
                return VaultFileIngestionService.Request(
                    validated: metadata,
                    fileID: stableID,
                    destinationRelativeDirectory: destinationDirectory(for: request.kind),
                    // The immutable original keeps the caller's raw filename.
                    // Friendly Journal copy belongs in the canonical title
                    // overlay and must not leak back into file identity.
                    filename: metadata.displayName,
                    filenameStrategy: .prefixWithStableID,
                    fileType: canonicalFileType(for: metadata.fileExtension, kind: request.kind),
                    folderID: nil,
                    title: request.displayName
                        ?? (metadata.displayName as NSString).deletingPathExtension,
                    timestamp: request.capturedAt
                )
            }
            return try ingestionService.ingestBatch(ingestionRequests) { results in
                guard results.count == requests.count else {
                    throw LocalFileIntakeError(.persistenceFailed)
                }
                let originals = zip(zip(results, validated), requests).map { pair, request in
                    let (result, metadata) = pair
                    let stableID = Self.stableFileID(sourceDigest: request.stableSourceDigest, kind: request.kind)
                    return JournalStoredOriginal(
                        file: result.file,
                        sourceID: request.sourceID,
                        sourceCardID: Self.sourceCardID(capturedAt: request.capturedAt, stableID: stableID),
                        capturedAt: request.capturedAt,
                        kind: request.kind,
                        byteSize: metadata.byteSize,
                        sha256: metadata.sha256,
                        retention: .preserveOriginal,
                        wasReused: result.wasReused
                    )
                }
                return try createSourceCards(originals)
            }
        } catch let error as LocalFileIntakeError {
            throw JournalMediaIntakeError(.fileIntake, intakeCode: error.code)
        } catch let error as JournalMediaIntakeError {
            throw error
        } catch {
            throw JournalMediaIntakeError(.fileIntake)
        }
    }

    private func validate(
        _ validated: LocalFileValidatedMetadata,
        for request: JournalMediaIntakeRequest
    ) throws {
        guard supports(validated.fileExtension, kind: request.kind) else {
            throw JournalMediaIntakeError(.unsupportedType)
        }
        if request.kind == .photo {
            do {
                try validator.withData(for: validated) { data in
                    guard Self.isDecodableImage(data) else {
                        throw JournalMediaIntakeError(.unsupportedType)
                    }
                }
            } catch let error as JournalMediaIntakeError {
                throw error
            } catch let error as LocalFileIntakeError {
                throw JournalMediaIntakeError(.fileIntake, intakeCode: error.code)
            } catch {
                throw JournalMediaIntakeError(.unsupportedType)
            }
        }
        if request.kind == .audio, let maximumDuration = policy.maximumAudioDuration {
            let duration: TimeInterval?
            do {
                duration = try validator.withSecurityScopedAccess(to: validated.identity.accessURL) {
                    _ = try validator.revalidateWithinActiveScope(
                        validated,
                        policy: .init(maximumByteSize: effectiveMaximumByteSize)
                    )
                    let measured = try audioDuration(validated.identity.standardizedURL)
                    _ = try validator.revalidateWithinActiveScope(
                        validated,
                        policy: .init(maximumByteSize: effectiveMaximumByteSize)
                    )
                    return measured
                }
            } catch let error as LocalFileIntakeError {
                throw JournalMediaIntakeError(.fileIntake, intakeCode: error.code)
            } catch {
                throw JournalMediaIntakeError(.durationUnavailable)
            }
            guard let duration else { throw JournalMediaIntakeError(.durationUnavailable) }
            guard duration <= maximumDuration else { throw JournalMediaIntakeError(.durationExceeded) }
        }
    }

    /// Transcribes one already validated caller-owned audio source through a
    /// disposable read-only copy. This is the pre-commit seam for atomic voice
    /// capture: the validated bytes are not materialized in canonical storage
    /// unless the caller later commits the same batch through the atomic writer.
    func transcribeValidatedAudio(
        _ batch: JournalValidatedMediaBatch,
        at index: Int = 0,
        using service: any CiderTranscriptionServicing
    ) async -> TranscriptionResult {
        guard batch.requests.indices.contains(index), batch.validated.indices.contains(index) else {
            return .failure(.init(
                code: .invalidSource,
                message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription
            ))
        }
        let request = batch.requests[index]
        let validated = batch.validated[index]
        guard request.kind == .audio else {
            return .failure(.init(
                code: .invalidSource,
                message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription
            ))
        }

        let rootExisted = fileManager.fileExists(atPath: transcriptionWorkingRoot.path)
        let session = transcriptionWorkingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extensionSuffix = validated.fileExtension.isEmpty ? "" : ".\(validated.fileExtension)"
        let workingCopy = session.appendingPathComponent("source\(extensionSuffix)")
        do {
            try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
            try validator.withSecurityScopedAccess(to: validated.identity.accessURL) {
                _ = try validator.revalidateWithinActiveScope(
                    validated,
                    policy: .init(maximumByteSize: effectiveMaximumByteSize)
                )
                try fileManager.copyItem(at: validated.identity.standardizedURL, to: workingCopy)
                _ = try validator.revalidateWithinActiveScope(
                    validated,
                    policy: .init(maximumByteSize: effectiveMaximumByteSize)
                )
            }
            let copied = try validator.validate(workingCopy)
            guard copied.byteSize == validated.byteSize, copied.sha256 == validated.sha256 else {
                throw LocalFileIntakeError(.changedDuringValidation)
            }
            try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: workingCopy.path)
        } catch {
            cleanupTranscriptionSession(session, removeRoot: !rootExisted)
            return .failure(.init(
                code: .sourceUnreadable,
                message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription
            ))
        }
        defer { cleanupTranscriptionSession(session, removeRoot: !rootExisted) }
        return await service.transcribeStoredAudio(.init(
            fileURL: workingCopy,
            sourceID: request.sourceID,
            displayName: request.displayName ?? validated.displayName
        ))
    }

    func transcribeStoredAudio(_ original: JournalStoredOriginal) async -> TranscriptionResult {
        guard original.kind == .audio else {
            return .failure(.init(code: .invalidSource, message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription))
        }
        let canonicalURL: URL
        do {
            canonicalURL = try containedCanonicalURL(relativePath: original.file.relativePath)
            let metadata = try validator.validate(canonicalURL)
            guard metadata.byteSize == original.byteSize, metadata.sha256 == original.sha256 else {
                throw LocalFileIntakeError(.changedDuringValidation)
            }
        } catch {
            return .failure(.init(
                code: .sourceUnreadable,
                message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription
            ))
        }
        let rootExisted = fileManager.fileExists(atPath: transcriptionWorkingRoot.path)
        let session = transcriptionWorkingRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extensionSuffix = canonicalURL.pathExtension.isEmpty ? "" : ".\(canonicalURL.pathExtension)"
        let workingCopy = session.appendingPathComponent("source\(extensionSuffix)")
        do {
            try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
            try fileManager.copyItem(at: canonicalURL, to: workingCopy)
            let copied = try validator.validate(workingCopy)
            let canonicalAfterCopy = try validator.validate(canonicalURL)
            guard copied.byteSize == original.byteSize,
                  copied.sha256 == original.sha256,
                  canonicalAfterCopy.byteSize == original.byteSize,
                  canonicalAfterCopy.sha256 == original.sha256 else {
                throw LocalFileIntakeError(.changedDuringValidation)
            }
            try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: workingCopy.path)
        } catch {
            cleanupTranscriptionSession(session, removeRoot: !rootExisted)
            return .failure(.init(
                code: .sourceUnreadable,
                message: JournalMediaIntakeError(.transcriptionUnavailable).localizedDescription
            ))
        }
        defer { cleanupTranscriptionSession(session, removeRoot: !rootExisted) }
        return await transcriptionService.transcribeStoredAudio(.init(
            fileURL: workingCopy,
            sourceID: original.sourceID,
            displayName: original.file.displayTitle
        ))
    }

    func cancelTranscription() {
        transcriptionService.cancelStoredAudio()
    }

    private func supports(_ fileExtension: String, kind: JournalMediaKind) -> Bool {
        switch kind {
        case .audio: Self.audioExtensions.contains(fileExtension)
        case .photo: Self.photoExtensions.contains(fileExtension)
        case .media: Self.mediaExtensions.contains(fileExtension)
        }
    }

    private var effectiveMaximumByteSize: Int64 {
        max(1, policy.maximumByteSize ?? JournalMediaIntakePolicy.defaultMaximumByteSize)
    }

    private func destinationDirectory(for kind: JournalMediaKind) -> String {
        switch kind {
        case .audio: "Journal/Audio"
        case .photo: "Journal/Photos"
        case .media: "Journal/Media"
        }
    }

    private func canonicalFileType(for fileExtension: String, kind: JournalMediaKind) -> VaultFileType {
        switch kind {
        case .audio: .audio
        case .photo: .image
        case .media: VaultFileType.from(extension: fileExtension)
        }
    }

    private static func stableFileID(sourceDigest: String, kind: JournalMediaKind) -> UUID {
        let digest = LocalFileIntakeValidator.sha256(Data("journal|\(kind.rawValue)|\(sourceDigest)".utf8))
        let raw = String(digest.prefix(32))
        let formatted = "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }

    private static func sourceCardID(capturedAt: Date, stableID: UUID) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "journal-media-\(formatter.string(from: capturedAt))-\(stableID.uuidString)"
    }

    private func containedCanonicalURL(relativePath: String) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        try validateExistingComponent(vaultRoot, requiresDirectory: true)
        let components = relativePath.split(separator: "/").map(String.init)
        var candidate = vaultRoot
        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(component, isDirectory: index < components.count - 1)
            guard fileManager.fileExists(atPath: candidate.path) else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
            try validateExistingComponent(candidate, requiresDirectory: index < components.count - 1)
        }
        let expected = vaultRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.standardizedFileURL == expected,
              Self.isContained(expected, in: vaultRoot),
              expected.resolvingSymlinksInPath().standardizedFileURL == expected else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        return expected
    }

    private func validateExistingComponent(_ url: URL, requiresDirectory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw LocalFileIntakeError(.unsafeDestination) }
        let kind = info.st_mode & S_IFMT
        guard kind != S_IFLNK else { throw LocalFileIntakeError(.unsafeDestination) }
        let values = try url.resourceValues(forKeys: [.isAliasFileKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isAliasFile != true else { throw LocalFileIntakeError(.unsafeDestination) }
        if requiresDirectory {
            guard kind == S_IFDIR, values.isDirectory == true else { throw LocalFileIntakeError(.unsafeDestination) }
        } else {
            guard kind == S_IFREG, values.isRegularFile == true else { throw LocalFileIntakeError(.unsafeDestination) }
        }
    }

    private func cleanupTranscriptionSession(_ session: URL, removeRoot: Bool) {
        try? fileManager.removeItem(at: session)
        if removeRoot,
           (try? fileManager.contentsOfDirectory(atPath: transcriptionWorkingRoot.path).isEmpty) == true {
            try? fileManager.removeItem(at: transcriptionWorkingRoot)
        }
    }

    private static func isDecodableImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }
}
