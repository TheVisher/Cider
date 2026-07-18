import CryptoKit
import Darwin
import Foundation
import SQLite3
import os

private typealias CiderDescriptorInfoFunction = @convention(c) (
    Int32,
    Int32,
    Int32,
    UnsafeMutableRawPointer,
    Int32
) -> Int32

@MainActor
final class DatabaseSafetyService {
    static let shared = DatabaseSafetyService()

    /// Atomically clones the object selected by `sourceDescriptor` into a new,
    /// exclusively-created child of `destinationDirectoryDescriptor`.
    /// Unlike renameatx_np, source selection is descriptor-bound.
    @discardableResult
    nonisolated static func clonePinnedDirectoryAtomically(
        sourceDescriptor: Int32,
        destinationDirectoryDescriptor: Int32,
        destinationName: String
    ) -> Int32 {
        fclonefileat(sourceDescriptor, destinationDirectoryDescriptor, destinationName, 0)
    }

    /// The typed publication boundary used by the full backup composition and
    /// by direct adversarial tests. The source inode is already selected by its
    /// descriptor and the destination is always create-only.
    nonisolated static func publishPinnedDirectoryAtomically(
        sourceDescriptor: Int32,
        destinationDirectoryDescriptor: Int32,
        destinationName: String
    ) throws {
        guard clonePinnedDirectoryAtomically(
            sourceDescriptor: sourceDescriptor,
            destinationDirectoryDescriptor: destinationDirectoryDescriptor,
            destinationName: destinationName
        ) == 0 else {
            let cloneError = errno
            if cloneError == EEXIST || cloneError == ENOTEMPTY {
                throw BackupError.collision(
                    "The destination became occupied; no existing artifact was replaced."
                )
            }
            throw BackupError.publication(
                "The pinned source could not be atomically cloned without replacement (errno \(cloneError))."
            )
        }
    }

    /// Reserves a brand-new regular file relative to a pinned directory and
    /// proves the opened descriptor is the sole link at that exact child name.
    /// This is the real staged database/manifest creation primitive.
    @discardableResult
    nonisolated static func createExclusivePinnedRegularFile(
        directoryDescriptor: Int32,
        name: String
    ) throws -> Int32 {
        let childDescriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard childDescriptor >= 0 else {
            let openError = errno
            throw BackupError.staging(
                "Could not exclusively reserve \(name) in the pinned staging directory (errno \(openError))."
            )
        }
        do {
            var descriptorStat = stat()
            guard fstat(childDescriptor, &descriptorStat) == 0 else {
                throw BackupError.staging("The pinned staging child descriptor could not be inspected.")
            }
            var pathStat = stat()
            guard fstatat(directoryDescriptor, name, &pathStat, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.staging("The pinned staging child \(name) is no longer reachable.")
            }
            guard descriptorStat.st_dev == pathStat.st_dev,
                  descriptorStat.st_ino == pathStat.st_ino,
                  descriptorStat.st_mode & S_IFMT == S_IFREG,
                  pathStat.st_mode & S_IFMT == S_IFREG,
                  descriptorStat.st_nlink == 1,
                  pathStat.st_nlink == 1,
                  descriptorStat.st_size == 0,
                  pathStat.st_size == 0 else {
                throw BackupError.staging(
                    "The pinned staging child \(name) changed identity, type, link count, or initial size."
                )
            }
            return childDescriptor
        } catch {
            Darwin.close(childDescriptor)
            throw error
        }
    }

    enum BackupVerificationState: String, Codable, Equatable {
        case created
        case verified
        case legacyRecovery
        case unusable
        case failed
    }

    enum BackupFailureKind: String, Codable, Equatable {
        case sourceUnavailable
        case staging
        case capture
        case verification
        case collision
        case publication
        case retentionCapacity
    }

    struct BackupVerification: Equatable {
        let state: BackupVerificationState
        let schemaVersion: Int?
        let databaseSHA256: String?
        let manifestSHA256: String?
        let artifactNames: [String]
        let retainedBytesUnchanged: Bool
        let messages: [String]

        var isVerified: Bool {
            state == .verified && retainedBytesUnchanged
        }

        var isRecoveryEligible: Bool {
            retainedBytesUnchanged && (state == .verified || state == .legacyRecovery)
        }
    }

    struct QualifiedBackupArtifact: Equatable {
        struct Object: Equatable {
            let device: dev_t
            let inode: ino_t
            let generation: UInt32
            let type: mode_t
            let linkCount: nlink_t
        }

        let policyURL: URL
        let policy: Object
        let packageName: String
        let package: Object
        let childrenByName: [String: Object]
        let contentSHA256ByName: [String: String]
        let lineageIdentifier: String

        fileprivate func currentURL() -> URL? {
            let policyDescriptor = Darwin.open(
                policyURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard policyDescriptor >= 0 else { return nil }
            defer { Darwin.close(policyDescriptor) }
            guard Self.object(for: policyDescriptor) == policy else { return nil }
            let packageDescriptor = Darwin.openat(
                policyDescriptor,
                packageName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard packageDescriptor >= 0 else { return nil }
            defer { Darwin.close(packageDescriptor) }
            guard Self.object(for: packageDescriptor) == package else { return nil }
            guard (try? RetainedPathReference.directoryNames(packageDescriptor))
                == childrenByName.keys.sorted() else { return nil }
            for (name, expected) in childrenByName {
                var value = stat()
                guard fstatat(packageDescriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      Self.object(from: value) == expected else { return nil }
                let descriptor = Darwin.openat(
                    packageDescriptor,
                    name,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                )
                guard descriptor >= 0 else { return nil }
                defer { Darwin.close(descriptor) }
                guard let expectedHash = contentSHA256ByName[name],
                      lseek(descriptor, 0, SEEK_SET) >= 0,
                      let data = try? FileHandle(
                        fileDescriptor: descriptor,
                        closeOnDealloc: false
                      ).readToEnd(),
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
                        == expectedHash else { return nil }
            }
            return policyURL.appendingPathComponent(packageName, isDirectory: true)
        }

        private static func object(for descriptor: Int32) -> Object? {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else { return nil }
            return object(from: value)
        }

        private static func object(from value: stat) -> Object {
            Object(
                device: value.st_dev,
                inode: value.st_ino,
                generation: value.st_gen,
                type: value.st_mode & S_IFMT,
                linkCount: value.st_mode & S_IFMT == S_IFDIR ? 0 : value.st_nlink
            )
        }
    }

    struct BackupCreationReceipt: Equatable {
        let state: BackupVerificationState
        private let qualifiedArtifact: QualifiedBackupArtifact?
        private let retainedReference: RetainedPathReference?
        let verification: BackupVerification?
        let failureKind: BackupFailureKind?
        let message: String
        let warnings: [String]

        init(
            state: BackupVerificationState,
            backupURL: URL?,
            verification: BackupVerification?,
            failureKind: BackupFailureKind?,
            message: String,
            warnings: [String],
            qualifiedArtifact: QualifiedBackupArtifact? = nil
        ) {
            self.state = state
            self.verification = verification
            self.failureKind = failureKind
            self.message = message
            self.warnings = warnings
            self.qualifiedArtifact = qualifiedArtifact
            retainedReference = qualifiedArtifact == nil
                ? backupURL.flatMap(RetainedPathReference.init(url:))
                : nil
        }

        var backupURL: URL? {
            guard qualifiedArtifact == nil else { return nil }
            return retainedReference?.currentURL()
        }

        var artifact: QualifiedBackupArtifact? { qualifiedArtifact }
        var artifactName: String? { qualifiedArtifact?.packageName }

        var created: Bool { state == .created || state == .verified }
        var verified: Bool { verification?.isVerified == true }
        var usable: Bool {
            state == .verified && verified && qualifiedArtifact?.currentURL() != nil
        }
    }

    fileprivate struct RetainedPathReference: Equatable {
        private static let maximumDepth = 32
        private static let maximumEntries = 4_096
        private static let maximumRegularFileBytes: Int64 = 128 * 1_024 * 1_024
        private static let maximumTotalBytes: Int64 = 128 * 1_024 * 1_024

        private struct Entry: Equatable {
            let device: dev_t
            let inode: ino_t
            let generation: UInt32
            let owner: uid_t
            let mode: mode_t
            let type: mode_t
            let linkCount: nlink_t
            let byteSize: off_t
            let sha256: String?
        }

        private struct VisitKey: Hashable {
            let device: dev_t
            let inode: ino_t
            let type: mode_t
            let generation: UInt32
        }

        private struct SnapshotState {
            var visited: Set<VisitKey> = []
            var entryCount = 0
            var totalBytes: Int64 = 0
        }

        let url: URL
        private let entriesByRelativePath: [String: Entry]

        init?(url: URL) {
            self.url = url
            guard let entries = try? Self.snapshot(at: url) else { return nil }
            entriesByRelativePath = entries
        }

        init?(
            url: URL,
            expectedDirectory: FileIdentity,
            expectedChildren: [String: FileIdentity],
            expectedHashes: [String: String]
        ) {
            self.url = url
            guard let entries = try? Self.snapshot(at: url),
                  Set(entries.keys) == Set(expectedChildren.keys).union([""]),
                  entries[""].map({ Self.matches($0, expectedDirectory) }) == true,
                  expectedChildren.allSatisfy({ name, identity in
                      entries[name].map { entry in
                          Self.matches(entry, identity)
                              && entry.sha256 == expectedHashes[name]
                      } == true
                  }) else { return nil }
            entriesByRelativePath = entries
        }

        init?(url: URL, expectedFile: FileIdentity, expectedSHA256: String) {
            self.url = url
            guard let entries = try? Self.snapshot(at: url),
                  Set(entries.keys) == [""],
                  entries[""].map({
                      Self.matches($0, expectedFile) && $0.sha256 == expectedSHA256
                  }) == true else { return nil }
            entriesByRelativePath = entries
        }

        func currentURL() -> URL? {
            guard (try? Self.snapshot(at: url)) == entriesByRelativePath else { return nil }
            return url
        }

        private static func snapshot(at url: URL) throws -> [String: Entry] {
            var pathMetadata = stat()
            guard lstat(url.path, &pathMetadata) == 0 else {
                throw BackupError.verification("The retained receipt artifact could not be inspected.")
            }
            let pathType = pathMetadata.st_mode & S_IFMT
            guard pathType == S_IFREG || pathType == S_IFDIR else {
                throw BackupError.verification(
                    "The retained receipt artifact is a symlink or special file."
                )
            }
            let openFlags = O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
                | (pathType == S_IFDIR ? O_DIRECTORY : 0)
            let descriptor = Darwin.open(
                url.path,
                openFlags
            )
            guard descriptor >= 0 else {
                throw BackupError.verification("The retained receipt artifact could not be pinned.")
            }
            defer { Darwin.close(descriptor) }
            var descriptorMetadata = stat()
            guard fstat(descriptor, &descriptorMetadata) == 0,
                  sameSnapshotIdentity(pathMetadata, descriptorMetadata) else {
                throw BackupError.verification(
                    "The retained receipt artifact changed between metadata inspection and open."
                )
            }
            var entries: [String: Entry] = [:]
            var state = SnapshotState()
            try snapshot(
                descriptor: descriptor,
                inspectedMetadata: descriptorMetadata,
                relativePath: "",
                depth: 0,
                state: &state,
                into: &entries
            )
            return entries
        }

        private static func snapshot(
            descriptor: Int32,
            inspectedMetadata: stat,
            relativePath: String,
            depth: Int,
            state: inout SnapshotState,
            into entries: inout [String: Entry]
        ) throws {
            guard depth <= maximumDepth else {
                throw BackupError.verification("The retained receipt tree exceeds the depth bound.")
            }
            var before = stat()
            guard fstat(descriptor, &before) == 0,
                  sameSnapshotIdentity(inspectedMetadata, before) else {
                throw BackupError.verification("A retained receipt identity could not be inspected.")
            }
            let type = before.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR else {
                throw BackupError.verification(
                    "A retained receipt entry is a symlink or special file."
                )
            }
            let visit = VisitKey(
                device: before.st_dev,
                inode: before.st_ino,
                type: type,
                generation: before.st_gen
            )
            guard state.visited.insert(visit).inserted else {
                throw BackupError.verification(
                    "The retained receipt tree repeats a filesystem identity."
                )
            }
            state.entryCount += 1
            guard state.entryCount <= maximumEntries else {
                throw BackupError.verification("The retained receipt tree exceeds the entry bound.")
            }
            let contentHash: String?
            if type == S_IFREG {
                guard before.st_nlink == 1,
                      before.st_size >= 0,
                      before.st_size <= maximumRegularFileBytes,
                      state.totalBytes <= maximumTotalBytes - before.st_size else {
                    throw BackupError.verification(
                        "A retained receipt regular file is linked or exceeds the byte bound."
                    )
                }
                state.totalBytes += before.st_size
                guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
                    throw BackupError.verification("A retained receipt file could not be rewound.")
                }
                var hasher = SHA256()
                var totalRead: Int64 = 0
                var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
                while true {
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                    }
                    if count < 0, errno == EINTR { continue }
                    guard count >= 0 else {
                        throw BackupError.verification(
                            "A retained receipt regular file could not be read safely."
                        )
                    }
                    if count == 0 { break }
                    totalRead += Int64(count)
                    guard totalRead <= before.st_size else {
                        throw BackupError.verification(
                            "A retained receipt regular file grew during hashing."
                        )
                    }
                    hasher.update(data: Data(buffer.prefix(count)))
                }
                guard totalRead == before.st_size else {
                    throw BackupError.verification(
                        "A retained receipt regular file changed size during hashing."
                    )
                }
                contentHash = hasher.finalize()
                    .map { String(format: "%02x", $0) }
                    .joined()
            } else if type == S_IFDIR {
                contentHash = nil
                let names = try directoryNames(descriptor)
                for name in names {
                    var childMetadata = stat()
                    guard fstatat(
                        descriptor,
                        name,
                        &childMetadata,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0 else {
                        throw BackupError.verification(
                            "A retained receipt child changed before metadata inspection."
                        )
                    }
                    let childType = childMetadata.st_mode & S_IFMT
                    guard childType == S_IFREG || childType == S_IFDIR else {
                        throw BackupError.verification(
                            "A retained receipt child is a symlink or special file."
                        )
                    }
                    let child = Darwin.openat(
                        descriptor,
                        name,
                        O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
                            | (childType == S_IFDIR ? O_DIRECTORY : 0)
                    )
                    guard child >= 0 else {
                        throw BackupError.verification(
                            "A retained receipt child changed during qualification."
                        )
                    }
                    do {
                        var openedMetadata = stat()
                        guard fstat(child, &openedMetadata) == 0,
                              sameSnapshotIdentity(childMetadata, openedMetadata) else {
                            throw BackupError.verification(
                                "A retained receipt child changed between metadata inspection and open."
                            )
                        }
                        let childPath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
                        try snapshot(
                            descriptor: child,
                            inspectedMetadata: openedMetadata,
                            relativePath: childPath,
                            depth: depth + 1,
                            state: &state,
                            into: &entries
                        )
                        Darwin.close(child)
                    } catch {
                        Darwin.close(child)
                        throw error
                    }
                }
                guard try directoryNames(descriptor) == names else {
                    throw BackupError.verification(
                        "The retained receipt directory membership changed during qualification."
                    )
                }
            } else {
                throw BackupError.verification(
                    "A retained receipt artifact is neither a regular file nor a directory."
                )
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0,
                  before.st_dev == after.st_dev,
                  before.st_ino == after.st_ino,
                  before.st_uid == after.st_uid,
                  before.st_mode == after.st_mode,
                  before.st_nlink == after.st_nlink,
                  before.st_size == after.st_size else {
                throw BackupError.verification(
                    "A retained receipt artifact changed during qualification."
                )
            }
            entries[relativePath] = Entry(
                device: after.st_dev,
                inode: after.st_ino,
                generation: after.st_gen,
                owner: after.st_uid,
                mode: after.st_mode & mode_t(0o7777),
                type: type,
                linkCount: after.st_nlink,
                byteSize: after.st_size,
                sha256: contentHash
            )
        }

        private static func sameSnapshotIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
            lhs.st_dev == rhs.st_dev
                && lhs.st_ino == rhs.st_ino
                && lhs.st_gen == rhs.st_gen
                && lhs.st_uid == rhs.st_uid
                && lhs.st_mode == rhs.st_mode
                && lhs.st_nlink == rhs.st_nlink
                && lhs.st_size == rhs.st_size
        }

        fileprivate static func directoryNames(_ descriptor: Int32) throws -> [String] {
            let duplicated = dup(descriptor)
            guard duplicated >= 0, let directory = fdopendir(duplicated) else {
                if duplicated >= 0 { Darwin.close(duplicated) }
                throw BackupError.verification(
                    "A retained receipt directory could not be enumerated."
                )
            }
            defer { closedir(directory) }
            rewinddir(directory)
            var names: [String] = []
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name != ".", name != ".." { names.append(name) }
            }
            return names.sorted()
        }

        private static func matches(_ entry: Entry, _ identity: FileIdentity) -> Bool {
            entry.device == identity.device
                && entry.inode == identity.inode
                && entry.generation == identity.generation
                && entry.type == identity.fileType
                && entry.linkCount == identity.linkCount
                && entry.byteSize == identity.byteSize
        }
    }

    /// One production composer owns the externally visible failure truth table.
    /// Keeping this separate from failure origin lets tests pair real failing
    /// filesystem primitives with the same receipt mapping used by manual backup.
    nonisolated static func failedCreationReceipt(for error: BackupError) -> BackupCreationReceipt {
        BackupCreationReceipt(
            state: error.failureState,
            backupURL: error.retainedArtifactURL,
            verification: nil,
            failureKind: error.kind,
            message: error.localizedDescription,
            warnings: []
        )
    }

    struct SQLiteBackupInfo: Equatable {
        enum Kind: String, Codable, Equatable {
            case rolling
            case preflight
        }

        let kind: Kind
        let url: URL
        let createdAt: Date
        let byteSize: Int64
        let verification: BackupVerification
    }

    enum BackupError: LocalizedError, Equatable {
        case sourceUnavailable(String)
        case staging(String)
        case capture(String)
        case verification(String)
        case collision(String)
        case publication(String)
        case retentionCapacity(String)
        case retainedArtifact(
            kind: BackupFailureKind,
            state: BackupVerificationState,
            detail: String,
            url: URL
        )
        case retainedArtifactLocationUnknown(
            kind: BackupFailureKind,
            state: BackupVerificationState,
            detail: String
        )

        var kind: BackupFailureKind {
            switch self {
            case .sourceUnavailable: .sourceUnavailable
            case .staging: .staging
            case .capture: .capture
            case .verification: .verification
            case .collision: .collision
            case .publication: .publication
            case .retentionCapacity: .retentionCapacity
            case .retainedArtifact(let kind, _, _, _): kind
            case .retainedArtifactLocationUnknown(let kind, _, _): kind
            }
        }

        var failureState: BackupVerificationState {
            switch self {
            case .verification: .unusable
            case .retainedArtifact(_, let state, _, _): state
            case .retainedArtifactLocationUnknown(_, let state, _): state
            default: .failed
            }
        }

