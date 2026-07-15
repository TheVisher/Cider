import Darwin
import Foundation

enum CiderExportOverwriteIntent: Equatable, Sendable {
    case prohibit
    case replaceExisting
}

enum CiderExportWriteError: Error, Equatable, LocalizedError {
    case invalidDestination
    case unsafeDestination
    case destinationExists
    case destinationChanged
    case cancelled
    case writeFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            "Choose a valid local export destination."
        case .unsafeDestination:
            "Cider blocked an unsafe export destination."
        case .destinationExists:
            "The export destination already exists."
        case .destinationChanged:
            "The export destination changed before Cider could finish."
        case .cancelled:
            "The export was cancelled."
        case .writeFailed:
            "Cider could not write the export."
        case .rollbackFailed:
            "Cider could not safely restore the prior export destination."
        }
    }
}

enum CiderExportWriteCheckpoint: Equatable, Sendable {
    case afterStaging
    case beforeCommit
    case afterReplacement
}

struct CiderExportWriteHooks {
    var checkpoint: (CiderExportWriteCheckpoint) throws -> Void = { _ in }
    var isCancelled: () -> Bool = { Task<Never, Never>.isCancelled }
}

/// Filesystem-only export commit policy. Output is fully staged beside the
/// destination before a no-replace rename or an explicit file swap. This is not
/// a transaction with databases or other external side effects.
struct CiderExportWritePolicy {
    private enum OutputKind {
        case file
        case directory
    }

