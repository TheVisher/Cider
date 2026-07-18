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

    /// Opens an unknown child without ever waiting for a FIFO peer, then lets
    /// the acquired descriptor's type decide whether any caller may read it.
    /// Path metadata is deliberately not authoritative because the child can
    /// be replaced between lookup and descriptor acquisition.
    nonisolated static func openPinnedRegularChildNonBlocking(
        directoryDescriptor: Int32,
        name: String,
        accessMode: Int32 = O_RDONLY
    ) -> Int32 {
        let descriptor = Darwin.openat(
            directoryDescriptor,
            name,
            accessMode | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { return -1 }
        var value = stat()
        guard fstat(descriptor, &value) == 0,
              value.st_mode & S_IFMT == S_IFREG else {
            let inspectionError = errno == 0 ? EFTYPE : errno
            Darwin.close(descriptor)
            errno = inspectionError
            return -1
        }
        return descriptor
    }

    nonisolated static func readBoundedDescriptor(
        _ descriptor: Int32,
        maximumBytes: Int64,
        artifactName: String
    ) throws -> Data {
        var before = stat()
        guard maximumBytes >= 0,
              fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0,
              before.st_size <= maximumBytes,
              before.st_size <= Int64(Int.max) else {
            throw BackupError.verification(
                "The pinned \(artifactName) descriptor exceeds its bounded read contract."
            )
        }
        var result = Data(count: Int(before.st_size))
        var offset = 0
        while offset < result.count {
            let count = result.withUnsafeMutableBytes { bytes in
                pread(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset,
                    off_t(offset)
                )
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw BackupError.verification(
                    "The pinned \(artifactName) descriptor became unreadable during its bounded read."
                )
            }
            offset += count
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_gen == after.st_gen,
              before.st_mode == after.st_mode,
              before.st_nlink == after.st_nlink,
              before.st_size == after.st_size else {
            throw BackupError.verification(
                "The pinned \(artifactName) descriptor changed during its bounded read."
            )
        }
        return result
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
            let byteSize: off_t
            let modifiedSeconds: Int64
            let modifiedNanoseconds: Int64
            let changedSeconds: Int64
            let changedNanoseconds: Int64
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
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard policyDescriptor >= 0 else { return nil }
            defer { Darwin.close(policyDescriptor) }
            guard Self.object(for: policyDescriptor) == policy else { return nil }
            let packageDescriptor = Darwin.openat(
                policyDescriptor,
                packageName,
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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
                let descriptor = DatabaseSafetyService.openPinnedRegularChildNonBlocking(
                    directoryDescriptor: packageDescriptor,
                    name: name
                )
                guard descriptor >= 0 else { return nil }
                defer { Darwin.close(descriptor) }
                let maximumBytes = name == "manifest.json"
                    ? min(expected.byteSize, DatabaseSafetyService.retentionMaximumManifestBytes)
                    : expected.byteSize
                guard maximumBytes >= 0,
                      Self.object(for: descriptor) == expected,
                      let expectedHash = contentSHA256ByName[name],
                      let data = try? DatabaseSafetyService.readBoundedDescriptor(
                        descriptor,
                        maximumBytes: Int64(maximumBytes),
                        artifactName: name
                      ),
                      Self.object(for: descriptor) == expected,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
                        == expectedHash,
                      fstatat(packageDescriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      Self.object(from: value) == expected else { return nil }
            }
            guard (try? RetainedPathReference.directoryNames(packageDescriptor))
                    == childrenByName.keys.sorted(),
                  Self.object(for: packageDescriptor) == package,
                  Self.object(for: policyDescriptor) == policy else { return nil }
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
                linkCount: value.st_mode & S_IFMT == S_IFDIR ? 0 : value.st_nlink,
                byteSize: value.st_mode & S_IFMT == S_IFDIR ? 0 : value.st_size,
                modifiedSeconds: value.st_mode & S_IFMT == S_IFDIR
                    ? 0 : Int64(value.st_mtimespec.tv_sec),
                modifiedNanoseconds: value.st_mode & S_IFMT == S_IFDIR
                    ? 0 : Int64(value.st_mtimespec.tv_nsec),
                changedSeconds: value.st_mode & S_IFMT == S_IFDIR
                    ? 0 : Int64(value.st_ctimespec.tv_sec),
                changedNanoseconds: value.st_mode & S_IFMT == S_IFDIR
                    ? 0 : Int64(value.st_ctimespec.tv_nsec)
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
        case recoveredFailure(String)
        case recoveryRequired(String, artifactURL: URL?)

        var requiresRecovery: Bool {
            if case .recoveryRequired = self { return true }
            return false
        }

        var retainedRecoveryArtifactURL: URL? {
            guard case .recoveryRequired(_, let artifactURL) = self else { return nil }
            return artifactURL
        }

        var errorDescription: String? {
            switch self {
            case .missingBackup(let url):
                return "Backup not found at \(url.path)."
            case .unhealthyBackup(let url, let messages):
                let detail = messages.isEmpty ? "unknown integrity failure" : messages.joined(separator: " | ")
                return "Backup at \(url.path) failed integrity check: \(detail)"
            case .recoveredFailure(let detail):
                return "Database restore failed and the exact original SQLite set was restored and reopened: \(detail)"
            case .recoveryRequired(let detail, let artifactURL):
                let retained = artifactURL.map {
                    " A preserved artifact was observed at \($0.path); this path is evidence only unless it remains listed and verified by the supported restore selector policy."
                } ?? ""
                return "Database restore is indeterminate and requires recovery: \(detail)\(retained)"
            }
        }
    }

    struct RestoreResult: Equatable {
        let restoredBackup: SQLiteBackupInfo
        let preRestoreSnapshotURL: URL?
        let terminalEvidenceInventory: RestoreEvidenceInventory?
        private let sourceReference: RetainedPathReference
        private let sourceDatabaseURL: URL?
        private let requiresCurrentV2Eligibility: Bool
        private let sourceCapabilityData: Data?

        @MainActor
        var sourceBackupURL: URL? {
            guard let current = sourceReference.currentURL() else { return nil }
            guard requiresCurrentV2Eligibility, let sourceDatabaseURL else { return current }
            let service = DatabaseSafetyService()
            guard let sourceCapabilityData else { return nil }
            return service.restoreReceiptSourceURL(
                current,
                expectedCapabilityData: sourceCapabilityData,
                databaseURL: sourceDatabaseURL
            )
        }

        fileprivate init(
            restoredBackup: SQLiteBackupInfo,
            preRestoreSnapshotURL: URL?,
            sourceReference: RetainedPathReference,
            sourceDatabaseURL: URL? = nil,
            requiresCurrentV2Eligibility: Bool = false,
            sourceCapabilityData: Data? = nil,
            terminalEvidenceInventory: RestoreEvidenceInventory? = nil
        ) {
            self.restoredBackup = restoredBackup
            self.preRestoreSnapshotURL = preRestoreSnapshotURL
            self.sourceReference = sourceReference
            self.sourceDatabaseURL = sourceDatabaseURL
            self.requiresCurrentV2Eligibility = requiresCurrentV2Eligibility
            self.sourceCapabilityData = sourceCapabilityData
            self.terminalEvidenceInventory = terminalEvidenceInventory
        }
    }

    enum RestoreEvidenceMemberStatus: String, Equatable {
        case presentQualified = "present-qualified"
        case absent
        case mutated
        case reoccupied
        case specialUnknownOccupant = "special-or-unknown-occupant"
    }

    struct RestoreEvidenceIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt32
    }

    struct RestoreEvidenceMember: Equatable {
        let role: String
        let basename: String
        let policyRelativeLocator: String
        let type: String
        let identity: RestoreEvidenceIdentity?
        let byteCount: Int64?
        let digest: String?
        let status: RestoreEvidenceMemberStatus
        let expectedTerminalMember: Bool
        let safeToRemoveOutOfBand: Bool
    }

    struct RestoreEvidenceInventory: Equatable {
        let policyRootPath: String
        let policyRootIdentity: RestoreEvidenceIdentity
        let transactionID: String?
        let recordSHA256: String?
        let recordPresent: Bool
        let recordPhase: String?
        let recordOutcome: String?
        let state: String
        let recoveryRequired: Bool
        let members: [RestoreEvidenceMember]
        let procedure: [String]
    }

    enum RestoreReconciliationState: String, Equatable {
        case none
        case rolledBack
        case completedCommit
    }

    struct RestoreReconciliationResult: Equatable {
        let state: RestoreReconciliationState
        let recoveryArtifactURL: URL?
        let terminalEvidenceInventory: RestoreEvidenceInventory?

        init(
            state: RestoreReconciliationState,
            recoveryArtifactURL: URL?,
            terminalEvidenceInventory: RestoreEvidenceInventory? = nil
        ) {
            self.state = state
            self.recoveryArtifactURL = recoveryArtifactURL
            self.terminalEvidenceInventory = terminalEvidenceInventory
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

        init(device: UInt64, inode: UInt64, generation: UInt32) {
            self.device = device
            self.inode = inode
            self.generation = generation
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
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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
        enum MembershipObservation {
            case pathAndDescriptor
            case descriptorOnly
        }

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
            let parent = try PinnedDirectory(
                url: packageURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            let directoryDescriptor = Darwin.openat(
                parent.descriptor,
                packageURL.lastPathComponent,
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard directoryDescriptor >= 0 else {
                throw BackupError.verification(
                    "The backup package directory could not be pinned relative to its parent."
                )
            }
            try self.init(
                packageURL: packageURL,
                requiredNames: requiredNames,
                fileManager: fileManager,
                directoryDescriptor: directoryDescriptor,
                relativeParent: parent,
                relativeName: packageURL.lastPathComponent,
                membershipObservation: .pathAndDescriptor
            )
        }

        convenience init(
            childNamed name: String,
            at packageURL: URL,
            in parent: PinnedDirectory,
            requiredNames: [String],
            fileManager: FileManager,
            membershipObservation: MembershipObservation = .pathAndDescriptor
        ) throws {
            let directoryDescriptor = Darwin.openat(
                parent.descriptor,
                name,
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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
                relativeName: name,
                membershipObservation: membershipObservation
            )
        }

        private init(
            packageURL: URL,
            requiredNames: [String],
            fileManager: FileManager,
            directoryDescriptor: Int32,
            relativeParent: PinnedDirectory?,
            relativeName: String?,
            membershipObservation: MembershipObservation
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
                    switch membershipObservation {
                    case .pathAndDescriptor:
                        observedNames = try fileManager.contentsOfDirectory(
                            at: packageURL,
                            includingPropertiesForKeys: nil,
                            options: []
                        ).map(\.lastPathComponent).sorted()
                    case .descriptorOnly:
                        observedNames = try Self.names(in: directoryDescriptor)
                    }
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
                        let descriptor = DatabaseSafetyService.openPinnedRegularChildNonBlocking(
                            directoryDescriptor: directoryDescriptor,
                            name: name
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

        func data(for name: String, maximumBytes: Int64) throws -> Data {
            guard let descriptor = descriptorsByName[name], maximumBytes >= 0 else {
                throw BackupError.verification("The pinned backup artifact \(name) became unreadable.")
            }
            guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
                throw BackupError.verification(
                    "The pinned backup artifact \(name) could not enter its bounded read."
                )
            }
            var before = stat()
            guard fstat(descriptor, &before) == 0,
                  before.st_mode & S_IFMT == S_IFREG,
                  before.st_size >= 0,
                  before.st_size <= maximumBytes,
                  before.st_size <= Int64(Int.max) else {
                throw BackupError.verification(
                    "The pinned backup artifact \(name) exceeds its bounded read contract."
                )
            }
            var result = Data(count: Int(before.st_size))
            var offset = 0
            while offset < result.count {
                let count = result.withUnsafeMutableBytes { bytes in
                    pread(
                        descriptor,
                        bytes.baseAddress?.advanced(by: offset),
                        bytes.count - offset,
                        off_t(offset)
                    )
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw BackupError.verification(
                        "The pinned backup artifact \(name) became unreadable during its bounded read."
                    )
                }
                offset += count
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0,
                  before.st_dev == after.st_dev,
                  before.st_ino == after.st_ino,
                  before.st_gen == after.st_gen,
                  before.st_mode == after.st_mode,
                  before.st_nlink == after.st_nlink,
                  before.st_size == after.st_size else {
                throw BackupError.verification(
                    "The pinned backup artifact \(name) changed during its bounded read."
                )
            }
            return result
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
                guard let expected = identity.childrenByName[name] else {
                    throw BackupError.verification(
                        "The pinned backup artifact \(name) lost its recorded identity."
                    )
                }
                hashes[name] = SHA256.hash(
                    data: try data(for: name, maximumBytes: Int64(expected.byteSize))
                )
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
                packageName: String?,
                authorityLease: PolicyLease?
            )
            case raw(
                parent: PinnedDirectory,
                descriptor: Int32,
                identity: FileIdentity,
                verification: BackupVerification
            )
        }

        let url: URL
        let storage: Storage

        init(url: URL, storage: Storage) {
            self.url = url
            self.storage = storage
        }

        deinit {
            if case .raw(_, let descriptor, _, _) = storage {
                Darwin.close(descriptor)
            }
        }

        var verification: BackupVerification {
            switch storage {
            case .package(_, let package, _, _, _): package.verification
            case .raw(_, _, _, let verification): verification
            }
        }

        var createdAt: Date {
            switch storage {
            case .package(_, let package, _, _, _): package.createdAt
            case .raw: .distantPast
            }
        }

        var kind: SQLiteBackupInfo.Kind {
            switch storage {
            case .package(_, let package, _, _, _): package.kind
            case .raw: .rolling
            }
        }

        @MainActor
        func metadataSnapshot(
            service: DatabaseSafetyService
        ) throws -> (createdAt: Date, byteSize: Int64) {
            switch storage {
            case .package(let package, let verified, _, _, let authorityLease):
                _ = authorityLease
                try package.validateUnchanged()
                guard verified.identity.childrenByName.count <= 2 else {
                    throw BackupError.verification(
                        "The qualified restore package exceeds the bounded metadata entry contract."
                    )
                }
                var total: Int64 = 0
                for identity in verified.identity.childrenByName.values {
                    guard identity.fileType == S_IFREG,
                          identity.linkCount == 1,
                          identity.byteSize >= 0 else {
                        throw BackupError.verification(
                            "A qualified restore package member has invalid descriptor metadata."
                        )
                    }
                    total = try DatabaseSafetyService.checkedRetentionCapacitySum(
                        total,
                        Int64(identity.byteSize)
                    )
                    guard total <= service.maximumDescriptorReadBytes else {
                        throw BackupError.verification(
                            "The qualified restore package exceeds the bounded metadata byte contract."
                        )
                    }
                }
                try package.validateUnchanged()
                return (verified.createdAt, total)
            case .raw(let parent, let descriptor, let identity, _):
                var value = stat()
                guard fstat(descriptor, &value) == 0,
                      try PinnedPackage.descriptorIdentity(descriptor) == identity,
                      try PinnedDirectory.childPathIdentity(
                        parent.descriptor,
                        name: url.lastPathComponent
                      ) == identity,
                      identity.byteSize >= 0,
                      identity.byteSize <= service.maximumDescriptorReadBytes else {
                    throw BackupError.verification(
                        "The qualified raw restore member changed before metadata construction."
                    )
                }
                return (
                    Date(timeIntervalSince1970: TimeInterval(value.st_mtimespec.tv_sec)
                        + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000),
                    Int64(identity.byteSize)
                )
            }
        }

        @MainActor
        func finalDatabaseData(
            service: DatabaseSafetyService
        ) throws -> (data: Data, reference: RetainedPathReference) {
            switch storage {
            case .package(
                let package,
                let verified,
                let policyDirectory,
                let packageName,
                let authorityLease
            ):
                _ = authorityLease
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
                let databaseData = try package.data(
                    for: service.databaseFilename,
                    maximumBytes: service.maximumDescriptorReadBytes
                )
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
            case .raw(let parent, let descriptor, let identity, let verification):
                let bytes = try service.data(from: descriptor, artifactName: url.lastPathComponent)
                guard try PinnedPackage.descriptorIdentity(descriptor) == identity,
                      try PinnedDirectory.childPathIdentity(
                        parent.descriptor,
                        name: url.lastPathComponent
                      ) == identity,
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
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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

        init(
            lockedParentURL url: URL,
            duplicatedAuthorityDescriptor descriptor: Int32,
            fileManager: FileManager
        ) throws {
            self.url = url
            self.fileManager = fileManager
            relativeParent = nil
            relativeName = nil
            self.descriptor = descriptor
            do {
                identity = try Self.descriptorIdentity(descriptor)
                guard identity.fileType == S_IFDIR else {
                    throw BackupError.staging(
                        "The duplicated restore authority is not a directory."
                    )
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
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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
            let childDescriptor = DatabaseSafetyService.openPinnedRegularChildNonBlocking(
                directoryDescriptor: descriptor,
                name: name,
                accessMode: O_RDWR
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
                    let child = DatabaseSafetyService.openPinnedRegularChildNonBlocking(
                        directoryDescriptor: descriptor,
                        name: name,
                        accessMode: O_RDWR
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
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
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

    /// Acquires a supported standalone recovery member relative to one pinned
    /// parent. Unknown occupants always pass through the same nonblocking open,
    /// descriptor-type proof, and parent-relative identity revalidation used by
    /// package and transaction members.
    private func pinnedStandaloneRegularFile(
        at url: URL
    ) throws -> (parent: PinnedDirectory, descriptor: Int32, identity: FileIdentity) {
        let parent = try PinnedDirectory(
            url: url.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: url.lastPathComponent
        )
        guard descriptor >= 0 else {
            throw BackupError.verification(
                "The standalone recovery member could not be acquired as a regular file."
            )
        }
        do {
            let identity = try PinnedPackage.descriptorIdentity(descriptor)
            guard identity.fileType == S_IFREG,
                  identity.linkCount == 1,
                  try PinnedDirectory.childPathIdentity(
                    parent.descriptor,
                    name: url.lastPathComponent
                  ) == identity else {
                throw BackupError.verification(
                    "The standalone recovery member changed during descriptor acquisition."
                )
            }
            return (parent, descriptor, identity)
        } catch {
            Darwin.close(descriptor)
            throw error
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
        let sha256: String
        let descriptor: Int32

        init(
            originalName: String,
            hiddenName: String,
            identity: FileIdentity,
            sha256: String,
            descriptor: Int32
        ) {
            self.originalName = originalName
            self.hiddenName = hiddenName
            self.identity = identity
            self.sha256 = sha256
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

    private struct RestorePersistedIdentity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt32
        let fileType: UInt32
        let linkCount: UInt64
        let byteSize: Int64

        init(_ identity: FileIdentity) {
            device = UInt64(truncatingIfNeeded: identity.device)
            inode = UInt64(truncatingIfNeeded: identity.inode)
            generation = identity.generation
            fileType = UInt32(identity.fileType)
            linkCount = UInt64(identity.linkCount)
            byteSize = Int64(identity.byteSize)
        }

        func matches(_ identity: FileIdentity) -> Bool {
            self == RestorePersistedIdentity(identity)
        }

        func isSameNode(as other: RestorePersistedIdentity) -> Bool {
            device == other.device
                && inode == other.inode
                && generation == other.generation
                && fileType == other.fileType
        }

        var ownershipIdentity: OwnershipLedgerIdentity {
            OwnershipLedgerIdentity(
                device: device,
                inode: inode,
                generation: generation
            )
        }
    }

    private struct RestoreJournalArtifact: Codable, Equatable {
        let originalName: String
        let retainedName: String
        let identity: RestorePersistedIdentity
        let sha256: String
    }

    private struct RestoreTransactionRecord: Codable, Equatable {
        static let currentVersion = 1

        let version: Int
        let databaseName: String
        let replacementName: String
        let originalDatabase: RestoreJournalArtifact
        let replacementDatabase: RestoreJournalArtifact
        let sidecars: [RestoreJournalArtifact]
        let recoveryArtifactPath: String?
    }

    private struct RestoreJournalRegistration: Codable, Equatable {
        static let currentVersion = 1

        let version: Int
        let authority: OwnershipLedgerIdentity
        let journalName: String
        let journal: OwnershipLedgerIdentity
        let journalIdentity: RestorePersistedIdentity
        let journalSHA256: String
        let record: RestoreTransactionRecord
        let stagingIntent: RestoreStagingIntent?
        let completion: RestoreCompletionNamespace?
    }

    private struct RestoreCompletionNamespace: Codable, Equatable {
        enum Outcome: String, Codable {
            case committed
            case compensated
        }

        let outcome: Outcome
        let database: RestoreJournalArtifact
        let sidecars: [RestoreJournalArtifact]
    }

    private struct RestoreStagingIntent: Codable, Equatable {
        enum Mode: String, Codable {
            case existing
            case absent
        }

        enum Phase: String, Codable {
            case planned
            case prepared
            case published
            case completed
        }

        static let currentVersion = 1

        let version: Int
        let authority: OwnershipLedgerIdentity
        let mode: Mode
        let phase: Phase
        let databaseName: String
        let stagingName: String
        let databaseSHA256: String
        let stagingIdentity: RestorePersistedIdentity?
        let installedIdentity: RestorePersistedIdentity?
        let completion: RestoreCompletionNamespace?
    }

    private final class RestoreTransactionJournal {
        let name: String
        let descriptor: Int32
        let identity: FileIdentity

        init(name: String, descriptor: Int32, identity: FileIdentity) {
            self.name = name
            self.descriptor = descriptor
            self.identity = identity
        }

        deinit { Darwin.close(descriptor) }
    }

    private struct RestoreV2Namespace: Codable, Equatable {
        let database: RestoreJournalArtifact?
        let wal: RestoreJournalArtifact?
        let shm: RestoreJournalArtifact?

        var artifacts: [RestoreJournalArtifact] {
            [database, wal, shm].compactMap { $0 }
        }
    }

    private struct RestoreV2SourceNamespace: Codable, Equatable {
        enum Kind: String, Codable {
            case currentV2
            case legacyPackage
            case legacyRaw
        }

        let kind: Kind
        let sourcePath: String
        let selector: String
        let policyPath: String?
        let policyIdentity: RestorePersistedIdentity?
        let packageIdentity: RestorePersistedIdentity
        let lineageIdentifier: String?
        let ownershipNonce: String?
        let ownershipLedgerSHA256: String?
        let members: [RestoreJournalArtifact]
        let recoveryEligible: Bool
    }

    private struct RestoreV2TransactionState: Codable, Equatable {
        enum Mode: String, Codable {
            case existing
            case absent
        }

        enum Phase: String, Codable {
            case planned
            case staged
            case originalsRetained
            case published
            case reopened
            case cleaning
            case rollingBack
            case rolledBack
            case completed
        }

        static let currentVersion = 2

        let version: Int
        let transactionID: String
        let authority: OwnershipLedgerIdentity
        let mode: Mode
        let phase: Phase
        let databaseName: String
        let stagingName: String
        let originalDatabaseRetainedName: String
        let originalWALRetainedName: String
        let originalSHMRetainedName: String
        let replacementWALRetainedName: String
        let replacementSHMRetainedName: String
        let cleanupOriginalDatabaseRetainedName: String
        let cleanupOriginalWALRetainedName: String
        let cleanupOriginalSHMRetainedName: String
        let cleanupStagedDatabaseRetainedName: String
        let cleanupReplacementDatabaseRetainedName: String
        let cleanupReplacementWALRetainedName: String
        let cleanupReplacementSHMRetainedName: String
        let source: RestoreV2SourceNamespace
        let initialNamespace: RestoreV2Namespace
        let stagedDatabase: RestoreJournalArtifact?
        let publishedNamespace: RestoreV2Namespace?
        let reopenedNamespace: RestoreV2Namespace?
        let completedNamespace: RestoreV2Namespace?
        let outcome: RestoreCompletionNamespace.Outcome?
        let recoveryArtifactPath: String?

        func changing(
            phase: Phase,
            stagedDatabase: RestoreJournalArtifact? = nil,
            publishedNamespace: RestoreV2Namespace? = nil,
            reopenedNamespace: RestoreV2Namespace? = nil,
            completedNamespace: RestoreV2Namespace? = nil,
            outcome: RestoreCompletionNamespace.Outcome? = nil
        ) -> RestoreV2TransactionState {
            RestoreV2TransactionState(
                version: version,
                transactionID: transactionID,
                authority: authority,
                mode: mode,
                phase: phase,
                databaseName: databaseName,
                stagingName: stagingName,
                originalDatabaseRetainedName: originalDatabaseRetainedName,
                originalWALRetainedName: originalWALRetainedName,
                originalSHMRetainedName: originalSHMRetainedName,
                replacementWALRetainedName: replacementWALRetainedName,
                replacementSHMRetainedName: replacementSHMRetainedName,
                cleanupOriginalDatabaseRetainedName: cleanupOriginalDatabaseRetainedName,
                cleanupOriginalWALRetainedName: cleanupOriginalWALRetainedName,
                cleanupOriginalSHMRetainedName: cleanupOriginalSHMRetainedName,
                cleanupStagedDatabaseRetainedName: cleanupStagedDatabaseRetainedName,
                cleanupReplacementDatabaseRetainedName: cleanupReplacementDatabaseRetainedName,
                cleanupReplacementWALRetainedName: cleanupReplacementWALRetainedName,
                cleanupReplacementSHMRetainedName: cleanupReplacementSHMRetainedName,
                source: source,
                initialNamespace: initialNamespace,
                stagedDatabase: stagedDatabase ?? self.stagedDatabase,
                publishedNamespace: publishedNamespace ?? self.publishedNamespace,
                reopenedNamespace: reopenedNamespace ?? self.reopenedNamespace,
                completedNamespace: completedNamespace ?? self.completedNamespace,
                outcome: outcome ?? self.outcome,
                recoveryArtifactPath: recoveryArtifactPath
            )
        }
    }

    private final class RestoreV2Transaction {
        let authority: DatabaseStartupLock
        let parent: PinnedDirectory
        let databaseURL: URL
        var state: RestoreV2TransactionState
        var canonicalBytes: Data
        let sourceCapabilityValidator: () throws -> Void

        init(
            authority: DatabaseStartupLock,
            parent: PinnedDirectory,
            databaseURL: URL,
            state: RestoreV2TransactionState,
            canonicalBytes: Data,
            sourceCapabilityValidator: @escaping () throws -> Void
        ) {
            self.authority = authority
            self.parent = parent
            self.databaseURL = databaseURL
            self.state = state
            self.canonicalBytes = canonicalBytes
            self.sourceCapabilityValidator = sourceCapabilityValidator
        }
    }

    private struct RestoreV2ChangeMetadata: Equatable {
        let byteSize: off_t
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ value: stat) {
            byteSize = value.st_size
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }
    }

    private final class RestoreV2PinnedMember {
        let descriptor: Int32
        let artifact: RestoreJournalArtifact
        let identity: FileIdentity
        let changeMetadata: RestoreV2ChangeMetadata

        init(
            descriptor: Int32,
            artifact: RestoreJournalArtifact,
            identity: FileIdentity,
            changeMetadata: RestoreV2ChangeMetadata
        ) {
            self.descriptor = descriptor
            self.artifact = artifact
            self.identity = identity
            self.changeMetadata = changeMetadata
        }

        deinit { Darwin.close(descriptor) }
    }

    private struct RestoreArtifactObservation: Equatable {
        let identity: FileIdentity
        let sha256: String
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
    private var maximumDescriptorReadBytes: Int64 {
        max(maximumPolicyBytes, 8 * 1_024 * 1_024 * 1_024)
    }
    private let maximumAggregatePolicyEntries = 128
    private let maximumAggregateOwnedNodes = 256
    private let maximumAggregateTraversalDepth = 8
    private let ownershipLedgerAttribute = "com.cider.cid850.parent-ownership-ledger-v1"
    private let restoreJournalRegistrationAttribute = "com.cider.cid851.restore-journal-registration-v1"
    private let restoreStagingIntentAttribute = "com.cider.cid851.restore-staging-intent-v1"
    private let restoreTransactionAttribute = "com.cider.cid851.restore-transaction-v2"
    private let maximumOwnershipLedgerEntries = 32

    // These names are intentionally transaction-independent. A completed
    // record can be removed only while every slot is absent, and any later
    // reoccupation blocks the next restore before intent publication.
    private let restoreV2StagingName = ".cid851-restore-fixed-staging.sqlite"
    private let restoreV2OriginalDatabaseName = ".cid851-restore-fixed-original.sqlite"
    private let restoreV2OriginalWALName = ".cid851-restore-fixed-original-wal"
    private let restoreV2OriginalSHMName = ".cid851-restore-fixed-original-shm"
    private let restoreV2ReplacementWALName = ".cid851-restore-fixed-replacement-wal"
    private let restoreV2ReplacementSHMName = ".cid851-restore-fixed-replacement-shm"
    private let restoreV2CleanupOriginalDatabaseName = ".cid851-restore-fixed-cleanup-retained-original.sqlite"
    private let restoreV2CleanupOriginalWALName = ".cid851-restore-fixed-cleanup-retained-original-wal"
    private let restoreV2CleanupOriginalSHMName = ".cid851-restore-fixed-cleanup-retained-original-shm"
    private let restoreV2CleanupStagedDatabaseName = ".cid851-restore-fixed-cleanup-retained-staging.sqlite"
    private let restoreV2CleanupReplacementDatabaseName = ".cid851-restore-fixed-cleanup-retained-replacement.sqlite"
    private let restoreV2CleanupReplacementWALName = ".cid851-restore-fixed-cleanup-retained-replacement-wal"
    private let restoreV2CleanupReplacementSHMName = ".cid851-restore-fixed-cleanup-retained-replacement-shm"

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

    /// The one supported restore selector surface. It includes both rolling
    /// packages and production-emitted pre-restore rollback packages while
    /// preserving verification state and policy kind.
    func listRestoreCandidates(databaseURL: URL) -> [SQLiteBackupInfo] {
        (listRollingBackups(databaseURL: databaseURL)
            + listPreOpenSnapshots(databaseURL: databaseURL))
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.url.lastPathComponent > $1.url.lastPathComponent
            }
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
            let verified = try qualifyRestorePackage(
                package,
                expectedKind: nil,
                expectedLineage: nil,
                policyDirectory: policyDirectory,
                backupURL: backupURL
            )
            return verified.verification
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

    private func reconcileRestoreV2(
        _ persisted: (RestoreV2TransactionState, Data),
        at databaseURL: URL,
        authority: DatabaseStartupLock,
        parent: PinnedDirectory
    ) throws -> RestoreReconciliationResult {
        let state = persisted.0
        guard validRestoreV2State(state, databaseURL: databaseURL, parent: parent) else {
            throw RestoreError.recoveryRequired(
                "The canonical restore transaction is invalid; no namespace occupant was modified.",
                artifactURL: nil
            )
        }
        let transaction = RestoreV2Transaction(
            authority: authority,
            parent: parent,
            databaseURL: databaseURL,
            state: state,
            canonicalBytes: persisted.1,
            sourceCapabilityValidator: { [self] in
                try requireRestoreSourceCapability(
                    state.source,
                    databaseURL: databaseURL,
                    namespaceAuthority: authority
                )
            }
        )
        try requireRestoreV2Capability(
            transaction,
            sourceRequired: state.phase != .completed
        )
        let recoveryURL = state.recoveryArtifactPath.map(URL.init(fileURLWithPath:))

        switch state.phase {
        case .planned:
            let current = try initialRestoreV2Namespace(
                databaseURL: databaseURL,
                transactionID: state.transactionID,
                parent: parent
            )
            guard current == state.initialNamespace else {
                throw RestoreError.recoveryRequired(
                    "The destination namespace changed after planned transaction publication.",
                    artifactURL: recoveryURL
                )
            }
            // Planned state contains no durable staging-member identity. A
            // pathname occupant is therefore unknown regardless of its current
            // inode, type, size, or bytes and must never be adopted or removed.
            if try restoreArtifactObservation(named: state.stagingName, in: parent) != nil {
                throw RestoreError.recoveryRequired(
                    "The planned restore has an unknown staging-path occupant. It was preserved because no durable member capability identifies it.",
                    artifactURL: parent.url.appendingPathComponent(state.stagingName)
                )
            }
            try removeRestoreV2Record(transaction: transaction)
            return RestoreReconciliationResult(state: .none, recoveryArtifactURL: recoveryURL)

        case .cleaning:
            _ = try finishCommittedRestoreV2(transaction: transaction)
            return RestoreReconciliationResult(
                state: .completedCommit,
                recoveryArtifactURL: recoveryURL
            )

        case .completed:
            guard state.completedNamespace != nil else {
                throw RestoreError.recoveryRequired(
                    "The completed transaction lost its resulting namespace.",
                    artifactURL: recoveryURL
                )
            }
            switch try cleanupRetentionStatus(transaction: transaction) {
            case .retained:
                // Terminal evidence is deliberately independent of the live
                // namespace, which ordinary SQLite use may legitimately change
                // after restore completion. Keep the canonical graph so every
                // restart recognizes the same names and never creates a copy.
                return RestoreReconciliationResult(
                    state: state.outcome == .committed ? .completedCommit : .rolledBack,
                    recoveryArtifactURL: recoveryURL,
                    terminalEvidenceInventory: try restoreEvidenceInventory(
                        persisted: persisted,
                        databaseURL: databaseURL,
                        parent: parent
                    )
                )
            case .operatorCleared:
                // Explicit out-of-band removal of the complete evidence set is
                // the only disposal signal recognized by this card. Partial or
                // replaced sets fail closed in cleanupRetentionStatus.
                try removeRestoreV2Record(
                    transaction: transaction,
                    sourceRequired: false,
                    requireClearedFixedSlots: true
                )
                return RestoreReconciliationResult(
                    state: state.outcome == .committed ? .completedCommit : .rolledBack,
                    recoveryArtifactURL: recoveryURL,
                    terminalEvidenceInventory: try restoreEvidenceInventory(
                        persisted: nil,
                        databaseURL: databaseURL,
                        parent: parent
                    )
                )
            }

        case .staged, .originalsRetained, .published, .reopened,
             .rollingBack, .rolledBack:
            _ = try finishRolledBackRestoreV2(
                transaction: transaction,
                reopenOriginal: {
                    if state.mode == .existing {
                        let inspection = try DatabaseStartupPreflight
                            .establishExistingDatabaseHealth(at: databaseURL)
                        inspection.close()
                    }
                }
            )
            return RestoreReconciliationResult(state: .rolledBack, recoveryArtifactURL: recoveryURL)
        }
    }

    /// Reconciles at most one fixed restore journal for this database. The
    /// operation is bounded and idempotent: it either restores the exact
    /// recorded original set, finishes cleanup of an already-proven commit, or
    /// stops with a typed recovery-required error while preserving occupants.
    func reconcileInterruptedRestore(
        at databaseURL: URL,
        namespaceAuthority: DatabaseStartupLock? = nil
    ) throws -> RestoreReconciliationResult {
        let authority = try namespaceAuthority ?? DatabaseStartupLock.acquire(for: databaseURL)
        let ownsAuthority = namespaceAuthority == nil
        defer {
            if ownsAuthority { authority.release() }
        }
        try authority.validate(for: databaseURL)
        let parent = try pinnedRestoreParent(for: databaseURL, authority: authority)
        if let persisted = try restoreV2State(in: parent) {
            return try reconcileRestoreV2(
                persisted,
                at: databaseURL,
                authority: authority,
                parent: parent
            )
        }
        let journalName = restoreJournalName(for: databaseURL)
        var journalStat = stat()
        guard fstatat(parent.descriptor, journalName, &journalStat, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
                if let registration = try restoreJournalRegistration(in: parent) {
                    return try reconcileRemovedRestoreJournal(
                        registration,
                        at: databaseURL,
                        in: parent
                    )
                }
                let registrationSize = fgetxattr(
                    parent.descriptor,
                    restoreJournalRegistrationAttribute,
                    nil,
                    0,
                    0,
                    0
                )
                guard registrationSize < 0, errno == ENOATTR else {
                    throw RestoreError.recoveryRequired(
                        "A malformed restore journal registration remains after record removal; no occupant was modified.",
                        artifactURL: nil
                    )
                }
                return try reconcileRestoreStagingIntent(
                    at: databaseURL,
                    in: parent
                )
            }
            throw RestoreError.recoveryRequired(
                "The bounded restore journal name could not be inspected.",
                artifactURL: nil
            )
        }
        let journalDescriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: journalName
        )
        guard journalDescriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "The interrupted restore journal could not be pinned.",
                artifactURL: nil
            )
        }
        defer { Darwin.close(journalDescriptor) }
        let journalIdentity = try PinnedPackage.descriptorIdentity(journalDescriptor)
        guard journalIdentity.fileType == S_IFREG,
              journalIdentity.linkCount == 1,
              try PinnedDirectory.childPathIdentity(parent.descriptor, name: journalName)
                == journalIdentity else {
            throw RestoreError.recoveryRequired(
                "The interrupted restore journal identity is not authoritative.",
                artifactURL: nil
            )
        }
        let record: RestoreTransactionRecord
        let journalData: Data
        do {
            journalData = try data(from: journalDescriptor, artifactName: journalName)
            guard try restoreJournalIsRegistered(
                identity: journalIdentity,
                sha256: sha256(journalData),
                record: try JSONDecoder().decode(
                    RestoreTransactionRecord.self,
                    from: journalData
                ),
                in: parent
            ) else {
                throw RestoreError.recoveryRequired(
                    "The interrupted restore journal has no exact Cider creation registration; no namespace occupant was modified.",
                    artifactURL: nil
                )
            }
            record = try JSONDecoder().decode(
                RestoreTransactionRecord.self,
                from: journalData
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(record) == journalData else {
                throw RestoreError.recoveryRequired(
                    "The interrupted restore journal is not the exact canonical Cider record encoding.",
                    artifactURL: nil
                )
            }
        } catch {
            if let restoreError = error as? RestoreError { throw restoreError }
            throw RestoreError.recoveryRequired(
                "The interrupted restore journal is malformed: \(error.localizedDescription)",
                artifactURL: nil
            )
        }
        guard validRestoreTransactionRecord(record, for: databaseURL) else {
            throw RestoreError.recoveryRequired(
                "The interrupted restore journal does not match the exact Cider DB/WAL/SHM transaction grammar.",
                artifactURL: nil
            )
        }
        _ = try requireRestoreJournalCapability(
            record: record,
            journalName: journalName,
            journalIdentity: journalIdentity,
            in: parent
        )
        let recoveryURL = record.recoveryArtifactPath.map(URL.init(fileURLWithPath:))

        let live = try restoreArtifactObservation(
            named: record.databaseName,
            in: parent
        )
        let retained = try restoreArtifactObservation(
            named: record.replacementName,
            in: parent
        )
        let liveIsOriginal = live.map { restoreObservation($0, matches: record.originalDatabase) } == true
        let liveIsReplacement = live.map { restoreObservation($0, matches: record.replacementDatabase) } == true
        let retainedIsOriginal = retained.map { restoreObservation($0, matches: record.originalDatabase) } == true
        let retainedIsReplacement = retained.map { restoreObservation($0, matches: record.replacementDatabase) } == true

        if liveIsReplacement, retained == nil {
            let completion: RestoreCompletionNamespace
            if let registered = try restoreJournalRegistration(in: parent)?.completion,
               registered.outcome == .committed,
               restoreCompletionNamespace(registered, matches: record) {
                completion = registered
            } else {
                completion = try saveRestoreCompletionNamespace(
                    outcome: .committed,
                    record: record,
                    at: databaseURL,
                    in: parent
                )
            }
            try reconcileCommittedRestoreSidecars(record.sidecars, in: parent)
            guard fsync(parent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "Committed restore reconciliation could not establish its first namespace durability point.",
                    artifactURL: recoveryURL
                )
            }
            return try finishRegisteredRestoreCompletion(
                completion,
                journalName: journalName,
                journalIdentity: journalIdentity,
                registrationRecord: record,
                databaseURL: databaseURL,
                in: parent
            )
        }

        var separatedReplacementSidecars: [RestoreJournalArtifact] = []
        if liveIsReplacement, retainedIsOriginal {
            let committedNamespace: RestoreCompletionNamespace
            if let registered = try restoreJournalRegistration(in: parent)?.completion,
               registered.outcome == .committed,
               restoreCompletionNamespace(registered, matches: record) {
                committedNamespace = registered
            } else {
                committedNamespace = try saveRestoreCompletionNamespace(
                    outcome: .committed,
                    record: record,
                    at: databaseURL,
                    in: parent
                )
            }
            try quarantineReplacementSidecars(committedNamespace.sidecars, in: parent)
            separatedReplacementSidecars = committedNamespace.sidecars
            _ = try requireRestoreJournalCapability(
                record: record,
                journalName: journalName,
                journalIdentity: journalIdentity,
                in: parent
            )
            guard renameatx_np(
                parent.descriptor,
                record.replacementName,
                parent.descriptor,
                record.databaseName,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw RestoreError.recoveryRequired(
                    "Interrupted restore reconciliation could not atomically restore the original database.",
                    artifactURL: recoveryURL
                )
            }
        } else if !(liveIsOriginal && retainedIsReplacement) {
            throw RestoreError.recoveryRequired(
                "Interrupted restore occupants do not match either recorded atomic state; all occupants were preserved.",
                artifactURL: recoveryURL
            )
        }

        if liveIsOriginal, retained == nil,
           let completion = try restoreJournalRegistration(in: parent)?.completion,
           completion.outcome == .compensated,
           restoreCompletionNamespace(completion, matches: record) {
            return try finishRegisteredRestoreCompletion(
                completion,
                journalName: journalName,
                journalIdentity: journalIdentity,
                registrationRecord: record,
                databaseURL: databaseURL,
                in: parent
            )
        }

        try reconcileRolledBackSidecars(record.sidecars, in: parent)
        try removeQuarantinedReplacementSidecars(separatedReplacementSidecars, in: parent)
        guard let restored = try restoreArtifactObservation(named: record.databaseName, in: parent),
              restoreObservation(restored, matches: record.originalDatabase),
              let replacement = try restoreArtifactObservation(named: record.replacementName, in: parent),
              restoreObservation(replacement, matches: record.replacementDatabase) else {
            throw RestoreError.recoveryRequired(
                "Interrupted restore compensation could not prove the exact original and replacement bytes.",
                artifactURL: recoveryURL
            )
        }
        _ = try requireRestoreJournalCapability(
            record: record,
            journalName: journalName,
            journalIdentity: journalIdentity,
            in: parent
        )
        try removeRestoreArtifact(
            named: record.replacementName,
            expected: replacement.identity,
            expectedSHA256: record.replacementDatabase.sha256,
            in: parent
        )
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Interrupted restore rollback could not establish its first namespace durability point.",
                artifactURL: recoveryURL
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: record.originalDatabase,
            expectedSidecars: record.sidecars,
            in: parent
        )
        try removeRestoreJournal(
            named: journalName,
            identity: journalIdentity,
            record: record,
            in: parent
        )
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Interrupted restore rollback removed its record, but the separate record-removal durability point failed.",
                artifactURL: recoveryURL
            )
        }
        try clearCompletedRestoreMetadata(in: parent)
        return RestoreReconciliationResult(state: .rolledBack, recoveryArtifactURL: recoveryURL)
    }

    private func reconcileRemovedRestoreJournal(
        _ registration: RestoreJournalRegistration,
        at databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreReconciliationResult {
        let record = registration.record
        guard validRestoreTransactionRecord(record, for: databaseURL),
              let completion = registration.completion,
              validRestoreCompletionNamespace(completion, for: databaseURL),
              restoreCompletionNamespace(completion, matches: record) else {
            throw RestoreError.recoveryRequired(
                "The record-removal registration does not contain an exact resulting DB/WAL/SHM namespace.",
                artifactURL: nil
            )
        }
        let recoveryURL = record.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: parent)
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Record-removal reconciliation could not re-establish resulting namespace durability.",
                artifactURL: recoveryURL
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: completion.database,
            expectedSidecars: completion.sidecars,
            in: parent
        )
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: parent)
        try clearCompletedRestoreMetadata(in: parent)
        return RestoreReconciliationResult(
            state: completion.outcome == .committed ? .completedCommit : .rolledBack,
            recoveryArtifactURL: recoveryURL
        )
    }

    private func finishRegisteredRestoreCompletion(
        _ completion: RestoreCompletionNamespace,
        journalName: String,
        journalIdentity: FileIdentity,
        registrationRecord: RestoreTransactionRecord,
        databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreReconciliationResult {
        guard validRestoreCompletionNamespace(completion, for: databaseURL),
              restoreCompletionNamespace(completion, matches: registrationRecord) else {
            throw RestoreError.recoveryRequired(
                "The registered resulting DB/WAL/SHM namespace is malformed.",
                artifactURL: nil
            )
        }
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: parent)
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Restore completion reconciliation could not establish namespace durability.",
                artifactURL: registrationRecord.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: completion.database,
            expectedSidecars: completion.sidecars,
            in: parent
        )
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: parent)
        try removeRestoreJournal(
            named: journalName,
            identity: journalIdentity,
            record: registrationRecord,
            in: parent
        )
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Restore completion reconciliation removed its record, but the separate record-removal durability point failed.",
                artifactURL: registrationRecord.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
            )
        }
        try clearCompletedRestoreMetadata(in: parent)
        return RestoreReconciliationResult(
            state: completion.outcome == .committed ? .completedCommit : .rolledBack,
            recoveryArtifactURL: registrationRecord.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
        )
    }

    private func reconcileRestoreStagingIntent(
        at databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreReconciliationResult {
        let intent = try restoreStagingIntent(in: parent)
        if intent == nil {
            let size = fgetxattr(
                parent.descriptor,
                restoreStagingIntentAttribute,
                nil,
                0,
                0,
                0
            )
            guard size < 0, errno == ENOATTR else {
                throw RestoreError.recoveryRequired(
                    "A malformed or replaced restore staging intent was preserved; no namespace occupant was modified.",
                    artifactURL: nil
                )
            }
            return RestoreReconciliationResult(state: .none, recoveryArtifactURL: nil)
        }
        guard let intent, intent.databaseName == databaseURL.lastPathComponent else {
            throw RestoreError.recoveryRequired(
                "The restore staging intent belongs to a different database namespace.",
                artifactURL: nil
            )
        }
        let staging = try restoreArtifactObservation(named: intent.stagingName, in: parent)
        switch intent.phase {
        case .planned:
            guard staging == nil else {
                throw RestoreError.recoveryRequired(
                    "A staging occupant appeared before its exact identity was registered; it was preserved.",
                    artifactURL: parent.url.appendingPathComponent(intent.stagingName)
                )
            }
        case .prepared:
            guard let expected = intent.stagingIdentity,
                  let staging,
                  expected.matches(staging.identity),
                  staging.sha256 == intent.databaseSHA256 else {
                throw RestoreError.recoveryRequired(
                    "The prepared restore staging occupant changed identity or content; it was preserved.",
                    artifactURL: parent.url.appendingPathComponent(intent.stagingName)
                )
            }
            if intent.mode == .absent {
                guard try restoreArtifactObservation(named: intent.databaseName, in: parent) == nil else {
                    throw RestoreError.recoveryRequired(
                        "An unregistered occupant appeared at the absent restore destination; every occupant was preserved.",
                        artifactURL: nil
                    )
                }
            }
            try removeRestoreArtifact(
                named: intent.stagingName,
                expected: staging.identity,
                expectedSHA256: intent.databaseSHA256,
                in: parent
            )
        case .published:
            guard intent.mode == .absent,
                  let stagingExpected = intent.stagingIdentity,
                  let installedExpected = intent.installedIdentity,
                  let staging,
                  stagingExpected.matches(staging.identity),
                  staging.sha256 == intent.databaseSHA256,
                  let installed = try restoreArtifactObservation(
                    named: intent.databaseName,
                    in: parent
                  ),
                  installedExpected.matches(installed.identity),
                  installed.sha256 == intent.databaseSHA256 else {
                throw RestoreError.recoveryRequired(
                    "The published absent-destination transaction changed identity or content; every occupant was preserved.",
                    artifactURL: nil
                )
            }
            let replacementNamespace = try captureRestoreCompletionNamespace(
                outcome: .committed,
                at: databaseURL,
                in: parent
            )
            try quarantineReplacementSidecars(
                replacementNamespace.sidecars,
                in: parent
            )
            try removeRestoreArtifact(
                named: intent.databaseName,
                expected: installed.identity,
                expectedSHA256: intent.databaseSHA256,
                in: parent
            )
            try removeRestoreArtifact(
                named: intent.stagingName,
                expected: staging.identity,
                expectedSHA256: intent.databaseSHA256,
                in: parent
            )
            try removeQuarantinedReplacementSidecars(
                replacementNamespace.sidecars,
                in: parent
            )
        case .completed:
            guard intent.mode == .absent,
                  let stagingExpected = intent.stagingIdentity,
                  let staging,
                  stagingExpected.matches(staging.identity),
                  staging.sha256 == intent.databaseSHA256,
                  let completion = intent.completion else {
                throw RestoreError.recoveryRequired(
                    "The completed absent-destination transaction lost its exact staging or DB/WAL/SHM capability.",
                    artifactURL: nil
                )
            }
            try requireRestoreCompletionNamespace(completion, at: databaseURL, in: parent)
            try removeRestoreArtifact(
                named: intent.stagingName,
                expected: staging.identity,
                expectedSHA256: intent.databaseSHA256,
                in: parent
            )
            guard fsync(parent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "Completed absent-destination staging cleanup could not establish durability.",
                    artifactURL: nil
                )
            }
            try physicallyVerifyRestoreNamespace(
                databaseURL,
                expectedDatabase: completion.database,
                expectedSidecars: completion.sidecars,
                in: parent
            )
            try clearRestoreStagingIntent(in: parent)
            return RestoreReconciliationResult(state: .completedCommit, recoveryArtifactURL: nil)
        }
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "Restore staging reconciliation could not establish its first namespace durability point.",
                artifactURL: nil
            )
        }
        try clearRestoreStagingIntent(in: parent)
        return RestoreReconciliationResult(state: .none, recoveryArtifactURL: nil)
    }

    private func physicallyVerifyRestoreNamespace(
        _ databaseURL: URL,
        expectedDatabase: RestoreJournalArtifact,
        expectedSidecars: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        try physicallyVerifyRestoreNamespaceOccupants(
            databaseURL,
            expectedDatabase: expectedDatabase,
            expectedSidecars: expectedSidecars,
            in: parent
        )
        do {
            let inspection = try DatabaseStartupPreflight
                .establishExistingDatabaseHealth(at: databaseURL)
            inspection.close()
        } catch {
            throw RestoreError.recoveryRequired(
                "The directory-synced restore namespace could not be physically reopened and verified: \(error.localizedDescription)",
                artifactURL: nil
            )
        }
        try physicallyVerifyRestoreNamespaceOccupants(
            databaseURL,
            expectedDatabase: expectedDatabase,
            expectedSidecars: expectedSidecars,
            in: parent
        )
    }

    private func physicallyVerifyRestoreNamespaceOccupants(
        _ databaseURL: URL,
        expectedDatabase: RestoreJournalArtifact,
        expectedSidecars: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        guard let database = try restoreArtifactObservation(
            named: databaseURL.lastPathComponent,
            in: parent
        ), restoreObservation(database, matches: expectedDatabase) else {
            throw RestoreError.recoveryRequired(
                "The resulting live database changed identity or content before physical verification.",
                artifactURL: nil
            )
        }
        for suffix in ["-wal", "-shm"] {
            let name = databaseURL.lastPathComponent + suffix
            let expected = expectedSidecars.first { $0.originalName == name }
            let observation = try restoreArtifactObservation(named: name, in: parent)
            guard expected.map({ artifact in
                observation.map { restoreObservation($0, matches: artifact) } == true
            }) ?? (observation == nil) else {
                throw RestoreError.recoveryRequired(
                    "The resulting SQLite sidecar namespace changed before physical verification.",
                    artifactURL: nil
                )
            }
        }
    }

    @discardableResult
    func restoreRollingBackup(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase? = nil,
        reopenDatabase: Bool = false
    ) throws -> RestoreResult {
        return try restoreRollingBackupV2(
            from: backupURL,
            into: databaseURL,
            database: database,
            reopenDatabase: reopenDatabase
        )
    }

    /// Retained only as implementation support for the bounded v1 recovery
    /// structures. New restore entry points do not call this method.
    private func restoreRollingBackupV1(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase? = nil,
        reopenDatabase: Bool = false
    ) throws -> RestoreResult {
        let namespaceAuthority = try DatabaseStartupLock.acquire(for: databaseURL)
        defer { namespaceAuthority.release() }
        try namespaceAuthority.validate(for: databaseURL)
        _ = try reconcileInterruptedRestore(
            at: databaseURL,
            namespaceAuthority: namespaceAuthority
        )
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
                reopenDatabase: reopenDatabase,
                namespaceAuthority: namespaceAuthority
            )
        }

        let destinationObservation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
        let destinationLineage = try destinationObservation.validate()
        let databaseParent = try PinnedDirectory(
            url: databaseURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        guard try destinationObservation.validate() == destinationLineage else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The restore destination lineage changed before source verification."]
            )
        }
        let retainedUse = try pinRestoreSource(
            at: backupURL,
            expectedKind: nil,
            expectedLineage: destinationLineage.identifier,
            legacyDestinationURL: databaseURL,
            namespaceAuthority: namespaceAuthority
        )
        guard retainedUse.verification.isRecoveryEligible else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: retainedUse.verification.messages
            )
        }
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
        do {
            let committedNamespace = try replaceLiveDatabaseAtomically(
            at: databaseURL,
            with: finalUse.data,
            in: databaseParent,
            expectedDestinationLineage: destinationLineage,
            recoveryArtifactURL: preRestoreSnapshotURL,
            beforeMutation: {
                finalUse = try retainedUse.finalDatabaseData(service: self)
            },
            beforeCleanup: {
                do {
                    try namespaceAuthority.validate(for: databaseURL)
                    try databaseParent.validatePath()
                    let revalidatedUse = try retainedUse.finalDatabaseData(service: self)
                    guard revalidatedUse.data == finalUse.data else {
                        throw RestoreError.recoveryRequired(
                            "The exact restore source capability changed before hidden recovery cleanup.",
                            artifactURL: preRestoreSnapshotURL
                        )
                    }
                    finalUse = revalidatedUse
                } catch let error as RestoreError {
                    throw error
                } catch {
                    throw RestoreError.recoveryRequired(
                        "Final source/parent capability revalidation failed before hidden recovery cleanup: \(error.localizedDescription)",
                        artifactURL: preRestoreSnapshotURL
                    )
                }
            },
            validateInstalledDatabase: {
                guard reopenDatabase, let database else {
                    let inspection = try DatabaseStartupPreflight
                        .establishExistingDatabaseHealth(at: databaseURL)
                    inspection.close()
                    return
                }
                do {
                    try database.open(
                        at: databaseURL,
                        reconcileInterruptedRestore: false,
                        namespaceAuthority: namespaceAuthority
                    )
                    let integrity = try database.integrityCheck()
                    guard integrity.isHealthy else {
                        throw RestoreError.unhealthyBackup(
                            backupURL,
                            messages: ["The physically reopened replacement failed integrity: \(integrity.messages.joined(separator: " | "))"]
                        )
                    }
                } catch {
                    database.close()
                    throw error
                }
            },
            reopenOriginalDatabase: {
                let inspection = try DatabaseStartupPreflight
                    .establishExistingDatabaseHealth(at: databaseURL)
                inspection.close()
            }
            )
            try namespaceAuthority.validate(for: databaseURL)
            try databaseParent.validatePath()
            let receiptUse = try retainedUse.finalDatabaseData(service: self)
            guard receiptUse.data == finalUse.data,
                  receiptUse.reference.currentURL() != nil else {
                throw RestoreError.recoveryRequired(
                    "The selected restore source capability changed before receipt construction.",
                    artifactURL: preRestoreSnapshotURL
                )
            }
            try physicallyVerifyRestoreNamespace(
                databaseURL,
                expectedDatabase: committedNamespace.database,
                expectedSidecars: committedNamespace.sidecars,
                in: databaseParent
            )
            guard fsync(databaseParent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "The final restored namespace could not be durably revalidated for its receipt.",
                    artifactURL: preRestoreSnapshotURL
                )
            }
            finalUse = receiptUse
        } catch {
            let failureTrigger = restoreFailureTrigger(error)
            if reopenDatabase, let database, !database.isOpen {
                do {
                    _ = try reconcileInterruptedRestore(
                        at: databaseURL,
                        namespaceAuthority: namespaceAuthority
                    )
                    let inspection = try DatabaseStartupPreflight
                        .establishExistingDatabaseHealth(at: databaseURL)
                    inspection.close()
                    throw RestoreError.recoveredFailure(
                        "The live replacement did not complete: \(failureTrigger) Durable reconciliation removed only identity-bound transaction artifacts."
                    )
                } catch let recoveryError as RestoreError {
                    if case .recoveryRequired(let detail, let artifactURL) = recoveryError {
                        throw RestoreError.recoveryRequired(
                            detail,
                            artifactURL: artifactURL ?? preRestoreSnapshotURL
                        )
                    }
                    throw recoveryError
                } catch {
                    throw RestoreError.recoveryRequired(
                        "Restore compensation or physical reopen could not be proven: \(error.localizedDescription)",
                        artifactURL: preRestoreSnapshotURL
                    )
                }
            }
            throw error
        }

        let restoredMetadata = try retainedUse.metadataSnapshot(service: self)
        let restoredBackup = SQLiteBackupInfo(
            kind: retainedUse.kind,
            url: backupURL,
            createdAt: restoredMetadata.createdAt,
            byteSize: restoredMetadata.byteSize,
            verification: retainedUse.verification
        )
        logger.info("Restored SQLite database from backup \(backupURL.lastPathComponent, privacy: .public)")
        return RestoreResult(
            restoredBackup: restoredBackup,
            preRestoreSnapshotURL: preRestoreSnapshotURL,
            sourceReference: finalUse.reference
        )
    }

    private func restoreRollingBackupV2(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase?,
        reopenDatabase: Bool
    ) throws -> RestoreResult {
        let authority = try DatabaseStartupLock.acquire(for: databaseURL)
        defer { authority.release() }
        try authority.validate(for: databaseURL)
        let reconciliation = try reconcileInterruptedRestore(
            at: databaseURL,
            namespaceAuthority: authority
        )
        guard reconciliation.state == .none else {
            throw RestoreError.recoveryRequired(
                "A completed restore still owns the fixed terminal-evidence capacity. Explicit operator cleanup is required before another restore; no new mutation was attempted.",
                artifactURL: reconciliation.recoveryArtifactURL
            )
        }
        let parent = try pinnedRestoreParent(for: databaseURL, authority: authority)
        try requireRestoreV2FixedSlotsAbsent(
            in: parent,
            detail: "Restore admission refused."
        )

        var databaseMetadata = stat()
        let destinationExists = fstatat(
            parent.descriptor,
            databaseURL.lastPathComponent,
            &databaseMetadata,
            AT_SYMLINK_NOFOLLOW
        ) == 0
        if !destinationExists, errno != ENOENT {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The restore destination could not be inspected through the locked parent descriptor."]
            )
        }
        if !destinationExists {
            for suffix in ["-wal", "-shm"] {
                guard try restoreArtifactObservation(
                    named: databaseURL.lastPathComponent + suffix,
                    in: parent
                ) == nil else {
                    throw RestoreError.unhealthyBackup(
                        backupURL,
                        messages: ["The absent destination has an orphan SQLite sidecar; no restore mutation was attempted."]
                    )
                }
            }
        }

        let destinationLineage: DatabaseSourceLineage?
        if destinationExists {
            let observation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
            destinationLineage = try observation.validate()
        } else {
            destinationLineage = nil
        }
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw RestoreError.missingBackup(backupURL)
        }
        let source = try pinRestoreSource(
            at: backupURL,
            expectedKind: nil,
            expectedLineage: destinationLineage?.identifier,
            legacyDestinationURL: databaseURL,
            destinationExists: destinationExists,
            namespaceAuthority: authority
        )
        guard source.verification.isRecoveryEligible else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: source.verification.messages
            )
        }
        var finalUse = try source.finalDatabaseData(service: self)
        let qualifiedSourceNamespace = try restoreSourceNamespace(from: source)
        try requireRestoreSourceCapability(
            qualifiedSourceNamespace,
            source: source,
            databaseURL: databaseURL
        )

        let transactionID = UUID().uuidString.lowercased()
        let capacityNamespace = try initialRestoreV2Namespace(
            databaseURL: databaseURL,
            transactionID: transactionID,
            parent: parent
        )
        try requireRestoreV2RetentionCapacity(
            artifacts: capacityNamespace.artifacts,
            prospectiveByteSizes: destinationExists
                ? [Int64(finalUse.data.count)]
                : [Int64(finalUse.data.count), Int64(finalUse.data.count)]
        )

        let preRestoreSnapshotURL = destinationExists
            ? try capturePreOpenSnapshot(
                databaseURL: databaseURL,
                reason: "pre-restore",
                authorityLeaseHeld: true
            )
            : nil
        // Snapshot publication advances the shared ledger and is also the
        // last service operation before the caller's live handle is closed.
        // Requalify and freeze the source now so a snapshot-boundary source
        // change cannot perturb the still-open destination namespace.
        finalUse = try source.finalDatabaseData(service: self)
        let sourceNamespace = try restoreSourceNamespace(from: source)
        try requireRestoreSourceCapability(
            sourceNamespace,
            source: source,
            databaseURL: databaseURL
        )
        if let database, database.isOpen, database.databaseURL == databaseURL {
            database.close()
        }
        try authority.validate(for: databaseURL)
        try parent.validatePath()
        finalUse = try source.finalDatabaseData(service: self)
        // The source capability frozen after snapshot publication remains the
        // durable transaction's exact source namespace.
        try requireRestoreSourceCapability(
            sourceNamespace,
            source: source,
            databaseURL: databaseURL
        )

        let initial = try initialRestoreV2Namespace(
            databaseURL: databaseURL,
            transactionID: transactionID,
            parent: parent
        )
        guard (destinationExists && initial.database != nil)
                || (!destinationExists && initial.artifacts.isEmpty) else {
            throw RestoreError.recoveryRequired(
                "The destination DB/WAL/SHM namespace changed before transaction publication.",
                artifactURL: preRestoreSnapshotURL
            )
        }
        let transaction = try createRestoreV2Transaction(
            databaseURL: databaseURL,
            transactionID: transactionID,
            mode: destinationExists ? .existing : .absent,
            initialNamespace: initial,
            sourceNamespace: sourceNamespace,
            recoveryArtifactURL: preRestoreSnapshotURL,
            authority: authority,
            parent: parent,
            source: source
        )

        let completion: RestoreV2Namespace
        do {
            completion = try replaceDatabaseWithRestoreV2(
                databaseData: finalUse.data,
                transaction: transaction,
                validateInstalledDatabase: {
                    guard reopenDatabase, let database else {
                        let inspection = try DatabaseStartupPreflight
                            .establishExistingDatabaseHealth(at: databaseURL)
                        inspection.close()
                        return
                    }
                    do {
                        try database.open(
                            at: databaseURL,
                            reconcileInterruptedRestore: false,
                            namespaceAuthority: authority
                        )
                        let integrity = try database.integrityCheck()
                        guard integrity.isHealthy else {
                            throw RestoreError.unhealthyBackup(
                                backupURL,
                                messages: integrity.messages
                            )
                        }
                    } catch {
                        database.close()
                        throw error
                    }
                },
                reopenOriginalDatabase: {
                    guard reopenDatabase, let database else {
                        let inspection = try DatabaseStartupPreflight
                            .establishExistingDatabaseHealth(at: databaseURL)
                        inspection.close()
                        return
                    }
                    database.close()
                    try database.open(
                        at: databaseURL,
                        reconcileInterruptedRestore: false,
                        namespaceAuthority: authority
                    )
                    let integrity = try database.integrityCheck()
                    guard integrity.isHealthy else {
                        database.close()
                        throw RestoreError.recoveryRequired(
                            "The compensated original database failed physical integrity.",
                            artifactURL: preRestoreSnapshotURL
                        )
                    }
                }
            )
        } catch let error as RestoreError {
            if reopenDatabase, let database, database.isOpen,
               transaction.state.outcome != .committed {
                database.close()
            }
            if case .recoveryRequired(let detail, nil) = error,
               let recoveryPath = transaction.state.recoveryArtifactPath {
                throw RestoreError.recoveryRequired(
                    detail,
                    artifactURL: URL(fileURLWithPath: recoveryPath)
                )
            }
            throw error
        } catch {
            if reopenDatabase, let database, database.isOpen,
               transaction.state.outcome != .committed {
                database.close()
            }
            throw error
        }

        try authority.validate(for: databaseURL)
        try parent.validatePath()
        try requireRestoreSourceCapability(
            sourceNamespace,
            source: source,
            databaseURL: databaseURL
        )
        guard let completedDatabase = completion.database else {
            throw RestoreError.recoveryRequired(
                "The successful restore has no complete live database capability.",
                artifactURL: preRestoreSnapshotURL
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: completedDatabase,
            expectedSidecars: [completion.wal, completion.shm].compactMap({ $0 }),
            in: parent
        )
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The final restore receipt namespace could not be directory-synced.",
                artifactURL: preRestoreSnapshotURL
            )
        }
        finalUse = try source.finalDatabaseData(service: self)
        try requireRestoreSourceCapability(
            sourceNamespace,
            source: source,
            databaseURL: databaseURL
        )
        let restoredMetadata = try source.metadataSnapshot(service: self)
        let restoredBackup = SQLiteBackupInfo(
            kind: source.kind,
            url: backupURL,
            createdAt: restoredMetadata.createdAt,
            byteSize: restoredMetadata.byteSize,
            verification: source.verification
        )
        logger.info("Restored SQLite database from backup \(backupURL.lastPathComponent, privacy: .public)")
        return RestoreResult(
            restoredBackup: restoredBackup,
            preRestoreSnapshotURL: preRestoreSnapshotURL,
            sourceReference: finalUse.reference,
            sourceDatabaseURL: databaseURL,
            requiresCurrentV2Eligibility: sourceNamespace.kind == .currentV2,
            sourceCapabilityData: try canonicalRestoreV2SourceBytes(sourceNamespace),
            terminalEvidenceInventory: try restoreEvidenceInventory(
                persisted: (transaction.state, transaction.canonicalBytes),
                databaseURL: databaseURL,
                parent: parent
            )
        )
    }

    private func restoreFailureTrigger(_ error: Error) -> String {
        guard case RestoreError.unhealthyBackup(_, let messages) = error else {
            return error.localizedDescription
        }
        return messages.map { message in
            for marker in [
                " The prior coherent database was restored",
                " The prior database was retained",
                " The prior database location could not be proven",
                " The replacement remains retained",
                " Original sidecars retained for operator recovery",
                " The rollback parent directory was flushed",
                " The rollback parent-directory flush failed"
            ] {
                if let range = message.range(of: marker) {
                    return String(message[..<range.lowerBound])
                }
            }
            return message
        }.joined(separator: " | ")
    }

    private func stateFileURL(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("state.json")
    }

    private func restoreIntoNewDestination(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase?,
        reopenDatabase: Bool,
        namespaceAuthority: DatabaseStartupLock
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
        try namespaceAuthority.validate(for: databaseURL)
        let retainedUse = try pinRestoreSource(
            at: backupURL,
            expectedKind: nil,
            expectedLineage: nil,
            legacyDestinationURL: databaseURL,
            destinationExists: false,
            namespaceAuthority: namespaceAuthority
        )
        guard retainedUse.verification.isRecoveryEligible else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: retainedUse.verification.messages
            )
        }
        var finalUse = try retainedUse.finalDatabaseData(service: self)
        let hiddenName = ".cid851-restore-new-\(UUID().uuidString.lowercased()).sqlite"
        let plannedIntent = RestoreStagingIntent(
            version: RestoreStagingIntent.currentVersion,
            authority: OwnershipLedgerIdentity(databaseParent.identity),
            mode: .absent,
            phase: .planned,
            databaseName: databaseURL.lastPathComponent,
            stagingName: hiddenName,
            databaseSHA256: sha256(finalUse.data),
            stagingIdentity: nil,
            installedIdentity: nil,
            completion: nil
        )
        try saveRestoreStagingIntent(plannedIntent, in: databaseParent)
        let hiddenDescriptor = try databaseParent.createExclusiveRegularFile(named: hiddenName)
        defer { Darwin.close(hiddenDescriptor) }
        try write(finalUse.data, to: hiddenDescriptor, artifactName: hiddenName)
        _ = try verifySQLiteDatabase(data: finalUse.data, descriptor: hiddenDescriptor)
        let hiddenIdentity = try PinnedPackage.descriptorIdentity(hiddenDescriptor)
        let preparedIntent = RestoreStagingIntent(
            version: plannedIntent.version,
            authority: plannedIntent.authority,
            mode: plannedIntent.mode,
            phase: .prepared,
            databaseName: plannedIntent.databaseName,
            stagingName: plannedIntent.stagingName,
            databaseSHA256: plannedIntent.databaseSHA256,
            stagingIdentity: RestorePersistedIdentity(hiddenIdentity),
            installedIdentity: nil,
            completion: nil
        )
        try saveRestoreStagingIntent(preparedIntent, in: databaseParent)
        finalUse = try retainedUse.finalDatabaseData(service: self)
        guard sha256(finalUse.data) == preparedIntent.databaseSHA256 else {
            throw RestoreError.recoveryRequired(
                "The restore source changed after absent-destination intent publication.",
                artifactURL: backupURL
            )
        }
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
        let installedDescriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: databaseParent.descriptor,
            name: databaseURL.lastPathComponent
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
        let installedIdentity = try PinnedPackage.descriptorIdentity(installedDescriptor)
        defer { Darwin.close(installedDescriptor) }
        let publishedIntent = RestoreStagingIntent(
            version: preparedIntent.version,
            authority: preparedIntent.authority,
            mode: preparedIntent.mode,
            phase: .published,
            databaseName: preparedIntent.databaseName,
            stagingName: preparedIntent.stagingName,
            databaseSHA256: preparedIntent.databaseSHA256,
            stagingIdentity: preparedIntent.stagingIdentity,
            installedIdentity: RestorePersistedIdentity(installedIdentity),
            completion: nil
        )
        try saveRestoreStagingIntent(publishedIntent, in: databaseParent)
        guard installedData == finalUse.data,
              try PinnedDirectory.childPathIdentity(
                databaseParent.descriptor,
                name: databaseURL.lastPathComponent
              ) == installedIdentity,
              fsync(databaseParent.descriptor) == 0 else {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The newly restored database identity, content, or publication durability differs from the held verified source."]
            )
        }
        if reopenDatabase, let database {
            do {
                try database.open(
                    at: databaseURL,
                    reconcileInterruptedRestore: false,
                    namespaceAuthority: namespaceAuthority
                )
                let integrity = try database.integrityCheck()
                guard integrity.isHealthy else {
                    throw RestoreError.unhealthyBackup(
                        backupURL,
                        messages: ["The new destination failed physical reopen integrity."]
                    )
                }
            } catch {
                database.close()
                guard (try? PinnedDirectory.childPathIdentity(
                        databaseParent.descriptor,
                        name: databaseURL.lastPathComponent
                      )) == installedIdentity else {
                    throw RestoreError.recoveryRequired(
                        "The absent-destination replacement failed reopen and could not be identity-bound for compensation: \(error.localizedDescription)",
                        artifactURL: backupURL
                    )
                }
                let failedNamespace = try captureRestoreCompletionNamespace(
                    outcome: .committed,
                    at: databaseURL,
                    in: databaseParent
                )
                try quarantineReplacementSidecars(
                    failedNamespace.sidecars,
                    in: databaseParent
                )
                try removeRestoreArtifact(
                    named: databaseURL.lastPathComponent,
                    expected: installedIdentity,
                    expectedSHA256: sha256(finalUse.data),
                    in: databaseParent
                )
                try removeQuarantinedReplacementSidecars(
                    failedNamespace.sidecars,
                    in: databaseParent
                )
                try removeRestoreArtifact(
                    named: hiddenName,
                    expected: hiddenIdentity,
                    expectedSHA256: sha256(finalUse.data),
                    in: databaseParent
                )
                guard fsync(databaseParent.descriptor) == 0 else {
                    throw RestoreError.recoveryRequired(
                        "The absent destination was restored, but compensation durability is uncertain.",
                        artifactURL: backupURL
                    )
                }
                try clearRestoreStagingIntent(in: databaseParent)
                throw RestoreError.recoveredFailure(error.localizedDescription)
            }
        } else {
            let inspection = try DatabaseStartupPreflight
                .establishExistingDatabaseHealth(at: databaseURL)
            inspection.close()
        }
        let completion = try captureRestoreCompletionNamespace(
            outcome: .committed,
            at: databaseURL,
            in: databaseParent
        )
        guard completion.database.identity == publishedIntent.installedIdentity,
              completion.database.sha256 == publishedIntent.databaseSHA256 else {
            throw RestoreError.recoveryRequired(
                "The reopened absent destination no longer matches its installed transaction capability.",
                artifactURL: backupURL
            )
        }
        let completedIntent = RestoreStagingIntent(
            version: publishedIntent.version,
            authority: publishedIntent.authority,
            mode: publishedIntent.mode,
            phase: .completed,
            databaseName: publishedIntent.databaseName,
            stagingName: publishedIntent.stagingName,
            databaseSHA256: publishedIntent.databaseSHA256,
            stagingIdentity: publishedIntent.stagingIdentity,
            installedIdentity: publishedIntent.installedIdentity,
            completion: completion
        )
        try saveRestoreStagingIntent(completedIntent, in: databaseParent)
        try namespaceAuthority.validate(for: databaseURL)
        try databaseParent.validatePath()
        let cleanupUse = try retainedUse.finalDatabaseData(service: self)
        guard cleanupUse.data == finalUse.data else {
            throw RestoreError.recoveryRequired(
                "The exact restore source changed before absent-destination staging cleanup.",
                artifactURL: backupURL
            )
        }
        finalUse = cleanupUse
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: databaseParent)
        try removeRestoreArtifact(
            named: hiddenName,
            expected: hiddenIdentity,
            expectedSHA256: sha256(finalUse.data),
            in: databaseParent
        )
        guard fsync(databaseParent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The new destination reopened, but staging cleanup durability is uncertain.",
                artifactURL: backupURL
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: completion.database,
            expectedSidecars: completion.sidecars,
            in: databaseParent
        )
        try namespaceAuthority.validate(for: databaseURL)
        try databaseParent.validatePath()
        let receiptUse = try retainedUse.finalDatabaseData(service: self)
        guard receiptUse.data == finalUse.data,
              receiptUse.reference.currentURL() != nil else {
            throw RestoreError.recoveryRequired(
                "The absent-destination source capability changed before receipt construction.",
                artifactURL: backupURL
            )
        }
        try clearRestoreStagingIntent(in: databaseParent)
        finalUse = receiptUse
        let restoredBackup = SQLiteBackupInfo(
            kind: retainedUse.kind,
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
        lineageIdentifier: String,
        membershipObservation: PinnedPackage.MembershipObservation = .pathAndDescriptor
    ) throws -> QualifiedBackupArtifact {
        func object(_ identity: FileIdentity) -> QualifiedBackupArtifact.Object {
            QualifiedBackupArtifact.Object(
                device: identity.device,
                inode: identity.inode,
                generation: identity.generation,
                type: identity.fileType,
                linkCount: identity.fileType == S_IFDIR ? 0 : identity.linkCount,
                byteSize: identity.fileType == S_IFDIR ? 0 : identity.byteSize,
                modifiedSeconds: 0,
                modifiedNanoseconds: 0,
                changedSeconds: 0,
                changedNanoseconds: 0
            )
        }
        func object(_ descriptor: Int32) throws -> QualifiedBackupArtifact.Object {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else {
                throw BackupError.verification(
                    "A qualified receipt member lost descriptor metadata."
                )
            }
            return QualifiedBackupArtifact.Object(
                device: value.st_dev,
                inode: value.st_ino,
                generation: value.st_gen,
                type: value.st_mode & S_IFMT,
                linkCount: value.st_nlink,
                byteSize: value.st_size,
                modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
                modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                changedSeconds: Int64(value.st_ctimespec.tv_sec),
                changedNanoseconds: Int64(value.st_ctimespec.tv_nsec)
            )
        }
        let packageURL = policyDirectory.url.appendingPathComponent(
            packageName,
            isDirectory: true
        )
        let pinned = try PinnedPackage(
            childNamed: packageName,
            at: packageURL,
            in: policyDirectory,
            requiredNames: package.identity.childrenByName.keys.sorted(),
            fileManager: fileManager,
            membershipObservation: membershipObservation
        )
        guard pinned.identity == package.identity,
              try pinned.fingerprint() == package.fingerprint else {
            throw BackupError.verification(
                "The qualified receipt package changed before its descriptor metadata snapshot."
            )
        }
        var childObjects: [String: QualifiedBackupArtifact.Object] = [:]
        for name in package.identity.childrenByName.keys.sorted() {
            childObjects[name] = try object(pinned.descriptor(for: name))
        }
        try pinned.validateUnchanged()
        return QualifiedBackupArtifact(
            policyURL: policyDirectory.url,
            policy: object(try policyDirectory.currentIdentity()),
            packageName: packageName,
            package: object(package.identity.directory),
            childrenByName: childObjects,
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
        expectedLineage: String? = nil,
        membershipObservation: PinnedPackage.MembershipObservation = .pathAndDescriptor
    ) throws -> VerifiedPackage {
        let requiredNames = [databaseFilename, manifestFilename].sorted()
        let package = try PinnedPackage(
            childNamed: name,
            at: packageURL,
            in: parent,
            requiredNames: requiredNames,
            fileManager: fileManager,
            membershipObservation: membershipObservation
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
            manifestData = try package.data(
                for: manifestFilename,
                maximumBytes: Self.retentionMaximumManifestBytes
            )
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

        let databaseData = try package.data(
            for: databaseFilename,
            maximumBytes: maximumDescriptorReadBytes
        )
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
        guard ["rolling", "preflight"].contains(policyURL.lastPathComponent),
              policyURL.deletingLastPathComponent().lastPathComponent == "sqlite",
              policyURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                == "backups" else { return nil }
        return try existingPolicyDirectory(at: policyURL)
    }

    private func verifyLegacyRawBackup(at url: URL) -> BackupVerification {
        let pinned: (parent: PinnedDirectory, descriptor: Int32, identity: FileIdentity)
        do {
            pinned = try pinnedStandaloneRegularFile(at: url)
        } catch {
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
        defer { Darwin.close(pinned.descriptor) }
        do {
            let before = try data(from: pinned.descriptor, artifactName: url.lastPathComponent)
            let database = try verifySQLiteDatabase(data: before, descriptor: pinned.descriptor)
            let after = try data(from: pinned.descriptor, artifactName: url.lastPathComponent)
            guard before == after,
                  try PinnedPackage.descriptorIdentity(pinned.descriptor) == pinned.identity,
                  try PinnedDirectory.childPathIdentity(
                    pinned.parent.descriptor,
                    name: url.lastPathComponent
                  ) == pinned.identity else {
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
        let pinned = try pinnedStandaloneRegularFile(at: url)
        defer { Darwin.close(pinned.descriptor) }
        let data = try self.data(from: pinned.descriptor, artifactName: url.lastPathComponent)
        guard !data.isEmpty else {
            throw BackupError.verification("The staged database is empty.")
        }
        guard try PinnedDirectory.childPathIdentity(
            pinned.parent.descriptor,
            name: url.lastPathComponent
        ) == pinned.identity else {
            throw BackupError.verification("The staged database changed during its bounded read.")
        }
        return try verifySQLiteDatabase(data: data, descriptor: pinned.descriptor)
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
            let pinned: (parent: PinnedDirectory, descriptor: Int32, identity: FileIdentity)
            do {
                pinned = try pinnedStandaloneRegularFile(at: backupURL)
            } catch {
                throw RestoreError.missingBackup(backupURL)
            }
            defer { Darwin.close(pinned.descriptor) }
            let before = try data(from: pinned.descriptor, artifactName: backupURL.lastPathComponent)
            let database = try verifySQLiteDatabase(data: before, descriptor: pinned.descriptor)
            let after = try data(from: pinned.descriptor, artifactName: backupURL.lastPathComponent)
            guard allowLegacyRecovery,
                  !database.sha256.isEmpty,
                  before == after,
                  try PinnedPackage.descriptorIdentity(pinned.descriptor) == pinned.identity,
                  try PinnedDirectory.childPathIdentity(
                    pinned.parent.descriptor,
                    name: backupURL.lastPathComponent
                  ) == pinned.identity else {
                throw RestoreError.unhealthyBackup(
                    backupURL,
                    messages: ["The raw legacy recovery occupant changed at the final use boundary."]
                )
            }
            guard let reference = RetainedPathReference(
                url: backupURL,
                expectedFile: pinned.identity,
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
                fileManager: fileManager,
                membershipObservation: .descriptorOnly
            )
        } else {
            package = try PinnedPackage(
                packageURL: backupURL,
                requiredNames: [databaseFilename, manifestFilename].sorted(),
                fileManager: fileManager
            )
        }
        let verified = try qualifyRestorePackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: expectedLineage,
            policyDirectory: policyDirectory,
            backupURL: backupURL
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
        let databaseData = try package.data(
            for: databaseFilename,
            maximumBytes: maximumDescriptorReadBytes
        )
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
        expectedKind: SQLiteBackupInfo.Kind?,
        expectedLineage: String?,
        legacyDestinationURL: URL,
        destinationExists: Bool = true,
        namespaceAuthority: DatabaseStartupLock? = nil
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
            let pinned: (parent: PinnedDirectory, descriptor: Int32, identity: FileIdentity)
            do {
                pinned = try pinnedStandaloneRegularFile(at: backupURL)
            } catch {
                throw RestoreError.missingBackup(backupURL)
            }
            do {
                guard try PinnedDirectory.childPathIdentity(
                    pinned.parent.descriptor,
                    name: backupURL.lastPathComponent
                ) == pinned.identity else {
                    throw RestoreError.unhealthyBackup(
                        backupURL,
                        messages: ["The raw legacy recovery path changed while it was pinned."]
                    )
                }
                let bytes = try data(from: pinned.descriptor, artifactName: backupURL.lastPathComponent)
                let database = try verifySQLiteDatabase(data: bytes, descriptor: pinned.descriptor)
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
                        parent: pinned.parent,
                        descriptor: pinned.descriptor,
                        identity: pinned.identity,
                        verification: verification
                    )
                )
            } catch {
                Darwin.close(pinned.descriptor)
                throw error
            }
        }

        let policyDirectory = try recognizedPolicyDirectory(for: backupURL)
        let authorityLease: PolicyLease?
        if let authority = policyDirectory?.authorityDirectory,
           namespaceAuthority?.coversDirectory(
                device: authority.identity.device,
                inode: authority.identity.inode,
                generation: authority.identity.generation
           ) == true {
            authorityLease = nil
        } else {
            authorityLease = try policyDirectory.map {
                try PolicyLease(policyDirectory: $0, exclusive: false)
            }
        }
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
        let isOwnedRollbackPolicy = policyDirectory?.url.lastPathComponent == "preflight"
        let verified = try qualifyRestorePackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: isOwnedRollbackPolicy ? nil : expectedLineage,
            policyDirectory: policyDirectory,
            backupURL: backupURL,
            allowRecordedLineageWithoutCurrentSource: !destinationExists
        )
        if isOwnedRollbackPolicy,
           verified.sourceDatabaseFilename != legacyDestinationURL.lastPathComponent {
            throw RestoreError.unhealthyBackup(
                backupURL,
                messages: ["The owned rollback package source filename does not match the restore destination."]
            )
        }
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
                packageName: policyDirectory == nil ? nil : backupURL.lastPathComponent,
                authorityLease: authorityLease
            )
        )
    }

    private func requireSupportedPackagePolicy(
        for verified: VerifiedPackage,
        policyDirectory: PinnedDirectory?,
        backupURL: URL,
        requireVisibleSelector: Bool = false
    ) throws {
        _ = requireVisibleSelector
        guard verified.verification.state != .verified
                || (policyDirectory != nil
                    && isGeneratedPackageSlotName(backupURL.lastPathComponent)) else {
            throw BackupError.verification(
                "The current v2 package at \(backupURL.path) must remain a visible generated child of a recognized Cider policy directory with exact ownership-ledger proof."
            )
        }
    }

    /// The sole current-v2 restore qualifier. Listing/direct verification,
    /// URL and capability materialization, CLI selection, live restore, and
    /// receipt revalidation all reach this policy before bytes are usable.
    private func qualifyRestorePackage(
        _ package: PinnedPackage,
        expectedKind: SQLiteBackupInfo.Kind?,
        expectedLineage: String?,
        policyDirectory: PinnedDirectory?,
        backupURL: URL,
        allowRecordedLineageWithoutCurrentSource: Bool = false
    ) throws -> VerifiedPackage {
        let isPreflight = policyDirectory?.url.lastPathComponent == "preflight"
        let verified = try verifyPinnedPackage(
            package,
            expectedKind: expectedKind,
            expectedLineage: isPreflight ? nil : expectedLineage,
            allowRecordedLineageWithoutCurrentSource:
                isPreflight || allowRecordedLineageWithoutCurrentSource
        )
        try requireSupportedPackagePolicy(
            for: verified,
            policyDirectory: policyDirectory,
            backupURL: backupURL,
            requireVisibleSelector: true
        )
        if verified.verification.state == .verified {
            guard let policyDirectory,
                  isGeneratedPackageSlotName(backupURL.lastPathComponent),
                  backupURL.deletingLastPathComponent().standardizedFileURL
                    == policyDirectory.url.standardizedFileURL else {
                throw BackupError.verification(
                    "The current-v2 restore package is outside its exact generated policy member."
                )
            }
            try requireGeneratedVisiblePackageOwnership(
                package,
                named: backupURL.lastPathComponent,
                in: policyDirectory,
                lineageIdentifier: verified.lineageIdentifier
            )
        }
        return verified
    }

    private func restoreJournalName(for databaseURL: URL) -> String {
        let token = String(sha256(Data(databaseURL.lastPathComponent.utf8)).prefix(16))
        return ".cid851-restore-\(token).json"
    }

    private func pinnedRestoreParent(
        for databaseURL: URL,
        authority: DatabaseStartupLock
    ) throws -> PinnedDirectory {
        let descriptor = try authority.duplicateParentDescriptor(for: databaseURL)
        let parent = try PinnedDirectory(
            lockedParentURL: databaseURL.deletingLastPathComponent(),
            duplicatedAuthorityDescriptor: descriptor,
            fileManager: fileManager
        )
        guard authority.coversDirectory(
            device: parent.identity.device,
            inode: parent.identity.inode,
            generation: parent.identity.generation
        ) else {
            throw RestoreError.recoveryRequired(
                "The pinned restore directory is not the exact descriptor protected by the held namespace authority.",
                artifactURL: nil
            )
        }
        return parent
    }

    private func xattrData(named name: String, descriptor: Int32) throws -> Data? {
        let size = fgetxattr(descriptor, name, nil, 0, 0, 0)
        if size < 0 {
            guard errno == ENOATTR else {
                throw RestoreError.recoveryRequired(
                    "A restore capability xattr could not be inspected.",
                    artifactURL: nil
                )
            }
            return nil
        }
        guard size > 0, size <= 64 * 1_024 else {
            throw RestoreError.recoveryRequired(
                "A restore capability xattr has an invalid byte length.",
                artifactURL: nil
            )
        }
        var bytes = Data(count: size)
        let read = bytes.withUnsafeMutableBytes { buffer in
            fgetxattr(descriptor, name, buffer.baseAddress, buffer.count, 0, 0)
        }
        guard read == size else {
            throw RestoreError.recoveryRequired(
                "A restore capability xattr changed during its exact read.",
                artifactURL: nil
            )
        }
        return bytes
    }

    private func restoreSourceNamespace(
        from source: RestoreSourceUse
    ) throws -> RestoreV2SourceNamespace {
        switch source.storage {
        case .package(
            let package,
            let verified,
            let policyDirectory,
            _,
            let authorityLease
        ):
            _ = authorityLease
            try package.validateUnchanged()
            let fingerprint = try package.fingerprint()
            let currentV2 = verified.verification.state == .verified
            let policyIdentity = try policyDirectory.map {
                RestorePersistedIdentity(try $0.currentIdentity())
            }
            let ledgerData = try policyDirectory.flatMap {
                try xattrData(
                    named: ownershipLedgerAttribute,
                    descriptor: $0.authorityDirectory.descriptor
                )
            }
            let members = verified.identity.childrenByName.keys.sorted().map { name in
                RestoreJournalArtifact(
                    originalName: name,
                    retainedName: name,
                    identity: RestorePersistedIdentity(verified.identity.childrenByName[name]!),
                    sha256: fingerprint.contentSHA256ByName[name]!
                )
            }
            return RestoreV2SourceNamespace(
                kind: currentV2 ? .currentV2 : .legacyPackage,
                sourcePath: source.url.path,
                selector: source.url.lastPathComponent,
                policyPath: policyDirectory?.url.path,
                policyIdentity: policyIdentity,
                packageIdentity: RestorePersistedIdentity(verified.identity.directory),
                lineageIdentifier: verified.lineageIdentifier.isEmpty
                    ? nil
                    : verified.lineageIdentifier,
                ownershipNonce: currentV2 ? package.ownershipNonce() : nil,
                ownershipLedgerSHA256: currentV2 ? ledgerData.map(sha256) : nil,
                members: members,
                recoveryEligible: verified.verification.isRecoveryEligible
            )
        case .raw(_, let descriptor, let identity, let verification):
            let bytes = try data(from: descriptor, artifactName: source.url.lastPathComponent)
            return RestoreV2SourceNamespace(
                kind: .legacyRaw,
                sourcePath: source.url.path,
                selector: source.url.lastPathComponent,
                policyPath: nil,
                policyIdentity: nil,
                packageIdentity: RestorePersistedIdentity(identity),
                lineageIdentifier: nil,
                ownershipNonce: nil,
                ownershipLedgerSHA256: nil,
                members: [RestoreJournalArtifact(
                    originalName: source.url.lastPathComponent,
                    retainedName: source.url.lastPathComponent,
                    identity: RestorePersistedIdentity(identity),
                    sha256: sha256(bytes)
                )],
                recoveryEligible: verification.isRecoveryEligible
            )
        }
    }

    private func requireRestoreSourceCapability(
        _ expected: RestoreV2SourceNamespace,
        source: RestoreSourceUse? = nil,
        databaseURL: URL,
        namespaceAuthority: DatabaseStartupLock? = nil
    ) throws {
        do {
            if let source {
                _ = try source.finalDatabaseData(service: self)
                guard try restoreSourceNamespace(from: source) == expected else {
                    throw RestoreError.recoveryRequired(
                        "The restore source namespace changed identity, bytes, ownership, or policy eligibility.",
                        artifactURL: nil
                    )
                }
                return
            }
            let sourceURL = URL(fileURLWithPath: expected.sourcePath)
            let currentUse = try pinRestoreSource(
                at: sourceURL,
                expectedKind: nil,
                expectedLineage: expected.kind == .currentV2
                    ? expected.lineageIdentifier
                    : nil,
                legacyDestinationURL: databaseURL,
                destinationExists: expected.kind != .legacyRaw
                    || FileManager.default.fileExists(atPath: databaseURL.path),
                namespaceAuthority: namespaceAuthority
            )
            guard try restoreSourceNamespace(from: currentUse) == expected else {
                throw RestoreError.recoveryRequired(
                    "The reachable restore source no longer matches the complete durable source namespace.",
                    artifactURL: nil
                )
            }
        } catch let error as RestoreError {
            throw error
        } catch {
            throw RestoreError.recoveryRequired(
                "The restore source capability could not be revalidated: \(error.localizedDescription)",
                artifactURL: nil
            )
        }
    }

    private func validRestoreV2State(
        _ state: RestoreV2TransactionState,
        databaseURL: URL,
        parent: PinnedDirectory
    ) -> Bool {
        let id = state.transactionID
        guard state.version == RestoreV2TransactionState.currentVersion,
              UUID(uuidString: id) != nil,
              id == id.lowercased(),
              state.authority == OwnershipLedgerIdentity(parent.identity),
              state.databaseName == databaseURL.lastPathComponent,
              isSafeRestoreMemberName(state.databaseName),
              state.stagingName == restoreV2StagingName,
              state.originalDatabaseRetainedName == restoreV2OriginalDatabaseName,
              state.originalWALRetainedName == restoreV2OriginalWALName,
              state.originalSHMRetainedName == restoreV2OriginalSHMName,
              state.replacementWALRetainedName == restoreV2ReplacementWALName,
              state.replacementSHMRetainedName == restoreV2ReplacementSHMName,
              state.cleanupOriginalDatabaseRetainedName == restoreV2CleanupOriginalDatabaseName,
              state.cleanupOriginalWALRetainedName == restoreV2CleanupOriginalWALName,
              state.cleanupOriginalSHMRetainedName == restoreV2CleanupOriginalSHMName,
              state.cleanupStagedDatabaseRetainedName == restoreV2CleanupStagedDatabaseName,
              state.cleanupReplacementDatabaseRetainedName == restoreV2CleanupReplacementDatabaseName,
              state.cleanupReplacementWALRetainedName == restoreV2CleanupReplacementWALName,
              state.cleanupReplacementSHMRetainedName == restoreV2CleanupReplacementSHMName,
              state.source.recoveryEligible,
              !state.source.sourcePath.isEmpty,
              !state.source.selector.isEmpty,
              state.source.members.allSatisfy(validRestoreArtifact) else { return false }

        let transactionNames = [
            state.databaseName,
            state.databaseName + "-wal",
            state.databaseName + "-shm",
            state.stagingName,
            state.originalDatabaseRetainedName,
            state.originalWALRetainedName,
            state.originalSHMRetainedName,
            state.replacementWALRetainedName,
            state.replacementSHMRetainedName,
            state.cleanupOriginalDatabaseRetainedName,
            state.cleanupOriginalWALRetainedName,
            state.cleanupOriginalSHMRetainedName,
            state.cleanupStagedDatabaseRetainedName,
            state.cleanupReplacementDatabaseRetainedName,
            state.cleanupReplacementWALRetainedName,
            state.cleanupReplacementSHMRetainedName,
        ]
        guard Set(transactionNames).count == transactionNames.count,
              transactionNames.allSatisfy(isSafeRestoreMemberName) else { return false }

        guard Set(state.source.members.map(\.originalName)).count == state.source.members.count,
              Set(state.source.members.map(\.retainedName)).count == state.source.members.count,
              state.source.members.allSatisfy({ $0.originalName == $0.retainedName }),
              Set(transactionNames + state.source.members.map(\.originalName)).count
                == transactionNames.count + state.source.members.count else {
            return false
        }
        if state.source.kind == .currentV2 {
            guard let policyPath = state.source.policyPath,
                  state.source.policyIdentity != nil,
                  state.source.lineageIdentifier.map(isLowercaseSHA256) == true,
                  state.source.ownershipNonce?.isEmpty == false,
                  state.source.ownershipLedgerSHA256.map(isLowercaseSHA256) == true,
                  isGeneratedPackageSlotName(state.source.selector),
                  URL(fileURLWithPath: policyPath)
                    .appendingPathComponent(state.source.selector, isDirectory: true).path
                    == state.source.sourcePath,
                  Set(state.source.members.map(\.originalName))
                    == Set([databaseFilename, manifestFilename]) else { return false }
        } else if state.source.kind == .legacyRaw {
            guard state.source.policyPath == nil,
                  state.source.policyIdentity == nil,
                  state.source.ownershipNonce == nil,
                  state.source.ownershipLedgerSHA256 == nil,
                  state.source.members.count == 1,
                  state.source.members[0].originalName == state.source.selector,
                  URL(fileURLWithPath: state.source.sourcePath).lastPathComponent
                    == state.source.selector else { return false }
        }

        if let recoveryPath = state.recoveryArtifactPath {
            let recoveryURL = URL(fileURLWithPath: recoveryPath)
            guard recoveryURL.path == recoveryPath,
                  recoveryURL.pathExtension.lowercased() == packageExtension else { return false }
        }

        var identityRoles: [OwnershipLedgerIdentity: String] = [:]
        func register(_ artifact: RestoreJournalArtifact, role: String) -> Bool {
            guard validRestoreArtifact(artifact) else { return false }
            let key = artifact.identity.ownershipIdentity
            if let existing = identityRoles[key] { return existing == role }
            identityRoles[key] = role
            return true
        }
        for member in state.source.members {
            guard register(member, role: "source:\(member.originalName)") else { return false }
        }

        func artifact(
            _ value: RestoreJournalArtifact?,
            originalName: String,
            retainedName: String,
            role: String
        ) -> Bool {
            guard let value else { return true }
            return value.originalName == originalName
                && value.retainedName == retainedName
                && register(value, role: role)
        }
        func namespace(
            _ value: RestoreV2Namespace,
            databaseRetainedName: String,
            walRetainedName: String,
            shmRetainedName: String,
            databaseRole: String,
            walRole: String,
            shmRole: String
        ) -> Bool {
            artifact(
                value.database,
                originalName: state.databaseName,
                retainedName: databaseRetainedName,
                role: databaseRole
            ) && artifact(
                value.wal,
                originalName: state.databaseName + "-wal",
                retainedName: walRetainedName,
                role: walRole
            ) && artifact(
                value.shm,
                originalName: state.databaseName + "-shm",
                retainedName: shmRetainedName,
                role: shmRole
            )
        }

        guard namespace(
            state.initialNamespace,
            databaseRetainedName: state.originalDatabaseRetainedName,
            walRetainedName: state.originalWALRetainedName,
            shmRetainedName: state.originalSHMRetainedName,
            databaseRole: "original-database",
            walRole: "original-wal",
            shmRole: "original-shm"
        ), artifact(
            state.stagedDatabase,
            originalName: state.databaseName,
            retainedName: state.stagingName,
            role: "replacement-staged"
        ) else { return false }

        if let published = state.publishedNamespace {
            let publishedDatabaseRole = state.mode == .existing
                ? "replacement-staged"
                : "replacement-live"
            guard namespace(
                published,
                databaseRetainedName: state.stagingName,
                walRetainedName: state.replacementWALRetainedName,
                shmRetainedName: state.replacementSHMRetainedName,
                databaseRole: publishedDatabaseRole,
                walRole: "replacement-wal",
                shmRole: "replacement-shm"
            ), published.wal == nil, published.shm == nil else { return false }
            if state.mode == .existing, published.database != state.stagedDatabase { return false }
            if state.mode == .absent,
               published.database?.identity.ownershipIdentity
                == state.stagedDatabase?.identity.ownershipIdentity { return false }
        }
        if let reopened = state.reopenedNamespace {
            guard let published = state.publishedNamespace,
                  reopened.database == published.database,
                  namespace(
                    reopened,
                    databaseRetainedName: state.stagingName,
                    walRetainedName: state.replacementWALRetainedName,
                    shmRetainedName: state.replacementSHMRetainedName,
                    databaseRole: state.mode == .existing
                        ? "replacement-staged"
                        : "replacement-live",
                    walRole: "replacement-wal",
                    shmRole: "replacement-shm"
                  ) else { return false }
        }
        if let completed = state.completedNamespace {
            switch state.outcome {
            case .committed:
                guard let reopened = state.reopenedNamespace,
                      completed == reopened,
                      namespace(
                        completed,
                        databaseRetainedName: state.stagingName,
                        walRetainedName: state.replacementWALRetainedName,
                        shmRetainedName: state.replacementSHMRetainedName,
                        databaseRole: state.mode == .existing
                            ? "replacement-staged"
                            : "replacement-live",
                        walRole: "replacement-wal",
                        shmRole: "replacement-shm"
                      ) else { return false }
            case .compensated:
                guard completed == state.initialNamespace,
                      namespace(
                        completed,
                        databaseRetainedName: state.originalDatabaseRetainedName,
                        walRetainedName: state.originalWALRetainedName,
                        shmRetainedName: state.originalSHMRetainedName,
                        databaseRole: "original-database",
                        walRole: "original-wal",
                        shmRole: "original-shm"
                      ) else { return false }
            case nil:
                return false
            }
        }

        // A transaction owns at most one deterministic retained cleanup set.
        // Count every inode that could require preservation before permitting
        // the state transition; completed evidence never grows on restart.
        let cleanupCapacityCandidates = state.initialNamespace.artifacts
            + [state.stagedDatabase].compactMap { $0 }
            + ((state.reopenedNamespace ?? state.publishedNamespace)?.artifacts ?? [])
        guard let cleanupCapacity = restoreV2RetentionCapacity(
            artifacts: cleanupCapacityCandidates
        ), cleanupCapacity.nodes <= 7,
        cleanupCapacity.bytes <= maximumPolicyBytes else { return false }

        switch state.mode {
        case .existing:
            guard state.initialNamespace.database != nil else { return false }
        case .absent:
            guard state.initialNamespace.artifacts.isEmpty else { return false }
        }
        switch state.phase {
        case .planned:
            return state.stagedDatabase == nil
                && state.publishedNamespace == nil
                && state.reopenedNamespace == nil
                && state.completedNamespace == nil
                && state.outcome == nil
        case .staged, .originalsRetained:
            return state.stagedDatabase != nil
                && state.publishedNamespace == nil
                && state.reopenedNamespace == nil
                && state.completedNamespace == nil
                && state.outcome == nil
        case .published:
            return state.stagedDatabase != nil
                && state.publishedNamespace?.database != nil
                && state.publishedNamespace?.wal == nil
                && state.publishedNamespace?.shm == nil
                && state.reopenedNamespace == nil
                && state.completedNamespace == nil
                && state.outcome == nil
        case .reopened:
            return state.stagedDatabase != nil
                && state.publishedNamespace?.database != nil
                && state.reopenedNamespace?.database != nil
                && state.completedNamespace == nil
                && state.outcome == nil
        case .cleaning:
            return state.stagedDatabase != nil
                && state.publishedNamespace?.database != nil
                && state.reopenedNamespace?.database != nil
                && state.completedNamespace == nil
                && state.outcome == .committed
        case .rollingBack:
            return state.stagedDatabase != nil
                && state.outcome == .compensated
                && state.completedNamespace == nil
        case .rolledBack:
            return state.completedNamespace != nil
                && state.outcome == .compensated
        case .completed:
            return state.completedNamespace != nil
                && state.outcome != nil
        }
    }

    private func restoreV2RetentionCapacity(
        artifacts: [RestoreJournalArtifact],
        prospectiveByteSizes: [Int64] = []
    ) -> (nodes: Int, bytes: Int64)? {
        var identities = Set<OwnershipLedgerIdentity>()
        var nodes = 0
        var bytes: Int64 = 0
        func add(byteSize: Int64) -> Bool {
            guard byteSize >= 0 else { return false }
            let (nodeBytes, nodeOverflow) = byteSize.addingReportingOverflow(
                Self.retentionAccountingNodeOverheadBytes
            )
            let (total, totalOverflow) = bytes.addingReportingOverflow(nodeBytes)
            guard !nodeOverflow, !totalOverflow else { return false }
            nodes += 1
            bytes = total
            return true
        }
        for artifact in artifacts
            where identities.insert(artifact.identity.ownershipIdentity).inserted {
            guard add(byteSize: Int64(artifact.identity.byteSize)) else { return nil }
        }
        for byteSize in prospectiveByteSizes {
            guard add(byteSize: byteSize) else { return nil }
        }
        return (nodes, bytes)
    }

    private func requireRestoreV2RetentionCapacity(
        artifacts: [RestoreJournalArtifact],
        prospectiveByteSizes: [Int64] = []
    ) throws {
        guard let capacity = restoreV2RetentionCapacity(
            artifacts: artifacts,
            prospectiveByteSizes: prospectiveByteSizes
        ), capacity.nodes <= 7,
        capacity.bytes <= maximumPolicyBytes else {
            throw RestoreError.recoveryRequired(
                "Restore terminal-evidence retention capacity is exhausted; no new transaction member was created or moved.",
                artifactURL: nil
            )
        }
    }

    private var restoreV2FixedSlotNames: [String] {
        [
            restoreV2StagingName,
            restoreV2OriginalDatabaseName,
            restoreV2OriginalWALName,
            restoreV2OriginalSHMName,
            restoreV2ReplacementWALName,
            restoreV2ReplacementSHMName,
            restoreV2CleanupOriginalDatabaseName,
            restoreV2CleanupOriginalWALName,
            restoreV2CleanupOriginalSHMName,
            restoreV2CleanupStagedDatabaseName,
            restoreV2CleanupReplacementDatabaseName,
            restoreV2CleanupReplacementWALName,
            restoreV2CleanupReplacementSHMName,
        ]
    }

    private var restoreV2FixedSlotRoles: [(role: String, name: String, terminal: Bool)] {
        [
            ("transaction-staging-database", restoreV2StagingName, false),
            ("transit-original-database", restoreV2OriginalDatabaseName, false),
            ("transit-original-wal", restoreV2OriginalWALName, false),
            ("transit-original-shm", restoreV2OriginalSHMName, false),
            ("transit-replacement-wal", restoreV2ReplacementWALName, false),
            ("transit-replacement-shm", restoreV2ReplacementSHMName, false),
            ("terminal-original-database", restoreV2CleanupOriginalDatabaseName, true),
            ("terminal-original-wal", restoreV2CleanupOriginalWALName, true),
            ("terminal-original-shm", restoreV2CleanupOriginalSHMName, true),
            ("terminal-staged-database", restoreV2CleanupStagedDatabaseName, true),
            ("terminal-replacement-database", restoreV2CleanupReplacementDatabaseName, true),
            ("terminal-replacement-wal", restoreV2CleanupReplacementWALName, true),
            ("terminal-replacement-shm", restoreV2CleanupReplacementSHMName, true),
        ]
    }

    private struct RestoreEvidenceObservedMember {
        let identity: FileIdentity
        let type: String
        let digest: String?
        let stableQualifiedRegular: Bool
    }

    private func restoreEvidenceTypeName(_ fileType: mode_t) -> String {
        switch fileType {
        case S_IFREG: "regular-file"
        case S_IFDIR: "directory"
        case S_IFLNK: "symlink"
        case S_IFIFO: "fifo"
        case S_IFSOCK: "socket"
        case S_IFCHR: "character-device"
        case S_IFBLK: "block-device"
        default: "unknown"
        }
    }

    private func observeRestoreEvidenceMember(
        named name: String,
        in parent: PinnedDirectory
    ) throws -> RestoreEvidenceObservedMember? {
        var reachable = stat()
        guard fstatat(parent.descriptor, name, &reachable, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw RestoreError.recoveryRequired(
                "A fixed restore-evidence slot could not be inspected for read-only inventory.",
                artifactURL: nil
            )
        }
        let reachableIdentity = restoreFileIdentity(from: reachable)
        guard reachableIdentity.fileType == S_IFREG else {
            return RestoreEvidenceObservedMember(
                identity: reachableIdentity,
                type: restoreEvidenceTypeName(reachableIdentity.fileType),
                digest: nil,
                stableQualifiedRegular: false
            )
        }
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: name
        )
        guard descriptor >= 0 else {
            return RestoreEvidenceObservedMember(
                identity: reachableIdentity,
                type: "regular-file",
                digest: nil,
                stableQualifiedRegular: false
            )
        }
        defer { Darwin.close(descriptor) }
        let descriptorIdentity = try PinnedPackage.descriptorIdentity(descriptor)
        guard descriptorIdentity == reachableIdentity,
              descriptorIdentity.linkCount == 1,
              descriptorIdentity.byteSize >= 0,
              descriptorIdentity.byteSize <= maximumDescriptorReadBytes else {
            return RestoreEvidenceObservedMember(
                identity: descriptorIdentity,
                type: "regular-file",
                digest: nil,
                stableQualifiedRegular: false
            )
        }
        let bytes = try Self.readBoundedDescriptor(
            descriptor,
            maximumBytes: Int64(descriptorIdentity.byteSize),
            artifactName: name
        )
        guard try PinnedPackage.descriptorIdentity(descriptor) == descriptorIdentity,
              try PinnedDirectory.childPathIdentity(parent.descriptor, name: name)
                == descriptorIdentity else {
            return RestoreEvidenceObservedMember(
                identity: descriptorIdentity,
                type: "regular-file",
                digest: sha256(bytes),
                stableQualifiedRegular: false
            )
        }
        return RestoreEvidenceObservedMember(
            identity: descriptorIdentity,
            type: "regular-file",
            digest: sha256(bytes),
            stableQualifiedRegular: true
        )
    }

    private func restoreEvidenceExpectedByName(
        state: RestoreV2TransactionState?
    ) -> [String: RestoreJournalArtifact] {
        guard let state, state.phase == .completed else { return [:] }
        var result: [String: RestoreJournalArtifact] = [:]
        switch state.outcome {
        case .committed:
            if state.mode == .existing, let original = state.initialNamespace.database {
                result[state.cleanupOriginalDatabaseRetainedName] = original
            } else if let staged = state.stagedDatabase {
                result[state.cleanupStagedDatabaseRetainedName] = staged
            }
            if let wal = state.initialNamespace.wal {
                result[state.cleanupOriginalWALRetainedName] = wal
            }
            if let shm = state.initialNamespace.shm {
                result[state.cleanupOriginalSHMRetainedName] = shm
            }
        case .compensated:
            let replacement = state.reopenedNamespace ?? state.publishedNamespace
            if let database = replacement?.database {
                result[state.cleanupReplacementDatabaseRetainedName] = database
            } else if state.mode == .existing, let staged = state.stagedDatabase {
                result[state.cleanupReplacementDatabaseRetainedName] = staged
            }
            if let wal = replacement?.wal {
                result[state.cleanupReplacementWALRetainedName] = wal
            }
            if let shm = replacement?.shm {
                result[state.cleanupReplacementSHMRetainedName] = shm
            }
            if state.mode == .absent, let staged = state.stagedDatabase {
                result[state.cleanupStagedDatabaseRetainedName] = staged
            }
        case nil:
            break
        }
        return result
    }

    private func restoreEvidenceInventory(
        persisted: (RestoreV2TransactionState, Data)?,
        databaseURL: URL,
        parent: PinnedDirectory
    ) throws -> RestoreEvidenceInventory {
        let state = persisted?.0
        let expectedByName = restoreEvidenceExpectedByName(state: state)
        var members: [RestoreEvidenceMember] = []
        for slot in restoreV2FixedSlotRoles {
            let expected = expectedByName[slot.name]
            let observed = try observeRestoreEvidenceMember(named: slot.name, in: parent)
            let status: RestoreEvidenceMemberStatus
            if let observed {
                if !observed.stableQualifiedRegular {
                    status = observed.identity.fileType == S_IFREG
                        ? .mutated
                        : .specialUnknownOccupant
                } else if let expected,
                          expected.identity.matches(observed.identity),
                          expected.sha256 == observed.digest {
                    status = .presentQualified
                } else if let expected,
                          expected.identity.isSameNode(as: RestorePersistedIdentity(observed.identity)) {
                    status = .mutated
                } else {
                    status = .reoccupied
                }
            } else {
                status = .absent
            }
            let identity = observed.map {
                RestoreEvidenceIdentity(
                    device: UInt64(truncatingIfNeeded: $0.identity.device),
                    inode: UInt64(truncatingIfNeeded: $0.identity.inode),
                    generation: $0.identity.generation
                )
            }
            members.append(RestoreEvidenceMember(
                role: slot.role,
                basename: slot.name,
                policyRelativeLocator: slot.name,
                type: observed?.type ?? "absent",
                identity: identity,
                byteCount: observed.map { Int64($0.identity.byteSize) },
                digest: observed?.digest,
                status: status,
                expectedTerminalMember: expected != nil,
                safeToRemoveOutOfBand: expected != nil && status == .presentQualified
            ))
        }
        let expectedMembers = members.filter(\.expectedTerminalMember)
        let unexpectedOccupied = members.contains {
            !$0.expectedTerminalMember && $0.status != .absent
        }
        let allSlotsAbsent = members.allSatisfy { $0.status == .absent }
        let allExpectedQualified = !expectedMembers.isEmpty
            && expectedMembers.allSatisfy { $0.status == .presentQualified }
        let inventoryState: String
        let recoveryRequired: Bool
        if state == nil {
            inventoryState = allSlotsAbsent ? "fully-cleared" : "reoccupied-without-record"
            recoveryRequired = !allSlotsAbsent
        } else if state?.phase != .completed {
            inventoryState = "active-or-interrupted-transaction"
            recoveryRequired = true
        } else if allExpectedQualified && !unexpectedOccupied {
            inventoryState = "terminal-evidence-qualified"
            recoveryRequired = false
        } else if allSlotsAbsent {
            inventoryState = "operator-cleared-pending-reconciliation"
            recoveryRequired = false
        } else {
            inventoryState = "recovery-required"
            recoveryRequired = true
        }
        return RestoreEvidenceInventory(
            policyRootPath: parent.url.path,
            policyRootIdentity: RestoreEvidenceIdentity(
                device: UInt64(truncatingIfNeeded: parent.identity.device),
                inode: UInt64(truncatingIfNeeded: parent.identity.inode),
                generation: parent.identity.generation
            ),
            transactionID: state?.transactionID,
            recordSHA256: persisted.map { sha256($0.1) },
            recordPresent: persisted != nil,
            recordPhase: state?.phase.rawValue,
            recordOutcome: state?.outcome?.rawValue,
            state: inventoryState,
            recoveryRequired: recoveryRequired,
            members: members,
            procedure: [
                "Stop and quiesce Cider and every cooperating database process.",
                "Inspect this read-only inventory and verify the pinned policy-root and record identities.",
                "Through an operator-controlled out-of-band mechanism, remove only the complete set whose members are currently marked present-qualified and safeToRemoveOutOfBand=true; do not use wildcard deletion.",
                "Do not delete a mutated, reoccupied, special, unknown, or identity-mismatched occupant.",
                "Rerun cider-cli db restore-evidence --json so reconciliation can confirm every fixed slot absent; partial, mutated, or reoccupied sets remain recovery-required.",
            ]
        )
    }

    func terminalRestoreEvidenceInventory(
        at databaseURL: URL
    ) throws -> RestoreEvidenceInventory {
        let authority = try DatabaseStartupLock.acquire(for: databaseURL)
        defer { authority.release() }
        let parent = try pinnedRestoreParent(for: databaseURL, authority: authority)
        let persisted = try restoreV2State(in: parent)
        if let persisted,
           !validRestoreV2State(persisted.0, databaseURL: databaseURL, parent: parent) {
            throw RestoreError.recoveryRequired(
                "The canonical restore record is invalid; the fixed-slot inventory was not treated as safe cleanup guidance.",
                artifactURL: nil
            )
        }
        return try restoreEvidenceInventory(
            persisted: persisted,
            databaseURL: databaseURL,
            parent: parent
        )
    }

    private func requireRestoreV2FixedSlotsAbsent(
        in parent: PinnedDirectory,
        detail: String
    ) throws {
        for name in restoreV2FixedSlotNames {
            var reachable = stat()
            if fstatat(parent.descriptor, name, &reachable, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else {
                    throw RestoreError.recoveryRequired(
                        "\(detail) A fixed restore-evidence slot could not be safely inspected.",
                        artifactURL: nil
                    )
                }
                continue
            }
            // Regular occupants are acquired through the shared nonblocking
            // contract and rebound to the parent-relative name. Special
            // occupants fail the regular gate but remain equally occupied.
            let descriptor = Self.openPinnedRegularChildNonBlocking(
                directoryDescriptor: parent.descriptor,
                name: name
            )
            if descriptor >= 0 {
                defer { Darwin.close(descriptor) }
                let descriptorIdentity = try PinnedPackage.descriptorIdentity(descriptor)
                let reachableIdentity = try PinnedDirectory.childPathIdentity(
                    parent.descriptor,
                    name: name
                )
                guard descriptorIdentity == reachableIdentity else {
                    throw RestoreError.recoveryRequired(
                        "\(detail) A fixed restore-evidence slot changed during pinned inspection; every occupant was preserved.",
                        artifactURL: parent.url.appendingPathComponent(name)
                    )
                }
            }
            throw RestoreError.recoveryRequired(
                "\(detail) Fixed restore-evidence slot \(name) is occupied; no new restore mutation is permitted until the read-only inventory reports the complete set safely cleared.",
                artifactURL: parent.url.appendingPathComponent(name)
            )
        }
    }

    private func canonicalRestoreV2Bytes(
        _ state: RestoreV2TransactionState
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    private func canonicalRestoreV2SourceBytes(
        _ source: RestoreV2SourceNamespace
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(source)
    }

    private func restoreReceiptSourceURL(
        _ currentURL: URL,
        expectedCapabilityData: Data,
        databaseURL: URL
    ) -> URL? {
        do {
            let expected = try JSONDecoder().decode(
                RestoreV2SourceNamespace.self,
                from: expectedCapabilityData
            )
            guard try canonicalRestoreV2SourceBytes(expected) == expectedCapabilityData,
                  expected.kind == .currentV2,
                  expected.sourcePath == currentURL.path,
                  expected.recoveryEligible,
                  expected.lineageIdentifier.map(isLowercaseSHA256) == true else {
                return nil
            }
            let source = try pinRestoreSource(
                at: currentURL,
                expectedKind: nil,
                expectedLineage: expected.lineageIdentifier,
                legacyDestinationURL: databaseURL,
                destinationExists: true
            )
            _ = try source.finalDatabaseData(service: self)
            guard source.verification.isRecoveryEligible,
                  try restoreSourceNamespace(from: source) == expected else { return nil }
            return currentURL
        } catch {
            return nil
        }
    }

    private func restoreV2State(in parent: PinnedDirectory) throws -> (RestoreV2TransactionState, Data)? {
        guard let bytes = try xattrData(
            named: restoreTransactionAttribute,
            descriptor: parent.descriptor
        ) else { return nil }
        let decoded = try JSONDecoder().decode(RestoreV2TransactionState.self, from: bytes)
        guard try canonicalRestoreV2Bytes(decoded) == bytes else {
            throw RestoreError.recoveryRequired(
                "The canonical restore transaction bytes are not an exact canonical encoding.",
                artifactURL: nil
            )
        }
        return (decoded, bytes)
    }

    private func requireRestoreV2Capability(
        _ transaction: RestoreV2Transaction,
        sourceRequired: Bool = true
    ) throws {
        try transaction.authority.validate(for: transaction.databaseURL)
        try transaction.parent.validatePath()
        guard transaction.authority.coversDirectory(
            device: transaction.parent.identity.device,
            inode: transaction.parent.identity.inode,
            generation: transaction.parent.identity.generation
        ), let current = try restoreV2State(in: transaction.parent),
        current.0 == transaction.state,
        current.1 == transaction.canonicalBytes,
        validRestoreV2State(
            current.0,
            databaseURL: transaction.databaseURL,
            parent: transaction.parent
        ) else {
            throw RestoreError.recoveryRequired(
                "The held restore transaction lost its locked directory or exact canonical state capability.",
                artifactURL: nil
            )
        }
        if sourceRequired {
            try transaction.sourceCapabilityValidator()
        }
    }

    private func publishRestoreV2State(
        _ next: RestoreV2TransactionState,
        transaction: RestoreV2Transaction,
        creating: Bool = false
    ) throws {
        if creating {
            try transaction.authority.validate(for: transaction.databaseURL)
            try transaction.parent.validatePath()
            try transaction.sourceCapabilityValidator()
            guard try restoreV2State(in: transaction.parent) == nil else {
                throw RestoreError.recoveryRequired(
                    "A canonical restore transaction is already active.",
                    artifactURL: nil
                )
            }
            try requireRestoreV2FixedSlotsAbsent(
                in: transaction.parent,
                detail: "Restore intent publication refused."
            )
        } else {
            try requireRestoreV2Capability(transaction)
        }
        guard validRestoreV2State(
            next,
            databaseURL: transaction.databaseURL,
            parent: transaction.parent
        ) else {
            throw RestoreError.recoveryRequired(
                "The next canonical restore transaction state is invalid.",
                artifactURL: nil
            )
        }
        let bytes = try canonicalRestoreV2Bytes(next)
        let result = bytes.withUnsafeBytes { buffer in
            fsetxattr(
                transaction.parent.descriptor,
                restoreTransactionAttribute,
                buffer.baseAddress,
                buffer.count,
                0,
                creating ? XATTR_CREATE : XATTR_REPLACE
            )
        }
        guard result == 0, fsync(transaction.parent.descriptor) == 0,
              let current = try restoreV2State(in: transaction.parent),
              current.0 == next,
              current.1 == bytes else {
            throw RestoreError.recoveryRequired(
                "The canonical restore transaction transition was not durably recorded and verified.",
                artifactURL: nil
            )
        }
        transaction.state = next
        transaction.canonicalBytes = bytes
        try requireRestoreV2Capability(transaction)
    }

    private func removeRestoreV2Record(
        transaction: RestoreV2Transaction,
        sourceRequired: Bool = true,
        requireClearedFixedSlots: Bool = false
    ) throws {
        try requireRestoreV2Capability(transaction, sourceRequired: sourceRequired)
        if requireClearedFixedSlots {
            try requireRestoreV2FixedSlotsAbsent(
                in: transaction.parent,
                detail: "Completed-record removal refused."
            )
        }
        guard fremovexattr(
            transaction.parent.descriptor,
            restoreTransactionAttribute,
            0
        ) == 0,
        fsync(transaction.parent.descriptor) == 0,
        try xattrData(
            named: restoreTransactionAttribute,
            descriptor: transaction.parent.descriptor
        ) == nil else {
            throw RestoreError.recoveryRequired(
                "The canonical restore transaction record could not be removed durably.",
                artifactURL: nil
            )
        }
        if requireClearedFixedSlots {
            do {
                try requireRestoreV2FixedSlotsAbsent(
                    in: transaction.parent,
                    detail: "Completed-record removal detected reoccupation."
                )
            } catch {
                let republished = transaction.canonicalBytes.withUnsafeBytes { buffer in
                    fsetxattr(
                        transaction.parent.descriptor,
                        restoreTransactionAttribute,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        XATTR_CREATE
                    )
                }
                guard republished == 0,
                      fsync(transaction.parent.descriptor) == 0,
                      let current = try restoreV2State(in: transaction.parent),
                      current.0 == transaction.state,
                      current.1 == transaction.canonicalBytes else {
                    throw RestoreError.recoveryRequired(
                        "A fixed evidence slot was reoccupied during completed-record removal. The occupant was preserved and future admission remains blocked, but durable record republication could not be proven.",
                        artifactURL: nil
                    )
                }
                throw error
            }
        }
    }

    private func restoreV2Artifact(
        named name: String,
        retainedName: String,
        in parent: PinnedDirectory
    ) throws -> RestoreJournalArtifact? {
        guard let observation = try restoreArtifactObservation(named: name, in: parent) else {
            return nil
        }
        return RestoreJournalArtifact(
            originalName: name,
            retainedName: retainedName,
            identity: RestorePersistedIdentity(observation.identity),
            sha256: observation.sha256
        )
    }

    private func observeRestoreV2Namespace(
        transaction: RestoreV2Transaction,
        databaseRetainedName: String,
        walRetainedName: String,
        shmRetainedName: String
    ) throws -> RestoreV2Namespace {
        try requireRestoreV2Capability(transaction)
        let databaseName = transaction.state.databaseName
        let namespace = RestoreV2Namespace(
            database: try restoreV2Artifact(
                named: databaseName,
                retainedName: databaseRetainedName,
                in: transaction.parent
            ),
            wal: try restoreV2Artifact(
                named: databaseName + "-wal",
                retainedName: walRetainedName,
                in: transaction.parent
            ),
            shm: try restoreV2Artifact(
                named: databaseName + "-shm",
                retainedName: shmRetainedName,
                in: transaction.parent
            )
        )
        try requireRestoreV2Capability(transaction)
        return namespace
    }

    private func observeRestoreV2Namespace(
        databaseURL: URL,
        parent: PinnedDirectory,
        databaseRetainedName: String,
        walRetainedName: String,
        shmRetainedName: String
    ) throws -> RestoreV2Namespace {
        RestoreV2Namespace(
            database: try restoreV2Artifact(
                named: databaseURL.lastPathComponent,
                retainedName: databaseRetainedName,
                in: parent
            ),
            wal: try restoreV2Artifact(
                named: databaseURL.lastPathComponent + "-wal",
                retainedName: walRetainedName,
                in: parent
            ),
            shm: try restoreV2Artifact(
                named: databaseURL.lastPathComponent + "-shm",
                retainedName: shmRetainedName,
                in: parent
            )
        )
    }

    private func requireRestoreV2Namespace(
        _ expected: RestoreV2Namespace,
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        let current = try observeRestoreV2Namespace(
            transaction: transaction,
            databaseRetainedName: expected.database?.retainedName
                ?? transaction.state.stagingName,
            walRetainedName: expected.wal?.retainedName
                ?? transaction.state.replacementWALRetainedName,
            shmRetainedName: expected.shm?.retainedName
                ?? transaction.state.replacementSHMRetainedName
        )
        guard current == expected else {
            throw RestoreError.recoveryRequired(
                "The complete live DB/WAL/SHM namespace changed from its durable transaction state.",
                artifactURL: nil
            )
        }
    }

    private func syncRestoreV2Directory(
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        guard fsync(transaction.parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "A restore namespace directory durability point failed.",
                artifactURL: nil
            )
        }
        try requireRestoreV2Capability(transaction)
    }

    private func pinRestoreV2Member(
        _ artifact: RestoreJournalArtifact,
        named name: String,
        transaction: RestoreV2Transaction
    ) throws -> RestoreV2PinnedMember {
        let state = transaction.state
        let generatedNames = Set([
            state.databaseName,
            state.databaseName + "-wal",
            state.databaseName + "-shm",
            state.stagingName,
            state.originalDatabaseRetainedName,
            state.originalWALRetainedName,
            state.originalSHMRetainedName,
            state.replacementWALRetainedName,
            state.replacementSHMRetainedName,
            state.cleanupOriginalDatabaseRetainedName,
            state.cleanupOriginalWALRetainedName,
            state.cleanupOriginalSHMRetainedName,
            state.cleanupStagedDatabaseRetainedName,
            state.cleanupReplacementDatabaseRetainedName,
            state.cleanupReplacementWALRetainedName,
            state.cleanupReplacementSHMRetainedName,
        ])
        guard generatedNames.contains(name) else {
            throw RestoreError.recoveryRequired(
                "A restore mutation requested a name outside the validated transaction graph.",
                artifactURL: nil
            )
        }
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: transaction.parent.descriptor,
            name: name
        )
        guard descriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "A restore transaction member could not be pinned before mutation.",
                artifactURL: transaction.parent.url.appendingPathComponent(name)
            )
        }
        do {
            var before = stat()
            guard fstat(descriptor, &before) == 0 else {
                throw RestoreError.recoveryRequired(
                    "A pinned restore member has no readable syscall-adjacent metadata.",
                    artifactURL: nil
                )
            }
            let identity = try PinnedPackage.descriptorIdentity(descriptor)
            let bytes = try data(from: descriptor, artifactName: name)
            var after = stat()
            var reachable = stat()
            guard artifact.identity.matches(identity),
                  sha256(bytes) == artifact.sha256,
                  fstat(descriptor, &after) == 0,
                  RestoreV2ChangeMetadata(before) == RestoreV2ChangeMetadata(after),
                  fstatat(
                    transaction.parent.descriptor,
                    name,
                    &reachable,
                    AT_SYMLINK_NOFOLLOW
                  ) == 0,
                  restoreFileIdentity(from: reachable) == identity else {
                throw RestoreError.recoveryRequired(
                    "A restore transaction member changed while its exact descriptor was pinned.",
                    artifactURL: transaction.parent.url.appendingPathComponent(name)
                )
            }
            return RestoreV2PinnedMember(
                descriptor: descriptor,
                artifact: artifact,
                identity: identity,
                changeMetadata: RestoreV2ChangeMetadata(after)
            )
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func requirePinnedRestoreV2MemberImmediately(
        _ member: RestoreV2PinnedMember,
        reachableAs name: String,
        transaction: RestoreV2Transaction
    ) throws {
        var before = stat()
        var after = stat()
        var reachable = stat()
        guard fstat(member.descriptor, &before) == 0,
              restoreFileIdentity(from: before) == member.identity,
              RestoreV2ChangeMetadata(before) == member.changeMetadata,
              sha256(try data(
                from: member.descriptor,
                artifactName: name
              )) == member.artifact.sha256,
              fstat(member.descriptor, &after) == 0,
              restoreFileIdentity(from: after) == member.identity,
              RestoreV2ChangeMetadata(after) == member.changeMetadata,
              fstatat(
                transaction.parent.descriptor,
                name,
                &reachable,
                AT_SYMLINK_NOFOLLOW
              ) == 0,
              restoreFileIdentity(from: reachable) == member.identity else {
            throw RestoreError.recoveryRequired(
                "A pinned restore member changed at the syscall-adjacent proof boundary.",
                artifactURL: transaction.parent.url.appendingPathComponent(name)
            )
        }
    }

    private func restoreFileIdentity(from value: stat) -> FileIdentity {
        FileIdentity(
            device: value.st_dev,
            inode: value.st_ino,
            generation: value.st_gen,
            fileType: value.st_mode & S_IFMT,
            linkCount: value.st_nlink,
            byteSize: value.st_size
        )
    }

    private func renameRestoreV2Member(
        _ artifact: RestoreJournalArtifact,
        from sourceName: String,
        to destinationName: String,
        flags: UInt32 = UInt32(RENAME_EXCL),
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        if flags != UInt32(RENAME_SWAP) {
            guard try restoreArtifactObservation(named: destinationName, in: transaction.parent) == nil else {
                throw RestoreError.recoveryRequired(
                    "A restore transition destination became occupied.",
                    artifactURL: transaction.parent.url.appendingPathComponent(destinationName)
                )
            }
        }
        let pinned = try pinRestoreV2Member(
            artifact,
            named: sourceName,
            transaction: transaction
        )
        try requirePinnedRestoreV2MemberImmediately(
            pinned,
            reachableAs: sourceName,
            transaction: transaction
        )
        guard renameatx_np(
            transaction.parent.descriptor,
            sourceName,
            transaction.parent.descriptor,
            destinationName,
            flags
        ) == 0 else {
            throw RestoreError.recoveryRequired(
                "A capability-bound restore rename failed (errno \(errno)).",
                artifactURL: transaction.parent.url.appendingPathComponent(sourceName)
            )
        }
        guard try restoreArtifactObservation(named: destinationName, in: transaction.parent)
            .map({ restoreObservation($0, matches: artifact) }) == true else {
            throw RestoreError.recoveryRequired(
                "A restore rename selected a different namespace occupant.",
                artifactURL: transaction.parent.url.appendingPathComponent(destinationName)
            )
        }
        try syncRestoreV2Directory(transaction: transaction)
    }

    private func swapRestoreV2Members(
        source: RestoreJournalArtifact,
        sourceName: String,
        destination: RestoreJournalArtifact,
        destinationName: String,
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        let pinnedSource = try pinRestoreV2Member(
            source,
            named: sourceName,
            transaction: transaction
        )
        let pinnedDestination = try pinRestoreV2Member(
            destination,
            named: destinationName,
            transaction: transaction
        )
        try requirePinnedRestoreV2MemberImmediately(
            pinnedSource,
            reachableAs: sourceName,
            transaction: transaction
        )
        try requirePinnedRestoreV2MemberImmediately(
            pinnedDestination,
            reachableAs: destinationName,
            transaction: transaction
        )
        guard renameatx_np(
            transaction.parent.descriptor,
            sourceName,
            transaction.parent.descriptor,
            destinationName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            throw RestoreError.recoveryRequired(
                "The capability-bound restore swap failed (errno \(errno)).",
                artifactURL: nil
            )
        }
        guard try restoreArtifactObservation(named: sourceName, in: transaction.parent)
            .map({ restoreObservation($0, matches: destination) }) == true,
        try restoreArtifactObservation(named: destinationName, in: transaction.parent)
            .map({ restoreObservation($0, matches: source) }) == true else {
            throw RestoreError.recoveryRequired(
                "The restore swap result did not match both durable member capabilities.",
                artifactURL: nil
            )
        }
        try syncRestoreV2Directory(transaction: transaction)
    }

    private func restoreArtifactsReferToSameMember(
        _ lhs: RestoreJournalArtifact,
        _ rhs: RestoreJournalArtifact
    ) -> Bool {
        lhs.identity.isSameNode(as: rhs.identity) && lhs.sha256 == rhs.sha256
    }

    private func cleanupRetentionName(
        for artifact: RestoreJournalArtifact,
        named name: String,
        transaction: RestoreV2Transaction
    ) throws -> String {
        let state = transaction.state
        if let original = state.initialNamespace.database,
           restoreArtifactsReferToSameMember(artifact, original) {
            return state.cleanupOriginalDatabaseRetainedName
        }
        if let original = state.initialNamespace.wal,
           restoreArtifactsReferToSameMember(artifact, original) {
            return state.cleanupOriginalWALRetainedName
        }
        if let original = state.initialNamespace.shm,
           restoreArtifactsReferToSameMember(artifact, original) {
            return state.cleanupOriginalSHMRetainedName
        }
        if state.mode == .absent,
           name == state.stagingName,
           let staged = state.stagedDatabase,
           restoreArtifactsReferToSameMember(artifact, staged) {
            return state.cleanupStagedDatabaseRetainedName
        }
        let replacement = state.reopenedNamespace ?? state.publishedNamespace
        if let database = replacement?.database,
           restoreArtifactsReferToSameMember(artifact, database) {
            return state.cleanupReplacementDatabaseRetainedName
        }
        if state.mode == .absent, name == state.databaseName {
            return state.cleanupReplacementDatabaseRetainedName
        }
        if let wal = replacement?.wal,
           restoreArtifactsReferToSameMember(artifact, wal) {
            return state.cleanupReplacementWALRetainedName
        }
        if let shm = replacement?.shm,
           restoreArtifactsReferToSameMember(artifact, shm) {
            return state.cleanupReplacementSHMRetainedName
        }
        if state.mode == .existing,
           name == state.stagingName,
           let staged = state.stagedDatabase,
           restoreArtifactsReferToSameMember(artifact, staged) {
            return state.cleanupReplacementDatabaseRetainedName
        }
        throw RestoreError.recoveryRequired(
            "A cleanup member has no deterministic policy-owned retention role.",
            artifactURL: transaction.parent.url.appendingPathComponent(name)
        )
    }

    private func cleanupRetentionPlan(
        transaction: RestoreV2Transaction
    ) throws -> [(artifact: RestoreJournalArtifact, sourceName: String, retainedName: String)] {
        let state = transaction.state
        var members: [(RestoreJournalArtifact, String)] = []
        switch state.outcome {
        case .committed:
            if state.mode == .existing, let original = state.initialNamespace.database {
                members.append((original, state.stagingName))
            } else if let staged = state.stagedDatabase {
                members.append((staged, state.stagingName))
            }
            members += [state.initialNamespace.wal, state.initialNamespace.shm]
                .compactMap { $0 }
                .map { ($0, $0.retainedName) }
        case .compensated:
            let replacement = state.reopenedNamespace ?? state.publishedNamespace
            if let database = replacement?.database {
                members.append((
                    database,
                    state.mode == .existing ? state.stagingName : state.databaseName
                ))
            } else if state.mode == .existing, let staged = state.stagedDatabase {
                members.append((staged, state.stagingName))
            }
            members += [replacement?.wal, replacement?.shm]
                .compactMap { $0 }
                .map { ($0, state.mode == .existing ? $0.retainedName : $0.originalName) }
            if state.mode == .absent, let staged = state.stagedDatabase {
                members.append((staged, state.stagingName))
            }
        case nil:
            throw RestoreError.recoveryRequired(
                "Cleanup retention has no durable transaction outcome.",
                artifactURL: nil
            )
        }
        return try members.map { artifact, sourceName in
            (
                artifact,
                sourceName,
                try cleanupRetentionName(
                    for: artifact,
                    named: sourceName,
                    transaction: transaction
                )
            )
        }
    }

    private enum CleanupRetentionStatus {
        case retained
        case operatorCleared
    }

    private func cleanupRetentionStatus(
        transaction: RestoreV2Transaction
    ) throws -> CleanupRetentionStatus {
        let plan = try cleanupRetentionPlan(transaction: transaction)
        var retainedCount = 0
        var absentCount = 0
        for item in plan {
            let source = try restoreArtifactObservation(
                named: item.sourceName,
                in: transaction.parent
            )
            let retained = try restoreArtifactObservation(
                named: item.retainedName,
                in: transaction.parent
            )
            guard source == nil else {
                throw RestoreError.recoveryRequired(
                    "A completed cleanup source name became occupied; the occupant was preserved.",
                    artifactURL: transaction.parent.url.appendingPathComponent(item.sourceName)
                )
            }
            if retained.map({ restoreObservation($0, matches: item.artifact) }) == true {
                retainedCount += 1
            } else if retained == nil {
                absentCount += 1
            } else {
                throw RestoreError.recoveryRequired(
                    "A policy-owned cleanup retention member changed; its exact occupant was preserved.",
                    artifactURL: transaction.parent.url.appendingPathComponent(item.retainedName)
                )
            }
        }
        if retainedCount == plan.count { return .retained }
        if absentCount == plan.count { return .operatorCleared }
        throw RestoreError.recoveryRequired(
            "Only part of the bounded cleanup retention set was removed; remaining evidence was preserved.",
            artifactURL: nil
        )
    }

    /// Cleanup is a preserve-first namespace transition. The selected member
    /// is moved create-only into its deterministic retained role; it is never
    /// unlinked or cloned back from an already-unlinked descriptor.
    private func retainRestoreV2Member(
        _ artifact: RestoreJournalArtifact,
        named name: String,
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        let retainedName = try cleanupRetentionName(
            for: artifact,
            named: name,
            transaction: transaction
        )
        let source = try restoreArtifactObservation(named: name, in: transaction.parent)
        let retained = try restoreArtifactObservation(
            named: retainedName,
            in: transaction.parent
        )
        if source == nil,
           retained.map({ restoreObservation($0, matches: artifact) }) == true {
            return
        }
        if source == nil, retained == nil {
            throw RestoreError.recoveryRequired(
                "A required terminal cleanup evidence member is absent; no pathname was modified.",
                artifactURL: transaction.parent.url.appendingPathComponent(retainedName)
            )
        }
        guard source.map({ restoreObservation($0, matches: artifact) }) == true,
              retained == nil else {
            throw RestoreError.recoveryRequired(
                "A cleanup source or deterministic retained destination is occupied by an unexpected member; both occupants were preserved.",
                artifactURL: source == nil
                    ? transaction.parent.url.appendingPathComponent(retainedName)
                    : transaction.parent.url.appendingPathComponent(name)
            )
        }
        let pinned = try pinRestoreV2Member(
            artifact,
            named: name,
            transaction: transaction
        )
        try requirePinnedRestoreV2MemberImmediately(
            pinned,
            reachableAs: name,
            transaction: transaction
        )
        guard renameatx_np(
            transaction.parent.descriptor,
            name,
            transaction.parent.descriptor,
            retainedName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw RestoreError.recoveryRequired(
                "The preserve-first cleanup retention transition failed; source and destination occupants were left in place.",
                artifactURL: transaction.parent.url.appendingPathComponent(name)
            )
        }
        let sourceAfter = try restoreArtifactObservation(named: name, in: transaction.parent)
        let retainedAfter = try restoreArtifactObservation(
            named: retainedName,
            in: transaction.parent
        )
        guard sourceAfter == nil,
              retainedAfter.map({ restoreObservation($0, matches: artifact) }) == true else {
            throw RestoreError.recoveryRequired(
                "A cleanup member changed at the final retention boundary. The exact moved bytes and every source-name replacement were preserved for recovery.",
                artifactURL: transaction.parent.url.appendingPathComponent(retainedName)
            )
        }
        try syncRestoreV2Directory(transaction: transaction)
    }

    private func cloneRestoreV2StagingToAbsentDestination(
        transaction: RestoreV2Transaction
    ) throws -> RestoreJournalArtifact {
        let state = transaction.state
        guard let staged = state.stagedDatabase else {
            throw RestoreError.recoveryRequired(
                "The absent-destination clone has no durable staged database capability.",
                artifactURL: nil
            )
        }
        try requireRestoreV2Capability(transaction)
        try requireRestoreV2RetentionCapacity(
            artifacts: transaction.state.initialNamespace.artifacts + [staged],
            prospectiveByteSizes: [Int64(staged.identity.byteSize)]
        )
        guard try restoreArtifactObservation(named: state.databaseName, in: transaction.parent) == nil,
              try restoreArtifactObservation(named: state.databaseName + "-wal", in: transaction.parent) == nil,
              try restoreArtifactObservation(named: state.databaseName + "-shm", in: transaction.parent) == nil else {
            throw RestoreError.recoveryRequired(
                "The absent restore destination or a sidecar became occupied before clone.",
                artifactURL: nil
            )
        }
        let pinned = try pinRestoreV2Member(
            staged,
            named: state.stagingName,
            transaction: transaction
        )
        try requirePinnedRestoreV2MemberImmediately(
            pinned,
            reachableAs: state.stagingName,
            transaction: transaction
        )
        guard fclonefileat(
            pinned.descriptor,
            transaction.parent.descriptor,
            state.databaseName,
            0
        ) == 0,
        let installed = try restoreV2Artifact(
            named: state.databaseName,
            retainedName: state.stagingName,
            in: transaction.parent
        ), installed.sha256 == staged.sha256 else {
            throw RestoreError.recoveryRequired(
                "The absent-destination clone did not produce the exact staged database.",
                artifactURL: nil
            )
        }
        try syncRestoreV2Directory(transaction: transaction)
        return installed
    }

    private func validateSQLiteOpenSidecars(
        _ namespace: RestoreV2Namespace,
        transaction: RestoreV2Transaction
    ) throws {
        try requireRestoreV2Capability(transaction)
        try validateSQLiteSidecars(namespace, parent: transaction.parent)
        try requireRestoreV2Capability(transaction)
    }

    private func validateSQLiteSidecars(
        _ namespace: RestoreV2Namespace,
        parent: PinnedDirectory
    ) throws {
        if let wal = namespace.wal {
            let descriptor = Self.openPinnedRegularChildNonBlocking(
                directoryDescriptor: parent.descriptor,
                name: wal.originalName
            )
            guard descriptor >= 0 else {
                throw RestoreError.recoveryRequired(
                    "The SQLite-open WAL capability could not be pinned.",
                    artifactURL: nil
                )
            }
            defer { Darwin.close(descriptor) }
            let bytes = try data(from: descriptor, artifactName: wal.originalName)
            let magic = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            // SQLite may create a zero-byte WAL while establishing WAL mode;
            // it contains no frames and is the VFS-equivalent of no WAL. Any
            // non-empty occupant must carry a complete SQLite WAL header.
            guard bytes.isEmpty || (
                bytes.count >= 32
                    && (magic == 0x377f0682 || magic == 0x377f0683)
            ) else {
                throw RestoreError.recoveryRequired(
                    "A WAL appearing at SQLite open was not a valid SQLite VFS WAL and was preserved.",
                    artifactURL: parent.url.appendingPathComponent(wal.originalName)
                )
            }
        }
        if let shm = namespace.shm {
            let descriptor = Self.openPinnedRegularChildNonBlocking(
                directoryDescriptor: parent.descriptor,
                name: shm.originalName
            )
            guard descriptor >= 0 else {
                throw RestoreError.recoveryRequired(
                    "The SQLite-open shared-memory capability could not be pinned.",
                    artifactURL: nil
                )
            }
            defer { Darwin.close(descriptor) }
            let identity = try PinnedPackage.descriptorIdentity(descriptor)
            guard identity.byteSize >= 32 * 1_024,
                  identity.byteSize.isMultiple(of: 32 * 1_024) else {
                throw RestoreError.recoveryRequired(
                    "A shared-memory file appearing at SQLite open did not match SQLite VFS sizing and was preserved.",
                    artifactURL: parent.url.appendingPathComponent(shm.originalName)
                )
            }
        }
    }

    private func initialRestoreV2Namespace(
        databaseURL: URL,
        transactionID: String,
        parent: PinnedDirectory
    ) throws -> RestoreV2Namespace {
        RestoreV2Namespace(
            database: try restoreV2Artifact(
                named: databaseURL.lastPathComponent,
                retainedName: restoreV2OriginalDatabaseName,
                in: parent
            ),
            wal: try restoreV2Artifact(
                named: databaseURL.lastPathComponent + "-wal",
                retainedName: restoreV2OriginalWALName,
                in: parent
            ),
            shm: try restoreV2Artifact(
                named: databaseURL.lastPathComponent + "-shm",
                retainedName: restoreV2OriginalSHMName,
                in: parent
            )
        )
    }

    private func createRestoreV2Transaction(
        databaseURL: URL,
        transactionID: String,
        mode: RestoreV2TransactionState.Mode,
        initialNamespace: RestoreV2Namespace,
        sourceNamespace: RestoreV2SourceNamespace,
        recoveryArtifactURL: URL?,
        authority: DatabaseStartupLock,
        parent: PinnedDirectory,
        source: RestoreSourceUse
    ) throws -> RestoreV2Transaction {
        try requireRestoreV2RetentionCapacity(artifacts: initialNamespace.artifacts)
        let state = RestoreV2TransactionState(
            version: RestoreV2TransactionState.currentVersion,
            transactionID: transactionID,
            authority: OwnershipLedgerIdentity(parent.identity),
            mode: mode,
            phase: .planned,
            databaseName: databaseURL.lastPathComponent,
            stagingName: restoreV2StagingName,
            originalDatabaseRetainedName: restoreV2OriginalDatabaseName,
            originalWALRetainedName: restoreV2OriginalWALName,
            originalSHMRetainedName: restoreV2OriginalSHMName,
            replacementWALRetainedName: restoreV2ReplacementWALName,
            replacementSHMRetainedName: restoreV2ReplacementSHMName,
            cleanupOriginalDatabaseRetainedName: restoreV2CleanupOriginalDatabaseName,
            cleanupOriginalWALRetainedName: restoreV2CleanupOriginalWALName,
            cleanupOriginalSHMRetainedName: restoreV2CleanupOriginalSHMName,
            cleanupStagedDatabaseRetainedName: restoreV2CleanupStagedDatabaseName,
            cleanupReplacementDatabaseRetainedName: restoreV2CleanupReplacementDatabaseName,
            cleanupReplacementWALRetainedName: restoreV2CleanupReplacementWALName,
            cleanupReplacementSHMRetainedName: restoreV2CleanupReplacementSHMName,
            source: sourceNamespace,
            initialNamespace: initialNamespace,
            stagedDatabase: nil,
            publishedNamespace: nil,
            reopenedNamespace: nil,
            completedNamespace: nil,
            outcome: nil,
            recoveryArtifactPath: recoveryArtifactURL?.path
        )
        let transaction = RestoreV2Transaction(
            authority: authority,
            parent: parent,
            databaseURL: databaseURL,
            state: state,
            canonicalBytes: try canonicalRestoreV2Bytes(state),
            sourceCapabilityValidator: { [self, source] in
                try requireRestoreSourceCapability(
                    sourceNamespace,
                    source: source,
                    databaseURL: databaseURL,
                    namespaceAuthority: authority
                )
            }
        )
        try publishRestoreV2State(state, transaction: transaction, creating: true)
        return transaction
    }

    private func stageRestoreV2Database(
        _ databaseData: Data,
        transaction: RestoreV2Transaction
    ) throws -> RestoreJournalArtifact {
        try requireRestoreV2Capability(transaction)
        try requireRestoreV2RetentionCapacity(
            artifacts: transaction.state.initialNamespace.artifacts,
            prospectiveByteSizes: [Int64(databaseData.count)]
        )
        let descriptor = Darwin.openat(
            transaction.parent.descriptor,
            transaction.state.stagingName,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "The deterministic restore staging member could not be created exclusively.",
                artifactURL: nil
            )
        }
        defer { Darwin.close(descriptor) }
        try write(
            databaseData,
            to: descriptor,
            artifactName: transaction.state.stagingName
        )
        _ = try verifySQLiteDatabase(data: databaseData, descriptor: descriptor)
        let identity = try PinnedPackage.descriptorIdentity(descriptor)
        let staged = RestoreJournalArtifact(
            originalName: transaction.state.databaseName,
            retainedName: transaction.state.stagingName,
            identity: RestorePersistedIdentity(identity),
            sha256: sha256(databaseData)
        )
        guard try restoreArtifactObservation(
            named: transaction.state.stagingName,
            in: transaction.parent
        ).map({ restoreObservation($0, matches: staged) }) == true else {
            throw RestoreError.recoveryRequired(
                "The deterministic restore staging member changed during preparation.",
                artifactURL: nil
            )
        }
        try syncRestoreV2Directory(transaction: transaction)
        try publishRestoreV2State(
            transaction.state.changing(phase: .staged, stagedDatabase: staged),
            transaction: transaction
        )
        return staged
    }

    private func moveInitialRestoreV2Sidecars(
        transaction: RestoreV2Transaction
    ) throws {
        let state = transaction.state
        for artifact in [state.initialNamespace.wal, state.initialNamespace.shm].compactMap({ $0 }) {
            let live = try restoreArtifactObservation(
                named: artifact.originalName,
                in: transaction.parent
            )
            let retained = try restoreArtifactObservation(
                named: artifact.retainedName,
                in: transaction.parent
            )
            if live == nil,
               retained.map({ restoreObservation($0, matches: artifact) }) == true {
                continue
            }
            guard live.map({ restoreObservation($0, matches: artifact) }) == true,
                  retained == nil else {
                throw RestoreError.recoveryRequired(
                    "An original SQLite sidecar changed before deterministic retention.",
                    artifactURL: nil
                )
            }
            try renameRestoreV2Member(
                artifact,
                from: artifact.originalName,
                to: artifact.retainedName,
                transaction: transaction
            )
        }
        for suffix in ["-wal", "-shm"] {
            let name = state.databaseName + suffix
            guard try restoreArtifactObservation(named: name, in: transaction.parent) == nil else {
                throw RestoreError.recoveryRequired(
                    "A SQLite sidecar appeared after the initial namespace was recorded.",
                    artifactURL: transaction.parent.url.appendingPathComponent(name)
                )
            }
        }
        try publishRestoreV2State(
            transaction.state.changing(phase: .originalsRetained),
            transaction: transaction
        )
    }

    private func publishRestoreV2Database(
        transaction: RestoreV2Transaction
    ) throws -> RestoreV2Namespace {
        guard let staged = transaction.state.stagedDatabase else {
            throw RestoreError.recoveryRequired(
                "The restore publication has no durable staged database capability.",
                artifactURL: nil
            )
        }
        let installed: RestoreJournalArtifact
        switch transaction.state.mode {
        case .existing:
            guard let original = transaction.state.initialNamespace.database else {
                throw RestoreError.recoveryRequired(
                    "The existing restore transaction lost its original database capability.",
                    artifactURL: nil
                )
            }
            try swapRestoreV2Members(
                source: staged,
                sourceName: transaction.state.stagingName,
                destination: original,
                destinationName: transaction.state.databaseName,
                transaction: transaction
            )
            installed = try requireRestoreV2Artifact(
                named: transaction.state.databaseName,
                retainedName: transaction.state.stagingName,
                transaction: transaction
            )
        case .absent:
            installed = try cloneRestoreV2StagingToAbsentDestination(transaction: transaction)
        }
        let published = RestoreV2Namespace(database: installed, wal: nil, shm: nil)
        try requireRestoreV2Namespace(published, transaction: transaction)
        try publishRestoreV2State(
            transaction.state.changing(
                phase: .published,
                publishedNamespace: published
            ),
            transaction: transaction
        )
        return published
    }

    private func requireRestoreV2Artifact(
        named name: String,
        retainedName: String,
        transaction: RestoreV2Transaction
    ) throws -> RestoreJournalArtifact {
        guard let artifact = try restoreV2Artifact(
            named: name,
            retainedName: retainedName,
            in: transaction.parent
        ) else {
            throw RestoreError.recoveryRequired(
                "A required restore transaction member is absent.",
                artifactURL: transaction.parent.url.appendingPathComponent(name)
            )
        }
        return artifact
    }

    private func retainRestoreV2MemberIfPresent(
        _ artifact: RestoreJournalArtifact,
        named name: String,
        transaction: RestoreV2Transaction
    ) throws {
        try retainRestoreV2Member(artifact, named: name, transaction: transaction)
    }

    private func finishCommittedRestoreV2(
        transaction: RestoreV2Transaction
    ) throws -> RestoreV2Namespace {
        guard let reopened = transaction.state.reopenedNamespace,
              reopened.database != nil else {
            throw RestoreError.recoveryRequired(
                "The commit cleanup has no durable post-open DB/WAL/SHM namespace.",
                artifactURL: nil
            )
        }
        if transaction.state.phase != .cleaning {
            try publishRestoreV2State(
                transaction.state.changing(phase: .cleaning, outcome: .committed),
                transaction: transaction
            )
        }
        try requireRestoreV2Namespace(reopened, transaction: transaction)
        if transaction.state.mode == .existing,
           let original = transaction.state.initialNamespace.database {
            try retainRestoreV2MemberIfPresent(
                original,
                named: transaction.state.stagingName,
                transaction: transaction
            )
        } else if let staged = transaction.state.stagedDatabase {
            try retainRestoreV2MemberIfPresent(
                staged,
                named: transaction.state.stagingName,
                transaction: transaction
            )
        }
        for artifact in [
            transaction.state.initialNamespace.wal,
            transaction.state.initialNamespace.shm,
        ].compactMap({ $0 }) {
            try retainRestoreV2MemberIfPresent(
                artifact,
                named: artifact.retainedName,
                transaction: transaction
            )
        }
        try requireRestoreV2Namespace(reopened, transaction: transaction)
        try physicallyVerifyRestoreNamespace(
            transaction.databaseURL,
            expectedDatabase: reopened.database!,
            expectedSidecars: [reopened.wal, reopened.shm].compactMap({ $0 }),
            in: transaction.parent
        )
        try publishRestoreV2State(
            transaction.state.changing(
                phase: .completed,
                completedNamespace: reopened,
                outcome: .committed
            ),
            transaction: transaction
        )
        try requireRestoreV2Namespace(reopened, transaction: transaction)
        return reopened
    }

    private func restoreOriginalV2Sidecars(
        transaction: RestoreV2Transaction
    ) throws {
        for artifact in [
            transaction.state.initialNamespace.wal,
            transaction.state.initialNamespace.shm,
        ].compactMap({ $0 }) {
            let live = try restoreArtifactObservation(
                named: artifact.originalName,
                in: transaction.parent
            )
            let retained = try restoreArtifactObservation(
                named: artifact.retainedName,
                in: transaction.parent
            )
            if live.map({ restoreObservation($0, matches: artifact) }) == true,
               retained == nil {
                continue
            }
            guard live == nil,
                  retained.map({ restoreObservation($0, matches: artifact) }) == true else {
                throw RestoreError.recoveryRequired(
                    "An original SQLite sidecar could not be restored without replacing an occupant.",
                    artifactURL: transaction.parent.url.appendingPathComponent(artifact.retainedName)
                )
            }
            try renameRestoreV2Member(
                artifact,
                from: artifact.retainedName,
                to: artifact.originalName,
                transaction: transaction
            )
        }
    }

    private func moveReplacementV2Sidecars(
        transaction: RestoreV2Transaction
    ) throws {
        guard let replacement = transaction.state.reopenedNamespace else { return }
        try validateSQLiteOpenSidecars(replacement, transaction: transaction)
        for artifact in [replacement.wal, replacement.shm].compactMap({ $0 }) {
            let live = try restoreArtifactObservation(named: artifact.originalName, in: transaction.parent)
            let retained = try restoreArtifactObservation(named: artifact.retainedName, in: transaction.parent)
            if live == nil,
               retained.map({ restoreObservation($0, matches: artifact) }) == true {
                continue
            }
            guard live.map({ restoreObservation($0, matches: artifact) }) == true,
                  retained == nil else {
                throw RestoreError.recoveryRequired(
                    "A replacement SQLite sidecar changed before rollback retention.",
                    artifactURL: nil
                )
            }
            try renameRestoreV2Member(
                artifact,
                from: artifact.originalName,
                to: artifact.retainedName,
                transaction: transaction
            )
        }
    }

    private func finishRolledBackRestoreV2(
        transaction: RestoreV2Transaction,
        reopenOriginal: () throws -> Void
    ) throws -> RestoreV2Namespace {
        if transaction.state.phase != .rollingBack,
           transaction.state.phase != .rolledBack {
            // Never infer a replacement sidecar capability from a pathname
            // observed after publication. Only a namespace already durably
            // recorded in the transaction may authorize later movement/removal.
            let current = transaction.state.reopenedNamespace
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .rollingBack,
                    reopenedNamespace: current,
                    outcome: .compensated
                ),
                transaction: transaction
            )
        }

        switch transaction.state.mode {
        case .existing:
            guard let original = transaction.state.initialNamespace.database,
                  let staged = transaction.state.stagedDatabase else {
                throw RestoreError.recoveryRequired(
                    "The existing rollback lost its original or staged database capability.",
                    artifactURL: nil
                )
            }
            let replacementNamespace = transaction.state.reopenedNamespace
            let live = try restoreArtifactObservation(
                named: transaction.state.databaseName,
                in: transaction.parent
            )
            let hidden = try restoreArtifactObservation(
                named: transaction.state.stagingName,
                in: transaction.parent
            )
            if live.map({ restoreObservation($0, matches: original) }) == true {
                guard hidden == nil
                        || restoreObservation(hidden!, matches: staged)
                        || replacementNamespace?.database.map({
                            restoreObservation(hidden!, matches: $0)
                        }) == true else {
                    throw RestoreError.recoveryRequired(
                        "The retained replacement database changed during rollback.",
                        artifactURL: nil
                    )
                }
            } else {
                guard hidden.map({ restoreObservation($0, matches: original) }) == true,
                      let replacement = replacementNamespace?.database
                        ?? transaction.state.publishedNamespace?.database
                        ?? transaction.state.stagedDatabase,
                      live.map({ restoreObservation($0, matches: replacement) }) == true else {
                    throw RestoreError.recoveryRequired(
                        "The existing rollback database occupants do not match a durable transaction state.",
                        artifactURL: nil
                    )
                }
                try swapRestoreV2Members(
                    source: original,
                    sourceName: transaction.state.stagingName,
                    destination: replacement,
                    destinationName: transaction.state.databaseName,
                    transaction: transaction
                )
            }
            try moveReplacementV2Sidecars(transaction: transaction)
            try restoreOriginalV2Sidecars(transaction: transaction)
            try reopenOriginal()
            let restored = try observeRestoreV2Namespace(
                transaction: transaction,
                databaseRetainedName: transaction.state.originalDatabaseRetainedName,
                walRetainedName: transaction.state.originalWALRetainedName,
                shmRetainedName: transaction.state.originalSHMRetainedName
            )
            guard let restoredDatabase = restored.database,
                  restoredDatabase.identity.isSameNode(as: original.identity),
                  restoredDatabase.sha256 == original.sha256 else {
                throw RestoreError.recoveryRequired(
                    "The reopened rollback namespace does not match the exact original DB/WAL/SHM set.",
                    artifactURL: nil
                )
            }
            try validateSQLiteOpenSidecars(restored, transaction: transaction)
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .rolledBack,
                    completedNamespace: restored,
                    outcome: .compensated
                ),
                transaction: transaction
            )
            if let replacement = replacementNamespace?.database
                ?? transaction.state.publishedNamespace?.database
                ?? transaction.state.stagedDatabase {
                try retainRestoreV2MemberIfPresent(
                    replacement,
                    named: transaction.state.stagingName,
                    transaction: transaction
                )
            }
            for artifact in [
                replacementNamespace?.wal,
                replacementNamespace?.shm,
            ].compactMap({ $0 }) {
                try retainRestoreV2MemberIfPresent(
                    artifact,
                    named: artifact.retainedName,
                    transaction: transaction
                )
            }
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .completed,
                    completedNamespace: restored,
                    outcome: .compensated
                ),
                transaction: transaction
            )
            return restored

        case .absent:
            if let replacement = transaction.state.reopenedNamespace {
                try validateSQLiteOpenSidecars(replacement, transaction: transaction)
                for artifact in [replacement.wal, replacement.shm].compactMap({ $0 }) {
                    try retainRestoreV2MemberIfPresent(
                        artifact,
                        named: artifact.originalName,
                        transaction: transaction
                    )
                }
                if let database = replacement.database {
                    try retainRestoreV2MemberIfPresent(
                        database,
                        named: transaction.state.databaseName,
                        transaction: transaction
                    )
                }
            } else if let published = transaction.state.publishedNamespace?.database {
                try retainRestoreV2MemberIfPresent(
                    published,
                    named: transaction.state.databaseName,
                    transaction: transaction
                )
            } else if let staged = transaction.state.stagedDatabase,
                      let live = try restoreArtifactObservation(
                        named: transaction.state.databaseName,
                        in: transaction.parent
                      ) {
                guard live.sha256 == staged.sha256 else {
                    throw RestoreError.recoveryRequired(
                        "An absent-destination clone occupant has unexpected content and was preserved.",
                        artifactURL: transaction.databaseURL
                    )
                }
                let inferred = RestoreJournalArtifact(
                    originalName: transaction.state.databaseName,
                    retainedName: transaction.state.stagingName,
                    identity: RestorePersistedIdentity(live.identity),
                    sha256: live.sha256
                )
                try publishRestoreV2State(
                    transaction.state.changing(
                        phase: .rollingBack,
                        publishedNamespace: RestoreV2Namespace(
                            database: inferred,
                            wal: nil,
                            shm: nil
                        ),
                        outcome: .compensated
                    ),
                    transaction: transaction
                )
                try retainRestoreV2Member(
                    inferred,
                    named: transaction.state.databaseName,
                    transaction: transaction
                )
            }
            if let staged = transaction.state.stagedDatabase {
                try retainRestoreV2MemberIfPresent(
                    staged,
                    named: transaction.state.stagingName,
                    transaction: transaction
                )
            }
            let empty = RestoreV2Namespace(database: nil, wal: nil, shm: nil)
            try requireRestoreV2Namespace(empty, transaction: transaction)
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .rolledBack,
                    completedNamespace: empty,
                    outcome: .compensated
                ),
                transaction: transaction
            )
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .completed,
                    completedNamespace: empty,
                    outcome: .compensated
                ),
                transaction: transaction
            )
            return empty
        }
    }

    private func replaceDatabaseWithRestoreV2(
        databaseData: Data,
        transaction: RestoreV2Transaction,
        validateInstalledDatabase: () throws -> Void,
        reopenOriginalDatabase: () throws -> Void
    ) throws -> RestoreV2Namespace {
        let published: RestoreV2Namespace
        do {
            _ = try stageRestoreV2Database(databaseData, transaction: transaction)
            if transaction.state.mode == .existing {
                try moveInitialRestoreV2Sidecars(transaction: transaction)
            }
            published = try publishRestoreV2Database(transaction: transaction)
            try requireRestoreV2Namespace(published, transaction: transaction)
        } catch {
            guard transaction.state.stagedDatabase != nil else { throw error }
            do {
                _ = try finishRolledBackRestoreV2(
                    transaction: transaction,
                    reopenOriginal: reopenOriginalDatabase
                )
            } catch let rollbackError as RestoreError {
                throw rollbackError
            } catch {
                throw RestoreError.recoveryRequired(
                    "Restore compensation could not complete physical original-database validation: \(error.localizedDescription)",
                    artifactURL: transaction.state.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
                )
            }
            throw RestoreError.recoveredFailure(error.localizedDescription)
        }

        do {
            guard let publishedDatabase = published.database else {
                throw RestoreError.recoveryRequired(
                    "The private validated replacement was not published as a database capability.",
                    artifactURL: nil
                )
            }
            // The exact staged descriptor was already opened immutable/read-only
            // before publication. Recheck the clean published bytes without a
            // read-write SQLite handle or public WAL/SHM, then durably commit the
            // intended namespace before the normal production open is allowed.
            try physicallyVerifyRestoreNamespace(
                transaction.databaseURL,
                expectedDatabase: publishedDatabase,
                expectedSidecars: [],
                in: transaction.parent
            )
            try publishRestoreV2State(
                transaction.state.changing(
                    phase: .reopened,
                    reopenedNamespace: published
                ),
                transaction: transaction
            )
        } catch {
            do {
                _ = try finishRolledBackRestoreV2(
                    transaction: transaction,
                    reopenOriginal: reopenOriginalDatabase
                )
            } catch let rollbackError as RestoreError {
                throw rollbackError
            } catch {
                throw RestoreError.recoveryRequired(
                    "Restore compensation could not complete physical original-database validation: \(error.localizedDescription)",
                    artifactURL: transaction.state.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
                )
            }
            throw RestoreError.recoveredFailure(error.localizedDescription)
        }

        let committed = try finishCommittedRestoreV2(transaction: transaction)
        do {
            // Only after the transaction record and clean live namespace have
            // reached their durability points may the ordinary production open
            // create or consume its own WAL/SHM under the still-held authority.
            try validateInstalledDatabase()
            try transaction.authority.validate(for: transaction.databaseURL)
            try transaction.parent.validatePath()
            let opened = try observeRestoreV2Namespace(
                databaseURL: transaction.databaseURL,
                parent: transaction.parent,
                databaseRetainedName: transaction.state.stagingName,
                walRetainedName: transaction.state.replacementWALRetainedName,
                shmRetainedName: transaction.state.replacementSHMRetainedName
            )
            guard let committedDatabase = committed.database,
                  let openedDatabase = opened.database,
                  openedDatabase.identity.isSameNode(as: committedDatabase.identity),
                  openedDatabase.sha256 == committedDatabase.sha256 else {
                throw RestoreError.recoveryRequired(
                    "The post-commit production open did not retain the exact validated database artifact.",
                    artifactURL: transaction.state.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
                )
            }
            try validateSQLiteSidecars(opened, parent: transaction.parent)
            return opened
        } catch let error as RestoreError {
            throw error
        } catch {
            throw RestoreError.recoveryRequired(
                "The clean restore committed, but the post-commit production open failed: \(error.localizedDescription)",
                artifactURL: transaction.state.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
            )
        }
    }

    private func validRestoreTransactionRecord(
        _ record: RestoreTransactionRecord,
        for databaseURL: URL
    ) -> Bool {
        let databaseName = databaseURL.lastPathComponent
        guard record.version == RestoreTransactionRecord.currentVersion,
              isSafeRestoreMemberName(databaseName),
              record.databaseName == databaseName,
              isGeneratedRestoreDatabaseName(record.replacementName),
              validRestoreArtifact(record.originalDatabase),
              validRestoreArtifact(record.replacementDatabase),
              record.originalDatabase.originalName == databaseName,
              record.originalDatabase.retainedName == record.replacementName,
              record.replacementDatabase.originalName == databaseName,
              record.replacementDatabase.retainedName == record.replacementName,
              record.originalDatabase.identity != record.replacementDatabase.identity,
              record.sidecars.count <= 2 else { return false }

        let expectedSidecarNames = ["-wal", "-shm"]
            .map { databaseName + $0 }
            .filter { name in record.sidecars.contains { $0.originalName == name } }
        guard record.sidecars.map(\.originalName) == expectedSidecarNames else { return false }
        var allNames = Set([databaseName, record.replacementName])
        for artifact in record.sidecars {
            guard validRestoreArtifact(artifact),
                  let suffix = ["-wal", "-shm"].first(where: {
                      artifact.originalName == databaseName + $0
                  }),
                  isGeneratedRestoreSidecarName(artifact.retainedName, suffix: suffix),
                  allNames.insert(artifact.originalName).inserted,
                  allNames.insert(artifact.retainedName).inserted else { return false }
        }
        if let recoveryPath = record.recoveryArtifactPath {
            let recoveryURL = URL(fileURLWithPath: recoveryPath)
            guard recoveryURL.path == recoveryPath,
                  recoveryURL.pathExtension.lowercased() == packageExtension else { return false }
        }
        return true
    }

    private func validRestoreArtifact(_ artifact: RestoreJournalArtifact) -> Bool {
        isSafeRestoreMemberName(artifact.originalName)
            && isSafeRestoreMemberName(artifact.retainedName)
            && artifact.identity.fileType == UInt32(S_IFREG)
            && artifact.identity.linkCount == 1
            && artifact.identity.byteSize >= 0
            && isLowercaseSHA256(artifact.sha256)
    }

    private func isSafeRestoreMemberName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && name.utf8.count <= Int(NAME_MAX)
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
    }

    private func isGeneratedRestoreDatabaseName(_ name: String) -> Bool {
        isCanonicalUUIDMember(
            name,
            prefix: ".cid850-restore-",
            suffix: ".sqlite"
        )
    }

    private func isGeneratedRestoreSidecarName(_ name: String, suffix: String) -> Bool {
        isCanonicalUUIDMember(
            name,
            prefix: ".cid851-restore-",
            suffix: suffix
        )
    }

    private func isCanonicalUUIDMember(
        _ name: String,
        prefix: String,
        suffix: String
    ) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return false }
        let token = String(name[start..<end])
        guard token == token.lowercased(),
              let uuid = UUID(uuidString: token) else { return false }
        return uuid.uuidString.lowercased() == token
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || (character >= "a" && character <= "f")
        }
    }

    private func plannedRestoreSidecars(
        for databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> [RestoreJournalArtifact] {
        var result: [RestoreJournalArtifact] = []
        for suffix in ["-wal", "-shm"] {
            let originalName = databaseURL.lastPathComponent + suffix
            guard let observation = try restoreArtifactObservation(named: originalName, in: parent) else {
                continue
            }
            guard observation.identity.fileType == S_IFREG,
                  observation.identity.linkCount == 1 else {
                throw RestoreError.unhealthyBackup(
                    databaseURL,
                    messages: ["A live SQLite sidecar is not a single-link regular file."]
                )
            }
            result.append(RestoreJournalArtifact(
                originalName: originalName,
                retainedName: ".cid851-restore-\(UUID().uuidString.lowercased())\(suffix)",
                identity: RestorePersistedIdentity(observation.identity),
                sha256: observation.sha256
            ))
        }
        return result
    }

    private func createRestoreJournal(
        _ record: RestoreTransactionRecord,
        consuming stagingIntent: RestoreStagingIntent,
        for databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreTransactionJournal {
        guard stagingIntent.phase == .prepared,
              try restoreStagingIntent(in: parent) == stagingIntent else {
            throw RestoreError.recoveryRequired(
                "Journal publication did not consume the exact prepared staging intent.",
                artifactURL: nil
            )
        }
        let name = restoreJournalName(for: databaseURL)
        let descriptor = Darwin.openat(
            parent.descriptor,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "A bounded restore transaction journal already exists or could not be exclusively created (errno \(errno)). Reconcile it before retrying.",
                artifactURL: record.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
            )
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(record)
            try write(encoded, to: descriptor, artifactName: name)
            let identity = try PinnedPackage.descriptorIdentity(descriptor)
            let registration = RestoreJournalRegistration(
                version: RestoreJournalRegistration.currentVersion,
                authority: OwnershipLedgerIdentity(try parent.currentIdentity()),
                journalName: name,
                journal: OwnershipLedgerIdentity(identity),
                journalIdentity: RestorePersistedIdentity(identity),
                journalSHA256: sha256(encoded),
                record: record,
                stagingIntent: stagingIntent,
                completion: nil
            )
            try saveRestoreJournalRegistration(registration, in: parent)
            guard identity.fileType == S_IFREG,
                  identity.linkCount == 1,
                  try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == identity,
                  try restoreJournalIsRegistered(
                    identity: identity,
                    sha256: registration.journalSHA256,
                    record: record,
                    in: parent
                  ),
                  fsync(parent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "The restore journal was written but its identity/publication durability could not be proven.",
                    artifactURL: record.recoveryArtifactPath.map(URL.init(fileURLWithPath:))
                )
            }
            return RestoreTransactionJournal(name: name, descriptor: descriptor, identity: identity)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func saveRestoreJournalRegistration(
        _ registration: RestoreJournalRegistration,
        in parent: PinnedDirectory
    ) throws {
        guard try validRestoreJournalRegistration(registration, in: parent) else {
            throw RestoreError.recoveryRequired(
                "The restore journal creation registration is invalid.",
                artifactURL: nil
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(registration)
        let result = encoded.withUnsafeBytes { bytes in
            fsetxattr(
                parent.descriptor,
                restoreJournalRegistrationAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard result == 0 else {
            throw RestoreError.recoveryRequired(
                "The restore journal creation registration could not be persisted (errno \(errno)).",
                artifactURL: nil
            )
        }
    }

    private func restoreJournalRegistration(
        in parent: PinnedDirectory
    ) throws -> RestoreJournalRegistration? {
        let size = fgetxattr(
            parent.descriptor,
            restoreJournalRegistrationAttribute,
            nil,
            0,
            0,
            0
        )
        if size < 0 {
            guard errno == ENOATTR else {
                throw RestoreError.recoveryRequired(
                    "The restore journal creation registration could not be inspected.",
                    artifactURL: nil
                )
            }
            return nil
        }
        guard size > 0, size <= 4 * 1_024 else { return nil }
        var encoded = Data(count: size)
        let read = encoded.withUnsafeMutableBytes { bytes in
            fgetxattr(
                parent.descriptor,
                restoreJournalRegistrationAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard read == size,
              let registration = try? JSONDecoder().decode(
                RestoreJournalRegistration.self,
                from: encoded
              ),
              try validRestoreJournalRegistration(registration, in: parent) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(registration) == encoded else { return nil }
        return registration
    }

    private func validRestoreJournalRegistration(
        _ registration: RestoreJournalRegistration,
        in parent: PinnedDirectory
    ) throws -> Bool {
        let databaseURL = parent.url.appendingPathComponent(registration.record.databaseName)
        guard registration.version == RestoreJournalRegistration.currentVersion,
              registration.authority == OwnershipLedgerIdentity(try parent.currentIdentity()),
              registration.journalName == restoreJournalName(for: databaseURL),
              registration.journal == registration.journalIdentity.ownershipIdentity,
              registration.journalIdentity.fileType == UInt32(S_IFREG),
              registration.journalIdentity.linkCount == 1,
              isLowercaseSHA256(registration.journalSHA256),
              validRestoreTransactionRecord(registration.record, for: databaseURL),
              let intent = registration.stagingIntent,
              intent.version == RestoreStagingIntent.currentVersion,
              intent.authority == registration.authority,
              intent.mode == .existing,
              intent.phase == .prepared,
              intent.databaseName == registration.record.databaseName,
              intent.stagingName == registration.record.replacementName,
              intent.databaseSHA256 == registration.record.replacementDatabase.sha256,
              intent.stagingIdentity == registration.record.replacementDatabase.identity,
              intent.installedIdentity == nil else { return false }
        if let completion = registration.completion {
            guard validRestoreCompletionNamespace(completion, for: databaseURL),
                  restoreCompletionNamespace(completion, matches: registration.record) else {
                return false
            }
        }
        return true
    }

    private func restoreJournalIsRegistered(
        identity: FileIdentity,
        sha256: String,
        record: RestoreTransactionRecord,
        in parent: PinnedDirectory
    ) throws -> Bool {
        guard let registration = try restoreJournalRegistration(in: parent) else { return false }
        return registration.journalName == restoreJournalName(
                for: parent.url.appendingPathComponent(record.databaseName)
            )
            && registration.journal == OwnershipLedgerIdentity(identity)
            && registration.journalIdentity == RestorePersistedIdentity(identity)
            && registration.journalSHA256 == sha256
            && registration.record == record
    }

    @discardableResult
    private func requireRestoreJournalCapability(
        record: RestoreTransactionRecord,
        journalName: String,
        journalIdentity: FileIdentity,
        in parent: PinnedDirectory
    ) throws -> RestoreJournalRegistration {
        guard journalName == restoreJournalName(
            for: parent.url.appendingPathComponent(record.databaseName)
        ),
        validRestoreTransactionRecord(
            record,
            for: parent.url.appendingPathComponent(record.databaseName)
        ),
        let registration = try restoreJournalRegistration(in: parent),
        registration.record == record,
        registration.journalName == journalName,
        registration.journal == OwnershipLedgerIdentity(journalIdentity),
        registration.journalIdentity == RestorePersistedIdentity(journalIdentity),
        let registeredIntent = registration.stagingIntent,
        try restoreStagingIntent(in: parent) == registeredIntent,
        let observation = try restoreArtifactObservation(named: journalName, in: parent),
        observation.identity == journalIdentity,
        observation.sha256 == registration.journalSHA256 else {
            throw RestoreError.recoveryRequired(
                "The exact parent/journal/record capability changed before a restore namespace mutation.",
                artifactURL: nil
            )
        }
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: journalName
        )
        guard descriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "The registered restore record was no longer descriptor-reachable.",
                artifactURL: nil
            )
        }
        defer { Darwin.close(descriptor) }
        let bytes = try data(from: descriptor, artifactName: journalName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard sha256(bytes) == registration.journalSHA256,
              try encoder.encode(record) == bytes,
              try PinnedPackage.descriptorIdentity(descriptor) == journalIdentity,
              try PinnedDirectory.childPathIdentity(
                parent.descriptor,
                name: journalName
              ) == journalIdentity else {
            throw RestoreError.recoveryRequired(
                "The canonical restore record changed during exact capability revalidation.",
                artifactURL: nil
            )
        }
        return registration
    }

    private func saveRestoreCompletionNamespace(
        outcome: RestoreCompletionNamespace.Outcome,
        record: RestoreTransactionRecord,
        at databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreCompletionNamespace {
        guard let registration = try restoreJournalRegistration(in: parent),
              registration.record == record else {
            throw RestoreError.recoveryRequired(
                "The restore completion namespace lost its exact transaction registration.",
                artifactURL: nil
            )
        }
        let journalName = restoreJournalName(for: databaseURL)
        guard let journal = try restoreArtifactObservation(named: journalName, in: parent),
              registration.journal == OwnershipLedgerIdentity(journal.identity) else {
            throw RestoreError.recoveryRequired(
                "The restore completion transition lost its exact journal capability.",
                artifactURL: nil
            )
        }
        _ = try requireRestoreJournalCapability(
            record: record,
            journalName: journalName,
            journalIdentity: journal.identity,
            in: parent
        )
        let completion = try captureRestoreCompletionNamespace(
            outcome: outcome,
            at: databaseURL,
            in: parent
        )
        guard restoreCompletionNamespace(completion, matches: record) else {
            throw RestoreError.recoveryRequired(
                "The resulting database does not match the registered committed or compensated transaction state.",
                artifactURL: nil
            )
        }
        try saveRestoreJournalRegistration(
            RestoreJournalRegistration(
                version: registration.version,
                authority: registration.authority,
                journalName: registration.journalName,
                journal: registration.journal,
                journalIdentity: registration.journalIdentity,
                journalSHA256: registration.journalSHA256,
                record: registration.record,
                stagingIntent: registration.stagingIntent,
                completion: completion
            ),
            in: parent
        )
        return completion
    }

    private func captureRestoreCompletionNamespace(
        outcome: RestoreCompletionNamespace.Outcome,
        at databaseURL: URL,
        in parent: PinnedDirectory
    ) throws -> RestoreCompletionNamespace {
        func artifact(
            _ name: String,
            _ observation: RestoreArtifactObservation,
            retainedName: String? = nil
        ) -> RestoreJournalArtifact {
            RestoreJournalArtifact(
                originalName: name,
                retainedName: retainedName ?? name,
                identity: RestorePersistedIdentity(observation.identity),
                sha256: observation.sha256
            )
        }
        guard let database = try restoreArtifactObservation(
            named: databaseURL.lastPathComponent,
            in: parent
        ) else {
            throw RestoreError.recoveryRequired(
                "The resulting database is absent while recording restore completion.",
                artifactURL: nil
            )
        }
        var sidecars: [RestoreJournalArtifact] = []
        for suffix in ["-wal", "-shm"] {
            let name = databaseURL.lastPathComponent + suffix
            if let observation = try restoreArtifactObservation(named: name, in: parent) {
                sidecars.append(artifact(
                    name,
                    observation,
                    retainedName: ".cid851-restore-\(UUID().uuidString.lowercased())\(suffix)"
                ))
            }
        }
        let completion = RestoreCompletionNamespace(
            outcome: outcome,
            database: artifact(databaseURL.lastPathComponent, database),
            sidecars: sidecars
        )
        guard validRestoreCompletionNamespace(completion, for: databaseURL) else {
            throw RestoreError.recoveryRequired(
                "The resulting DB/WAL/SHM namespace could not be registered exactly.",
                artifactURL: nil
            )
        }
        return completion
    }

    private func validRestoreCompletionNamespace(
        _ completion: RestoreCompletionNamespace,
        for databaseURL: URL
    ) -> Bool {
        let databaseName = databaseURL.lastPathComponent
        guard validRestoreArtifact(completion.database),
              completion.database.originalName == databaseName,
              completion.database.retainedName == databaseName,
              completion.sidecars.count <= 2 else { return false }
        let expectedNames = ["-wal", "-shm"]
            .map { databaseName + $0 }
            .filter { name in completion.sidecars.contains { $0.originalName == name } }
        return completion.sidecars.map(\.originalName) == expectedNames
            && completion.sidecars.allSatisfy { artifact in
                guard validRestoreArtifact(artifact),
                      let suffix = ["-wal", "-shm"].first(where: {
                          artifact.originalName == databaseName + $0
                      }) else { return false }
                return isGeneratedRestoreSidecarName(artifact.retainedName, suffix: suffix)
            }
    }

    private func restoreCompletionNamespace(
        _ completion: RestoreCompletionNamespace,
        matches record: RestoreTransactionRecord
    ) -> Bool {
        let expected = completion.outcome == .committed
            ? record.replacementDatabase
            : record.originalDatabase
        return completion.database.identity == expected.identity
            && completion.database.sha256 == expected.sha256
    }

    private func requireRestoreCompletionNamespace(
        _ completion: RestoreCompletionNamespace,
        at databaseURL: URL,
        in parent: PinnedDirectory
    ) throws {
        try physicallyVerifyRestoreNamespaceOccupants(
            databaseURL,
            expectedDatabase: completion.database,
            expectedSidecars: completion.sidecars,
            in: parent
        )
    }

    private func clearRestoreJournalRegistration(in parent: PinnedDirectory) throws {
        let result = fremovexattr(
            parent.descriptor,
            restoreJournalRegistrationAttribute,
            0
        )
        guard result == 0 || errno == ENOATTR else {
            throw RestoreError.recoveryRequired(
                "The restore journal registration could not be cleared after record durability.",
                artifactURL: nil
            )
        }
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The restore journal registration cleanup could not be durably flushed.",
                artifactURL: nil
            )
        }
    }

    private func clearCompletedRestoreMetadata(in parent: PinnedDirectory) throws {
        try clearRestoreStagingIntent(in: parent)
        try clearRestoreJournalRegistration(in: parent)
    }

    private func saveRestoreStagingIntent(
        _ intent: RestoreStagingIntent,
        in parent: PinnedDirectory
    ) throws {
        guard validRestoreStagingIntent(intent, in: parent) else {
            throw RestoreError.recoveryRequired(
                "The deterministic restore staging intent is invalid.",
                artifactURL: nil
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(intent)
        let result = encoded.withUnsafeBytes { bytes in
            fsetxattr(
                parent.descriptor,
                restoreStagingIntentAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard result == 0, fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The deterministic restore staging intent could not be durably published.",
                artifactURL: nil
            )
        }
        guard try restoreStagingIntent(in: parent) == intent else {
            throw RestoreError.recoveryRequired(
                "The deterministic restore staging intent failed exact read-back validation.",
                artifactURL: nil
            )
        }
    }

    private func restoreStagingIntent(
        in parent: PinnedDirectory
    ) throws -> RestoreStagingIntent? {
        let size = fgetxattr(
            parent.descriptor,
            restoreStagingIntentAttribute,
            nil,
            0,
            0,
            0
        )
        if size < 0 {
            guard errno == ENOATTR else {
                throw RestoreError.recoveryRequired(
                    "The restore staging intent could not be inspected.",
                    artifactURL: nil
                )
            }
            return nil
        }
        guard size > 0, size <= 8 * 1_024 else { return nil }
        var encoded = Data(count: size)
        let read = encoded.withUnsafeMutableBytes { bytes in
            fgetxattr(
                parent.descriptor,
                restoreStagingIntentAttribute,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        guard read == size,
              let intent = try? JSONDecoder().decode(RestoreStagingIntent.self, from: encoded),
              validRestoreStagingIntent(intent, in: parent) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(intent) == encoded else { return nil }
        return intent
    }

    private func validRestoreStagingIntent(
        _ intent: RestoreStagingIntent,
        in parent: PinnedDirectory
    ) -> Bool {
        guard intent.version == RestoreStagingIntent.currentVersion,
              intent.authority == OwnershipLedgerIdentity(parent.identity),
              isSafeRestoreMemberName(intent.databaseName),
              isLowercaseSHA256(intent.databaseSHA256) else { return false }
        let stagingNameIsValid: Bool
        switch intent.mode {
        case .existing:
            stagingNameIsValid = isGeneratedRestoreDatabaseName(intent.stagingName)
        case .absent:
            stagingNameIsValid = isCanonicalUUIDMember(
                intent.stagingName,
                prefix: ".cid851-restore-new-",
                suffix: ".sqlite"
            )
        }
        guard stagingNameIsValid else { return false }
        switch intent.phase {
        case .planned:
            return intent.stagingIdentity == nil
                && intent.installedIdentity == nil
                && intent.completion == nil
        case .prepared:
            return intent.stagingIdentity != nil
                && intent.installedIdentity == nil
                && intent.completion == nil
        case .published:
            return intent.mode == .absent
                && intent.stagingIdentity != nil
                && intent.installedIdentity != nil
                && intent.completion == nil
        case .completed:
            guard intent.mode == .absent,
                  intent.stagingIdentity != nil,
                  let installed = intent.installedIdentity,
                  let completion = intent.completion,
                  completion.outcome == .committed,
                  validRestoreCompletionNamespace(
                    completion,
                    for: parent.url.appendingPathComponent(intent.databaseName)
                  ) else { return false }
            return completion.database.identity == installed
                && completion.database.sha256 == intent.databaseSHA256
        }
    }

    private func clearRestoreStagingIntent(in parent: PinnedDirectory) throws {
        let result = fremovexattr(
            parent.descriptor,
            restoreStagingIntentAttribute,
            0
        )
        guard result == 0 || errno == ENOATTR else {
            throw RestoreError.recoveryRequired(
                "The restore staging intent could not be cleared.",
                artifactURL: nil
            )
        }
        guard fsync(parent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The restore staging-intent removal durability point failed.",
                artifactURL: nil
            )
        }
    }

    private func restoreArtifactObservation(
        named name: String,
        in parent: PinnedDirectory
    ) throws -> RestoreArtifactObservation? {
        var reachable = stat()
        guard fstatat(parent.descriptor, name, &reachable, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw RestoreError.recoveryRequired(
                "A restore namespace occupant could not be inspected safely.",
                artifactURL: nil
            )
        }
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: name
        )
        guard descriptor >= 0 else {
            throw RestoreError.recoveryRequired(
                "A restore namespace occupant could not be pinned safely.",
                artifactURL: nil
            )
        }
        defer { Darwin.close(descriptor) }
        let identity = try PinnedPackage.descriptorIdentity(descriptor)
        guard identity.fileType == S_IFREG,
              identity.linkCount == 1,
              try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == identity else {
            throw RestoreError.recoveryRequired(
                "A restore namespace occupant changed identity while being pinned.",
                artifactURL: nil
            )
        }
        let bytes = try data(from: descriptor, artifactName: name)
        guard try PinnedPackage.descriptorIdentity(descriptor) == identity,
              try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == identity else {
            throw RestoreError.recoveryRequired(
                "A restore namespace occupant changed during content revalidation.",
                artifactURL: nil
            )
        }
        return RestoreArtifactObservation(identity: identity, sha256: sha256(bytes))
    }

    private func restoreObservation(
        _ observation: RestoreArtifactObservation,
        matches artifact: RestoreJournalArtifact
    ) -> Bool {
        artifact.identity.matches(observation.identity) && artifact.sha256 == observation.sha256
    }

    private func removeRestoreArtifact(
        named name: String,
        expected: FileIdentity,
        expectedSHA256: String? = nil,
        in parent: PinnedDirectory
    ) throws {
        guard (expectedSHA256 == nil
                ? try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == expected
                : try restoreArtifactMatches(
                    named: name,
                    identity: expected,
                    sha256: expectedSHA256!,
                    in: parent
                )),
              unlinkat(
                parent.descriptor,
                name,
                AT_SYMLINK_NOFOLLOW_ANY | AT_UNIQUE
              ) == 0 else {
            throw RestoreError.recoveryRequired(
                "An exact restore-owned artifact could not be identity-bound and removed; every replacement occupant was preserved.",
                artifactURL: parent.url.appendingPathComponent(name)
            )
        }
        var value = stat()
        guard fstatat(parent.descriptor, name, &value, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else {
            throw RestoreError.recoveryRequired(
                "An exact restore-owned artifact remained reachable after cleanup.",
                artifactURL: parent.url.appendingPathComponent(name)
            )
        }
    }

    private func removeRestoreJournal(
        named name: String,
        identity: FileIdentity,
        record: RestoreTransactionRecord,
        in parent: PinnedDirectory
    ) throws {
        let registration = try requireRestoreJournalCapability(
            record: record,
            journalName: name,
            journalIdentity: identity,
            in: parent
        )
        try removeRestoreArtifact(
            named: name,
            expected: identity,
            expectedSHA256: registration.journalSHA256,
            in: parent
        )
    }

    private func reconcileRolledBackSidecars(
        _ artifacts: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        for artifact in artifacts {
            let original = try restoreArtifactObservation(named: artifact.originalName, in: parent)
            let retained = try restoreArtifactObservation(named: artifact.retainedName, in: parent)
            if original.map({ restoreObservation($0, matches: artifact) }) == true, retained == nil {
                continue
            }
            guard original == nil,
                  let retained,
                  restoreObservation(retained, matches: artifact),
                  renameatx_np(
                    parent.descriptor,
                    artifact.retainedName,
                    parent.descriptor,
                    artifact.originalName,
                    UInt32(RENAME_EXCL)
                  ) == 0 else {
                throw RestoreError.recoveryRequired(
                    "An interrupted restore sidecar could not be restored without replacing an occupant.",
                    artifactURL: parent.url.appendingPathComponent(artifact.retainedName)
                )
            }
        }
    }

    private func reconcileCommittedRestoreSidecars(
        _ artifacts: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        for artifact in artifacts {
            if let retained = try restoreArtifactObservation(named: artifact.retainedName, in: parent) {
                guard restoreObservation(retained, matches: artifact) else {
                    throw RestoreError.recoveryRequired(
                        "A retained committed sidecar was replaced; it was preserved.",
                        artifactURL: parent.url.appendingPathComponent(artifact.retainedName)
                    )
                }
                try removeRestoreArtifact(
                    named: artifact.retainedName,
                    expected: retained.identity,
                    expectedSHA256: artifact.sha256,
                    in: parent
                )
            }
        }
    }

    private func quarantineReplacementSidecars(
        _ artifacts: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        for artifact in artifacts {
            let live = try restoreArtifactObservation(named: artifact.originalName, in: parent)
            let retained = try restoreArtifactObservation(named: artifact.retainedName, in: parent)
            if retained.map({ restoreObservation($0, matches: artifact) }) == true,
               live == nil {
                continue
            }
            guard retained == nil,
                  let live,
                  restoreObservation(live, matches: artifact),
                  renameatx_np(
                    parent.descriptor,
                    artifact.originalName,
                    parent.descriptor,
                    artifact.retainedName,
                    UInt32(RENAME_EXCL)
                  ) == 0,
                  let moved = try restoreArtifactObservation(
                    named: artifact.retainedName,
                    in: parent
                  ),
                  restoreObservation(moved, matches: artifact),
                  try restoreArtifactObservation(named: artifact.originalName, in: parent) == nil else {
                throw RestoreError.recoveryRequired(
                    "The complete replacement WAL/SHM namespace could not be separated before compensation.",
                    artifactURL: parent.url.appendingPathComponent(artifact.retainedName)
                )
            }
        }
    }

    private func removeQuarantinedReplacementSidecars(
        _ artifacts: [RestoreJournalArtifact],
        in parent: PinnedDirectory
    ) throws {
        for artifact in artifacts {
            guard let retained = try restoreArtifactObservation(
                named: artifact.retainedName,
                in: parent
            ) else { continue }
            guard restoreObservation(retained, matches: artifact) else {
                throw RestoreError.recoveryRequired(
                    "A separated replacement sidecar changed before cleanup and was preserved.",
                    artifactURL: parent.url.appendingPathComponent(artifact.retainedName)
                )
            }
            try removeRestoreArtifact(
                named: artifact.retainedName,
                expected: retained.identity,
                expectedSHA256: artifact.sha256,
                in: parent
            )
        }
    }

    private func replaceLiveDatabaseAtomically(
        at databaseURL: URL,
        with databaseData: Data,
        in databaseParent: PinnedDirectory,
        expectedDestinationLineage: DatabaseSourceLineage,
        recoveryArtifactURL: URL?,
        beforeMutation: () throws -> Void,
        beforeCleanup: () throws -> Void,
        validateInstalledDatabase: () throws -> Void,
        reopenOriginalDatabase: () throws -> Void
    ) throws -> RestoreCompletionNamespace {
        let destinationObservation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
        guard try destinationObservation.validate() == expectedDestinationLineage else {
            throw RestoreError.unhealthyBackup(
                databaseURL,
                messages: ["The live database identity changed before atomic replacement."]
            )
        }
        let liveDescriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: databaseParent.descriptor,
            name: databaseURL.lastPathComponent
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
        let liveSHA256 = sha256(try data(
            from: liveDescriptor,
            artifactName: databaseURL.lastPathComponent
        ))
        let plannedSidecars = try plannedRestoreSidecars(
            for: databaseURL,
            in: databaseParent
        )
        let plannedIntent = RestoreStagingIntent(
            version: RestoreStagingIntent.currentVersion,
            authority: OwnershipLedgerIdentity(databaseParent.identity),
            mode: .existing,
            phase: .planned,
            databaseName: databaseURL.lastPathComponent,
            stagingName: replacementName,
            databaseSHA256: sha256(databaseData),
            stagingIdentity: nil,
            installedIdentity: nil,
            completion: nil
        )
        try saveRestoreStagingIntent(plannedIntent, in: databaseParent)
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
        let preparedIntent = RestoreStagingIntent(
            version: plannedIntent.version,
            authority: plannedIntent.authority,
            mode: plannedIntent.mode,
            phase: .prepared,
            databaseName: plannedIntent.databaseName,
            stagingName: plannedIntent.stagingName,
            databaseSHA256: plannedIntent.databaseSHA256,
            stagingIdentity: RestorePersistedIdentity(replacementIdentity),
            installedIdentity: nil,
            completion: nil
        )
        try saveRestoreStagingIntent(preparedIntent, in: databaseParent)
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

        let journalRecord = RestoreTransactionRecord(
            version: RestoreTransactionRecord.currentVersion,
            databaseName: databaseURL.lastPathComponent,
            replacementName: replacementName,
            originalDatabase: RestoreJournalArtifact(
                originalName: databaseURL.lastPathComponent,
                retainedName: replacementName,
                identity: RestorePersistedIdentity(liveIdentity),
                sha256: liveSHA256
            ),
            replacementDatabase: RestoreJournalArtifact(
                originalName: databaseURL.lastPathComponent,
                retainedName: replacementName,
                identity: RestorePersistedIdentity(replacementIdentity),
                sha256: sha256(try data(from: replacementDescriptor, artifactName: replacementName))
            ),
            sidecars: plannedSidecars,
            recoveryArtifactPath: recoveryArtifactURL?.path
        )
        let transactionJournal = try createRestoreJournal(
            journalRecord,
            consuming: preparedIntent,
            for: databaseURL,
            in: databaseParent
        )
        _ = try requireRestoreJournalCapability(
            record: journalRecord,
            journalName: transactionJournal.name,
            journalIdentity: transactionJournal.identity,
            in: databaseParent
        )
        let quarantinedSidecars = try quarantineLiveSidecars(
            for: databaseURL,
            in: databaseParent,
            planned: plannedSidecars
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

        guard try restoreArtifactMatches(
            named: databaseURL.lastPathComponent,
            identity: liveIdentity,
            sha256: journalRecord.originalDatabase.sha256,
            in: databaseParent
        ),
        try restoreArtifactMatches(
            named: replacementName,
            identity: replacementIdentity,
            sha256: journalRecord.replacementDatabase.sha256,
            in: databaseParent
        ) else {
            rollbackQuarantinedLiveFiles(quarantinedSidecars, in: databaseParent)
            throw RestoreError.recoveryRequired(
                "The DB/WAL/SHM content changed immediately before the final atomic swap; every occupant and the transaction record were preserved.",
                artifactURL: recoveryArtifactURL
            )
        }

        _ = try requireRestoreJournalCapability(
            record: journalRecord,
            journalName: transactionJournal.name,
            journalIdentity: transactionJournal.identity,
            in: databaseParent
        )

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
                liveSHA256: journalRecord.originalDatabase.sha256,
                replacementSHA256: journalRecord.replacementDatabase.sha256,
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
        guard try restoreArtifactMatches(
            named: databaseURL.lastPathComponent,
            identity: replacementIdentity,
            sha256: journalRecord.replacementDatabase.sha256,
            in: databaseParent
        ),
        try restoreArtifactMatches(
            named: replacementName,
            identity: liveIdentity,
            sha256: journalRecord.originalDatabase.sha256,
            in: databaseParent
        ) else {
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                liveSHA256: journalRecord.originalDatabase.sha256,
                replacementSHA256: journalRecord.replacementDatabase.sha256,
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
                liveSHA256: journalRecord.originalDatabase.sha256,
                replacementSHA256: journalRecord.replacementDatabase.sha256,
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
                liveSHA256: journalRecord.originalDatabase.sha256,
                replacementSHA256: journalRecord.replacementDatabase.sha256,
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
        do {
            try validateInstalledDatabase()
        } catch {
            let replacementNamespace = try saveRestoreCompletionNamespace(
                outcome: .committed,
                record: journalRecord,
                at: databaseURL,
                in: databaseParent
            )
            try quarantineReplacementSidecars(
                replacementNamespace.sidecars,
                in: databaseParent
            )
            let outcome = rollbackDatabaseSwap(
                at: databaseURL,
                replacementName: replacementName,
                in: databaseParent,
                liveIdentity: liveIdentity,
                replacementIdentity: replacementIdentity,
                liveSHA256: journalRecord.originalDatabase.sha256,
                replacementSHA256: journalRecord.replacementDatabase.sha256,
                quarantinedSidecars: quarantinedSidecars
            )
            guard outcome.priorCoherentDatabaseRestored, outcome.parentFlushed else {
                throw RestoreError.recoveryRequired(
                    rollbackFailureMessage(
                        trigger: "The replacement failed physical reopen/integrity and exact compensation could not be durably proven. Trigger: \(error.localizedDescription)",
                        outcome: outcome
                    ),
                    artifactURL: recoveryArtifactURL
                )
            }
            try beforeCleanup()
            _ = try requireRestoreJournalCapability(
                record: journalRecord,
                journalName: transactionJournal.name,
                journalIdentity: transactionJournal.identity,
                in: databaseParent
            )
            try removeQuarantinedReplacementSidecars(
                replacementNamespace.sidecars,
                in: databaseParent
            )
            try removeRestoreArtifact(
                named: replacementName,
                expected: replacementIdentity,
                expectedSHA256: journalRecord.replacementDatabase.sha256,
                in: databaseParent
            )
            guard fsync(databaseParent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "The compensated original namespace could not establish its first cleanup durability point.",
                    artifactURL: recoveryArtifactURL
                )
            }
            do {
                try reopenOriginalDatabase()
            } catch {
                throw RestoreError.recoveryRequired(
                    "The exact original namespace was restored, but physical reopen failed: \(error.localizedDescription)",
                    artifactURL: recoveryArtifactURL
                )
            }
            let completion = try saveRestoreCompletionNamespace(
                outcome: .compensated,
                record: journalRecord,
                at: databaseURL,
                in: databaseParent
            )
            guard let compensatedDatabase = try restoreArtifactObservation(
                named: databaseURL.lastPathComponent,
                in: databaseParent
            ), restoreObservation(compensatedDatabase, matches: journalRecord.originalDatabase),
            fsync(databaseParent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "The reopened compensated namespace could not establish its completion durability point.",
                    artifactURL: recoveryArtifactURL
                )
            }
            try physicallyVerifyRestoreNamespace(
                databaseURL,
                expectedDatabase: completion.database,
                expectedSidecars: completion.sidecars,
                in: databaseParent
            )
            try requireRestoreCompletionNamespace(completion, at: databaseURL, in: databaseParent)
            try removeRestoreJournal(
                named: transactionJournal.name,
                identity: transactionJournal.identity,
                record: journalRecord,
                in: databaseParent
            )
            guard fsync(databaseParent.descriptor) == 0 else {
                throw RestoreError.recoveryRequired(
                    "The compensated namespace was durable and reopened, but the separate record-removal durability point failed.",
                    artifactURL: recoveryArtifactURL
                )
            }
            try clearCompletedRestoreMetadata(in: databaseParent)
            throw RestoreError.recoveredFailure(error.localizedDescription)
        }

        let completion = try saveRestoreCompletionNamespace(
            outcome: .committed,
            record: journalRecord,
            at: databaseURL,
            in: databaseParent
        )
        try requireRestoreCompletionNamespace(
            completion,
            at: databaseURL,
            in: databaseParent
        )
        guard try restoreArtifactMatches(
            named: databaseURL.lastPathComponent,
            identity: replacementIdentity,
            sha256: journalRecord.replacementDatabase.sha256,
            in: databaseParent
        ),
        try restoreArtifactMatches(
            named: replacementName,
            identity: liveIdentity,
            sha256: journalRecord.originalDatabase.sha256,
            in: databaseParent
        ),
        try quarantinedSidecars.allSatisfy({ sidecar in
            try restoreArtifactMatches(
                named: sidecar.hiddenName,
                identity: sidecar.identity,
                sha256: sidecar.sha256,
                in: databaseParent
            )
        }) else {
            throw RestoreError.recoveryRequired(
                "The live or retained DB/WAL/SHM content changed after reopen; no cleanup was attempted.",
                artifactURL: recoveryArtifactURL
            )
        }
        try beforeCleanup()
        _ = try requireRestoreJournalCapability(
            record: journalRecord,
            journalName: transactionJournal.name,
            journalIdentity: transactionJournal.identity,
            in: databaseParent
        )
        try removeRestoreArtifact(
            named: replacementName,
            expected: liveIdentity,
            expectedSHA256: journalRecord.originalDatabase.sha256,
            in: databaseParent
        )
        for sidecar in quarantinedSidecars {
            _ = try requireRestoreJournalCapability(
                record: journalRecord,
                journalName: transactionJournal.name,
                journalIdentity: transactionJournal.identity,
                in: databaseParent
            )
            try removeRestoreArtifact(
                named: sidecar.hiddenName,
                expected: sidecar.identity,
                expectedSHA256: sidecar.sha256,
                in: databaseParent
            )
        }
        guard fsync(databaseParent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The replacement reopened, but the resulting namespace could not establish its first cleanup durability point.",
                artifactURL: recoveryArtifactURL
            )
        }
        guard let committedDatabase = try restoreArtifactObservation(
            named: databaseURL.lastPathComponent,
            in: databaseParent
        ), restoreObservation(committedDatabase, matches: journalRecord.replacementDatabase) else {
            throw RestoreError.recoveryRequired(
                "The directory-synced replacement changed content before transaction-record cleanup.",
                artifactURL: recoveryArtifactURL
            )
        }
        try physicallyVerifyRestoreNamespace(
            databaseURL,
            expectedDatabase: completion.database,
            expectedSidecars: completion.sidecars,
            in: databaseParent
        )
        try requireRestoreCompletionNamespace(completion, at: databaseURL, in: databaseParent)
        try removeRestoreJournal(
            named: transactionJournal.name,
            identity: transactionJournal.identity,
            record: journalRecord,
            in: databaseParent
        )
        guard fsync(databaseParent.descriptor) == 0 else {
            throw RestoreError.recoveryRequired(
                "The replacement namespace was durable and reopened, but the separate record-removal durability point failed.",
                artifactURL: recoveryArtifactURL
            )
        }
        try clearCompletedRestoreMetadata(in: databaseParent)
        return completion
    }

    private func quarantineLiveSidecars(
        for databaseURL: URL,
        in databaseParent: PinnedDirectory,
        planned: [RestoreJournalArtifact]
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
                let descriptor = Self.openPinnedRegularChildNonBlocking(
                    directoryDescriptor: databaseParent.descriptor,
                    name: originalName
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
                let plannedArtifact = planned.first { $0.originalName == originalName }
                guard identity.fileType == S_IFREG,
                      identity.linkCount == 1,
                      FileIdentity(
                        device: reachable.st_dev,
                        inode: reachable.st_ino,
                        generation: reachable.st_gen,
                        fileType: reachable.st_mode & S_IFMT,
                        linkCount: reachable.st_nlink,
                        byteSize: reachable.st_size
                      ) == identity,
                      let plannedArtifact,
                      plannedArtifact.identity.matches(identity),
                      plannedArtifact.sha256 == sha256(try data(
                        from: descriptor,
                        artifactName: originalName
                      )) else {
                    throw RestoreError.unhealthyBackup(
                        databaseURL,
                        messages: ["A live SQLite sidecar changed before atomic quarantine."]
                    )
                }
                let hiddenName = plannedArtifact.retainedName
                let pinned = QuarantinedLiveFile(
                    originalName: originalName,
                    hiddenName: hiddenName,
                    identity: identity,
                    sha256: plannedArtifact.sha256,
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
            guard Set(moved.map(\.originalName)) == Set(planned.map(\.originalName)) else {
                throw RestoreError.unhealthyBackup(
                    databaseURL,
                    messages: ["A planned live SQLite sidecar disappeared before quarantine."]
                )
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
                  (try? sha256(data(
                    from: file.descriptor,
                    artifactName: file.hiddenName
                  ))) == file.sha256,
                  (try? restoreArtifactMatches(
                    named: file.hiddenName,
                    identity: file.identity,
                    sha256: file.sha256,
                    in: databaseParent
                  )) == true else { continue }
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
                && (try? sha256(data(
                    from: file.descriptor,
                    artifactName: file.originalName
                ))) == file.sha256
                && (try? restoreArtifactMatches(
                    named: file.originalName,
                    identity: file.identity,
                    sha256: file.sha256,
                    in: databaseParent
                )) == true
        }
    }

    private func rollbackDatabaseSwap(
        at databaseURL: URL,
        replacementName: String,
        in databaseParent: PinnedDirectory,
        liveIdentity: FileIdentity,
        replacementIdentity: FileIdentity,
        liveSHA256: String,
        replacementSHA256: String,
        quarantinedSidecars: [QuarantinedLiveFile]
    ) -> RestoreRollbackOutcome {
        let liveName = databaseURL.lastPathComponent
        let liveBeforeIsReplacement = (try? restoreArtifactMatches(
            named: liveName,
            identity: replacementIdentity,
            sha256: replacementSHA256,
            in: databaseParent
        )) == true
        let replacementBeforeIsOriginal = (try? restoreArtifactMatches(
            named: replacementName,
            identity: liveIdentity,
            sha256: liveSHA256,
            in: databaseParent
        )) == true
        if liveBeforeIsReplacement, replacementBeforeIsOriginal {
            _ = renameatx_np(
                databaseParent.descriptor,
                replacementName,
                databaseParent.descriptor,
                liveName,
                UInt32(RENAME_SWAP)
            )
        }

        let liveAfterIsOriginal = (try? restoreArtifactMatches(
            named: liveName,
            identity: liveIdentity,
            sha256: liveSHA256,
            in: databaseParent
        )) == true
        let replacementAfterIsOriginal = (try? restoreArtifactMatches(
            named: replacementName,
            identity: liveIdentity,
            sha256: liveSHA256,
            in: databaseParent
        )) == true
        let liveAfterIsReplacement = (try? restoreArtifactMatches(
            named: liveName,
            identity: replacementIdentity,
            sha256: replacementSHA256,
            in: databaseParent
        )) == true
        let replacementAfterIsReplacement = (try? restoreArtifactMatches(
            named: replacementName,
            identity: replacementIdentity,
            sha256: replacementSHA256,
            in: databaseParent
        )) == true
        let priorDatabaseLocation: String?
        if liveAfterIsOriginal {
            priorDatabaseLocation = "live:\(databaseURL.path)"
        } else if replacementAfterIsOriginal {
            priorDatabaseLocation = "retained:\(databaseParent.url.appendingPathComponent(replacementName).path)"
        } else {
            priorDatabaseLocation = nil
        }
        let replacementLocation: String?
        if replacementAfterIsReplacement {
            replacementLocation = databaseParent.url.appendingPathComponent(replacementName).path
        } else if liveAfterIsReplacement {
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

    private func restoreArtifactMatches(
        named name: String,
        identity: FileIdentity,
        sha256 expectedSHA256: String,
        in parent: PinnedDirectory
    ) throws -> Bool {
        guard let observation = try restoreArtifactObservation(named: name, in: parent) else {
            return false
        }
        return observation.identity == identity && observation.sha256 == expectedSHA256
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
            linkCount: 0,
            byteSize: 0,
            modifiedSeconds: 0,
            modifiedNanoseconds: 0,
            changedSeconds: 0,
            changedNanoseconds: 0
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
            fileManager: fileManager,
            membershipObservation: .descriptorOnly
        )
        let verified = try qualifyRestorePackage(
            package,
            expectedKind: nil,
            expectedLineage: artifact.lineageIdentifier,
            policyDirectory: policyDirectory,
            backupURL: packageURL
        )
        guard verified.verification.isVerified,
              verified.fingerprint.contentSHA256ByName == artifact.contentSHA256ByName,
              try qualifiedArtifact(
                policyDirectory: policyDirectory,
                packageName: artifact.packageName,
                package: verified,
                lineageIdentifier: artifact.lineageIdentifier,
                membershipObservation: .descriptorOnly
              ) == artifact else {
            throw BackupError.verification(
                "The qualified backup occupant changed before final use."
            )
        }
        let databaseData = try package.data(
            for: databaseFilename,
            maximumBytes: maximumDescriptorReadBytes
        )
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
        _ = packageName
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
            let child = Self.openPinnedRegularChildNonBlocking(
                directoryDescriptor: package.descriptor,
                name: childName
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
        var pathValue = stat()
        guard lstat(stateURL.path, &pathValue) == 0 else {
            if errno == ENOENT { return SafetyState() }
            throw BackupError.verification("The safety state member could not be inspected.")
        }
        let pinned = try pinnedStandaloneRegularFile(at: stateURL)
        defer { Darwin.close(pinned.descriptor) }
        let data = try self.data(
            from: pinned.descriptor,
            artifactName: stateURL.lastPathComponent
        )
        guard try PinnedDirectory.childPathIdentity(
            pinned.parent.descriptor,
            name: stateURL.lastPathComponent
        ) == pinned.identity else {
            throw BackupError.verification("The safety state member changed during its bounded read.")
        }
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
        kind: SQLiteBackupInfo.Kind
    ) -> [SQLiteBackupInfo] {
        guard let policyDirectory = try? existingPolicyDirectory(at: directoryURL),
              let authorityLease = try? PolicyLease(
                policyDirectory: policyDirectory,
                exclusive: false
              ) else { return [] }
        _ = authorityLease
        guard let names = try? boundedDirectoryNames(
            descriptor: policyDirectory.descriptor,
            maximumEntries: maximumAggregatePolicyEntries
        ) else { return [] }
        return names.compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let url = directoryURL.appendingPathComponent(
                name,
                isDirectory: URL(fileURLWithPath: name).pathExtension == packageExtension
            )
            switch URL(fileURLWithPath: name).pathExtension.lowercased() {
            case packageExtension:
                do {
                    let package = try PinnedPackage(
                        childNamed: name,
                        at: url,
                        in: policyDirectory,
                        requiredNames: [databaseFilename, manifestFilename].sorted(),
                        fileManager: fileManager,
                        membershipObservation: .descriptorOnly
                    )
                    let manifestBytes = try package.data(
                        for: manifestFilename,
                        maximumBytes: Self.retentionMaximumManifestBytes
                    )
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .secondsSince1970
                    let manifest = try decoder.decode(BackupManifest.self, from: manifestBytes)
                    try package.validateUnchanged()
                    if manifest.formatVersion >= BackupManifest.currentFormatVersion,
                       !isGeneratedPackageSlotName(name) {
                        return nil
                    }
                    let verified = try qualifyRestorePackage(
                        package,
                        expectedKind: kind,
                        expectedLineage: nil,
                        policyDirectory: policyDirectory,
                        backupURL: url,
                        allowRecordedLineageWithoutCurrentSource: kind == .preflight
                    )
                    return SQLiteBackupInfo(
                        kind: kind,
                        url: url,
                        createdAt: verified.createdAt,
                        byteSize: try boundedQualifiedPackageByteSize(verified),
                        verification: verified.verification
                    )
                } catch {
                    let requiredNames = [databaseFilename, manifestFilename].sorted()
                    let pinned = try? PinnedPackage(
                        childNamed: name,
                        at: url,
                        in: policyDirectory,
                        requiredNames: requiredNames,
                        fileManager: fileManager,
                        membershipObservation: .descriptorOnly
                    )
                    let before = try? pinned?.fingerprint()
                    let unchanged = pinned.flatMap { package in
                        guard (try? package.validateUnchanged()) != nil,
                              let after = try? package.fingerprint(),
                              before == after else { return false }
                        return true
                    } ?? false
                    let fallbackBytes: Int64 = pinned.flatMap { package in
                        guard package.identity.childrenByName.count <= 2 else { return nil }
                        var total: Int64 = 0
                        for identity in package.identity.childrenByName.values {
                            guard identity.fileType == S_IFREG,
                                  identity.linkCount == 1,
                                  identity.byteSize >= 0,
                                  let next = try? Self.checkedRetentionCapacitySum(
                                    total,
                                    Int64(identity.byteSize)
                                  ),
                                  next <= maximumDescriptorReadBytes else { return nil }
                            total = next
                        }
                        return total
                    } ?? 0
                    return SQLiteBackupInfo(
                        kind: kind,
                        url: url,
                        createdAt: .distantPast,
                        byteSize: fallbackBytes,
                        verification: BackupVerification(
                            state: .unusable,
                            schemaVersion: nil,
                            databaseSHA256: nil,
                            manifestSHA256: nil,
                            artifactNames: pinned?.artifactNames ?? [],
                            retainedBytesUnchanged: unchanged,
                            messages: [error.localizedDescription]
                        )
                    )
                }
            case "db":
                return descriptorBoundRawBackupInfo(
                    named: name,
                    at: url,
                    kind: kind,
                    in: policyDirectory
                )
            default:
                return nil
            }
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

    private func boundedQualifiedPackageByteSize(
        _ verified: VerifiedPackage
    ) throws -> Int64 {
        guard verified.identity.childrenByName.count <= 2 else {
            throw BackupError.verification(
                "The qualified package exceeds the listing metadata entry bound."
            )
        }
        var total: Int64 = 0
        for identity in verified.identity.childrenByName.values {
            guard identity.fileType == S_IFREG,
                  identity.linkCount == 1,
                  identity.byteSize >= 0 else {
                throw BackupError.verification(
                    "A qualified package member has invalid listing metadata."
                )
            }
            total = try Self.checkedRetentionCapacitySum(total, Int64(identity.byteSize))
            guard total <= maximumDescriptorReadBytes else {
                throw BackupError.verification(
                    "The qualified package exceeds the listing metadata byte bound."
                )
            }
        }
        return total
    }

    private func descriptorBoundRawBackupInfo(
        named name: String,
        at url: URL,
        kind: SQLiteBackupInfo.Kind,
        in parent: PinnedDirectory
    ) -> SQLiteBackupInfo {
        let descriptor = Self.openPinnedRegularChildNonBlocking(
            directoryDescriptor: parent.descriptor,
            name: name
        )
        guard descriptor >= 0 else {
            return SQLiteBackupInfo(
                kind: kind,
                url: url,
                createdAt: .distantPast,
                byteSize: 0,
                verification: BackupVerification(
                    state: .unusable,
                    schemaVersion: nil,
                    databaseSHA256: nil,
                    manifestSHA256: nil,
                    artifactNames: [name],
                    retainedBytesUnchanged: false,
                    messages: ["The raw recovery candidate is not a qualified regular file."]
                )
            )
        }
        defer { Darwin.close(descriptor) }
        do {
            var metadata = stat()
            let identity = try PinnedPackage.descriptorIdentity(descriptor)
            guard fstat(descriptor, &metadata) == 0,
                  identity.fileType == S_IFREG,
                  identity.linkCount == 1,
                  identity.byteSize >= 0,
                  identity.byteSize <= maximumDescriptorReadBytes,
                  try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == identity else {
                throw BackupError.verification(
                    "The raw recovery candidate changed during descriptor-bound metadata acquisition."
                )
            }
            let bytes = try data(from: descriptor, artifactName: name)
            let database = try verifySQLiteDatabase(data: bytes, descriptor: descriptor)
            guard try PinnedPackage.descriptorIdentity(descriptor) == identity,
                  try PinnedDirectory.childPathIdentity(parent.descriptor, name: name) == identity else {
                throw BackupError.verification(
                    "The raw recovery candidate changed during descriptor-bound verification."
                )
            }
            return SQLiteBackupInfo(
                kind: kind,
                url: url,
                createdAt: Date(timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec)
                    + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000),
                byteSize: Int64(identity.byteSize),
                verification: BackupVerification(
                    state: .legacyRecovery,
                    schemaVersion: database.schemaVersion,
                    databaseSHA256: database.sha256,
                    manifestSHA256: nil,
                    artifactNames: [name],
                    retainedBytesUnchanged: true,
                    messages: ["legacy recovery only; no current source lineage evidence"]
                )
            )
        } catch {
            return SQLiteBackupInfo(
                kind: kind,
                url: url,
                createdAt: .distantPast,
                byteSize: 0,
                verification: BackupVerification(
                    state: .unusable,
                    schemaVersion: nil,
                    databaseSHA256: nil,
                    manifestSHA256: nil,
                    artifactNames: [name],
                    retainedBytesUnchanged: false,
                    messages: [error.localizedDescription]
                )
            )
        }
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
        try Self.readBoundedDescriptor(
            descriptor,
            maximumBytes: maximumDescriptorReadBytes,
            artifactName: artifactName
        )
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