        var retainedArtifactURL: URL? {
            guard case .retainedArtifact(_, _, _, let url) = self else { return nil }
            return url
        }

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable(let detail): "Backup source is unavailable: \(detail)"
            case .staging(let detail): "Backup staging failed: \(detail)"
            case .capture(let detail): "SQLite backup capture failed: \(detail)"
            case .verification(let detail): "Backup verification failed: \(detail)"
            case .collision(let detail): "Backup publication collided: \(detail)"
            case .publication(let detail): "Backup publication failed: \(detail)"
            case .retentionCapacity(let detail): "Backup retention capacity was reached: \(detail)"
            case .retainedArtifact(let kind, _, let detail, let url):
                "Backup \(kind.rawValue) failed and retained an unusable artifact at \(url.path): \(detail)"
            case .retainedArtifactLocationUnknown(let kind, _, let detail):
                "Backup \(kind.rawValue) failed and may have retained recoverable bytes, but their exact current pathname could not be proven; no artifact URL is reported: \(detail)"
            }
        }
    }

    enum RestoreError: LocalizedError {
        case missingBackup(URL)
        case unhealthyBackup(URL, messages: [String])

        var errorDescription: String? {
            switch self {
            case .missingBackup(let url):
                return "Backup not found at \(url.path)."
            case .unhealthyBackup(let url, let messages):
                let detail = messages.isEmpty ? "unknown integrity failure" : messages.joined(separator: " | ")
                return "Backup at \(url.path) failed integrity check: \(detail)"
            }
        }
    }

    struct RestoreResult: Equatable {
        let restoredBackup: SQLiteBackupInfo
        let preRestoreSnapshotURL: URL?
        private let sourceReference: RetainedPathReference

        var sourceBackupURL: URL? { sourceReference.currentURL() }

        fileprivate init(
            restoredBackup: SQLiteBackupInfo,
            preRestoreSnapshotURL: URL?,
            sourceReference: RetainedPathReference
        ) {
            self.restoredBackup = restoredBackup
            self.preRestoreSnapshotURL = preRestoreSnapshotURL
            self.sourceReference = sourceReference
        }
    }

    private struct SafetyState: Codable {
        var lastPreOpenSnapshotAt: Date?
        var lastIntegrityCheckAt: Date?
        var lastRollingBackupAt: Date?
    }

    private struct BackupManifest: Codable, Equatable {
        static let currentFormatVersion = 2

        let formatVersion: Int
        let kind: SQLiteBackupInfo.Kind
        let reason: String
        let createdAt: Date
        let sourceDatabaseFilename: String
        let sourceLineageIdentifier: String?
        let databaseFilename: String
        let schemaVersion: Int
        let databaseByteSize: Int64
        let databaseSHA256: String
        let artifactNames: [String]
    }

    private struct PackageFingerprint: Equatable {
        let artifactNames: [String]
        let contentSHA256ByName: [String: String]
    }

    fileprivate struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let generation: UInt32
        let fileType: mode_t
        let linkCount: nlink_t
        let byteSize: off_t

        func isSameNode(as other: FileIdentity) -> Bool {
            device == other.device
                && inode == other.inode
                && generation == other.generation
                && fileType == other.fileType
        }

        func isSameObject(as other: FileIdentity) -> Bool {
            isSameNode(as: other) && linkCount == other.linkCount
        }
    }

    private struct PackageIdentity: Equatable {
        let directory: FileIdentity
        let childrenByName: [String: FileIdentity]

        func isSameObject(as other: PackageIdentity) -> Bool {
            guard directory.isSameNode(as: other.directory),
                  childrenByName.keys == other.childrenByName.keys else { return false }
            return childrenByName.allSatisfy { name, identity in
                other.childrenByName[name].map { identity.isSameObject(as: $0) } == true
            }
        }
    }

    private struct OwnershipLedgerIdentity: Codable, Equatable, Hashable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt32

        init(_ identity: FileIdentity) {
            device = UInt64(truncatingIfNeeded: identity.device)
            inode = UInt64(truncatingIfNeeded: identity.inode)
            generation = identity.generation
        }
    }

    private struct OwnershipLedgerEntry: Codable, Equatable, Hashable {
        let policy: OwnershipLedgerIdentity
        let package: OwnershipLedgerIdentity
        let lineageIdentifier: String
        let creationNonce: String
    }

    private struct ParentOwnershipLedger: Codable, Equatable {
        static let currentVersion = 1

        let version: Int
        let authority: OwnershipLedgerIdentity
        var entries: [OwnershipLedgerEntry]
    }

    private struct VerifiedPackage {
        let verification: BackupVerification
        let fingerprint: PackageFingerprint
        let identity: PackageIdentity
        let lineageIdentifier: String
        let createdAt: Date
        let kind: SQLiteBackupInfo.Kind
        let sourceDatabaseFilename: String
    }

    private final class PolicyLease {
        private let descriptor: Int32

        init(policyDirectory: PinnedDirectory, exclusive: Bool) throws {
            let authority = policyDirectory.authorityDirectory
            descriptor = Darwin.openat(
                authority.descriptor,
                ".",
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw BackupError.retentionCapacity(
                    "The process-shared database authority could not be pinned (errno \(errno))."
                )
            }
            var value = stat()
            guard fstat(descriptor, &value) == 0,
                  value.st_mode & S_IFMT == S_IFDIR,
                  value.st_uid == geteuid(),
                  FileIdentity(
                    device: value.st_dev,
                    inode: value.st_ino,
                    generation: value.st_gen,
                    fileType: value.st_mode & S_IFMT,
                    linkCount: value.st_nlink,
                    byteSize: value.st_size
                  ).isSameNode(as: authority.identity) else {
                Darwin.close(descriptor)
                throw BackupError.retentionCapacity(
                    "The process-shared database authority is not the pinned private parent inode."
                )
            }
            guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
                let lockError = errno
                Darwin.close(descriptor)
                throw BackupError.retentionCapacity(
                    "The process-shared retention lease could not be acquired (errno \(lockError))."
                )
            }
        }

        deinit {
            _ = flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
    }

    private final class SourceLineageBinding {
        let lineage: DatabaseSourceLineage
        private let observation: DatabaseSourceLineageObservation

        init(databaseURL: URL, expected: DatabaseSourceLineage) throws {
            do {
                observation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
                lineage = try observation.validate()
            } catch {
                throw BackupError.sourceUnavailable(
                    "The current source pathname could not be bound to its parent: \(error.localizedDescription)"
                )
            }
            guard lineage == expected else {
                throw BackupError.sourceUnavailable(
                    "The current database source/parent identity does not match the open SQLite handle lineage."
                )
            }
        }

        func validate() throws {
            do {
                guard try observation.validate() == lineage else {
                    throw BackupError.sourceUnavailable("The database lineage changed during capture.")
                }
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.sourceUnavailable(
                    "The database lineage drifted during backup creation: \(error.localizedDescription)"
                )
            }
        }

        func coherentSQLiteSetByteUpperBound() throws -> Int64 {
            do {
                return try observation.coherentSQLiteSetByteUpperBound()
            } catch let error as CiderDatabaseBackupCapacityError {
                throw BackupError.retentionCapacity(error.localizedDescription)
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.sourceUnavailable(
                    "The pinned SQLite DB/WAL/SHM set could not be bounded: \(error.localizedDescription)"
                )
            }
        }
    }

    private final class VnodeContinuityWatcher {
        private let queueDescriptor: Int32

        init() throws {
            queueDescriptor = kqueue()
            guard queueDescriptor >= 0 else {
                throw BackupError.verification("The backup identity monitor could not be created.")
            }
        }

        deinit {
            Darwin.close(queueDescriptor)
        }

        func watch(
            _ descriptor: Int32,
            notes: UInt32 = UInt32(NOTE_DELETE) | UInt32(NOTE_WRITE) | UInt32(NOTE_EXTEND)
                | UInt32(NOTE_ATTRIB) | UInt32(NOTE_LINK) | UInt32(NOTE_RENAME)
                | UInt32(NOTE_REVOKE)
        ) throws {
            let flags = UInt16(EV_ADD) | UInt16(EV_CLEAR)
            var change = kevent(
                ident: UInt(descriptor),
                filter: Int16(EVFILT_VNODE),
                flags: flags,
                fflags: notes,
                data: 0,
                udata: nil
            )
            guard kevent(queueDescriptor, &change, 1, nil, 0, nil) == 0 else {
                throw BackupError.verification("The backup identity monitor could not watch an artifact.")
            }
        }

        func hasObservedChange() -> Bool {
            var event = kevent()
            var timeout = timespec(tv_sec: 0, tv_nsec: 0)
            return kevent(queueDescriptor, nil, 0, &event, 1, &timeout) > 0
        }
    }

    private final class PinnedPackage {
        let packageURL: URL
        let identity: PackageIdentity
        let artifactNames: [String]

        private let fileManager: FileManager
        private let directoryDescriptor: Int32
        private let descriptorsByName: [String: Int32]
        private let watcher: VnodeContinuityWatcher
        private let relativeParent: PinnedDirectory?
        private let relativeName: String?

        var ownershipParent: PinnedDirectory? { relativeParent }
        var ownershipName: String? { relativeName }

        convenience init(packageURL: URL, requiredNames: [String], fileManager: FileManager) throws {
            let directoryDescriptor = Darwin.open(
                packageURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard directoryDescriptor >= 0 else {
                throw BackupError.verification("The backup package directory could not be pinned.")
            }
            try self.init(
                packageURL: packageURL,
                requiredNames: requiredNames,
                fileManager: fileManager,
                directoryDescriptor: directoryDescriptor,
                relativeParent: nil,
                relativeName: nil
            )
        }

        convenience init(
            childNamed name: String,
            at packageURL: URL,
            in parent: PinnedDirectory,
            requiredNames: [String],
            fileManager: FileManager
        ) throws {
            let directoryDescriptor = Darwin.openat(
                parent.descriptor,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard directoryDescriptor >= 0 else {
                throw BackupError.verification("The backup package directory could not be pinned relative to its policy directory.")
            }
            try self.init(
                packageURL: packageURL,
                requiredNames: requiredNames,
                fileManager: fileManager,
                directoryDescriptor: directoryDescriptor,
                relativeParent: parent,
                relativeName: name
            )
        }

        private init(
            packageURL: URL,
            requiredNames: [String],
            fileManager: FileManager,
            directoryDescriptor: Int32,
            relativeParent: PinnedDirectory?,
            relativeName: String?
        ) throws {
            self.packageURL = packageURL
            self.fileManager = fileManager
            self.directoryDescriptor = directoryDescriptor
            self.relativeParent = relativeParent
            self.relativeName = relativeName

            do {
                let watcher = try VnodeContinuityWatcher()
                self.watcher = watcher
                try watcher.watch(directoryDescriptor)

                let directoryIdentity = try Self.descriptorIdentity(directoryDescriptor)
                let reachableIdentity: FileIdentity
                let observedNames: [String]
                if let relativeParent, let relativeName {
                    observedNames = try fileManager.contentsOfDirectory(
                        at: packageURL,
                        includingPropertiesForKeys: nil,
                        options: []
                    ).map(\.lastPathComponent).sorted()
                    reachableIdentity = try Self.childPathIdentity(relativeParent.descriptor, name: relativeName)
                } else {
                    // Public path verification intentionally observes the path
                    // while watched so swap-and-restore cannot return verified.
                    observedNames = try fileManager.contentsOfDirectory(
                        at: packageURL,
                        includingPropertiesForKeys: nil,
                        options: []
                    ).map(\.lastPathComponent).sorted()
                    reachableIdentity = try Self.pathIdentity(packageURL)
                }
                guard directoryIdentity.fileType == S_IFDIR,
                      reachableIdentity == directoryIdentity else {
                    throw BackupError.verification("The backup package path changed while it was pinned.")
                }

                let names = try Self.names(in: directoryDescriptor)
                guard names == requiredNames,
                      observedNames == requiredNames else {
                    throw BackupError.verification(
                        "The package DB/WAL/SHM set is incomplete or contains unexpected files "
                            + "(path: \(observedNames.joined(separator: ", ")); "
                            + "pinned: \(names.joined(separator: ", ")))."
                    )
                }

                var descriptors: [String: Int32] = [:]
                var childIdentities: [String: FileIdentity] = [:]
                do {
                    for name in names {
                        let descriptor = Darwin.openat(
                            directoryDescriptor,
                            name,
                            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                        )
                        guard descriptor >= 0 else {
                            throw BackupError.verification("The backup artifact \(name) could not be pinned.")
                        }
                        descriptors[name] = descriptor
                        let identity = try Self.descriptorIdentity(descriptor)
                        guard identity.fileType == S_IFREG,
                              identity.linkCount == 1,
                              try Self.childPathIdentity(directoryDescriptor, name: name) == identity else {
                            throw BackupError.verification(
                                "The backup artifact \(name) is linked, non-regular, or changed during open."
                            )
                        }
                        childIdentities[name] = identity
                        try watcher.watch(descriptor)
                    }
                } catch {
                    for descriptor in descriptors.values { Darwin.close(descriptor) }
                    throw error
                }
                descriptorsByName = descriptors
                artifactNames = names
                identity = PackageIdentity(
                    directory: directoryIdentity,
                    childrenByName: childIdentities
                )
            } catch {
                Darwin.close(directoryDescriptor)
                throw error
            }
        }

        deinit {
            for descriptor in descriptorsByName.values { Darwin.close(descriptor) }
            Darwin.close(directoryDescriptor)
        }

        func data(for name: String) throws -> Data {
            guard let descriptor = descriptorsByName[name], lseek(descriptor, 0, SEEK_SET) >= 0 else {
                throw BackupError.verification("The pinned backup artifact \(name) became unreadable.")
            }
            return try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
        }

        func descriptor(for name: String) throws -> Int32 {
            guard let descriptor = descriptorsByName[name] else {
                throw BackupError.verification("The pinned backup artifact \(name) is missing.")
            }
            return descriptor
        }

        func hasPublicOwnershipMarker() -> Bool {
            PinnedDirectory.hasPublicOwnershipMarker(descriptor: directoryDescriptor)
        }

        func ownershipNonce() -> String? {
            PinnedDirectory.ownershipNonce(descriptor: directoryDescriptor)
        }

        func fingerprint() throws -> PackageFingerprint {
            var hashes: [String: String] = [:]
            for name in artifactNames {
                hashes[name] = SHA256.hash(data: try data(for: name))
                    .map { String(format: "%02x", $0) }
                    .joined()
            }
            return PackageFingerprint(
                artifactNames: artifactNames,
                contentSHA256ByName: hashes
            )
        }

        func validateUnchanged() throws {
            let pinnedNames = try Self.names(in: directoryDescriptor)
            let reachableIdentity: FileIdentity
            let observedNames: [String]
            if let relativeParent, let relativeName {
                reachableIdentity = try Self.childPathIdentity(relativeParent.descriptor, name: relativeName)
                observedNames = pinnedNames
            } else {
                observedNames = try fileManager.contentsOfDirectory(
                    at: packageURL,
                    includingPropertiesForKeys: nil,
                    options: []
                ).map(\.lastPathComponent).sorted()
                reachableIdentity = try Self.pathIdentity(packageURL)
            }
            guard observedNames == artifactNames,
                  reachableIdentity == identity.directory,
                  pinnedNames == artifactNames else {
                throw BackupError.verification(
                    "The backup package path or complete membership changed during verification "
                        + "(pathIdentity=\(reachableIdentity == identity.directory), "
                        + "pathMembers=\(observedNames == artifactNames), "
                        + "pinnedMembers=\(pinnedNames == artifactNames))."
                )
            }
            for (name, expected) in identity.childrenByName {
                guard let descriptor = descriptorsByName[name],
                      try Self.descriptorIdentity(descriptor) == expected,
                      try Self.childPathIdentity(directoryDescriptor, name: name) == expected else {
                    throw BackupError.verification("The backup artifact \(name) changed identity during verification.")
                }
            }
            guard !watcher.hasObservedChange() else {
                throw BackupError.verification("A backup artifact was renamed, linked, or written during verification.")
            }
        }

        func exactAccountedBytes() throws -> Int64 {
            try validateUnchanged()
            var total = DatabaseSafetyService.retentionAccountingNodeOverheadBytes
            for name in artifactNames {
                guard let child = identity.childrenByName[name],
                      child.fileType == S_IFREG,
                      child.linkCount == 1,
                      child.byteSize >= 0 else {
                    throw BackupError.retentionCapacity(
                        "A verified staged child is not a single-link regular file for exact accounting."
                    )
                }
                total = try DatabaseSafetyService.checkedRetentionCapacitySum(
                    total,
                    try DatabaseSafetyService.checkedRetentionCapacitySum(
                        Int64(child.byteSize),
                        DatabaseSafetyService.retentionAccountingNodeOverheadBytes
                    )
                )
            }
            try validateUnchanged()
            return total
        }

        private static func names(in directoryDescriptor: Int32) throws -> [String] {
            let duplicated = dup(directoryDescriptor)
            guard duplicated >= 0, let directory = fdopendir(duplicated) else {
                if duplicated >= 0 { Darwin.close(duplicated) }
                throw BackupError.verification("The pinned package membership could not be enumerated.")
            }
            defer { closedir(directory) }
            rewinddir(directory)
            var names: [String] = []
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name != ".", name != ".." { names.append(name) }
            }
            return names.sorted()
        }

        fileprivate static func descriptorIdentity(_ descriptor: Int32) throws -> FileIdentity {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else {
                throw BackupError.verification("A pinned backup identity could not be read.")
            }
            return identity(from: value)
        }

        private static func pathIdentity(_ url: URL) throws -> FileIdentity {
            var value = stat()
            guard lstat(url.path, &value) == 0 else {
                throw BackupError.verification("A backup path identity could not be read.")
            }
            return identity(from: value)
        }

        private static func childPathIdentity(_ directoryDescriptor: Int32, name: String) throws -> FileIdentity {
            var value = stat()
            guard fstatat(directoryDescriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.verification("A backup child identity could not be read.")
            }
            return identity(from: value)
        }

        private static func identity(from value: stat) -> FileIdentity {
            FileIdentity(
                device: value.st_dev,
                inode: value.st_ino,
                generation: value.st_gen,
                fileType: value.st_mode & S_IFMT,
                linkCount: value.st_nlink,
                byteSize: value.st_size
            )
        }
    }

    private final class RestoreSourceUse {
        enum Storage {
            case package(
                PinnedPackage,
                VerifiedPackage,
                policyDirectory: PinnedDirectory?,
                packageName: String?
            )
            case raw(descriptor: Int32, identity: FileIdentity, verification: BackupVerification)
        }

        let url: URL
        let storage: Storage

        init(url: URL, storage: Storage) {
            self.url = url
            self.storage = storage
        }

        deinit {
            if case .raw(let descriptor, _, _) = storage {
                Darwin.close(descriptor)
            }
        }

        var verification: BackupVerification {
            switch storage {
            case .package(_, let package, _, _): package.verification
            case .raw(_, _, let verification): verification
            }
        }

        var createdAt: Date {
            switch storage {
            case .package(_, let package, _, _): package.createdAt
            case .raw: .distantPast
            }
        }

        @MainActor
        func finalDatabaseData(
            service: DatabaseSafetyService
        ) throws -> (data: Data, reference: RetainedPathReference) {
            switch storage {
            case .package(let package, let verified, let policyDirectory, let packageName):
                if let policyDirectory, let packageName,
                   verified.verification.state == .verified {
                    try service.requireGeneratedVisiblePackageOwnership(
                        package,
                        named: packageName,
                        in: policyDirectory,
                        lineageIdentifier: verified.lineageIdentifier
                    )
                }
                guard try package.fingerprint() == verified.fingerprint else {
                    throw RestoreError.unhealthyBackup(
                        url,
                        messages: ["The held package changed before the final restore read."]
                    )
                }
                try package.validateUnchanged()
                let databaseData = try package.data(for: service.databaseFilename)
                guard try package.fingerprint() == verified.fingerprint else {
                    throw RestoreError.unhealthyBackup(
                        url,
                        messages: ["The held package changed at the final restore read."]
                    )
                }
                try package.validateUnchanged()
                guard let reference = RetainedPathReference(
                    url: url,
                    expectedDirectory: verified.identity.directory,
                    expectedChildren: verified.identity.childrenByName,
                    expectedHashes: verified.fingerprint.contentSHA256ByName
                ) else {
                    throw RestoreError.unhealthyBackup(
                        url,
                        messages: ["The held package pathname no longer names the exact verified capability."]
                    )
                }
                return (databaseData, reference)
            case .raw(let descriptor, let identity, let verification):
                let bytes = try service.data(from: descriptor, artifactName: url.lastPathComponent)
                guard try PinnedPackage.descriptorIdentity(descriptor) == identity,
                      try service.pathIdentity(at: url, requiring: S_IFREG) == identity,
                      service.sha256(bytes) == verification.databaseSHA256,
                      let hash = verification.databaseSHA256,
                      let reference = RetainedPathReference(
                        url: url,
                        expectedFile: identity,
                        expectedSHA256: hash
                      ) else {
                    throw RestoreError.unhealthyBackup(
                        url,
                        messages: ["The held raw recovery capability changed before final restore use."]
                    )
                }
                return (bytes, reference)
            }
        }
    }

    /// Keeps a policy or staging directory bound to one filesystem node. Child
    /// creation is performed relative to this descriptor, so replacing the
    /// pathname cannot redirect database or manifest writes.
    private final class PinnedDirectory {
        private static let ownershipAttribute = "com.cider.cid850.package-owner-v1"
        private static let ownershipValue = Data("cider-owned-package-v1".utf8)
        private static let ownershipNonceAttribute = "com.cider.cid850.package-creation-nonce-v1"

        let url: URL
        let identity: FileIdentity
        let descriptor: Int32

        private let fileManager: FileManager
        private let relativeParent: PinnedDirectory?
        private let relativeName: String?

        var authorityDirectory: PinnedDirectory {
            relativeParent?.authorityDirectory ?? self
        }

        init(url: URL, fileManager: FileManager) throws {
            self.url = url
            self.fileManager = fileManager
            relativeParent = nil
            relativeName = nil
            descriptor = Darwin.open(
                url.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw BackupError.staging("The directory at \(url.path) could not be pinned.")
            }
            do {
                identity = try Self.descriptorIdentity(descriptor)
                guard identity.fileType == S_IFDIR else {
                    throw BackupError.staging("The pinned object at \(url.path) is not a directory.")
                }
                try Self.validatePrivateOwnership(descriptor, label: url.path)
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        init(childNamed name: String, at url: URL, in parent: PinnedDirectory, fileManager: FileManager) throws {
            self.url = url
            self.fileManager = fileManager
            relativeParent = parent
            relativeName = name
            descriptor = Darwin.openat(
                parent.descriptor,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw BackupError.staging("The directory at \(url.path) could not be pinned relative to its policy directory.")
            }
            do {
                identity = try Self.descriptorIdentity(descriptor)
                guard identity.fileType == S_IFDIR,
                      try Self.childPathIdentity(parent.descriptor, name: name) == identity else {
                    throw BackupError.staging("The pinned object at \(url.path) is not a directory.")
                }
                try Self.validatePrivateOwnership(descriptor, label: url.path)
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        deinit {
            Darwin.close(descriptor)
        }

        func observeAndValidatePath() throws {
            try validatePath()
        }

        func createExclusiveDirectory(named name: String, at childURL: URL) throws -> PinnedDirectory {
            guard mkdirat(descriptor, name, S_IRWXU) == 0 else {
                throw BackupError.staging(
                    "Could not exclusively create a directory in the pinned parent (errno \(errno))."
                )
            }
            return try PinnedDirectory(
                childNamed: name,
                at: childURL,
                in: self,
                fileManager: fileManager
            )
        }

        func createExclusiveOwnedDirectory(named name: String, at childURL: URL) throws -> PinnedDirectory {
            let child = try createExclusiveDirectory(named: name, at: childURL)
            do {
                try child.establishDurableOwnership()
                return child
            } catch {
                throw child.retainedArtifactError(
                    kind: .staging,
                    state: .failed,
                    detail: "The exclusively created hidden package could not establish durable ownership: \(error.localizedDescription)"
                )
            }
        }

        func openOrCreateDirectory(named name: String, at childURL: URL) throws -> PinnedDirectory {
            var value = stat()
            if fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 {
                return try PinnedDirectory(
                    childNamed: name,
                    at: childURL,
                    in: self,
                    fileManager: fileManager
                )
            }
            let lookupError = errno
            guard lookupError == ENOENT else {
                throw BackupError.staging(
                    "The backup policy component \(name) could not be inspected without following links (errno \(lookupError))."
                )
            }
            return try createExclusiveDirectory(named: name, at: childURL)
        }

        func openExistingDirectory(named name: String, at childURL: URL) throws -> PinnedDirectory {
            var value = stat()
            guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                  value.st_mode & S_IFMT == S_IFDIR else {
                throw BackupError.verification(
                    "The existing backup policy component \(name) could not be pinned without mutation."
                )
            }
            return try PinnedDirectory(
                childNamed: name,
                at: childURL,
                in: self,
                fileManager: fileManager
            )
        }

        func directoryNames() throws -> [String] {
            let duplicated = dup(descriptor)
            guard duplicated >= 0, let directory = fdopendir(duplicated) else {
                if duplicated >= 0 { Darwin.close(duplicated) }
                throw BackupError.verification("The pinned policy directory could not be enumerated.")
            }
            defer { closedir(directory) }
            rewinddir(directory)
            var names: [String] = []
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name != ".", name != ".." { names.append(name) }
            }
            return names.sorted()
        }

        func childDirectoryIdentity(named name: String) throws -> FileIdentity {
            var value = stat()
            guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.verification("The pinned policy child \(name) is no longer reachable.")
            }
            let childIdentity = Self.identity(from: value)
            guard childIdentity.fileType == S_IFDIR else {
                throw BackupError.verification("The pinned policy child \(name) is not a directory.")
            }
            return childIdentity
        }

        func currentIdentity() throws -> FileIdentity {
            try Self.descriptorIdentity(descriptor)
        }

        func clonePinnedDirectoryExclusively(
            from source: PinnedDirectory,
            verifiedSource: PinnedPackage,
            to destinationName: String,
            at destinationURL: URL
        ) throws -> PinnedDirectory {
            guard try Self.descriptorIdentity(source.descriptor).isSameNode(as: source.identity),
                  verifiedSource.identity.directory.isSameNode(as: source.identity) else {
                throw BackupError.publication("The pinned source descriptor changed identity before publication.")
            }
            // This is intentionally the last operation before fclonefileat. It
            // revalidates the exact verified/cap-accounted child descriptors,
            // their parent-relative names, link counts, and regular-file sizes.
            try verifiedSource.validateUnchanged()
            try DatabaseSafetyService.publishPinnedDirectoryAtomically(
                sourceDescriptor: source.descriptor,
                destinationDirectoryDescriptor: descriptor,
                destinationName: destinationName
            )
            return try PinnedDirectory(
                childNamed: destinationName,
                at: destinationURL,
                in: self,
                fileManager: fileManager
            )
        }

        func movePinnedDirectoryExclusively(
            from source: PinnedDirectory,
            sourceName: String,
            to destinationName: String,
            at destinationURL: URL
        ) throws -> PinnedDirectory {
            guard try Self.descriptorIdentity(source.descriptor).isSameNode(as: source.identity) else {
                throw BackupError.publication("The pinned staging descriptor changed before publication.")
            }
            guard renameatx_np(
                descriptor,
                sourceName,
                descriptor,
                destinationName,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                let moveError = errno
                if moveError == EEXIST || moveError == ENOTEMPTY {
                    throw BackupError.collision(
                        "The destination became occupied; no existing artifact was replaced."
                    )
                }
                throw BackupError.publication(
                    "The verified staging package could not be atomically moved without replacement (errno \(moveError))."
                )
            }
            let published = try PinnedDirectory(
                childNamed: destinationName,
                at: destinationURL,
                in: self,
                fileManager: fileManager
            )
            guard published.identity.isSameNode(as: source.identity) else {
                throw BackupError.publication(
                    "The atomic publication moved an object other than the pinned staging package."
                )
            }
            return published
        }

        func childURL(named name: String) throws -> URL {
            try currentURL().appendingPathComponent(name, isDirectory: true)
        }

        func validatePath() throws {
            let descriptorIdentity = try Self.descriptorIdentity(descriptor)
            let reachableIdentity: FileIdentity
            if let relativeParent, let relativeName {
                try relativeParent.validatePath()
                reachableIdentity = try Self.childPathIdentity(
                    relativeParent.descriptor,
                    name: relativeName
                )
            } else {
                reachableIdentity = try Self.pathIdentity(url)
            }
            guard descriptorIdentity.isSameNode(as: identity),
                  reachableIdentity.isSameNode(as: identity) else {
                throw BackupError.staging("The pinned directory path changed identity at \(url.path).")
            }
        }

        func currentURL() throws -> URL {
            if let relativeParent, let relativeName,
               let reachableIdentity = try? Self.childPathIdentity(
                   relativeParent.descriptor,
                   name: relativeName
               ),
               reachableIdentity.isSameNode(as: identity) {
                return try relativeParent.currentURL().appendingPathComponent(
                    relativeName,
                    isDirectory: true
                )
            }
            if let pathIdentity = try? Self.pathIdentity(url),
               pathIdentity.isSameNode(as: identity) {
                return url
            }
            var descriptorInfo = vnode_fdinfowithpath()
            var descriptorPathResult: Int32 = -1
            if let library = dlopen(nil, RTLD_LAZY) {
                defer { dlclose(library) }
                if let symbol = dlsym(library, "proc_pidfdinfo") {
                    let infoForDescriptor = unsafeBitCast(
                        symbol,
                        to: CiderDescriptorInfoFunction.self
                    )
                    descriptorPathResult = withUnsafeMutablePointer(to: &descriptorInfo) { pointer in
                        infoForDescriptor(
                            getpid(),
                            descriptor,
                            2, // PROC_PIDFDVNODEPATHINFO
                            UnsafeMutableRawPointer(pointer),
                            Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                        )
                    }
                }
            }
            if descriptorPathResult > 0 {
                let path = withUnsafeBytes(of: descriptorInfo.pvip.vip_path) { bytes in
                    String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
                }
                let candidate = URL(
                    fileURLWithPath: path,
                    isDirectory: true
                )
                if let candidateIdentity = try? Self.pathIdentity(candidate),
                   candidateIdentity.isSameNode(as: identity) {
                    return candidate
                }
            }
            let searchRoot = url.deletingLastPathComponent().deletingLastPathComponent()
            if let enumerator = fileManager.enumerator(
                at: searchRoot,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                for case let candidate as URL in enumerator {
                    guard let candidateIdentity = try? Self.pathIdentity(candidate) else { continue }
                    if candidateIdentity.isSameNode(as: identity) { return candidate }
                }
            }
            throw BackupError.staging("The retained pinned directory path could not be resolved.")
        }

        func retainedArtifactError(
            kind: BackupFailureKind,
            state: BackupVerificationState,
            detail: String
        ) -> BackupError {
            do {
                return .retainedArtifact(
                    kind: kind,
                    state: state,
                    detail: detail,
                    url: try currentURL()
                )
            } catch {
                return .retainedArtifactLocationUnknown(
                    kind: kind,
                    state: state,
                    detail: "\(detail) Exact-path resolution failed: \(error.localizedDescription)"
                )
            }
        }

        func createExclusiveRegularFile(named name: String) throws -> Int32 {
            try DatabaseSafetyService.createExclusivePinnedRegularFile(
                directoryDescriptor: descriptor,
                name: name
            )
        }

        func prepareRegularFile(named name: String, reusing: Bool) throws -> Int32 {
            guard reusing else { return try createExclusiveRegularFile(named: name) }
            var reachable = stat()
            if fstatat(descriptor, name, &reachable, AT_SYMLINK_NOFOLLOW) != 0 {
                let lookupError = errno
                guard lookupError == ENOENT else {
                    throw BackupError.staging(
                        "The reusable package child \(name) could not be inspected (errno \(lookupError))."
                    )
                }
                return try createExclusiveRegularFile(named: name)
            }
            let childDescriptor = Darwin.openat(
                descriptor,
                name,
                O_RDWR | O_NOFOLLOW | O_CLOEXEC
            )
            guard childDescriptor >= 0 else {
                throw BackupError.staging(
                    "The reusable package child \(name) could not be pinned (errno \(errno))."
                )
            }
            do {
                try validateChild(named: name, descriptor: childDescriptor)
                guard ftruncate(childDescriptor, 0) == 0,
                      fsync(childDescriptor) == 0 else {
                    throw BackupError.staging(
                        "The retired package child \(name) could not be reset through its descriptor."
                    )
                }
                try validateChild(named: name, descriptor: childDescriptor)
                return childDescriptor
            } catch {
                Darwin.close(childDescriptor)
                throw error
            }
        }

        func isReusableGeneratedPackageSlot(allowedNames: Set<String>) -> Bool {
            do {
                try validatePath()
                guard hasDurableOwnership() else { return false }
                let names = try directoryNames()
                guard Set(names).isSubset(of: allowedNames) else { return false }
                for name in names {
                    let child = Darwin.openat(
                        descriptor,
                        name,
                        O_RDWR | O_NOFOLLOW | O_CLOEXEC
                    )
                    guard child >= 0 else { return false }
                    var value = stat()
                    let inspected = fstat(child, &value) == 0
                        && value.st_mode & S_IFMT == S_IFREG
                        && value.st_uid == geteuid()
                        && value.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0
                        && value.st_nlink == 1
                    do {
                        if inspected {
                            try validateChild(named: name, descriptor: child)
                        }
                        Darwin.close(child)
                    } catch {
                        Darwin.close(child)
                        return false
                    }
                    guard inspected else { return false }
                }
                try validatePath()
                return try directoryNames() == names
            } catch {
                return false
            }
        }

        func establishDurableOwnership() throws {
            let result = Self.ownershipValue.withUnsafeBytes { bytes in
                fsetxattr(
                    descriptor,
                    Self.ownershipAttribute,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    XATTR_CREATE
                )
            }
            guard result == 0 else {
                throw BackupError.staging(
                    "The Cider package ownership attribute could not be established (errno \(errno))."
                )
            }
            let nonce = Data(UUID().uuidString.lowercased().utf8)
            let nonceResult = nonce.withUnsafeBytes { bytes in
                fsetxattr(
                    descriptor,
                    Self.ownershipNonceAttribute,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    XATTR_CREATE
                )
            }
            guard nonceResult == 0 else {
                throw BackupError.staging(
                    "The Cider package creation nonce could not be established (errno \(errno))."
                )
            }
            guard hasDurableOwnership() else {
                throw BackupError.staging("The Cider package ownership attribute was not durable.")
            }
        }

        func hasDurableOwnership() -> Bool {
            hasPublicOwnershipMarker() && ownershipNonce() != nil
        }

        func hasPublicOwnershipMarker() -> Bool {
            Self.hasPublicOwnershipMarker(descriptor: descriptor)
        }

        fileprivate static func hasPublicOwnershipMarker(descriptor: Int32) -> Bool {
            let size = fgetxattr(descriptor, ownershipAttribute, nil, 0, 0, 0)
            guard size == Self.ownershipValue.count else { return false }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { bytes in
                fgetxattr(
                    descriptor,
                    ownershipAttribute,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    0
                )
            }
            return read == size && data == Self.ownershipValue
        }

        func ownershipNonce() -> String? {
            Self.ownershipNonce(descriptor: descriptor)
        }

        fileprivate static func ownershipNonce(descriptor: Int32) -> String? {
            let size = fgetxattr(descriptor, ownershipNonceAttribute, nil, 0, 0, 0)
            guard size > 0, size <= 128 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { bytes in
                fgetxattr(
                    descriptor,
                    ownershipNonceAttribute,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    0
                )
            }
            guard read == size,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else { return nil }
            return value
        }

        func validateChild(named name: String, descriptor childDescriptor: Int32) throws {
            let descriptorIdentity = try Self.descriptorIdentity(childDescriptor)
            var pathStat = stat()
            guard fstatat(descriptor, name, &pathStat, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.staging("The pinned staging child \(name) is no longer reachable.")
            }
            let pathIdentity = Self.identity(from: pathStat)
            guard descriptorIdentity.fileType == S_IFREG,
                  descriptorIdentity.linkCount == 1,
                  pathIdentity == descriptorIdentity else {
                throw BackupError.staging("The pinned staging child \(name) changed identity or link count.")
            }
        }

        private static func descriptorIdentity(_ descriptor: Int32) throws -> FileIdentity {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else {
                throw BackupError.staging("A pinned directory identity could not be read.")
            }
            return identity(from: value)
        }

        private static func pathIdentity(_ url: URL) throws -> FileIdentity {
            let pathDescriptor = Darwin.open(
                url.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard pathDescriptor >= 0 else {
                throw BackupError.staging("The pinned directory path identity could not be read without following links.")
            }
            defer { Darwin.close(pathDescriptor) }
            var value = stat()
            guard fstat(pathDescriptor, &value) == 0 else {
                throw BackupError.staging("The pinned directory path identity could not be read.")
            }
            return identity(from: value)
        }

        fileprivate static func childPathIdentity(_ directoryDescriptor: Int32, name: String) throws -> FileIdentity {
            var value = stat()
            guard fstatat(directoryDescriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.staging("The pinned child directory identity could not be read.")
            }
            return identity(from: value)
        }

        private static func identity(from value: stat) -> FileIdentity {
            FileIdentity(
                device: value.st_dev,
                inode: value.st_ino,
                generation: value.st_gen,
                fileType: value.st_mode & S_IFMT,
                linkCount: value.st_nlink,
                byteSize: value.st_size
            )
        }

        private static func validatePrivateOwnership(_ descriptor: Int32, label: String) throws {
            var value = stat()
            guard fstat(descriptor, &value) == 0,
                  value.st_uid == geteuid(),
                  value.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
                throw BackupError.staging(
                    "The policy component \(label) must be owned by the current user and not writable by group or others."
                )
            }
        }
    }

    private struct PublishedBackup {
        let url: URL
        let verification: BackupVerification
        let qualifiedArtifact: QualifiedBackupArtifact
        var warnings: [String]
    }

    private struct PackageTarget {
        let name: String
        let url: URL
        let directory: PinnedDirectory
        let isReusedSlot: Bool
        let finalName: String
        let finalURL: URL
        let captureByteLimit: Int64
    }

    private struct RotationCandidate {
        let name: String
        let package: VerifiedPackage
    }

    private struct RotationPlan {
        let candidatesToRetire: [RotationCandidate]
        let warnings: [String]
    }

    private struct AggregateOwnedArtifact {
        let identity: FileIdentity
        let accountedBytes: Int64
    }

    private struct AggregatePolicyInventory {
        let names: [String]
        let ledger: ParentOwnershipLedger
        let ownedArtifacts: [AggregateOwnedArtifact]
        let accountedBytes: Int64
    }

    private final class QuarantinedLiveFile {
        let originalName: String
        let hiddenName: String
        let identity: FileIdentity
        let descriptor: Int32

        init(
            originalName: String,
            hiddenName: String,
            identity: FileIdentity,
            descriptor: Int32
        ) {
            self.originalName = originalName
            self.hiddenName = hiddenName
            self.identity = identity
            self.descriptor = descriptor
        }

        deinit {
            Darwin.close(descriptor)
        }
    }

    private struct RestoreRollbackOutcome {
        let priorDatabaseLocation: String?
        let replacementLocation: String?
        let sidecarsRestored: Bool
        let retainedSidecarLocations: [String]
        let parentFlushed: Bool

        var priorCoherentDatabaseRestored: Bool {
            priorDatabaseLocation?.hasPrefix("live:") == true && sidecarsRestored
        }
    }

    private let logger = Logger(subsystem: "com.cider.app", category: "DatabaseSafety")
    private let fileManager: FileManager

    private let preOpenSnapshotInterval: TimeInterval = 12 * 60 * 60
    private let rollingBackupInterval: TimeInterval = 12 * 60 * 60
    private let preOpenRetentionCount = 3
    private let rollingBackupRetentionCount = 7
    private let packageExtension = "ciderbackup"
    private let databaseFilename = "database.sqlite"
    private let manifestFilename = "manifest.json"
    nonisolated static let retentionAccountingNodeOverheadBytes: Int64 = 4 * 1_024
    nonisolated static let retentionMaximumManifestBytes: Int64 = 64 * 1_024
    nonisolated static let retentionLedgerPayloadBytes: Int64 = 128 * 1_024
    nonisolated static let retentionLedgerOverheadBytes: Int64 = 4 * 1_024

    private let maximumPolicyBytes: Int64
    private let maximumAggregatePolicyEntries = 128
    private let maximumAggregateOwnedNodes = 256
    private let maximumAggregateTraversalDepth = 8
    private let ownershipLedgerAttribute = "com.cider.cid850.parent-ownership-ledger-v1"
    private let maximumOwnershipLedgerEntries = 32

    init(
        fileManager: FileManager = .default,
        maximumPolicyBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.maximumPolicyBytes = maximumPolicyBytes
    }

    func capturePreOpenSnapshotIfNeeded(databaseURL: URL) {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }

        do {
            var state = try loadState(for: databaseURL)
            guard shouldRun(lastRunAt: state.lastPreOpenSnapshotAt, minimumInterval: preOpenSnapshotInterval) else {
                return
            }

            let snapshotURL = try capturePreOpenSnapshot(databaseURL: databaseURL, reason: "pre-open")
            state.lastPreOpenSnapshotAt = Date()
            try saveState(state, for: databaseURL)
            logger.info("Captured and verified pre-open database snapshot at \(snapshotURL.path)")
        } catch {
            logger.error("Failed to capture pre-open database snapshot: \(error.localizedDescription)")
        }
    }

    func performStartupSafetyPass(database: CiderDatabase = .shared) {
        guard database.isOpen, let databaseURL = database.databaseURL else { return }

        do {
            var state = try loadState(for: databaseURL)
            // CiderDatabase.open owns mandatory preflight and post-open
            // integrity validation. This best-effort service now performs only
            // the existing rolling-backup cadence after that gate succeeds.
            if shouldRun(lastRunAt: state.lastRollingBackupAt, minimumInterval: rollingBackupInterval) {
                _ = try createRollingBackup(reason: "startup", database: database, updateState: false)
                state.lastRollingBackupAt = Date()
                try saveState(state, for: databaseURL)
            }
        } catch {
            logger.error("Database safety pass failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createRollingBackup(
        reason: String,
        database: CiderDatabase = .shared,
        updateState: Bool = true
    ) throws -> QualifiedBackupArtifact {
        let receipt = try createRollingBackupReceipt(
            reason: reason,
            database: database,
            updateState: updateState
        )
        guard let artifact = receipt.artifact, receipt.usable else {
            throw BackupError.verification("A retained verified artifact was not produced.")
        }
        return artifact
    }

    func createRollingBackupReceipt(
        reason: String,
        database: CiderDatabase = .shared,
        updateState: Bool = true
    ) throws -> BackupCreationReceipt {
        guard let sourceDatabaseURL = database.databaseURL else {
            throw BackupError.sourceUnavailable("SQLite database is not open.")
        }
        guard let sourceLineage = database.backupSourceLineage else {
            throw BackupError.sourceUnavailable("The open SQLite handle has no verified source lineage.")
        }
        var published = try createPublishedBackup(
            kind: .rolling,
            reason: reason,
            sourceDatabaseURL: sourceDatabaseURL,
            sourceLineage: sourceLineage,
            retentionCount: rollingBackupRetentionCount
        ) { stagedDatabaseDescriptor, maximumBytes in
            do {
                try database.captureOnlineBackup(
                    into: stagedDatabaseDescriptor,
                    maximumBytes: maximumBytes
                )
            } catch let error as CiderDatabaseBackupCapacityError {
                throw BackupError.retentionCapacity(error.localizedDescription)
            } catch {
                throw BackupError.capture(error.localizedDescription)
            }
        }

        if updateState {
            do {
                var state = try loadState(for: sourceDatabaseURL)
                state.lastRollingBackupAt = Date()
                try saveState(state, for: sourceDatabaseURL)
            } catch {
                published.warnings.append("The backup is verified, but its cadence state was not updated: \(error.localizedDescription)")
            }
        }

        logger.info("Created and verified rolling SQLite backup at \(published.url.path)")
        return BackupCreationReceipt(
            state: .verified,
            backupURL: published.url,
            verification: published.verification,
            failureKind: nil,
            message: "Created and verified \(published.url.lastPathComponent).",
            warnings: published.warnings,
            qualifiedArtifact: published.qualifiedArtifact
        )
    }

    func createManualBackup(database: CiderDatabase = .shared) -> BackupCreationReceipt {
        do {
            return try createRollingBackupReceipt(reason: "manual", database: database)
        } catch let error as BackupError {
            return Self.failedCreationReceipt(for: error)
        } catch {
            return BackupCreationReceipt(
                state: .failed,
                backupURL: nil,
                verification: nil,
                failureKind: .publication,
                message: error.localizedDescription,
                warnings: []
            )
        }
    }

    // MARK: - Paths and inspection

    func backupsRootDirectory(for databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("sqlite", isDirectory: true)
    }

    func rollingBackupsDirectory(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("rolling", isDirectory: true)
    }

    func preOpenSnapshotsDirectory(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("preflight", isDirectory: true)
    }

    func listRollingBackups(databaseURL: URL) -> [SQLiteBackupInfo] {
        listBackups(in: rollingBackupsDirectory(for: databaseURL), kind: .rolling)
    }

    func listPreOpenSnapshots(databaseURL: URL) -> [SQLiteBackupInfo] {
        listBackups(in: preOpenSnapshotsDirectory(for: databaseURL), kind: .preflight)
    }

    func verifyBackup(at backupURL: URL) -> BackupVerification {
        if backupURL.pathExtension.lowercased() == "db" {
            return verifyLegacyRawBackup(at: backupURL)
        }
        let requiredNames = [databaseFilename, manifestFilename].sorted()
        let package: PinnedPackage
        let policyDirectory: PinnedDirectory?
        let authorityLease: PolicyLease?
        do {
            policyDirectory = try recognizedPolicyDirectory(for: backupURL)
            if let policyDirectory {
                authorityLease = try PolicyLease(policyDirectory: policyDirectory, exclusive: false)
                package = try PinnedPackage(
                    childNamed: backupURL.lastPathComponent,
                    at: backupURL,
                    in: policyDirectory,
                    requiredNames: requiredNames,
                    fileManager: fileManager
                )
            } else {
                authorityLease = nil
                package = try PinnedPackage(
                    packageURL: backupURL,
                    requiredNames: requiredNames,
                    fileManager: fileManager
                )
            }
        } catch let error as BackupError {
            return BackupVerification(
                state: .unusable,
                schemaVersion: nil,
                databaseSHA256: nil,
                manifestSHA256: nil,
                artifactNames: artifactNames(at: backupURL),
                retainedBytesUnchanged: false,
                messages: [error.localizedDescription]
            )
        } catch {
            return BackupVerification(
                state: .failed,
                schemaVersion: nil,
                databaseSHA256: nil,
                manifestSHA256: nil,
                artifactNames: artifactNames(at: backupURL),
                retainedBytesUnchanged: false,
                messages: [error.localizedDescription]
            )
        }

        let before = try? package.fingerprint()
        do {
            _ = authorityLease
            return try verifyPinnedPackage(
                package,
                expectedKind: nil,
                expectedLineage: nil
            ).verification
        } catch {
            let after = try? package.fingerprint()
            let identityUnchanged = (try? package.validateUnchanged()) != nil
            return BackupVerification(
                state: .unusable,
                schemaVersion: nil,
                databaseSHA256: nil,
                manifestSHA256: nil,
                artifactNames: package.artifactNames,
                retainedBytesUnchanged: before != nil && before == after && identityUnchanged,
                messages: [error.localizedDescription]
            )
        }
    }

    @discardableResult
    func materializeVerifiedBackupDatabase(
        from backupURL: URL,
        at destinationURL: URL
    ) throws -> URL {
        let databaseData = try verifiedDatabaseData(
            at: backupURL,
            expectedKind: nil,
            allowLegacyRecovery: true
        ).data
        let destinationDescriptor = Darwin.open(
            destinationURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard destinationDescriptor >= 0 else {
            throw BackupError.publication(
                "The verified database materialization destination could not be exclusively created."
            )
        }
        defer { Darwin.close(destinationDescriptor) }
        try write(databaseData, to: destinationDescriptor, artifactName: destinationURL.lastPathComponent)
        return destinationURL
    }

    @discardableResult
    func materializeVerifiedBackupDatabase(
        from artifact: QualifiedBackupArtifact,
        at destinationURL: URL
    ) throws -> URL {
        let databaseData = try verifiedDatabaseData(from: artifact)
        let destinationDescriptor = Darwin.open(
            destinationURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard destinationDescriptor >= 0 else {
            throw BackupError.publication(
                "The verified database materialization destination could not be exclusively created."
            )
        }
        defer { Darwin.close(destinationDescriptor) }
        try write(databaseData, to: destinationDescriptor, artifactName: destinationURL.lastPathComponent)
        return destinationURL
    }

    // MARK: - Restore compatibility (replacement policy remains CID-851)

    @discardableResult
    func restoreRollingBackup(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase? = nil,
        reopenDatabase: Bool = false
    ) throws -> RestoreResult {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw RestoreError.missingBackup(backupURL)
        }
        var destinationStat = stat()
        if lstat(databaseURL.path, &destinationStat) != 0 {
            guard errno == ENOENT else {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The restore destination could not be inspected without following links."]
                )
            }
            return try restoreIntoNewDestination(
                from: backupURL,
                into: databaseURL,
                database: database,
                reopenDatabase: reopenDatabase
            )
        }

        let destinationObservation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
        let destinationLineage = try destinationObservation.validate()
        let databaseParent = try PinnedDirectory(
            url: databaseURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        var authorityLease: PolicyLease? = try PolicyLease(
            policyDirectory: databaseParent,
            exclusive: true
        )
        _ = authorityLease
        guard try destinationObservation.validate() == destinationLineage else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The restore destination lineage changed before source verification."]
            )
        }
        let retainedUse = try pinRestoreSource(
            at: backupURL,
            expectedKind: .rolling,
            expectedLineage: destinationLineage.identifier,
            legacyDestinationURL: databaseURL
        )
        guard retainedUse.verification.isRecoveryEligible else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: retainedUse.verification.messages
            )
        }
        let restoredBackup = SQLiteBackupInfo(
            kind: .rolling,
            url: backupURL,
            createdAt: retainedUse.createdAt,
            byteSize: (try? folderSize(at: backupURL)) ?? 0,
            verification: retainedUse.verification
        )

        let preRestoreSnapshotURL: URL?
        if fileManager.fileExists(atPath: databaseURL.path) {
            preRestoreSnapshotURL = try capturePreOpenSnapshot(
                databaseURL: databaseURL,
                reason: "pre-restore",
                authorityLeaseHeld: true
            )
        } else {
            preRestoreSnapshotURL = nil
        }
        _ = try retainedUse.finalDatabaseData(service: self)

        if let database, database.isOpen, database.databaseURL == databaseURL {
            database.close()
        }

        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard try destinationObservation.validate() == destinationLineage else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The restore destination changed identity before live mutation."]
            )
        }
        var finalUse = try retainedUse.finalDatabaseData(service: self)
        try replaceLiveDatabaseAtomically(
            at: databaseURL,
            with: finalUse.data,
            in: databaseParent,
            expectedDestinationLineage: destinationLineage,
            beforeMutation: {
                finalUse = try retainedUse.finalDatabaseData(service: self)
            }
        )

        authorityLease = nil
        if reopenDatabase, let database {
            try database.open(at: databaseURL)
        }

        logger.info("Restored SQLite database from backup \(backupURL.lastPathComponent, privacy: .public)")
        return RestoreResult(
            restoredBackup: restoredBackup,
            preRestoreSnapshotURL: preRestoreSnapshotURL,
            sourceReference: finalUse.reference
        )
    }

    private func stateFileURL(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("state.json")
    }

    private func restoreIntoNewDestination(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase?,
        reopenDatabase: Bool
    ) throws -> RestoreResult {
        for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: databaseURL.path + suffix) {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The absent destination has an orphan SQLite sidecar; no restore mutation was attempted."]
            )
        }
        let databaseParent = try PinnedDirectory(
            url: databaseURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        var authorityLease: PolicyLease? = try PolicyLease(
            policyDirectory: databaseParent,
            exclusive: true
        )
        _ = authorityLease
        let retainedUse = try pinRestoreSource(
            at: backupURL,
            expectedKind: .rolling,
            expectedLineage: nil,
            legacyDestinationURL: databaseURL,
            destinationExists: false
        )
        guard retainedUse.verification.isRecoveryEligible else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: retainedUse.verification.messages
            )
        }
        var finalUse = try retainedUse.finalDatabaseData(service: self)
        let hiddenName = ".cid850-restore-new-\(UUID().uuidString.lowercased()).sqlite"
        let hiddenDescriptor = try databaseParent.createExclusiveRegularFile(named: hiddenName)
        defer { Darwin.close(hiddenDescriptor) }
        try write(finalUse.data, to: hiddenDescriptor, artifactName: hiddenName)
        _ = try verifySQLiteDatabase(data: finalUse.data, descriptor: hiddenDescriptor)
        finalUse = try retainedUse.finalDatabaseData(service: self)
        guard fclonefileat(
            hiddenDescriptor,
            databaseParent.descriptor,
            databaseURL.lastPathComponent,
            0
        ) == 0 else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The verified restore could not be atomically installed at the absent destination."]
            )
        }
        let installedDescriptor = Darwin.openat(
            databaseParent.descriptor,
            databaseURL.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard installedDescriptor >= 0 else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The newly restored database could not be pinned after atomic publication."]
            )
        }
        let installedData = try data(
            from: installedDescriptor,
            artifactName: databaseURL.lastPathComponent
        )
        Darwin.close(installedDescriptor)
        guard installedData == finalUse.data else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The newly restored database differs from the held verified source."]
            )
        }
        var hiddenStat = stat()
        if fstatat(
            databaseParent.descriptor,
            hiddenName,
            &hiddenStat,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            _ = unlinkat(
                databaseParent.descriptor,
                hiddenName,
                AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
            )
        }
        authorityLease = nil
        if reopenDatabase, let database {
            try database.open(at: databaseURL)
        }
        let restoredBackup = SQLiteBackupInfo(
            kind: .rolling,
            url: backupURL,
            createdAt: retainedUse.createdAt,
            byteSize: Int64(finalUse.data.count),
            verification: retainedUse.verification
        )
        return RestoreResult(
            restoredBackup: restoredBackup,
            preRestoreSnapshotURL: nil,
            sourceReference: finalUse.reference
        )
    }

    // MARK: - Capture, verification, and publication

    private func capturePreOpenSnapshot(
        databaseURL: URL,
        reason: String,
        authorityLeaseHeld: Bool = false
    ) throws -> URL {
        let inspection: ExistingDatabaseInspection
        do {
            inspection = try DatabaseStartupPreflight.establishExistingDatabaseHealth(at: databaseURL)
        } catch {
            throw BackupError.sourceUnavailable(error.localizedDescription)
        }
        defer { inspection.close() }

        let published = try createPublishedBackup(
            kind: .preflight,
            reason: reason,
            sourceDatabaseURL: databaseURL,
            sourceLineage: inspection.sourceLineage,
            retentionCount: preOpenRetentionCount,
            authorityLeaseHeld: authorityLeaseHeld
        ) { stagedDatabaseDescriptor, maximumBytes in
            do {
                try DatabaseStartupPreflight.captureBackup(
                    from: inspection,
                    to: stagedDatabaseDescriptor,
                    maximumBytes: maximumBytes
                )
            } catch let error as CiderDatabaseBackupCapacityError {
                throw BackupError.retentionCapacity(error.localizedDescription)
            } catch {
                throw BackupError.capture(error.localizedDescription)
            }
        }
        return published.url
    }

    private func createPublishedBackup(
        kind: SQLiteBackupInfo.Kind,
        reason: String,
        sourceDatabaseURL: URL,
        sourceLineage: DatabaseSourceLineage,
        retentionCount: Int,
        authorityLeaseHeld: Bool = false,
        capture: (Int32, Int64) throws -> Void
    ) throws -> PublishedBackup {
        let directoryURL = kind == .rolling
            ? rollingBackupsDirectory(for: sourceDatabaseURL)
            : preOpenSnapshotsDirectory(for: sourceDatabaseURL)
        do {
            let sourceBinding = try SourceLineageBinding(
                databaseURL: sourceDatabaseURL,
                expected: sourceLineage
            )
            let databaseDirectoryURL = sourceDatabaseURL.deletingLastPathComponent().standardizedFileURL
            var policyDirectory = try PinnedDirectory(
                url: databaseDirectoryURL,
                fileManager: fileManager
            )
            for component in ["backups", "sqlite", kind == .rolling ? "rolling" : "preflight"] {
                let childURL = policyDirectory.url.appendingPathComponent(component, isDirectory: true)
                policyDirectory = try policyDirectory.openOrCreateDirectory(
                    named: component,
                    at: childURL
                )
            }
            guard policyDirectory.url.standardizedFileURL == directoryURL.standardizedFileURL else {
                throw BackupError.staging("The descriptor-created backup policy resolved to an unexpected path.")
            }
            do {
                try policyDirectory.observeAndValidatePath()
            } catch {
                throw policyDirectory.retainedArtifactError(
                    kind: .staging,
                    state: .failed,
                    detail: "The backup policy directory changed identity before staging: \(error.localizedDescription)"
                )
            }
            return try createPublishedBackup(
                in: policyDirectory,
                kind: kind,
                reason: reason,
                sourceDatabaseURL: sourceDatabaseURL,
                retentionCount: retentionCount,
                sourceBinding: sourceBinding,
                authorityLeaseHeld: authorityLeaseHeld,
                capture: capture
            )
        } catch {
            throw error
        }
    }

    private func createPublishedBackup(
        in policyDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        reason: String,
        sourceDatabaseURL: URL,
        retentionCount: Int,
        sourceBinding: SourceLineageBinding,
        authorityLeaseHeld: Bool,
        capture: (Int32, Int64) throws -> Void
    ) throws -> PublishedBackup {
        let directoryURL = policyDirectory.url
        let lease = authorityLeaseHeld
            ? nil
            : try PolicyLease(policyDirectory: policyDirectory, exclusive: true)
        _ = lease
        try sourceBinding.validate()
        let sourceByteUpperBound = try sourceBinding.coherentSQLiteSetByteUpperBound()
        let target = try packageTarget(
            in: policyDirectory,
            kind: kind,
            sourceLineage: sourceBinding.lineage,
            slotLimit: retentionCount + 1,
            incomingBytes: sourceByteUpperBound,
            reason: reason
        )
        do {
            return try completeStagedBackup(
                at: target.url,
                in: directoryURL,
                policyDirectory: policyDirectory,
                stagingDirectory: target.directory,
                kind: kind,
                reason: reason,
                sourceDatabaseURL: sourceDatabaseURL,
                finalName: target.finalName,
                retentionCount: retentionCount,
                sourceBinding: sourceBinding,
                reusingSlot: target.isReusedSlot,
                captureByteLimit: target.captureByteLimit,
                capture: capture
            )
        } catch {
            if let backupError = error as? BackupError,
               backupError.retainedArtifactURL != nil {
                throw backupError
            }
            if let backupError = error as? BackupError,
               backupError.kind == .retentionCapacity {
                var stagingStat = stat()
                let stagingIsAbsent = fstatat(
                    policyDirectory.descriptor,
                    target.name,
                    &stagingStat,
                    AT_SYMLINK_NOFOLLOW
                ) != 0 && errno == ENOENT
                var publicationStat = stat()
                let publicationIsAbsent = fstatat(
                    policyDirectory.descriptor,
                    target.finalName,
                    &publicationStat,
                    AT_SYMLINK_NOFOLLOW
                ) != 0 && errno == ENOENT
                if stagingIsAbsent,
                   publicationIsAbsent,
                   (try? enforceExactAggregateCapacity(in: policyDirectory)) != nil {
                    throw backupError
                }
            }
            if let observedURL = try? target.directory.currentURL() {
                _ = try? fileManager.contentsOfDirectory(
                    at: observedURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            }
            let backupError = error as? BackupError
            throw target.directory.retainedArtifactError(
                kind: backupError?.kind ?? .staging,
                state: backupError?.failureState ?? .failed,
                detail: "The failed policy-owned package slot was retained without pathname cleanup. Original failure: \(error.localizedDescription)"
            )
        }
    }

    private func completeStagedBackup(
        at stagingURL: URL,
        in directoryURL: URL,
        policyDirectory: PinnedDirectory,
        stagingDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        reason: String,
        sourceDatabaseURL: URL,
        finalName: String,
        retentionCount: Int,
        sourceBinding: SourceLineageBinding,
        reusingSlot: Bool,
        captureByteLimit: Int64,
        capture: (Int32, Int64) throws -> Void
    ) throws -> PublishedBackup {
        try policyDirectory.validatePath()
        try stagingDirectory.validatePath()

        let manifestDescriptor = try stagingDirectory.prepareRegularFile(
            named: manifestFilename,
            reusing: reusingSlot
        )
        defer { Darwin.close(manifestDescriptor) }

        let databaseDescriptor: Int32
        do {
            databaseDescriptor = try stagingDirectory.prepareRegularFile(
                named: databaseFilename,
                reusing: reusingSlot
            )
        } catch {
            throw BackupError.capture(error.localizedDescription)
        }
        defer { Darwin.close(databaseDescriptor) }
        do {
            try capture(databaseDescriptor, captureByteLimit)
        } catch {
            throw error
        }
        try sourceBinding.validate()
        try stagingDirectory.validateChild(named: databaseFilename, descriptor: databaseDescriptor)
        try stagingDirectory.validatePath()

        let databaseData = try data(from: databaseDescriptor, artifactName: databaseFilename)
        let captured = try verifySQLiteDatabase(data: databaseData, descriptor: databaseDescriptor)
        let manifest = BackupManifest(
            formatVersion: BackupManifest.currentFormatVersion,
            kind: kind,
            reason: sanitize(reason),
            createdAt: Date(),
            sourceDatabaseFilename: sourceDatabaseURL.lastPathComponent,
            sourceLineageIdentifier: sourceBinding.lineage.identifier,
            databaseFilename: databaseFilename,
            schemaVersion: captured.schemaVersion,
            databaseByteSize: captured.byteSize,
            databaseSHA256: captured.sha256,
            artifactNames: [databaseFilename, manifestFilename].sorted()
        )
        let manifestData: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            manifestData = try encoder.encode(manifest)
        } catch {
            throw BackupError.staging("Cannot encode the staged backup manifest: \(error.localizedDescription)")
        }
        guard manifestData.count <= Self.retentionMaximumManifestBytes else {
            throw BackupError.retentionCapacity(
                "The bounded backup manifest exceeds \(Self.retentionMaximumManifestBytes) bytes."
            )
        }

        do {
            try write(manifestData, to: manifestDescriptor, artifactName: manifestFilename)
        } catch {
            throw BackupError.staging("Cannot write the staged backup manifest: \(error.localizedDescription)")
        }
        try stagingDirectory.validateChild(named: manifestFilename, descriptor: manifestDescriptor)
        try stagingDirectory.observeAndValidatePath()

        let stagedPinnedPackage = try PinnedPackage(
            childNamed: stagingURL.lastPathComponent,
            at: stagingURL,
            in: policyDirectory,
            requiredNames: [databaseFilename, manifestFilename].sorted(),
            fileManager: fileManager
        )
        let stagedPackage = try verifyPinnedPackage(
            stagedPinnedPackage,
            expectedKind: kind,
            expectedLineage: sourceBinding.lineage.identifier
        )
        guard stagedPackage.verification.isVerified,
              stagedPackage.identity.directory.isSameNode(as: stagingDirectory.identity) else {
            throw BackupError.verification("The staged artifact did not reach verified state.")
        }

        do {
            try enforceExactAggregateCapacity(
                in: policyDirectory,
                binding: stagedPinnedPackage
            )
        } catch {
            do {
                try removeOwnedHiddenPackage(
                    stagingDirectory,
                    named: stagingURL.lastPathComponent,
                    from: policyDirectory,
                    lineageIdentifier: sourceBinding.lineage.identifier
                )
                try enforceExactAggregateCapacity(in: policyDirectory)
            } catch let rollbackError {
                throw stagingDirectory.retainedArtifactError(
                    kind: .retentionCapacity,
                    state: .failed,
                    detail: "Post-capture exact-cap accounting failed and descriptor-bound staging rollback was not fully durable: \(rollbackError.localizedDescription). Original failure: \(error.localizedDescription)"
                )
            }
            throw BackupError.retentionCapacity(
                "Post-capture exact-cap accounting failed; the exact newly created staging package and ledger entry were rolled back durably. \(error.localizedDescription)"
            )
        }
        let rotation = try rotationPlan(
            in: policyDirectory,
            kind: kind,
            sourceLineage: sourceBinding.lineage,
            slotLimit: retentionCount + 1,
            excluding: stagingDirectory.identity
        )
        let finalURL = directoryURL.appendingPathComponent(finalName, isDirectory: true)
        let publishedDirectory: PinnedDirectory
        do {
            try sourceBinding.validate()
            try policyDirectory.validatePath()
            try stagedPinnedPackage.validateUnchanged()
            let namesBeforePublication = try policyDirectory.directoryNames()
            publishedDirectory = try policyDirectory.clonePinnedDirectoryExclusively(
                from: stagingDirectory,
                verifiedSource: stagedPinnedPackage,
                to: finalName,
                at: finalURL
            )
            guard try policyDirectory.directoryNames()
                == (namesBeforePublication + [finalName]).sorted() else {
                throw BackupError.publication(
                    "The policy membership changed around descriptor publication; the new occupant was not adopted."
                )
            }
            guard publishedDirectory.hasDurableOwnership() else {
                throw BackupError.publication(
                    "The atomically published package lost its durable Cider ownership proof."
                )
            }
            try registerLedgerOwnership(
                publishedDirectory,
                in: policyDirectory,
                lineageIdentifier: sourceBinding.lineage.identifier
            )
        } catch {
            throw stagingDirectory.retainedArtifactError(
                kind: (error as? BackupError)?.kind ?? .publication,
                state: .failed,
                detail: "The verified hidden package could not be published atomically: \(error.localizedDescription)"
            )
        }
        do {
            try stagedPinnedPackage.validateUnchanged()
            try enforceExactAggregateCapacity(
                in: policyDirectory,
                binding: stagedPinnedPackage
            )
        } catch {
            let publicationRollback = Result {
                try rollbackOwnedVisiblePublication(
                    publishedDirectory,
                    named: finalName,
                    from: policyDirectory,
                    lineageIdentifier: sourceBinding.lineage.identifier
                )
            }
            let stagingRollback = Result {
                try removeOwnedHiddenPackage(
                    stagingDirectory,
                    named: stagingURL.lastPathComponent,
                    from: policyDirectory,
                    lineageIdentifier: sourceBinding.lineage.identifier
                )
            }
            do {
                try enforceExactAggregateCapacity(in: policyDirectory)
            } catch let capacityError {
                throw BackupError.retentionCapacity(
                    "Clone-seam accounting failed and exact rollback could not re-establish the hard cap. Publication rollback: \(publicationRollback). Staging rollback: \(stagingRollback). Capacity proof: \(capacityError.localizedDescription). Original failure: \(error.localizedDescription)"
                )
            }
            guard case .success = publicationRollback,
                  case .success = stagingRollback else {
                throw BackupError.retentionCapacity(
                    "Clone-seam accounting failed; every uncertain occupant was preserved and the final inventory is within cap, but exact rollback was incomplete. Publication rollback: \(publicationRollback). Staging rollback: \(stagingRollback). Original failure: \(error.localizedDescription)"
                )
            }
            throw BackupError.retentionCapacity(
                "Clone-seam growth, shrink, replacement, or link drift was rejected; the exact stage, publication, and just-created ledger entries were rolled back and both parents were flushed."
            )
        }

        let retainedPackage: VerifiedPackage
        do {
            retainedPackage = try verifyPackageWithIdentity(
                childNamed: finalName,
                at: finalURL,
                in: policyDirectory,
                expectedKind: kind,
                expectedLineage: sourceBinding.lineage.identifier
            )
            guard stagedPackage.fingerprint == retainedPackage.fingerprint,
                  retainedPackage.lineageIdentifier == sourceBinding.lineage.identifier,
                  retainedPackage.identity.directory.isSameNode(as: publishedDirectory.identity) else {
                throw BackupError.verification("The retained package differs from the verified staged package.")
            }
        } catch {
            let stagingCleanup = Result {
                try removeOwnedHiddenPackage(
                    stagingDirectory,
                    named: stagingURL.lastPathComponent,
                    from: policyDirectory,
                    lineageIdentifier: sourceBinding.lineage.identifier
                )
            }
            do {
                let quarantine = try quarantineFailedPublication(
                    publishedDirectory,
                    named: finalName,
                    in: policyDirectory,
                    lineageIdentifier: sourceBinding.lineage.identifier
                )
                throw quarantine.retainedArtifactError(
                    kind: .verification,
                    state: .unusable,
                    detail: "Published verification failed; the exact continuously held package was moved into bounded quarantine. Staging cleanup: \(stagingCleanup). Original failure: \(error.localizedDescription)"
                )
            } catch let quarantineError as BackupError where quarantineError.retainedArtifactURL != nil {
                throw quarantineError
            } catch {
                throw publishedDirectory.retainedArtifactError(
                    kind: .verification,
                    state: .unusable,
                    detail: "Published verification failed and exact quarantine was uncertain; future admission is blocked while this visible occupant remains. Original failure: \(error.localizedDescription)"
                )
            }
        }

        var warnings = rotation.warnings
        try sourceBinding.validate()
        try policyDirectory.validatePath()
        guard try publishedDirectory.currentURL().standardizedFileURL == finalURL.standardizedFileURL else {
            throw BackupError.retainedArtifact(
                kind: .publication,
                state: .failed,
                detail: "The verified retained package path changed before publication completed.",
                url: try publishedDirectory.currentURL()
            )
        }
        do {
            try removeOwnedHiddenPackage(
                stagingDirectory,
                named: stagingURL.lastPathComponent,
                from: policyDirectory,
                lineageIdentifier: sourceBinding.lineage.identifier
            )
        } catch {
            warnings.append(
                "The verified hidden publication source was preserved for safe later reuse: \(error.localizedDescription)"
            )
        }
        for candidate in rotation.candidatesToRetire {
            do {
                try retireOwnedVisiblePackage(
                    candidate,
                    from: policyDirectory,
                    expectedKind: kind,
                    expectedLineage: sourceBinding.lineage.identifier
                )
            } catch {
                warnings.append(
                    "Preserved verified excess backup \(candidate.name): \(error.localizedDescription)"
                )
            }
        }
        let qualifiedArtifact = try qualifiedArtifact(
            policyDirectory: policyDirectory,
            packageName: finalName,
            package: retainedPackage,
            lineageIdentifier: sourceBinding.lineage.identifier
        )
        guard qualifiedArtifact.currentURL() != nil else {
            throw BackupError.retainedArtifactLocationUnknown(
                kind: .publication,
                state: .unusable,
                detail: "The verified package identity was displaced before its receipt could be qualified."
            )
        }
        return PublishedBackup(
            url: finalURL,
            verification: retainedPackage.verification,
            qualifiedArtifact: qualifiedArtifact,
            warnings: warnings
        )
    }

    private func verifyPackage(
        at packageURL: URL,
        expectedKind: SQLiteBackupInfo.Kind?
    ) throws -> BackupVerification {
        try verifyPackageWithIdentity(
            at: packageURL,
            expectedKind: expectedKind,
            expectedLineage: nil
        ).verification
    }

    private func qualifiedArtifact(
        policyDirectory: PinnedDirectory,
        packageName: String,
        package: VerifiedPackage,
        lineageIdentifier: String
    ) throws -> QualifiedBackupArtifact {
        func object(_ identity: FileIdentity) -> QualifiedBackupArtifact.Object {
            QualifiedBackupArtifact.Object(
                device: identity.device,
                inode: identity.inode,
                generation: identity.generation,
                type: identity.fileType,
                linkCount: identity.fileType == S_IFDIR ? 0 : identity.linkCount
            )
        }
        return QualifiedBackupArtifact(
            policyURL: policyDirectory.url,
            policy: object(try policyDirectory.currentIdentity()),
            packageName: packageName,
            package: object(package.identity.directory),
            childrenByName: package.identity.childrenByName.mapValues(object),
            contentSHA256ByName: package.fingerprint.contentSHA256ByName,
            lineageIdentifier: lineageIdentifier
        )
    }

    private func verifyPackageWithIdentity(
        at packageURL: URL,
        expectedKind: SQLiteBackupInfo.Kind?,
        expectedLineage: String? = nil
    ) throws -> VerifiedPackage {
        let requiredNames = [databaseFilename, manifestFilename].sorted()
        let package = try PinnedPackage(
            packageURL: packageURL,
            requiredNames: requiredNames,
            fileManager: fileManager
        )
        return try verifyPinnedPackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage
        )
    }

    private func verifyPackageWithIdentity(
        childNamed name: String,
        at packageURL: URL,
        in parent: PinnedDirectory,
        expectedKind: SQLiteBackupInfo.Kind?,
        expectedLineage: String? = nil
    ) throws -> VerifiedPackage {
        let requiredNames = [databaseFilename, manifestFilename].sorted()
        let package = try PinnedPackage(
            childNamed: name,
            at: packageURL,
            in: parent,
            requiredNames: requiredNames,
            fileManager: fileManager
        )
        return try verifyPinnedPackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage
        )
    }

    private func verifyPinnedPackage(
        _ package: PinnedPackage,
        expectedKind: SQLiteBackupInfo.Kind?,
        expectedLineage: String?,
        allowRecordedLineageWithoutCurrentSource: Bool = false
    ) throws -> VerifiedPackage {
        let before = try package.fingerprint()

        let manifestData: Data
        let manifest: BackupManifest
        do {
            manifestData = try package.data(for: manifestFilename)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            manifest = try decoder.decode(BackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.verification("The retained manifest is unreadable or malformed: \(error.localizedDescription)")
        }

        guard (manifest.formatVersion == 1
                || manifest.formatVersion == BackupManifest.currentFormatVersion),
              manifest.databaseFilename == databaseFilename,
              manifest.artifactNames.sorted() == package.artifactNames else {
            throw BackupError.verification("The retained manifest does not describe the complete package.")
        }
        if let expectedKind, manifest.kind != expectedKind {
            throw BackupError.verification("The retained manifest backup kind does not match its storage policy.")
        }

        let databaseData = try package.data(for: databaseFilename)
        let database = try verifySQLiteDatabase(
            data: databaseData,
            descriptor: package.descriptor(for: databaseFilename)
        )
        guard database.schemaVersion == manifest.schemaVersion else {
            throw BackupError.verification(
                "The reopened schema version \(database.schemaVersion) does not match manifest version \(manifest.schemaVersion)."
            )
        }
        guard database.byteSize == manifest.databaseByteSize,
              database.sha256 == manifest.databaseSHA256 else {
            throw BackupError.verification("The retained database bytes do not match the manifest SHA-256 and size.")
        }

        let after = try package.fingerprint()
        guard before == after else {
            throw BackupError.verification("The retained DB/WAL/SHM set or manifest changed during read-only verification.")
        }
        try package.validateUnchanged()

        let state: BackupVerificationState
        let lineageIdentifier: String
        if manifest.formatVersion == BackupManifest.currentFormatVersion {
            guard let recordedLineage = manifest.sourceLineageIdentifier,
                  recordedLineage.count == 64 else {
                throw BackupError.verification(
                    "The current-format manifest has no authoritative source lineage."
                )
            }
            let authoritativeLineage: String
            if let expectedLineage {
                authoritativeLineage = expectedLineage
            } else if allowRecordedLineageWithoutCurrentSource {
                authoritativeLineage = recordedLineage
            } else {
                authoritativeLineage = try authoritativeLineageIdentifier(
                    for: package.packageURL,
                    sourceFilename: manifest.sourceDatabaseFilename
                )
            }
            guard recordedLineage == authoritativeLineage else {
                throw BackupError.verification(
                    "The retained package lineage does not match the current authoritative database lineage."
                )
            }
            if let ownershipPolicyDirectory = package.ownershipParent,
               let ownershipPackageName = package.ownershipName {
                try requireGeneratedVisiblePackageOwnership(
                    package,
                    named: ownershipPackageName,
                    in: ownershipPolicyDirectory,
                    lineageIdentifier: recordedLineage
                )
            }
            state = .verified
            lineageIdentifier = recordedLineage
        } else {
            guard manifest.sourceLineageIdentifier == nil else {
                throw BackupError.verification(
                    "The v1 recovery manifest contains ambiguous lineage evidence."
                )
            }
            state = .legacyRecovery
            lineageIdentifier = ""
        }

        let verification = BackupVerification(
            state: state,
            schemaVersion: database.schemaVersion,
            databaseSHA256: database.sha256,
            manifestSHA256: sha256(manifestData),
            artifactNames: after.artifactNames,
            retainedBytesUnchanged: true,
            messages: ["ok"]
        )
        return VerifiedPackage(
            verification: verification,
            fingerprint: after,
            identity: package.identity,
            lineageIdentifier: lineageIdentifier,
            createdAt: manifest.createdAt,
            kind: manifest.kind,
            sourceDatabaseFilename: manifest.sourceDatabaseFilename
        )
    }

    private func authoritativeLineageIdentifier(
        for packageURL: URL,
        sourceFilename: String
    ) throws -> String {
        let policyURL = packageURL.deletingLastPathComponent()
        guard ["rolling", "preflight"].contains(policyURL.lastPathComponent),
              policyURL.deletingLastPathComponent().lastPathComponent == "sqlite",
              policyURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                == "backups" else {
            throw BackupError.verification(
                "The package is outside a recognized policy lineage and is not a current artifact."
            )
        }
        let databaseDirectory = policyURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            return try DatabaseSourceLineageObservation(
                databaseURL: databaseDirectory.appendingPathComponent(sourceFilename)
            ).validate().identifier
        } catch {
            throw BackupError.verification(
                "The current authoritative database lineage could not be established: \(error.localizedDescription)"
            )
        }
    }

    private func recognizedPolicyDirectory(for packageURL: URL) throws -> PinnedDirectory? {
        let policyURL = packageURL.deletingLastPathComponent()
        guard packageURL.pathExtension.lowercased() == packageExtension,
              ["rolling", "preflight"].contains(policyURL.lastPathComponent),
              policyURL.deletingLastPathComponent().lastPathComponent == "sqlite",
              policyURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                == "backups" else { return nil }
        return try existingPolicyDirectory(at: policyURL)
    }

    private func verifyLegacyRawBackup(at url: URL) -> BackupVerification {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            return BackupVerification(
                state: .unusable,
                schemaVersion: nil,
                databaseSHA256: nil,
                manifestSHA256: nil,
                artifactNames: [url.lastPathComponent],
                retainedBytesUnchanged: false,
                messages: ["The raw legacy recovery file could not be pinned."]
            )
        }
        defer { Darwin.close(descriptor) }
        do {
            let beforeIdentity = try PinnedPackage.descriptorIdentity(descriptor)
            guard beforeIdentity.fileType == S_IFREG,
                  try pathIdentity(at: url, requiring: S_IFREG) == beforeIdentity else {
                throw BackupError.verification(
                    "The raw legacy recovery path changed while it was pinned."
                )
            }
            let before = try data(from: descriptor, artifactName: url.lastPathComponent)
            let database = try verifySQLiteDatabase(data: before, descriptor: descriptor)
            let after = try data(from: descriptor, artifactName: url.lastPathComponent)
            guard before == after,
                  try PinnedPackage.descriptorIdentity(descriptor) == beforeIdentity,
                  try pathIdentity(at: url, requiring: S_IFREG) == beforeIdentity else {
                throw BackupError.verification(
                    "The raw legacy recovery file changed during immutable verification."
                )
            }
            return BackupVerification(
                state: .legacyRecovery,
                schemaVersion: database.schemaVersion,
                databaseSHA256: database.sha256,
                manifestSHA256: nil,
                artifactNames: [url.lastPathComponent],
                retainedBytesUnchanged: true,
                messages: ["legacy recovery only; no current source lineage evidence"]
            )
        } catch {
            return BackupVerification(
                state: .unusable,
                schemaVersion: nil,
                databaseSHA256: nil,
                manifestSHA256: nil,
                artifactNames: [url.lastPathComponent],
                retainedBytesUnchanged: true,
                messages: [error.localizedDescription]
            )
        }
    }

    private func verifySQLiteDatabase(at url: URL) throws -> (schemaVersion: Int, byteSize: Int64, sha256: String) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BackupError.verification("The staged database is unreadable: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            throw BackupError.verification("The staged database is empty.")
        }

        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw BackupError.verification("The completed database could not be pinned for physical reopen.")
        }
        defer { Darwin.close(descriptor) }
        return try verifySQLiteDatabase(data: data, descriptor: descriptor)
    }

    private func verifySQLiteDatabase(
        data: Data,
        descriptor: Int32
    ) throws -> (schemaVersion: Int, byteSize: Int64, sha256: String) {
        guard !data.isEmpty else {
            throw BackupError.verification("The staged database is empty.")
        }
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            "file:/dev/fd/\(descriptor)?mode=ro&immutable=1",
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite open error"
            sqlite3_close_v2(handle)
            throw BackupError.verification("The completed database could not be physically reopened: \(message)")
        }
        defer { sqlite3_close_v2(handle) }

        do {
            let integrity = try integrityMessages(handle)
            guard integrity.count == 1,
                  integrity[0].caseInsensitiveCompare("ok") == .orderedSame else {
                throw BackupError.verification(
                    "The physically reopened database is unhealthy: \(integrity.joined(separator: " | "))"
                )
            }
            let schemaVersion = try DatabaseMigrations.currentVersion(on: handle)
            return (schemaVersion, Int64(data.count), sha256(data))
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.verification("Physical integrity/schema verification failed: \(error.localizedDescription)")
        }
    }

    private func integrityMessages(_ handle: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK else {
            throw BackupError.verification(String(cString: sqlite3_errmsg(handle)))
        }
        var messages: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw BackupError.verification(String(cString: sqlite3_errmsg(handle)))
            }
            if let text = sqlite3_column_text(statement, 0) {
                messages.append(String(cString: text))
            }
        }
        return messages
    }

    private func verifiedDatabaseData(
        at backupURL: URL,
        expectedKind: SQLiteBackupInfo.Kind?,
        allowLegacyRecovery: Bool,
        expectedLineage: String? = nil,
        legacyDestinationURL: URL? = nil
    ) throws -> (data: Data, reference: RetainedPathReference) {
        if backupURL.pathExtension.lowercased() == "db" {
            if let legacyDestinationURL,
               !isConservativelyAssociatedLegacyArtifact(
                    backupURL,
                    with: legacyDestinationURL,
                    sourceFilename: nil
               ) {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The raw legacy recovery file has no proven association with the restore destination."]
                )
            }
            let descriptor = Darwin.open(backupURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw RestoreError.missingBackup(backupURL) }
            defer { Darwin.close(descriptor) }
            let beforeIdentity = try PinnedPackage.descriptorIdentity(descriptor)
            let before = try data(from: descriptor, artifactName: backupURL.lastPathComponent)
            let database = try verifySQLiteDatabase(data: before, descriptor: descriptor)
            let after = try data(from: descriptor, artifactName: backupURL.lastPathComponent)
            guard allowLegacyRecovery,
                  !database.sha256.isEmpty,
                  before == after,
                  try PinnedPackage.descriptorIdentity(descriptor) == beforeIdentity,
                  try pathIdentity(at: backupURL, requiring: S_IFREG) == beforeIdentity else {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The raw legacy recovery occupant changed at the final use boundary."]
                )
            }
            guard let reference = RetainedPathReference(
                url: backupURL,
                expectedFile: beforeIdentity,
                expectedSHA256: database.sha256
            ) else {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The raw legacy recovery capability changed before use completed."]
                )
            }
            return (after, reference)
        }

        let policyDirectory = try recognizedPolicyDirectory(for: backupURL)
        let authorityLease = try policyDirectory.map {
            try PolicyLease(policyDirectory: $0, exclusive: false)
        }
        _ = authorityLease
        let package: PinnedPackage
        if let policyDirectory {
            package = try PinnedPackage(
                childNamed: backupURL.lastPathComponent,
                at: backupURL,
                in: policyDirectory,
                requiredNames: [databaseFilename, manifestFilename].sorted(),
                fileManager: fileManager
            )
        } else {
            package = try PinnedPackage(
                packageURL: backupURL,
                requiredNames: [databaseFilename, manifestFilename].sorted(),
                fileManager: fileManager
            )
        }
        let verified = try verifyPinnedPackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage
        )
        if verified.verification.state == .legacyRecovery,
           let legacyDestinationURL,
           !isConservativelyAssociatedLegacyArtifact(
                backupURL,
                with: legacyDestinationURL,
                sourceFilename: verified.sourceDatabaseFilename
           ) {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The v1 legacy recovery package has no proven association with the restore destination."]
            )
        }
        guard verified.verification.isVerified
                || (allowLegacyRecovery && verified.verification.isRecoveryEligible) else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: verified.verification.messages
            )
        }
        let databaseData = try package.data(for: databaseFilename)
        guard try package.fingerprint() == verified.fingerprint else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The package changed at the final database-use boundary."]
            )
        }
        try package.validateUnchanged()
        guard let reference = RetainedPathReference(
            url: backupURL,
            expectedDirectory: verified.identity.directory,
            expectedChildren: verified.identity.childrenByName,
            expectedHashes: verified.fingerprint.contentSHA256ByName
        ) else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The package capability changed before use completed."]
            )
        }
        return (databaseData, reference)
    }

    private func pinRestoreSource(
        at backupURL: URL,
        expectedKind: SQLiteBackupInfo.Kind,
        expectedLineage: String?,
        legacyDestinationURL: URL,
        destinationExists: Bool = true
    ) throws -> RestoreSourceUse {
        if backupURL.pathExtension.lowercased() == "db" {
            guard isConservativelyAssociatedLegacyArtifact(
                backupURL,
                with: legacyDestinationURL,
                sourceFilename: nil,
                requireFilenameAssociation: !destinationExists
            ) else {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The raw legacy recovery file has no proven association with the restore destination."]
                )
            }
            let descriptor = Darwin.open(backupURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw RestoreError.missingBackup(backupURL) }
            do {
                let identity = try PinnedPackage.descriptorIdentity(descriptor)
                guard identity.fileType == S_IFREG,
                      try pathIdentity(at: backupURL, requiring: S_IFREG) == identity else {
                    throw RestoreError.unhealthyBackup(
                        backupURL,
                        messages: ["The raw legacy recovery path changed while it was pinned."]
                    )
                }
                let bytes = try data(from: descriptor, artifactName: backupURL.lastPathComponent)
                let database = try verifySQLiteDatabase(data: bytes, descriptor: descriptor)
                let verification = BackupVerification(
                    state: .legacyRecovery,
                    schemaVersion: database.schemaVersion,
                    databaseSHA256: database.sha256,
                    manifestSHA256: nil,
                    artifactNames: [backupURL.lastPathComponent],
                    retainedBytesUnchanged: true,
                    messages: ["legacy recovery only; conservatively associated with destination policy"]
                )
                return RestoreSourceUse(
                    url: backupURL,
                    storage: .raw(
                        descriptor: descriptor,
                        identity: identity,
                        verification: verification
                    )
                )
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        let policyDirectory = try recognizedPolicyDirectory(for: backupURL)
        let package: PinnedPackage
        if let policyDirectory {
            package = try PinnedPackage(
                childNamed: backupURL.lastPathComponent,
                at: backupURL,
                in: policyDirectory,
                requiredNames: [databaseFilename, manifestFilename].sorted(),
                fileManager: fileManager
            )
        } else {
            package = try PinnedPackage(
                packageURL: backupURL,
                requiredNames: [databaseFilename, manifestFilename].sorted(),
                fileManager: fileManager
            )
        }
        let verified = try verifyPinnedPackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage,
            allowRecordedLineageWithoutCurrentSource: !destinationExists
        )
        if (!destinationExists || verified.verification.state == .legacyRecovery),
           !isConservativelyAssociatedLegacyArtifact(
                backupURL,
                with: legacyDestinationURL,
                sourceFilename: verified.sourceDatabaseFilename,
                requireFilenameAssociation: !destinationExists
           ) {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The recovery package policy and source filename do not match the restore destination."]
            )
        }
        return RestoreSourceUse(
            url: backupURL,
            storage: .package(
                package,
                verified,
                policyDirectory: policyDirectory,
                packageName: policyDirectory == nil ? nil : backupURL.lastPathComponent
            )
        )
    }

    private func replaceLiveDatabaseAtomically(
        at databaseURL: URL,
        with databaseData: Data,
        in databaseParent: PinnedDirectory,
        expectedDestinationLineage: DatabaseSourceLineage,
        beforeMutation: () throws -> Void
    ) throws {
        let destinationObservation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
        guard try destinationObservation.validate() == expectedDestinationLineage else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live database identity changed before atomic replacement."]
            )
        }
        let liveDescriptor = Darwin.openat(
            databaseParent.descriptor,
            databaseURL.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard liveDescriptor >= 0 else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live database could not be pinned for atomic replacement."]
            )
        }
        defer { Darwin.close(liveDescriptor) }
        let liveIdentity = try PinnedPackage.descriptorIdentity(liveDescriptor)
        guard liveIdentity.fileType == S_IFREG,
              try pathIdentity(at: databaseURL, requiring: S_IFREG) == liveIdentity else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live database path changed while it was pinned."]
            )
        }

        let replacementName = ".cid850-restore-\(UUID().uuidString.lowercased()).sqlite"
        let replacementDescriptor = try databaseParent.createExclusiveRegularFile(named: replacementName)
        defer { Darwin.close(replacementDescriptor) }
        do {
            try write(databaseData, to: replacementDescriptor, artifactName: replacementName)
            _ = try verifySQLiteDatabase(data: databaseData, descriptor: replacementDescriptor)
        } catch {
            throw BackupError.verification(
                "The descriptor-bound restore replacement could not be prepared: \(error.localizedDescription)"
            )
        }
        let replacementIdentity = try PinnedPackage.descriptorIdentity(replacementDescriptor)
        guard try destinationObservation.validate() == expectedDestinationLineage,
              try PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: databaseURL.lastPathComponent
              ) == liveIdentity,
              try PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: replacementName
              ) == replacementIdentity else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live or replacement identity changed at the atomic swap boundary."]
            )
        }
        try beforeMutation()
        guard try destinationObservation.validate() == expectedDestinationLineage,
              try PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: databaseURL.lastPathComponent
              ) == liveIdentity,
              try PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: replacementName
              ) == replacementIdentity else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The source or live identities changed immediately before atomic mutation."]
            )
        }

        let quarantinedSidecars = try quarantineLiveSidecars(
            for: databaseURL,
            in: databaseParent
        )

        do {
            try requireOriginalSidecarNamesAbsent(
                for: databaseURL,
                in: databaseParent
            )
        } catch {
            rollbackQuarantinedLiveFiles(quarantinedSidecars, in: databaseParent)
            throw error
        }

        guard renameatx_np(
            databaseParent.descriptor,
            replacementName,
            databaseParent.descriptor,
            databaseURL.lastPathComponent,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            rollbackQuarantinedLiveFiles(quarantinedSidecars, in: databaseParent)
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live database could not be atomically swapped (errno \(errno))."]
            )
        }
        do {
            try requireOriginalSidecarNamesAbsent(
                for: databaseURL,
                in: databaseParent
            )
        } catch {
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                quarantinedSidecars: quarantinedSidecars
            )
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: [rollbackFailureMessage(
                    trigger: "An unexpected SQLite sidecar appeared at the database swap seam; every unexpected occupant was preserved.",
                    outcome: outcome
                )]
            )
        }
        let liveAfter = try PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: databaseURL.lastPathComponent
        )
        let retiredAfter = try PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: replacementName
        )
        guard liveAfter == replacementIdentity, retiredAfter == liveIdentity else {
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                quarantinedSidecars: quarantinedSidecars
            )
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: [rollbackFailureMessage(
                    trigger: "A live-path replacement was selected by the atomic swap; all occupants were preserved.",
                    outcome: outcome
                )]
            )
        }
        guard fsync(databaseParent.descriptor) == 0 else {
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                quarantinedSidecars: quarantinedSidecars
            )
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: [rollbackFailureMessage(
                    trigger: "The atomic restore directory update could not be flushed after the database swap.",
                    outcome: outcome
                )]
            )
        }
        do {
            try requireOriginalSidecarNamesAbsent(
                for: databaseURL,
                in: databaseParent
            )
        } catch {
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                quarantinedSidecars: quarantinedSidecars
            )
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: [rollbackFailureMessage(
                    trigger: "A SQLite sidecar reappeared before restore commit; all sidecar occupants were preserved.",
                    outcome: outcome
                )]
            )
        }
        var retiredStat = stat()
        if fstatat(
            databaseParent.descriptor,
            replacementName,
            &retiredStat,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        FileIdentity(
            device: retiredStat.st_dev,
            inode: retiredStat.st_ino,
            generation: retiredStat.st_gen,
            fileType: retiredStat.st_mode & S_IFMT,
            linkCount: retiredStat.st_nlink,
            byteSize: retiredStat.st_size
        ) == liveIdentity {
            _ = unlinkat(
                databaseParent.descriptor,
                replacementName,
                AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
            )
        }
        for sidecar in quarantinedSidecars {
            var value = stat()
            if fstatat(
                databaseParent.descriptor,
                sidecar.hiddenName,
                &value,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            FileIdentity(
                device: value.st_dev,
                inode: value.st_ino,
                generation: value.st_gen,
                fileType: value.st_mode & S_IFMT,
                linkCount: value.st_nlink,
                byteSize: value.st_size
            ) == sidecar.identity {
                _ = unlinkat(
                    databaseParent.descriptor,
                    sidecar.hiddenName,
                    AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
                )
            }
        }
    }

    private func quarantineLiveSidecars(
        for databaseURL: URL,
        in databaseParent: PinnedDirectory
    ) throws -> [QuarantinedLiveFile] {
        var moved: [QuarantinedLiveFile] = []
        do {
            for suffix in ["-wal", "-shm"] {
                let originalName = databaseURL.lastPathComponent + suffix
                var reachable = stat()
                if fstatat(
                    databaseParent.descriptor,
                    originalName,
                    &reachable,
                    AT_SYMLINK_NOFOLLOW
                ) != 0 {
                    guard errno == ENOENT else {
                        throw RestoreError.unhealthyBackup(
                            databaseURL,
                            messages: ["A live SQLite sidecar could not be inspected safely."]
                        )
                    }
                    continue
                }
                let descriptor = Darwin.openat(
                    databaseParent.descriptor,
                    originalName,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                )
                guard descriptor >= 0 else {
                    throw RestoreError.unhealthyBackup(
                        databaseURL,
                        messages: ["A live SQLite sidecar could not be pinned safely."]
                    )
                }
                var descriptorTransferred = false
                defer {
                    if !descriptorTransferred { Darwin.close(descriptor) }
                }
                let identity = try PinnedPackage.descriptorIdentity(descriptor)
                guard identity.fileType == S_IFREG,
                      identity.linkCount == 1,
                      FileIdentity(
                        device: reachable.st_dev,
                        inode: reachable.st_ino,
                        generation: reachable.st_gen,
                        fileType: reachable.st_mode & S_IFMT,
                        linkCount: reachable.st_nlink,
                        byteSize: reachable.st_size
                      ) == identity else {
                    throw RestoreError.unhealthyBackup(
                        databaseURL,
                        messages: ["A live SQLite sidecar changed before atomic quarantine."]
                    )
                }
                let hiddenName = ".cid850-restore-\(UUID().uuidString.lowercased())\(suffix)"
                let pinned = QuarantinedLiveFile(
                    originalName: originalName,
                    hiddenName: hiddenName,
                    identity: identity,
                    descriptor: descriptor
                )
                descriptorTransferred = true
                guard renameatx_np(
                    databaseParent.descriptor,
                    originalName,
                    databaseParent.descriptor,
                    hiddenName,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    throw RestoreError.unhealthyBackup(
                        databaseURL,
                        messages: ["A live SQLite sidecar could not be atomically quarantined."]
                    )
                }
                var hidden = stat()
                guard fstatat(
                    databaseParent.descriptor,
                    hiddenName,
                    &hidden,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                FileIdentity(
                    device: hidden.st_dev,
                    inode: hidden.st_ino,
                    generation: hidden.st_gen,
                    fileType: hidden.st_mode & S_IFMT,
                    linkCount: hidden.st_nlink,
                    byteSize: hidden.st_size
                ) == identity else {
                    if renameatx_np(
                        databaseParent.descriptor,
                        hiddenName,
                        databaseParent.descriptor,
                        originalName,
                        UInt32(RENAME_EXCL)
                    ) != 0 {
                        throw RestoreError.unhealthyBackup(
                            databaseURL,
                            messages: ["A replacement sidecar was quarantined and safe rollback failed."]
                        )
                    }
                    throw RestoreError.unhealthyBackup(
                        databaseURL,
                        messages: ["A replacement sidecar was quarantined and rolled back."]
                    )
                }
                moved.append(pinned)
            }
            return moved
        } catch {
            rollbackQuarantinedLiveFiles(moved, in: databaseParent)
            throw error
        }
    }

    private func requireOriginalSidecarNamesAbsent(
        for databaseURL: URL,
        in databaseParent: PinnedDirectory
    ) throws {
        try databaseParent.validatePath()
        for suffix in ["-wal", "-shm"] {
            var value = stat()
            let result = fstatat(
                databaseParent.descriptor,
                databaseURL.lastPathComponent + suffix,
                &value,
                AT_SYMLINK_NOFOLLOW
            )
            if result == 0 {
                throw RestoreError.unhealthyBackup(
                    databaseURL,
                    messages: ["An unexpected occupant appeared at the original SQLite \(suffix) name."]
                )
            }
            guard errno == ENOENT else {
                throw RestoreError.unhealthyBackup(
                    databaseURL,
                    messages: ["An original SQLite sidecar name could not be monitored safely."]
                )
            }
        }
        try databaseParent.validatePath()
    }

    @discardableResult
    private func rollbackQuarantinedLiveFiles(
        _ files: [QuarantinedLiveFile],
        in databaseParent: PinnedDirectory
    ) -> Bool {
        for file in files.reversed() {
            guard (try? PinnedPackage.descriptorIdentity(file.descriptor)) == file.identity,
                  (try? PinnedDirectory.childPathIdentity(
                    databaseParent.descriptor,
                    name: file.hiddenName
                  )) == file.identity else { continue }
            var original = stat()
            if fstatat(
                databaseParent.descriptor,
                file.originalName,
                &original,
                AT_SYMLINK_NOFOLLOW
            ) == 0 {
                continue
            }
            guard errno == ENOENT else { continue }
            _ = renameatx_np(
                databaseParent.descriptor,
                file.hiddenName,
                databaseParent.descriptor,
                file.originalName,
                UInt32(RENAME_EXCL)
            )
        }
        return files.allSatisfy { file in
            (try? PinnedPackage.descriptorIdentity(file.descriptor)) == file.identity
                && (try? PinnedDirectory.childPathIdentity(
                    databaseParent.descriptor,
                    name: file.originalName
                )) == file.identity
        }
    }

    private func rollbackDatabaseSwap(
        at databaseURL: URL,
        replacementName: String,
        in databaseParent: PinnedDirectory,
        liveIdentity: FileIdentity,
        replacementIdentity: FileIdentity,
        quarantinedSidecars: [QuarantinedLiveFile]
    ) -> RestoreRollbackOutcome {
        let liveName = databaseURL.lastPathComponent
        let liveBefore = try? PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: liveName
        )
        let replacementBefore = try? PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: replacementName
        )
        if liveBefore == replacementIdentity, replacementBefore == liveIdentity {
            _ = renameatx_np(
                databaseParent.descriptor,
                replacementName,
                databaseParent.descriptor,
                liveName,
                UInt32(RENAME_SWAP)
            )
        }

        let liveAfter = try? PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: liveName
        )
        let replacementAfter = try? PinnedDirectory.childPathIdentity(
            databaseParent.descriptor,
            name: replacementName
        )
        let priorDatabaseLocation: String?
        if liveAfter == liveIdentity {
            priorDatabaseLocation = "live:\(databaseURL.path)"
        } else if replacementAfter == liveIdentity {
            priorDatabaseLocation = "retained:\(databaseParent.url.appendingPathComponent(replacementName).path)"
        } else {
            priorDatabaseLocation = nil
        }
        let replacementLocation: String?
        if replacementAfter == replacementIdentity {
            replacementLocation = databaseParent.url.appendingPathComponent(replacementName).path
        } else if liveAfter == replacementIdentity {
            replacementLocation = databaseURL.path
        } else {
            replacementLocation = nil
        }

        let sidecarsRestored = rollbackQuarantinedLiveFiles(
            quarantinedSidecars,
            in: databaseParent
        )
        let retainedSidecarLocations = quarantinedSidecars.compactMap { file -> String? in
            guard (try? PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: file.hiddenName
            )) == file.identity else { return nil }
            return databaseParent.url.appendingPathComponent(file.hiddenName).path
        }
        let parentFlushed = fsync(databaseParent.descriptor) == 0
        return RestoreRollbackOutcome(
            priorDatabaseLocation: priorDatabaseLocation,
            replacementLocation: replacementLocation,
            sidecarsRestored: sidecarsRestored,
            retainedSidecarLocations: retainedSidecarLocations,
            parentFlushed: parentFlushed
        )
    }

    private func rollbackFailureMessage(
        trigger: String,
        outcome: RestoreRollbackOutcome
    ) -> String {
        var messages = [trigger]
        if outcome.priorCoherentDatabaseRestored,
           let location = outcome.priorDatabaseLocation?.dropFirst("live:".count) {
            messages.append("The prior coherent database was restored at \(location).")
        } else if let location = outcome.priorDatabaseLocation {
            messages.append(
                "The prior database was retained for operator recovery at \(location.replacingOccurrences(of: "retained:", with: "")); a coherent live SQLite set was not claimed."
            )
        } else {
            messages.append(
                "The prior database location could not be proven after identity-checked rollback; every unexpected occupant was preserved."
            )
        }
        if let replacementLocation = outcome.replacementLocation {
            messages.append("The replacement remains retained at \(replacementLocation).")
        }
        if !outcome.retainedSidecarLocations.isEmpty {
            messages.append(
                "Original sidecars retained for operator recovery: \(outcome.retainedSidecarLocations.joined(separator: ", "))."
            )
        }
        if outcome.parentFlushed {
            messages.append("The rollback parent directory was flushed.")
        } else {
            messages.append(
                "The rollback parent-directory flush failed; crash durability is uncertain even though the reported namespace state was identity-checked."
            )
        }
        return messages.joined(separator: " ")
    }

    private func isConservativelyAssociatedLegacyArtifact(
        _ artifactURL: URL,
        with databaseURL: URL,
        sourceFilename: String?,
        requireFilenameAssociation: Bool = false
    ) -> Bool {
        if let sourceFilename, sourceFilename != databaseURL.lastPathComponent {
            return false
        }
        if sourceFilename == nil, requireFilenameAssociation {
            let expectedPrefix = databaseURL.lastPathComponent.lowercased() + "."
            guard artifactURL.lastPathComponent.lowercased().hasPrefix(expectedPrefix) else {
                return false
            }
        }
        let parent = artifactURL.deletingLastPathComponent().standardizedFileURL
        return parent == rollingBackupsDirectory(for: databaseURL).standardizedFileURL
            || parent == preOpenSnapshotsDirectory(for: databaseURL).standardizedFileURL
    }

    private func verifiedDatabaseData(from artifact: QualifiedBackupArtifact) throws -> Data {
        guard let policyDirectory = try recognizedPolicyDirectory(
            for: artifact.policyURL.appendingPathComponent(
                artifact.packageName,
                isDirectory: true
            )
        ) else {
            throw BackupError.verification(
                "The qualified backup no longer belongs to a recognized Cider rolling policy."
            )
        }
        guard QualifiedBackupArtifact.Object(
            device: policyDirectory.identity.device,
            inode: policyDirectory.identity.inode,
            generation: policyDirectory.identity.generation,
            type: policyDirectory.identity.fileType,
            linkCount: 0
        ) == artifact.policy else {
            throw BackupError.verification(
                "The qualified backup policy identity changed before use."
            )
        }
        let lease = try PolicyLease(policyDirectory: policyDirectory, exclusive: false)
        _ = lease
        let packageURL = artifact.policyURL.appendingPathComponent(
            artifact.packageName,
            isDirectory: true
        )
        let package = try PinnedPackage(
            childNamed: artifact.packageName,
            at: packageURL,
            in: policyDirectory,
            requiredNames: [databaseFilename, manifestFilename].sorted(),
            fileManager: fileManager
        )
        let verified = try verifyPinnedPackage(
            package,
            expectedKind: nil,
            expectedLineage: artifact.lineageIdentifier
        )
        guard verified.verification.isVerified,
              verified.fingerprint.contentSHA256ByName == artifact.contentSHA256ByName,
              try qualifiedArtifact(
                policyDirectory: policyDirectory,
                packageName: artifact.packageName,
                package: verified,
                lineageIdentifier: artifact.lineageIdentifier
              ) == artifact else {
            throw BackupError.verification(
                "The qualified backup occupant changed before final use."
            )
        }
        let databaseData = try package.data(for: databaseFilename)
        guard try package.fingerprint() == verified.fingerprint else {
            throw BackupError.verification(
                "The qualified backup occupant changed at the final read boundary."
            )
        }
        try package.validateUnchanged()
        return databaseData
    }

    // MARK: - State, listing, and retention

    private func ownershipLedger(for policyDirectory: PinnedDirectory) throws -> ParentOwnershipLedger {
        let authority = policyDirectory.authorityDirectory
        let authorityIdentity = OwnershipLedgerIdentity(try authority.currentIdentity())
        let size = fgetxattr(
            authority.descriptor,
            ownershipLedgerAttribute,
            nil,
            0,
            0,
            0
        )
        if size < 0 {
            guard errno == ENOATTR else {
                throw BackupError.retentionCapacity(
                    "The parent ownership ledger could not be inspected (errno \(errno))."
                )
            }
            return ParentOwnershipLedger(
                version: ParentOwnershipLedger.currentVersion,
                authority: authorityIdentity,
                entries: []
            )
        }
        guard size > 0, size <= 128 * 1_024 else {
            return ParentOwnershipLedger(
                version: ParentOwnershipLedger.currentVersion,
                authority: authorityIdentity,
                entries: []
            )
        }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { bytes in
            fgetxattr(
                authority.descriptor,
                ownershipLedgerAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard read == size,
              let decoded = try? JSONDecoder().decode(ParentOwnershipLedger.self, from: data),
              decoded.version == ParentOwnershipLedger.currentVersion,
              decoded.authority == authorityIdentity,
              decoded.entries.count <= maximumOwnershipLedgerEntries,
              Set(decoded.entries).count == decoded.entries.count else {
            // Corrupt, copied, or oversized ledgers are never used to adopt an
            // existing package. A later exact creation publishes a fresh ledger.
            return ParentOwnershipLedger(
                version: ParentOwnershipLedger.currentVersion,
                authority: authorityIdentity,
                entries: []
            )
        }
        return decoded
    }

    private func saveOwnershipLedger(
        _ ledger: ParentOwnershipLedger,
        for policyDirectory: PinnedDirectory
    ) throws {
        let authority = policyDirectory.authorityDirectory
        guard ledger.version == ParentOwnershipLedger.currentVersion,
              ledger.authority == OwnershipLedgerIdentity(try authority.currentIdentity()),
              ledger.entries.count <= maximumOwnershipLedgerEntries else {
            throw BackupError.retentionCapacity("The parent ownership ledger update is invalid or unbounded.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ledger)
        let result = data.withUnsafeBytes { bytes in
            fsetxattr(
                authority.descriptor,
                ownershipLedgerAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard result == 0, fsync(authority.descriptor) == 0 else {
            throw BackupError.retentionCapacity(
                "The parent ownership ledger could not be atomically persisted (errno \(errno))."
            )
        }
        let persisted = try ownershipLedger(for: policyDirectory)
        guard persisted == ledger else {
            throw BackupError.retentionCapacity(
                "The parent ownership ledger did not survive exact read-back validation."
            )
        }
    }

    private func ownershipEntry(
        for package: PinnedDirectory,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) -> OwnershipLedgerEntry? {
        guard let nonce = package.ownershipNonce() else { return nil }
        return ownershipEntry(
            packageIdentity: package.identity,
            creationNonce: nonce,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
    }

    private func ownershipEntry(
        packageIdentity: FileIdentity,
        creationNonce: String,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) -> OwnershipLedgerEntry {
        return OwnershipLedgerEntry(
            policy: OwnershipLedgerIdentity(policyDirectory.identity),
            package: OwnershipLedgerIdentity(packageIdentity),
            lineageIdentifier: lineageIdentifier,
            creationNonce: creationNonce
        )
    }

    private func hasLedgerOwnership(
        _ package: PinnedDirectory,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) -> Bool {
        guard package.hasDurableOwnership(),
              let expected = ownershipEntry(
                for: package,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
              ),
              let ledger = try? ownershipLedger(for: policyDirectory) else { return false }
        return ledger.entries.contains(expected)
    }

    private func hasLedgerOwnership(
        _ package: PinnedPackage,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) -> Bool {
        guard package.hasPublicOwnershipMarker(),
              let nonce = package.ownershipNonce(),
              let ledger = try? ownershipLedger(for: policyDirectory) else { return false }
        let expected = ownershipEntry(
            packageIdentity: package.identity.directory,
            creationNonce: nonce,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
        return ledger.entries.contains(expected)
    }

    private func requireGeneratedVisiblePackageOwnership(
        _ package: PinnedPackage,
        named packageName: String,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws {
        guard isGeneratedPackageSlotName(packageName)
                || package.hasPublicOwnershipMarker() else { return }
        guard hasLedgerOwnership(
            package,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        ) else {
            throw BackupError.verification(
                "The generated visible package lacks exact parent ownership ledger continuity. "
                    + "Its pinned bytes remain preserved and are unusable for verification, "
                    + "materialization, export, or restore."
            )
        }
    }

    private func hasAnyLedgerOwnership(
        _ package: PinnedDirectory,
        in policyDirectory: PinnedDirectory
    ) -> Bool {
        guard package.hasDurableOwnership(),
              let nonce = package.ownershipNonce(),
              let ledger = try? ownershipLedger(for: policyDirectory) else { return false }
        let policy = OwnershipLedgerIdentity(policyDirectory.identity)
        let packageIdentity = OwnershipLedgerIdentity(package.identity)
        return ledger.entries.contains {
            $0.policy == policy
                && $0.package == packageIdentity
                && $0.creationNonce == nonce
        }
    }

    private func registerLedgerOwnership(
        _ package: PinnedDirectory,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws {
        guard package.hasDurableOwnership(),
              let entry = ownershipEntry(
                for: package,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
              ) else {
            throw BackupError.retentionCapacity(
                "The package marker and creation nonce are incomplete; ownership was not recorded."
            )
        }
        var ledger = try ownershipLedger(for: policyDirectory)
        ledger.entries = try prunedOwnershipEntries(
            ledger.entries,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
        if !ledger.entries.contains(entry) {
            guard ledger.entries.count < maximumOwnershipLedgerEntries else {
                throw BackupError.retentionCapacity("The bounded parent ownership ledger is full.")
            }
            ledger.entries.append(entry)
        }
        ledger.entries.sort {
            if $0.policy != $1.policy { return $0.policy.inode < $1.policy.inode }
            if $0.package.inode != $1.package.inode { return $0.package.inode < $1.package.inode }
            return $0.creationNonce < $1.creationNonce
        }
        try saveOwnershipLedger(ledger, for: policyDirectory)
    }

    private func unregisterLedgerOwnership(
        _ package: PinnedDirectory,
        from policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws {
        guard let entry = ownershipEntry(
            for: package,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        ) else { return }
        var ledger = try ownershipLedger(for: policyDirectory)
        ledger.entries.removeAll { $0 == entry }
        try saveOwnershipLedger(ledger, for: policyDirectory)
    }

    private func prunedOwnershipEntries(
        _ entries: [OwnershipLedgerEntry],
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws -> [OwnershipLedgerEntry] {
        let policyIdentity = OwnershipLedgerIdentity(policyDirectory.identity)
        var live: Set<OwnershipLedgerEntry> = []
        for name in try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        ) {
            guard let url = try? policyDirectory.childURL(named: name),
                  let directory = try? PinnedDirectory(
                    childNamed: name,
                    at: url,
                    in: policyDirectory,
                    fileManager: fileManager
                  ),
                  let entry = ownershipEntry(
                    for: directory,
                    in: policyDirectory,
                    lineageIdentifier: lineageIdentifier
                  ) else { continue }
            live.insert(entry)
        }
        return entries.filter { entry in
            entry.policy != policyIdentity
                || entry.lineageIdentifier != lineageIdentifier
                || live.contains(entry)
        }
    }

    private func recoverFailedPublicationWorkspace(
        in policyDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        lineageIdentifier: String
    ) throws -> PinnedDirectory? {
        var failed: [(name: String, directory: PinnedDirectory)] = []
        for name in try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        )
            where URL(fileURLWithPath: name).pathExtension == packageExtension {
            let url = try policyDirectory.childURL(named: name)
            guard let directory = try? PinnedDirectory(
                childNamed: name,
                at: url,
                in: policyDirectory,
                fileManager: fileManager
            ) else { continue }
            if hasAnyLedgerOwnership(directory, in: policyDirectory) {
                if hasLedgerOwnership(
                    directory,
                    in: policyDirectory,
                    lineageIdentifier: lineageIdentifier
                ) {
                    let verified = try? verifyPackageWithIdentity(
                        childNamed: name,
                        at: url,
                        in: policyDirectory,
                        expectedKind: kind,
                        expectedLineage: lineageIdentifier
                    )
                    if verified?.verification.isVerified != true {
                        failed.append((name, directory))
                    }
                }
                continue
            }
            if isGeneratedPackageSlotName(name),
               directory.hasPublicOwnershipMarker() {
                throw directory.retainedArtifactError(
                    kind: .retentionCapacity,
                    state: .unusable,
                    detail: "A publicly marked generated package lacks exact parent ownership-ledger continuity. It was preserved without adoption, mutation, rotation, deletion, or ledger registration, and admission stopped before capture."
                )
            }
        }
        guard !failed.isEmpty else { return nil }
        guard failed.count == 1 else {
            throw BackupError.retentionCapacity(
                "Multiple exact failed publications require conservative recovery before another visible artifact can be created."
            )
        }
        return try quarantineFailedPublication(
            failed[0].directory,
            named: failed[0].name,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
    }

    private func quarantineFailedPublication(
        _ failed: PinnedDirectory,
        named failedName: String,
        in policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws -> PinnedDirectory {
        guard hasLedgerOwnership(
            failed,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        ) else {
            throw BackupError.retentionCapacity(
                "The failed publication no longer has exact parent-ledger ownership."
            )
        }
        let quarantineName = ".cid850-failed-publication.staging"
        var existingStat = stat()
        if fstatat(
            policyDirectory.descriptor,
            quarantineName,
            &existingStat,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            let existingURL = try policyDirectory.childURL(named: quarantineName)
            let existing = try PinnedDirectory(
                childNamed: quarantineName,
                at: existingURL,
                in: policyDirectory,
                fileManager: fileManager
            )
            guard hasLedgerOwnership(
                existing,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
            ) else {
                throw BackupError.retentionCapacity(
                    "The bounded failed-publication workspace is occupied by an unknown identity."
                )
            }
            try removeOwnedHiddenPackage(
                existing,
                named: quarantineName,
                from: policyDirectory,
                lineageIdentifier: lineageIdentifier
            )
        } else if errno != ENOENT {
            throw BackupError.retentionCapacity(
                "The bounded failed-publication workspace could not be inspected."
            )
        }
        guard renameatx_np(
            policyDirectory.descriptor,
            failedName,
            policyDirectory.descriptor,
            quarantineName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw BackupError.retentionCapacity(
                "The exact failed publication could not enter bounded quarantine (errno \(errno))."
            )
        }
        let quarantineURL = try policyDirectory.childURL(named: quarantineName)
        let quarantine = try PinnedDirectory(
            childNamed: quarantineName,
            at: quarantineURL,
            in: policyDirectory,
            fileManager: fileManager
        )
        guard quarantine.identity == failed.identity,
              hasLedgerOwnership(
                quarantine,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
              ) else {
            let rolledBack = renameatx_np(
                policyDirectory.descriptor,
                quarantineName,
                policyDirectory.descriptor,
                failedName,
                UInt32(RENAME_EXCL)
            ) == 0
            throw BackupError.retentionCapacity(rolledBack
                ? "A replacement was selected for failed-publication quarantine and was rolled back."
                : "Failed-publication continuity became uncertain; every occupant was preserved.")
        }
        return quarantine
    }

    private func packageTarget(
        in policyDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        sourceLineage: DatabaseSourceLineage,
        slotLimit: Int,
        incomingBytes: Int64,
        reason: String
    ) throws -> PackageTarget {
        guard slotLimit > 0, incomingBytes > 0 else {
            throw BackupError.retentionCapacity(
                "The next logical SQLite image exceeds the hard per-policy byte cap."
            )
        }
        try policyDirectory.validatePath()
        let recoveredWorkspace = try recoverFailedPublicationWorkspace(
            in: policyDirectory,
            kind: kind,
            lineageIdentifier: sourceLineage.identifier
        )
        let policyNames = try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        )
        var reusable: [(name: String, directory: PinnedDirectory)] = []
        if let recoveredWorkspace {
            reusable.append((
                ".cid850-failed-publication.staging",
                recoveredWorkspace
            ))
        }
        for name in policyNames where name.hasPrefix(".cid850-") {
            if name == ".cid850-failed-publication.staging", recoveredWorkspace != nil {
                continue
            }
            let url = try policyDirectory.childURL(named: name)
            guard let candidate = try? PinnedDirectory(
                childNamed: name,
                at: url,
                in: policyDirectory,
                fileManager: fileManager
            ), hasLedgerOwnership(
                candidate,
                in: policyDirectory,
                lineageIdentifier: sourceLineage.identifier
            ), candidate.isReusableGeneratedPackageSlot(
                allowedNames: [databaseFilename, manifestFilename]
            ) else { continue }
            reusable.append((name, candidate))
        }

        let finalIdentifier = UUID().uuidString.lowercased()
        let finalName = "\(timestampString())-\(sanitize(reason))-\(finalIdentifier.prefix(12)).\(packageExtension)"
        let finalURL = policyDirectory.url.appendingPathComponent(finalName, isDirectory: true)
        if let existing = reusable.sorted(by: { $0.name < $1.name }).first {
            try enforceAggregateAdmission(
                in: policyDirectory,
                incomingDatabaseBytes: incomingBytes,
                reusing: existing.directory
            )
            return PackageTarget(
                name: existing.name,
                url: try policyDirectory.childURL(named: existing.name),
                directory: existing.directory,
                isReusedSlot: true,
                finalName: finalName,
                finalURL: finalURL,
                captureByteLimit: incomingBytes
            )
        }

        try enforceAggregateAdmission(
            in: policyDirectory,
            incomingDatabaseBytes: incomingBytes,
            reusing: nil
        )

        let stagingName = ".cid850-stage-\(UUID().uuidString.lowercased()).staging"
        let stagingURL = policyDirectory.url.appendingPathComponent(stagingName, isDirectory: true)
        let staging = try policyDirectory.createExclusiveOwnedDirectory(
            named: stagingName,
            at: stagingURL
        )
        do {
            try registerLedgerOwnership(
                staging,
                in: policyDirectory,
                lineageIdentifier: sourceLineage.identifier
            )
        } catch {
            throw staging.retainedArtifactError(
                kind: .staging,
                state: .failed,
                detail: "The exact created package could not enter the parent ownership ledger: \(error.localizedDescription)"
            )
        }
        return PackageTarget(
            name: stagingName,
            url: stagingURL,
            directory: staging,
            isReusedSlot: false,
            finalName: finalName,
            finalURL: finalURL,
            captureByteLimit: incomingBytes
        )
    }

    private func rotationPlan(
        in policyDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        sourceLineage: DatabaseSourceLineage,
        slotLimit: Int,
        excluding stagingIdentity: FileIdentity
    ) throws -> RotationPlan {
        guard slotLimit > 0 else {
            throw BackupError.retentionCapacity("The rolling slot limit is invalid.")
        }
        try policyDirectory.validatePath()
        var current: [RotationCandidate] = []
        var warnings: [String] = []
        for name in try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        ) {
            let url = try policyDirectory.childURL(named: name)
            guard URL(fileURLWithPath: name).pathExtension == packageExtension else {
                if !name.hasPrefix(".cid850-") {
                    warnings.append("Preserved unowned policy entry \(name); it is not a rotatable Cider slot.")
                }
                continue
            }
            guard let directory = try? PinnedDirectory(
                childNamed: name,
                at: url,
                in: policyDirectory,
                fileManager: fileManager
            ), !directory.identity.isSameNode(as: stagingIdentity), hasLedgerOwnership(
                directory,
                in: policyDirectory,
                lineageIdentifier: sourceLineage.identifier
            ) else {
                warnings.append("Preserved unowned package-shaped entry \(name); it is not a rotatable Cider slot.")
                continue
            }
            guard let package = try? verifyPackageWithIdentity(
                childNamed: name,
                at: url,
                in: policyDirectory,
                expectedKind: kind,
                expectedLineage: sourceLineage.identifier
            ), package.verification.isVerified else {
                warnings.append("Preserved malformed Cider-owned package \(name); it is not safely rotatable.")
                continue
            }
            current.append(RotationCandidate(name: name, package: package))
        }
        current.sort {
            if $0.package.createdAt != $1.package.createdAt {
                return $0.package.createdAt < $1.package.createdAt
            }
            return $0.name < $1.name
        }
        let retirementCount = max(0, current.count + 1 - slotLimit)
        let toRetire = Array(current.prefix(retirementCount))
        try policyDirectory.validatePath()
        return RotationPlan(candidatesToRetire: toRetire, warnings: warnings)
    }

    private func retireOwnedVisiblePackage(
        _ candidate: RotationCandidate,
        from policyDirectory: PinnedDirectory,
        expectedKind: SQLiteBackupInfo.Kind,
        expectedLineage: String
    ) throws {
        let sourceURL = try policyDirectory.childURL(named: candidate.name)
        let source = try PinnedDirectory(
            childNamed: candidate.name,
            at: sourceURL,
            in: policyDirectory,
            fileManager: fileManager
        )
        guard hasLedgerOwnership(
                source,
                in: policyDirectory,
                lineageIdentifier: expectedLineage
              ),
              source.identity.isSameNode(as: candidate.package.identity.directory) else {
            throw BackupError.retentionCapacity(
                "The selected old visible package is no longer the exact Cider-owned slot."
            )
        }
        let reverified = try verifyPackageWithIdentity(
            childNamed: candidate.name,
            at: sourceURL,
            in: policyDirectory,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage
        )
        guard reverified.identity == candidate.package.identity,
              reverified.fingerprint == candidate.package.fingerprint else {
            throw BackupError.retentionCapacity(
                "The selected old visible package changed before retirement."
            )
        }

        let retiredName = ".cid850-retired-\(UUID().uuidString.lowercased()).staging"
        guard renameatx_np(
            policyDirectory.descriptor,
            candidate.name,
            policyDirectory.descriptor,
            retiredName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw BackupError.retentionCapacity(
                "The exact old visible package could not be atomically retired (errno \(errno))."
            )
        }
        let retiredURL = try policyDirectory.childURL(named: retiredName)
        let retired = try PinnedDirectory(
            childNamed: retiredName,
            at: retiredURL,
            in: policyDirectory,
            fileManager: fileManager
        )
        guard hasLedgerOwnership(
                retired,
                in: policyDirectory,
                lineageIdentifier: expectedLineage
              ),
              retired.identity.isSameNode(as: source.identity) else {
            if renameatx_np(
                policyDirectory.descriptor,
                retiredName,
                policyDirectory.descriptor,
                candidate.name,
                UInt32(RENAME_EXCL)
            ) != 0 {
                throw BackupError.retentionCapacity(
                    "A replacement was moved at retirement and could not be rolled back safely."
                )
            }
            throw BackupError.retentionCapacity(
                "A replacement was selected at retirement; it was rolled back without deletion."
            )
        }
        let retiredVerification = try verifyPackageWithIdentity(
            childNamed: retiredName,
            at: retiredURL,
            in: policyDirectory,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage
        )
        guard retiredVerification.identity == candidate.package.identity,
              retiredVerification.fingerprint == candidate.package.fingerprint else {
            throw BackupError.retentionCapacity(
                "The retired hidden package did not preserve the selected verified bytes."
            )
        }
        try removeOwnedHiddenPackage(
            retired,
            named: retiredName,
            from: policyDirectory,
            lineageIdentifier: expectedLineage
        )
    }

    private func removeOwnedHiddenPackage(
        _ package: PinnedDirectory,
        named name: String,
        from policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws {
        guard name.hasPrefix(".cid850-"), hasLedgerOwnership(
            package,
            in: policyDirectory,
            lineageIdentifier: lineageIdentifier
        ) else {
            throw BackupError.staging("An unowned or visible package was never eligible for cleanup.")
        }
        try policyDirectory.validatePath()
        try package.validatePath()
        let names = try package.directoryNames()
        guard Set(names).isSubset(of: [databaseFilename, manifestFilename]) else {
            throw BackupError.staging("The owned hidden package has unexpected members and was preserved.")
        }
        for childName in names {
            let child = Darwin.openat(
                package.descriptor,
                childName,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC
            )
            guard child >= 0 else {
                throw BackupError.staging("A hidden package child could not be pinned for cleanup.")
            }
            let matches: Bool
            do {
                defer { Darwin.close(child) }
                let descriptorIdentity = try PinnedPackage.descriptorIdentity(child)
                var reachable = stat()
                matches = fstatat(
                    package.descriptor,
                    childName,
                    &reachable,
                    AT_SYMLINK_NOFOLLOW
                ) == 0
                    && descriptorIdentity.fileType == S_IFREG
                    && descriptorIdentity.linkCount == 1
                    && FileIdentity(
                        device: reachable.st_dev,
                        inode: reachable.st_ino,
                        generation: reachable.st_gen,
                        fileType: reachable.st_mode & S_IFMT,
                        linkCount: reachable.st_nlink,
                        byteSize: reachable.st_size
                    ) == descriptorIdentity
            }
            guard matches,
                  unlinkat(
                    package.descriptor,
                    childName,
                    AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
                  ) == 0 else {
                throw BackupError.staging(
                    "A hidden package child changed at cleanup and was preserved (errno \(errno))."
                )
            }
        }
        try package.validatePath()
        guard try package.directoryNames().isEmpty,
              fsync(package.descriptor) == 0,
              unlinkat(
                policyDirectory.descriptor,
                name,
                AT_REMOVEDIR | AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
              ) == 0 else {
            throw BackupError.staging(
                "The empty owned hidden package could not be removed safely (errno \(errno))."
            )
        }
        guard fsync(policyDirectory.descriptor) == 0 else {
            throw BackupError.staging(
                "The exact hidden-package namespace rollback could not be flushed (errno \(errno))."
            )
        }
        try unregisterLedgerOwnership(
            package,
            from: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
    }

    private func rollbackOwnedVisiblePublication(
        _ publication: PinnedDirectory,
        named name: String,
        from policyDirectory: PinnedDirectory,
        lineageIdentifier: String
    ) throws {
        guard !name.hasPrefix("."),
              hasLedgerOwnership(
                publication,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
              ) else {
            throw BackupError.retentionCapacity(
                "The newly published package lacks exact ledger ownership for rollback."
            )
        }
        try policyDirectory.validatePath()
        try publication.validatePath()
        let rollbackName = ".cid850-rollback-\(UUID().uuidString.lowercased()).staging"
        guard renameatx_np(
            policyDirectory.descriptor,
            name,
            policyDirectory.descriptor,
            rollbackName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw BackupError.retentionCapacity(
                "The exact publication could not be atomically isolated for rollback (errno \(errno))."
            )
        }
        guard fsync(policyDirectory.descriptor) == 0 else {
            throw BackupError.retentionCapacity(
                "The isolated publication namespace could not be flushed (errno \(errno))."
            )
        }
        let rollbackURL = try policyDirectory.childURL(named: rollbackName)
        let rollback = try PinnedDirectory(
            childNamed: rollbackName,
            at: rollbackURL,
            in: policyDirectory,
            fileManager: fileManager
        )
        guard rollback.identity.isSameNode(as: publication.identity),
              hasLedgerOwnership(
                rollback,
                in: policyDirectory,
                lineageIdentifier: lineageIdentifier
              ) else {
            throw rollback.retainedArtifactError(
                kind: .retentionCapacity,
                state: .failed,
                detail: "The atomically isolated publication did not preserve exact descriptor and ledger identity."
            )
        }
        try removeOwnedHiddenPackage(
            rollback,
            named: rollbackName,
            from: policyDirectory,
            lineageIdentifier: lineageIdentifier
        )
    }

    private func isGeneratedPackageSlotName(_ name: String) -> Bool {
        guard name.hasSuffix(".\(packageExtension)") else { return false }
        let stem = String(name.dropLast(packageExtension.count + 1))
        guard stem.count > 30,
              stem.index(stem.startIndex, offsetBy: 8) < stem.endIndex else { return false }
        let timestamp = String(stem.prefix(16))
        guard timestamp.count == 16,
              timestamp[timestamp.index(timestamp.startIndex, offsetBy: 8)] == "T",
              timestamp.last == "Z",
              timestamp.enumerated().allSatisfy({ offset, character in
                  offset == 8 || offset == 15 || character.isNumber
              }) else { return false }
        let token = stem.suffix(12)
        let prefix = stem.dropLast(12)
        guard prefix.last == "-" else { return false }
        let reason = prefix.dropLast()[stem.index(stem.startIndex, offsetBy: 16)...]
        return reason.first == "-"
            && reason.count > 1
            && token.count == 12
            && token.enumerated().allSatisfy { offset, character in
                if offset == 8 { return character == "-" }
                return character.isHexDigit && !character.isUppercase
            }
    }

    private func isGeneratedHiddenPackageSlotName(_ name: String) -> Bool {
        name == ".cid850-failed-publication.staging"
            || (name.hasPrefix(".cid850-stage-") && name.hasSuffix(".staging"))
            || (name.hasPrefix(".cid850-retired-") && name.hasSuffix(".staging"))
    }

    nonisolated static func checkedRetentionCapacitySum(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        guard lhs >= 0, rhs >= 0 else {
            throw BackupError.retentionCapacity("Retained byte accounting received a negative value.")
        }
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw BackupError.retentionCapacity("Retained byte accounting overflowed Int64.")
        }
        return sum
    }

    private func enforceAggregateAdmission(
        in policyDirectory: PinnedDirectory,
        incomingDatabaseBytes: Int64,
        reusing workspace: PinnedDirectory?
    ) throws {
        guard maximumPolicyBytes > 0, incomingDatabaseBytes > 0 else {
            throw BackupError.retentionCapacity("The aggregate retention byte policy is invalid.")
        }
        let inventory = try aggregatePolicyInventory(
            in: policyDirectory
        )
        let ledgerAdditions = workspace == nil ? 2 : 1
        guard inventory.ledger.entries.count <= maximumOwnershipLedgerEntries - ledgerAdditions else {
            throw BackupError.retentionCapacity(
                "The bounded parent ownership ledger cannot reserve staging and publication entries."
            )
        }
        guard inventory.names.count <= maximumAggregatePolicyEntries - ledgerAdditions else {
            throw BackupError.retentionCapacity(
                "The bounded policy membership cannot reserve staging and publication entries."
            )
        }

        var incomingPackageBytes = try Self.checkedRetentionCapacitySum(
            incomingDatabaseBytes,
            Self.retentionMaximumManifestBytes
        )
        for _ in 0..<3 {
            incomingPackageBytes = try Self.checkedRetentionCapacitySum(
                incomingPackageBytes,
                Self.retentionAccountingNodeOverheadBytes
            )
        }

        let reusedBytes: Int64
        if let workspace {
            guard let owned = inventory.ownedArtifacts.first(where: {
                $0.identity.isSameNode(as: workspace.identity)
            }) else {
                throw BackupError.retentionCapacity(
                    "The selected reusable workspace was not exactly present in aggregate ownership accounting."
                )
            }
            reusedBytes = owned.accountedBytes
        } else {
            reusedBytes = 0
        }
        let workspaceGrowth = max(0, incomingPackageBytes - reusedBytes)
        let reservedGrowth = try Self.checkedRetentionCapacitySum(
            workspaceGrowth,
            incomingPackageBytes
        )
        let projected = try Self.checkedRetentionCapacitySum(
            inventory.accountedBytes,
            reservedGrowth
        )
        guard projected <= maximumPolicyBytes else {
            throw BackupError.retentionCapacity(
                "Counted retained policy bytes \(inventory.accountedBytes) plus bounded staging/publication growth \(reservedGrowth) exceed hard cap \(maximumPolicyBytes); no staging artifact was created or written."
            )
        }
        try policyDirectory.validatePath()
        guard try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        ) == inventory.names else {
            throw BackupError.retentionCapacity(
                "The policy membership changed during aggregate admission; no staging artifact was created or written."
            )
        }
    }

    @discardableResult
    private func enforceExactAggregateCapacity(
        in policyDirectory: PinnedDirectory,
        binding exactPackage: PinnedPackage? = nil
    ) throws -> AggregatePolicyInventory {
        let boundBytes = try exactPackage?.exactAccountedBytes()
        let inventory = try aggregatePolicyInventory(
            in: policyDirectory
        )
        guard inventory.accountedBytes <= maximumPolicyBytes else {
            throw BackupError.retentionCapacity(
                "Exact post-capture aggregate accounting reached \(inventory.accountedBytes) bytes above hard cap \(maximumPolicyBytes)."
            )
        }
        if let exactPackage, let boundBytes {
            guard let accounted = inventory.ownedArtifacts.first(where: {
                $0.identity.isSameNode(as: exactPackage.identity.directory)
            }), accounted.accountedBytes == boundBytes else {
                throw BackupError.retentionCapacity(
                    "The exact verified staged descriptors do not match the cap-accounted package."
                )
            }
            try exactPackage.validateUnchanged()
        }
        return inventory
    }

    private func aggregatePolicyInventory(
        in policyDirectory: PinnedDirectory
    ) throws -> AggregatePolicyInventory {
        try policyDirectory.validatePath()
        let names = try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        )
        let ledger = try ownershipLedger(for: policyDirectory)
        let authority = policyDirectory.authorityDirectory
        let ledgerPayloadSize = fgetxattr(
            authority.descriptor,
            ownershipLedgerAttribute,
            nil,
            0,
            0,
            0
        )
        guard ledgerPayloadSize >= 0 || errno == ENOATTR else {
            throw BackupError.retentionCapacity(
                "The parent ownership ledger payload could not be bounded (errno \(errno))."
            )
        }
        guard Int64(ledgerPayloadSize) <= Self.retentionLedgerPayloadBytes else {
            throw BackupError.retentionCapacity(
                "The parent ownership ledger payload exceeds its bounded accounting reservation."
            )
        }
        var accountedBytes = try Self.checkedRetentionCapacitySum(
            Self.retentionLedgerPayloadBytes,
            Self.retentionLedgerOverheadBytes
        )
        var ownedArtifacts: [AggregateOwnedArtifact] = []
        var remainingNodes = maximumAggregateOwnedNodes
        let policyIdentity = OwnershipLedgerIdentity(policyDirectory.identity)

        for name in names {
            var childStat = stat()
            guard fstatat(
                policyDirectory.descriptor,
                name,
                &childStat,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw BackupError.retentionCapacity(
                    "A policy child changed during bounded aggregate accounting."
                )
            }
            guard childStat.st_mode & S_IFMT == S_IFDIR else {
                if isGeneratedHiddenPackageSlotName(name)
                    || URL(fileURLWithPath: name).pathExtension == packageExtension {
                    throw BackupError.retentionCapacity(
                        "A policy-shaped retained entry is not a directory; it was preserved and admission stopped."
                    )
                }
                continue
            }
            let childURL = try policyDirectory.childURL(named: name)
            guard let directory = try? PinnedDirectory(
                childNamed: name,
                at: childURL,
                in: policyDirectory,
                fileManager: fileManager
            ) else {
                throw BackupError.retentionCapacity(
                    "A retained policy directory could not be pinned for bounded accounting."
                )
            }
            guard directory.hasDurableOwnership(),
                  let nonce = directory.ownershipNonce() else {
                if isGeneratedHiddenPackageSlotName(name) {
                    throw BackupError.retentionCapacity(
                        "An exact retained Cider workspace lacks complete ownership proof; it was preserved and admission stopped."
                    )
                }
                continue
            }
            let packageIdentity = OwnershipLedgerIdentity(directory.identity)
            let ledgerOwned = ledger.entries.contains {
                $0.policy == policyIdentity
                    && $0.package == packageIdentity
                    && $0.creationNonce == nonce
            }
            guard ledgerOwned else {
                if isGeneratedHiddenPackageSlotName(name)
                    || (isGeneratedPackageSlotName(name) && directory.hasPublicOwnershipMarker()) {
                    throw BackupError.retentionCapacity(
                        "A policy-owned-looking retained package lacks exact ledger continuity; it was preserved and admission stopped."
                    )
                }
                continue
            }
            let artifactBytes = try retainedByteCount(
                descriptor: directory.descriptor,
                observedIdentity: directory.identity,
                remainingNodes: &remainingNodes,
                depth: 0
            )
            guard try directory.currentIdentity() == directory.identity,
                  try PinnedDirectory.childPathIdentity(
                    policyDirectory.descriptor,
                    name: name
                  ) == directory.identity else {
                throw BackupError.retentionCapacity(
                    "A retained policy directory changed during bounded aggregate accounting."
                )
            }
            accountedBytes = try Self.checkedRetentionCapacitySum(accountedBytes, artifactBytes)
            ownedArtifacts.append(AggregateOwnedArtifact(
                identity: directory.identity,
                accountedBytes: artifactBytes
            ))
        }
        try policyDirectory.validatePath()
        guard try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        ) == names else {
            throw BackupError.retentionCapacity(
                "The policy membership changed during bounded aggregate accounting."
            )
        }
        return AggregatePolicyInventory(
            names: names,
            ledger: ledger,
            ownedArtifacts: ownedArtifacts,
            accountedBytes: accountedBytes
        )
    }

    private func boundedDirectoryNames(
        descriptor: Int32,
        maximumEntries: Int
    ) throws -> [String] {
        guard maximumEntries > 0 else {
            throw BackupError.retentionCapacity("The aggregate directory-entry bound is invalid.")
        }
        let duplicated = dup(descriptor)
        guard duplicated >= 0, let directory = fdopendir(duplicated) else {
            if duplicated >= 0 { Darwin.close(duplicated) }
            throw BackupError.retentionCapacity("A retained directory could not be enumerated.")
        }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard names.count < maximumEntries else {
                throw BackupError.retentionCapacity(
                    "The retained policy exceeds the bounded aggregate entry count."
                )
            }
            names.append(name)
        }
        return names.sorted()
    }

    private func retainedByteCount(
        descriptor: Int32,
        observedIdentity: FileIdentity,
        remainingNodes: inout Int,
        depth: Int
    ) throws -> Int64 {
        guard remainingNodes > 0, depth <= maximumAggregateTraversalDepth else {
            throw BackupError.retentionCapacity(
                "A retained artifact exceeds bounded aggregate traversal."
            )
        }
        remainingNodes -= 1
        var value = stat()
        guard fstat(descriptor, &value) == 0 else {
            throw BackupError.retentionCapacity("A retained artifact identity could not be inspected.")
        }
        let initialIdentity = FileIdentity(
            device: value.st_dev,
            inode: value.st_ino,
            generation: value.st_gen,
            fileType: value.st_mode & S_IFMT,
            linkCount: value.st_nlink,
            byteSize: value.st_size
        )
        guard initialIdentity == observedIdentity else {
            throw BackupError.retentionCapacity(
                "A retained artifact changed between parent-relative observation and descriptor accounting."
            )
        }
        let type = initialIdentity.fileType
        if type == S_IFREG {
            guard initialIdentity.linkCount == 1, initialIdentity.byteSize >= 0 else {
                throw BackupError.retentionCapacity(
                    "A retained regular file is hard-linked or has an invalid size."
                )
            }
            let accounted = try Self.checkedRetentionCapacitySum(
                Int64(initialIdentity.byteSize),
                Self.retentionAccountingNodeOverheadBytes
            )
            var finalValue = stat()
            guard fstat(descriptor, &finalValue) == 0,
                  FileIdentity(
                    device: finalValue.st_dev,
                    inode: finalValue.st_ino,
                    generation: finalValue.st_gen,
                    fileType: finalValue.st_mode & S_IFMT,
                    linkCount: finalValue.st_nlink,
                    byteSize: finalValue.st_size
                  ) == initialIdentity else {
                throw BackupError.retentionCapacity(
                    "A retained regular file grew, shrank, was linked, or changed during accounting."
                )
            }
            return accounted
        }
        guard type == S_IFDIR else {
            throw BackupError.retentionCapacity(
                "A retained policy entry is neither a regular file nor a directory."
            )
        }
        let names = try boundedDirectoryNames(
            descriptor: descriptor,
            maximumEntries: maximumAggregateOwnedNodes
        )
        var total = Self.retentionAccountingNodeOverheadBytes
        for name in names {
            var observed = stat()
            guard fstatat(descriptor, name, &observed, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackupError.retentionCapacity(
                    "A retained child disappeared before descriptor-relative accounting."
                )
            }
            let childIdentity = FileIdentity(
                device: observed.st_dev,
                inode: observed.st_ino,
                generation: observed.st_gen,
                fileType: observed.st_mode & S_IFMT,
                linkCount: observed.st_nlink,
                byteSize: observed.st_size
            )
            guard childIdentity.fileType == S_IFREG || childIdentity.fileType == S_IFDIR else {
                throw BackupError.retentionCapacity(
                    "A retained child is a symlink or special entry."
                )
            }
            let child = Darwin.openat(
                descriptor,
                name,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
                    | (childIdentity.fileType == S_IFDIR ? O_DIRECTORY : 0)
            )
            guard child >= 0 else {
                throw BackupError.retentionCapacity("A retained child changed during byte accounting.")
            }
            let childBytes: Int64
            do {
                defer { Darwin.close(child) }
                var opened = stat()
                guard fstat(child, &opened) == 0,
                      FileIdentity(
                        device: opened.st_dev,
                        inode: opened.st_ino,
                        generation: opened.st_gen,
                        fileType: opened.st_mode & S_IFMT,
                        linkCount: opened.st_nlink,
                        byteSize: opened.st_size
                      ) == childIdentity else {
                    throw BackupError.retentionCapacity(
                        "A retained child changed identity, type, link count, or size during open."
                    )
                }
                childBytes = try retainedByteCount(
                    descriptor: child,
                    observedIdentity: childIdentity,
                    remainingNodes: &remainingNodes,
                    depth: depth + 1
                )
                var finalDescriptorStat = stat()
                var finalPathStat = stat()
                guard fstat(child, &finalDescriptorStat) == 0,
                      fstatat(
                        descriptor,
                        name,
                        &finalPathStat,
                        AT_SYMLINK_NOFOLLOW
                      ) == 0,
                      FileIdentity(
                        device: finalDescriptorStat.st_dev,
                        inode: finalDescriptorStat.st_ino,
                        generation: finalDescriptorStat.st_gen,
                        fileType: finalDescriptorStat.st_mode & S_IFMT,
                        linkCount: finalDescriptorStat.st_nlink,
                        byteSize: finalDescriptorStat.st_size
                      ) == childIdentity,
                      FileIdentity(
                        device: finalPathStat.st_dev,
                        inode: finalPathStat.st_ino,
                        generation: finalPathStat.st_gen,
                        fileType: finalPathStat.st_mode & S_IFMT,
                        linkCount: finalPathStat.st_nlink,
                        byteSize: finalPathStat.st_size
                      ) == childIdentity else {
                    throw BackupError.retentionCapacity(
                        "A retained child grew, shrank, disappeared, was linked, or was replaced during accounting."
                    )
                }
            }
            total = try Self.checkedRetentionCapacitySum(total, childBytes)
        }
        guard try boundedDirectoryNames(
            descriptor: descriptor,
            maximumEntries: maximumAggregateOwnedNodes
        ) == names else {
            throw BackupError.retentionCapacity(
                "A retained directory changed during bounded byte accounting."
            )
        }
        var finalDirectoryStat = stat()
        guard fstat(descriptor, &finalDirectoryStat) == 0,
              FileIdentity(
                device: finalDirectoryStat.st_dev,
                inode: finalDirectoryStat.st_ino,
                generation: finalDirectoryStat.st_gen,
                fileType: finalDirectoryStat.st_mode & S_IFMT,
                linkCount: finalDirectoryStat.st_nlink,
                byteSize: finalDirectoryStat.st_size
              ) == initialIdentity else {
            throw BackupError.retentionCapacity(
                "A retained directory identity, type, link count, or metadata changed during accounting."
            )
        }
        return total
    }

    private func loadState(for databaseURL: URL) throws -> SafetyState {
        let stateURL = stateFileURL(for: databaseURL)
        guard fileManager.fileExists(atPath: stateURL.path) else { return SafetyState() }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(SafetyState.self, from: data)
    }

    private func saveState(_ state: SafetyState, for databaseURL: URL) throws {
        let root = backupsRootDirectory(for: databaseURL)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL(for: databaseURL), options: .atomic)
    }

    private func pruneVerifiedBackups(
        in policyDirectory: PinnedDirectory,
        kind: SQLiteBackupInfo.Kind,
        keep count: Int
    ) throws -> [String] {
        guard count > 0 else { return [] }
        try policyDirectory.observeAndValidatePath()

        var verified: [(name: String, package: VerifiedPackage)] = []
        for name in try boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        )
            where URL(fileURLWithPath: name).pathExtension == packageExtension {
            let packageURL = try policyDirectory.childURL(named: name)
            guard let package = try? verifyPackageWithIdentity(
                childNamed: name,
                at: packageURL,
                in: policyDirectory,
                expectedKind: kind
            ), package.verification.isVerified else { continue }
            verified.append((name, package))
        }
        verified.sort { $0.name > $1.name }

        var warnings: [String] = []
        for candidate in verified.dropFirst(count) {
            do {
                let classified = try verifyPackageWithIdentity(
                    childNamed: candidate.name,
                    at: try policyDirectory.childURL(named: candidate.name),
                    in: policyDirectory,
                    expectedKind: kind
                )
                guard classified.identity == candidate.package.identity,
                      classified.fingerprint == candidate.package.fingerprint else {
                    warnings.append("Preserved changed retention candidate \(candidate.name).")
                    continue
                }
                warnings.append(
                    "Preserved verified excess backup \(candidate.name); macOS has no inode-bound directory rename or unlink."
                )
            } catch {
                warnings.append("Could not prune \(candidate.name): \(error.localizedDescription)")
            }
        }
        try policyDirectory.validatePath()
        return warnings
    }

    private func listBackups(
        in directoryURL: URL,
        kind: SQLiteBackupInfo.Kind?
    ) -> [SQLiteBackupInfo] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let policyDirectory = try? existingPolicyDirectory(at: directoryURL)
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard url.pathExtension == packageExtension || url.pathExtension == "db" else { return nil }
            let inferredKind = kind ?? ((try? manifest(at: url).kind) ?? .rolling)
            return try? backupInfo(
                for: url,
                kind: inferredKind,
                policyDirectory: policyDirectory
            )
        }
        .sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
    }

    private func existingPolicyDirectory(at directoryURL: URL) throws -> PinnedDirectory {
        let databaseDirectoryURL = directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var directory = try PinnedDirectory(url: databaseDirectoryURL, fileManager: fileManager)
        let relativeComponents = directoryURL.standardizedFileURL.pathComponents
            .dropFirst(databaseDirectoryURL.standardizedFileURL.pathComponents.count)
        for component in relativeComponents {
            let childURL = directory.url.appendingPathComponent(component, isDirectory: true)
            directory = try directory.openExistingDirectory(named: component, at: childURL)
        }
        guard directory.url.standardizedFileURL == directoryURL.standardizedFileURL else {
            throw BackupError.verification("The visible backup policy resolved to an unexpected path.")
        }
        return directory
    }

    private func backupInfo(
        for url: URL,
        kind: SQLiteBackupInfo.Kind,
        policyDirectory: PinnedDirectory?
    ) throws -> SQLiteBackupInfo {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        _ = policyDirectory
        let verification = verifyBackup(at: url)
        let createdAt = (try? manifest(at: url).createdAt)
            ?? values.contentModificationDate
            ?? values.creationDate
            ?? .distantPast
        return SQLiteBackupInfo(
            kind: kind,
            url: url,
            createdAt: createdAt,
            byteSize: (try? folderSize(at: url)) ?? 0,
            verification: verification
        )
    }

    private func manifest(at packageURL: URL) throws -> BackupManifest {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(manifestFilename))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(BackupManifest.self, from: data)
    }

    private func folderSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let fileValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard fileValues.isRegularFile == true else { continue }
            total += Int64(fileValues.fileSize ?? 0)
        }
        return total
    }

    private func removeDatabaseArtifacts(at databaseURL: URL) throws {
        let paths = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]

        for url in paths where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func pathIdentity(at url: URL, requiring fileType: mode_t) throws -> FileIdentity {
        var value = stat()
        guard lstat(url.path, &value) == 0,
              value.st_mode & S_IFMT == fileType else {
            throw BackupError.verification("The filesystem object identity at \(url.lastPathComponent) is unavailable or has the wrong type.")
        }
        return FileIdentity(
            device: value.st_dev,
            inode: value.st_ino,
            generation: value.st_gen,
            fileType: value.st_mode & S_IFMT,
            linkCount: value.st_nlink,
            byteSize: value.st_size
        )
    }

    private func backupDatabaseURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(databaseFilename)
    }

    private func artifactNames(at packageURL: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(at: packageURL, includingPropertiesForKeys: nil)) ?? [])
            .map(\.lastPathComponent)
            .sorted()
    }

    private func shouldRun(lastRunAt: Date?, minimumInterval: TimeInterval) -> Bool {
        guard let lastRunAt else { return true }
        return Date().timeIntervalSince(lastRunAt) >= minimumInterval
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    private func sanitize(_ reason: String) -> String {
        let invalid = CharacterSet.alphanumerics.inverted
        let cleaned = reason
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return cleaned.isEmpty ? "backup" : cleaned
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func data(from descriptor: Int32, artifactName: String) throws -> Data {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw BackupError.verification("The pinned \(artifactName) descriptor could not be rewound.")
        }
        do {
            return try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
        } catch {
            throw BackupError.verification(
                "The pinned \(artifactName) descriptor could not be read: \(error.localizedDescription)"
            )
        }
    }

    private func write(_ data: Data, to descriptor: Int32, artifactName: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    throw BackupError.staging(
                        "The pinned \(artifactName) descriptor could not be written (errno \(errno))."
                    )
                }
                offset += result
            }
        }
        guard fsync(descriptor) == 0 else {
            throw BackupError.staging(
                "The pinned \(artifactName) descriptor could not be flushed (errno \(errno))."
            )
        }
    }

    private func immutableURI(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = "file"
        components.queryItems = [
            URLQueryItem(name: "mode", value: "ro"),
            URLQueryItem(name: "immutable", value: "1"),
        ]
        return components.string ?? "file:\(url.path)?mode=ro&immutable=1"
    }
}