    private struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let isDirectory: Bool
        let isRegularFile: Bool
        let byteSize: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
    }

    private struct DirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct DestinationContext {
        let requestedParent: URL
        let resolvedParent: URL
        let canonicalDestination: URL
        let parentIdentity: DirectoryIdentity
        let existing: FileSnapshot?
    }

    private let fileManager: FileManager
    private let hooks: CiderExportWriteHooks

    init(fileManager: FileManager = .default, hooks: CiderExportWriteHooks = .init()) {
        self.fileManager = fileManager
        self.hooks = hooks
    }

    func writeData(
        _ data: Data,
        to destination: URL,
        overwrite: CiderExportOverwriteIntent = .prohibit
    ) throws {
        try writeFile(to: destination, overwrite: overwrite) { staging in
            try data.write(to: staging, options: .withoutOverwriting)
        }
    }

    func writeText(
        _ text: String,
        to destination: URL,
        overwrite: CiderExportOverwriteIntent = .prohibit
    ) throws {
        guard let data = text.data(using: .utf8) else { throw CiderExportWriteError.writeFailed }
        try writeData(data, to: destination, overwrite: overwrite)
    }

    func copyFile(
        from source: URL,
        to destination: URL,
        overwrite: CiderExportOverwriteIntent = .prohibit
    ) throws {
        guard source.isFileURL,
              fileManager.fileExists(atPath: source.path),
              !isSymbolicLink(source),
              (try? snapshotIfPresent(source)?.isRegularFile) == true
        else { throw CiderExportWriteError.writeFailed }

        try writeFile(to: destination, overwrite: overwrite) { staging in
            try fileManager.copyItem(at: source, to: staging)
        }
    }

    func writeFile(
        to destination: URL,
        overwrite: CiderExportOverwriteIntent = .prohibit,
        populate: (URL) throws -> Void
    ) throws {
        try performWrite(kind: .file, to: destination, overwrite: overwrite, populate: populate)
    }

    func writeDirectory(
        to destination: URL,
        overwrite: CiderExportOverwriteIntent = .prohibit,
        populate: (URL) throws -> Void
    ) throws {
        guard overwrite == .prohibit else {
            // Package replacement is intentionally unsupported: recursively deleting an
            // old package cannot provide the same bounded rollback as a single file swap.
            throw CiderExportWriteError.unsafeDestination
        }
        try performWrite(kind: .directory, to: destination, overwrite: overwrite, populate: populate)
    }

    private func performWrite(
        kind: OutputKind,
        to destination: URL,
        overwrite: CiderExportOverwriteIntent,
        populate: (URL) throws -> Void
    ) throws {
        try checkCancellation()
        let context = try inspectDestination(destination, kind: kind)
        if overwrite == .prohibit, context.existing != nil {
            throw CiderExportWriteError.destinationExists
        }

        let staging = context.resolvedParent.appendingPathComponent(
            ".cider-export-\(UUID().uuidString).partial",
            isDirectory: kind == .directory
        )
        var stagingExists = false
        defer {
            if stagingExists {
                try? fileManager.removeItem(at: staging)
            }
        }

        do {
            if kind == .directory {
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            }
            stagingExists = true
            try populate(staging)
            try validateStaging(staging, kind: kind, parent: context.resolvedParent)
            try hooks.checkpoint(.afterStaging)
            try checkCancellation()
            try hooks.checkpoint(.beforeCommit)
            try checkCancellation()
            try revalidate(context, kind: kind, overwrite: overwrite)

            if let existing = context.existing, overwrite == .replaceExisting {
                guard kind == .file, !existing.isDirectory else {
                    throw CiderExportWriteError.unsafeDestination
                }
                try swap(staging, context.canonicalDestination)
                do {
                    try hooks.checkpoint(.afterReplacement)
                    try checkCancellation()
                    try fileManager.removeItem(at: staging)
                    stagingExists = false
                } catch let commitError {
                    do {
                        try swap(staging, context.canonicalDestination)
                    } catch {
                        // `staging` may still contain the only prior destination bytes.
                        // Do not let the outer cleanup destroy it after an indeterminate rollback.
                        stagingExists = false
                        throw CiderExportWriteError.rollbackFailed
                    }
                    try? fileManager.removeItem(at: staging)
                    stagingExists = false
                    if let policyError = commitError as? CiderExportWriteError,
                       policyError == .cancelled {
                        throw policyError
                    }
                    throw CiderExportWriteError.writeFailed
                }
            } else {
                try moveExclusively(staging, context.canonicalDestination)
                stagingExists = false
            }
        } catch let error as CiderExportWriteError {
            throw error
        } catch {
            throw CiderExportWriteError.writeFailed
        }
    }

    private func inspectDestination(_ destination: URL, kind: OutputKind) throws -> DestinationContext {
        guard destination.isFileURL,
              !destination.lastPathComponent.isEmpty,
              destination.lastPathComponent != ".",
              destination.lastPathComponent != ".."
        else { throw CiderExportWriteError.invalidDestination }

        let requestedParent = destination.standardizedFileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: requestedParent.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw CiderExportWriteError.invalidDestination }

        let resolvedParent = requestedParent.resolvingSymlinksInPath().standardizedFileURL
        let canonicalDestination = resolvedParent.appendingPathComponent(
            destination.lastPathComponent,
            isDirectory: kind == .directory
        )
        let parentIdentity = try directoryIdentity(for: resolvedParent)
        if isSymbolicLink(destination.standardizedFileURL)
            || isSymbolicLink(canonicalDestination) {
            throw CiderExportWriteError.unsafeDestination
        }

        let existing = try snapshotIfPresent(canonicalDestination)
        if let existing {
            switch kind {
            case .file where !existing.isRegularFile:
                throw CiderExportWriteError.invalidDestination
            case .directory where !existing.isDirectory:
                throw CiderExportWriteError.invalidDestination
            default:
                break
            }
        }
        return DestinationContext(
            requestedParent: requestedParent,
            resolvedParent: resolvedParent,
            canonicalDestination: canonicalDestination,
            parentIdentity: parentIdentity,
            existing: existing
        )
    }

    private func revalidate(
        _ context: DestinationContext,
        kind: OutputKind,
        overwrite: CiderExportOverwriteIntent
    ) throws {
        let currentParent = context.requestedParent.resolvingSymlinksInPath().standardizedFileURL
        guard currentParent == context.resolvedParent,
              try directoryIdentity(for: currentParent) == context.parentIdentity
        else { throw CiderExportWriteError.unsafeDestination }
        guard !isSymbolicLink(context.canonicalDestination) else {
            throw CiderExportWriteError.unsafeDestination
        }

        let current = try snapshotIfPresent(context.canonicalDestination)
        switch (context.existing, current, overwrite) {
        case (nil, nil, _):
            return
        case (nil, .some, .prohibit):
            throw CiderExportWriteError.destinationExists
        case (nil, .some, .replaceExisting):
            throw CiderExportWriteError.destinationChanged
        case (.some, nil, _):
            throw CiderExportWriteError.destinationChanged
        case (let expected?, let actual?, .replaceExisting):
            guard expected == actual else { throw CiderExportWriteError.destinationChanged }
            guard kind == .file, !actual.isDirectory else {
                throw CiderExportWriteError.unsafeDestination
            }
        case (.some, .some, .prohibit):
            throw CiderExportWriteError.destinationExists
        }
    }

    private func validateStaging(_ staging: URL, kind: OutputKind, parent: URL) throws {
        guard staging.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL,
              !isSymbolicLink(staging),
              let snapshot = try snapshotIfPresent(staging)
        else { throw CiderExportWriteError.writeFailed }
        switch kind {
        case .file where !snapshot.isRegularFile:
            throw CiderExportWriteError.writeFailed
        case .directory where !snapshot.isDirectory:
            throw CiderExportWriteError.writeFailed
        default:
            break
        }
    }

    private func snapshotIfPresent(_ url: URL) throws -> FileSnapshot? {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw CiderExportWriteError.unsafeDestination
        }
        let fileType = metadata.st_mode & mode_t(S_IFMT)
        guard fileType != mode_t(S_IFLNK) else {
            throw CiderExportWriteError.unsafeDestination
        }
        return FileSnapshot(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            isDirectory: fileType == mode_t(S_IFDIR),
            isRegularFile: fileType == mode_t(S_IFREG),
            byteSize: metadata.st_size,
            modificationSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec)
        )
    }

    private func directoryIdentity(for url: URL) throws -> DirectoryIdentity {
        guard let snapshot = try snapshotIfPresent(url), snapshot.isDirectory else {
            throw CiderExportWriteError.unsafeDestination
        }
        return DirectoryIdentity(device: snapshot.device, inode: snapshot.inode)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func checkCancellation() throws {
        if hooks.isCancelled() { throw CiderExportWriteError.cancelled }
    }

    private func moveExclusively(_ source: URL, _ destination: URL) throws {
        let errorNumber = rename(source, destination, flags: UInt32(RENAME_EXCL))
        guard errorNumber == 0 else {
            if errorNumber == EEXIST || errorNumber == ENOTEMPTY {
                throw CiderExportWriteError.destinationExists
            }
            throw CiderExportWriteError.writeFailed
        }
    }

    private func swap(_ source: URL, _ destination: URL) throws {
        guard rename(source, destination, flags: UInt32(RENAME_SWAP)) == 0 else {
            throw CiderExportWriteError.writeFailed
        }
    }

    private func rename(_ source: URL, _ destination: URL, flags: UInt32) -> Int32 {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, flags)
            }
        }
        return result == 0 ? 0 : errno
    }
}
