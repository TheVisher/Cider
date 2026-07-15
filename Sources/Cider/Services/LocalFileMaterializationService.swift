import Darwin
import Foundation

protocol LocalFileMaterializationFailureDisposition {
    var retainPreparedMaterialization: Bool { get }
}

/// Rooted, filesystem-only materialization for validated local files whose domain
/// identity is not a `VaultFile`. Domain adapters remain responsible for policy,
/// persistence, and when a prepared asset becomes authoritative.
@MainActor
final class LocalFileMaterializationService {
    struct Request: Sendable {
        let validated: LocalFileValidatedMetadata
        let rootURL: URL
        let destinationRelativeDirectory: String
        let filename: String
        let stableID: UUID
    }

    struct Result: Equatable, Sendable {
        let fileURL: URL
        let relativePath: String
        let validatedMetadata: LocalFileValidatedMetadata
        let wasReused: Bool
    }

    struct Hooks {
        var beforeSourceCopy: ((_ accessURL: URL, _ sourceURL: URL, _ destinationURL: URL) throws -> Void)?
        var afterCopy: ((URL) throws -> Void)?

        init(
            beforeSourceCopy: ((_ accessURL: URL, _ sourceURL: URL, _ destinationURL: URL) throws -> Void)? = nil,
            afterCopy: ((URL) throws -> Void)? = nil
        ) {
            self.beforeSourceCopy = beforeSourceCopy
            self.afterCopy = afterCopy
        }
    }

    private final class Prepared {
        let result: Result
        private let fileManager: FileManager
        private let ownedURLs: [URL]
        private let createdDirectories: [URL]
        private var finalized = false

        init(result: Result, fileManager: FileManager, ownedURLs: [URL], createdDirectories: [URL]) {
            self.result = result
            self.fileManager = fileManager
            self.ownedURLs = ownedURLs
            self.createdDirectories = createdDirectories
        }

        func commit() { finalized = true }

        func rollback() {
            guard !finalized else { return }
            finalized = true
            for url in ownedURLs.reversed() {
                try? fileManager.removeItem(at: url)
            }
            for directory in createdDirectories {
                if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                    try? fileManager.removeItem(at: directory)
                }
            }
        }

        deinit { rollback() }
    }

    private let validator: LocalFileIntakeValidator
    private let fileManager: FileManager
    private let hooks: Hooks

    init(
        validator: LocalFileIntakeValidator = LocalFileIntakeValidator(),
        fileManager: FileManager = .default,
        hooks: Hooks = .init()
    ) {
        self.validator = validator
        self.fileManager = fileManager
        self.hooks = hooks
    }

    func materialize<T>(
        _ request: Request,
        finalize: (Result) async throws -> T
    ) async throws -> T {
        let prepared = try prepare(request)
        do {
            let value = try await finalize(prepared.result)
            prepared.commit()
            return value
        } catch {
            if let disposition = error as? LocalFileMaterializationFailureDisposition,
               disposition.retainPreparedMaterialization {
                prepared.commit()
            } else {
                prepared.rollback()
            }
            throw error
        }
    }

    private func prepare(_ request: Request) throws -> Prepared {
        let root = request.rootURL.standardizedFileURL
        guard Self.isSafeRelativePath(request.destinationRelativeDirectory) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        try validateExistingComponent(root, requiresDirectory: true)

        var createdDirectories: [URL] = []
        var ownedURLs: [URL] = []
        do {
            let directory = try createDestinationDirectory(
                root: root,
                relativePath: request.destinationRelativeDirectory,
                createdDirectories: &createdDirectories
            )
            let destination = try destinationURL(for: request, directory: directory)
            if entryExists(at: destination) {
                try validateDestinationDirectory(root: root, relativePath: request.destinationRelativeDirectory)
                try validateExistingComponent(destination, requiresDirectory: false)
                let existing = try validator.validate(destination)
                guard LocalFileIntakeValidator.matchesContent(existing, request.validated) else {
                    throw LocalFileIntakeError(.identityConflict)
                }
                return Prepared(
                    result: Result(
                        fileURL: destination,
                        relativePath: try relativePath(of: destination, root: root),
                        validatedMetadata: request.validated,
                        wasReused: true
                    ),
                    fileManager: fileManager,
                    ownedURLs: [],
                    createdDirectories: createdDirectories
                )
            }

            // Stage directly under the validated root, not inside a destination
            // component that can be replaced while caller hooks/provider reads run.
            let temporary = root.appendingPathComponent(".cider-intake-\(UUID().uuidString).partial")
            ownedURLs.append(temporary)
            try validator.withSecurityScopedAccess(to: request.validated.identity.accessURL) {
                _ = try validator.revalidateWithinActiveScope(request.validated)
                try hooks.beforeSourceCopy?(
                    request.validated.identity.accessURL,
                    request.validated.identity.standardizedURL,
                    temporary
                )
                try fileManager.copyItem(at: request.validated.identity.standardizedURL, to: temporary)
                try hooks.afterCopy?(temporary)
                let copied = try validator.validate(temporary)
                guard LocalFileIntakeValidator.matchesContent(copied, request.validated) else {
                    throw LocalFileIntakeError(.changedDuringValidation)
                }
                _ = try validator.revalidateWithinActiveScope(request.validated)
            }

            try validateDestinationDirectory(root: root, relativePath: request.destinationRelativeDirectory)
            guard !entryExists(at: destination) else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            ownedURLs.append(destination)
            try validateDestinationDirectory(root: root, relativePath: request.destinationRelativeDirectory)
            try validateExistingComponent(destination, requiresDirectory: false)
            guard destination.resolvingSymlinksInPath().standardizedFileURL == destination.standardizedFileURL,
                  Self.isContained(destination, in: root) else {
                throw LocalFileIntakeError(.unsafeDestination)
            }
            return Prepared(
                result: Result(
                    fileURL: destination,
                    relativePath: try relativePath(of: destination, root: root),
                    validatedMetadata: request.validated,
                    wasReused: false
                ),
                fileManager: fileManager,
                ownedURLs: ownedURLs,
                createdDirectories: createdDirectories
            )
        } catch let error as LocalFileIntakeError {
            rollback(ownedURLs: ownedURLs, createdDirectories: createdDirectories)
            throw error
        } catch {
            rollback(ownedURLs: ownedURLs, createdDirectories: createdDirectories)
            throw LocalFileIntakeError(.materializationFailed)
        }
    }

    private func createDestinationDirectory(
        root: URL,
        relativePath: String,
        createdDirectories: inout [URL]
    ) throws -> URL {
        let directory = root.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        guard Self.isContained(directory, in: root) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        try validateDestinationDirectory(root: root, relativePath: relativePath)
        if !entryExists(at: directory) {
            var candidate = directory
            while candidate.path != root.path, !entryExists(at: candidate) {
                createdDirectories.append(candidate)
                candidate = candidate.deletingLastPathComponent()
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try validateDestinationDirectory(root: root, relativePath: relativePath)
        return directory
    }

    private func destinationURL(for request: Request, directory: URL) throws -> URL {
        let safeName = LocalFileIntakeValidator.sanitizedFilename(request.filename)
        return directory.appendingPathComponent("\(request.stableID.uuidString)-\(safeName)")
    }

    private func validateDestinationDirectory(root: URL, relativePath: String) throws {
        let expected = root.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        guard Self.isContained(expected, in: root), Self.isSafeRelativePath(relativePath) else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        try validateExistingComponent(root, requiresDirectory: true)
        var candidate = root
        for component in relativePath.split(separator: "/").map(String.init) {
            candidate.appendPathComponent(component, isDirectory: true)
            if entryExists(at: candidate) {
                try validateExistingComponent(candidate, requiresDirectory: true)
            }
        }
        guard candidate.standardizedFileURL == expected else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
    }

    private func validateExistingComponent(_ url: URL, requiresDirectory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw LocalFileIntakeError(.unsafeDestination)
        }
        let kind = info.st_mode & S_IFMT
        guard kind != S_IFLNK else { throw LocalFileIntakeError(.unsafeDestination) }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isAliasFileKey, .isDirectoryKey, .isRegularFileKey])
        } catch {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        guard values.isAliasFile != true else { throw LocalFileIntakeError(.unsafeDestination) }
        if requiresDirectory {
            guard kind == S_IFDIR, values.isDirectory == true else { throw LocalFileIntakeError(.unsafeDestination) }
        } else {
            guard kind == S_IFREG, values.isRegularFile == true else { throw LocalFileIntakeError(.unsafeDestination) }
        }
    }

    private func rollback(ownedURLs: [URL], createdDirectories: [URL]) {
        for url in ownedURLs.reversed() { try? fileManager.removeItem(at: url) }
        for directory in createdDirectories {
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func relativePath(of url: URL, root: URL) throws -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(prefix),
              url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else {
            throw LocalFileIntakeError(.unsafeDestination)
        }
        return String(url.standardizedFileURL.path.dropFirst(prefix.count))
    }

    private func entryExists(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}
