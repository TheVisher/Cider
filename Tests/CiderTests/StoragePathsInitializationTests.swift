import Foundation
import XCTest
@testable import Cider

final class StoragePathsInitializationTests: XCTestCase {
    private struct InjectedFailure: LocalizedError {
        let errorDescription: String?
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-storage-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEnsureVaultStructureReportsDirectoryCreationFailureWithContext() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let failedURL = vault.appendingPathComponent(".cider/memory/daily", isDirectory: true)
        let fileSystem = StoragePaths.VaultStructureFileSystem(
            createDirectory: { url in
                if url.path == failedURL.path {
                    throw InjectedFailure(errorDescription: "injected directory failure")
                }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            writeUTF8Atomically: { content, url in
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        )

        let report = StoragePaths.ensureVaultStructure(
            config: CiderConfig(vaultDirectory: vault.path),
            fileSystem: fileSystem
        )

        XCTAssertFalse(report.isFullyInitialized)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures.first?.operation, .createDirectory)
        XCTAssertEqual(report.failures.first?.path, failedURL.path)
        XCTAssertEqual(report.failures.first?.underlyingError, "injected directory failure")
    }

    func testEnsureVaultStructureReportsTemplateWriteFailureWithoutFabricatedSuccess() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let failedURL = vault.appendingPathComponent(".cider/memory/open_loops.md")
        let fileSystem = StoragePaths.VaultStructureFileSystem(
            createDirectory: {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            writeUTF8Atomically: { content, url in
                if url.path == failedURL.path {
                    throw InjectedFailure(errorDescription: "injected template failure")
                }
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        )

        let report = StoragePaths.ensureVaultStructure(
            config: CiderConfig(vaultDirectory: vault.path),
            fileSystem: fileSystem
        )

        XCTAssertFalse(report.isFullyInitialized)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures.first?.operation, .writeCompatibilityTemplate)
        XCTAssertEqual(report.failures.first?.path, failedURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider/memory/index.md").path))
    }

    func testEnsureVaultStructureIsIdempotentAndPreservesCompatibilityTemplates() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let config = CiderConfig(vaultDirectory: vault.path)

        let firstReport = StoragePaths.ensureVaultStructure(config: config)
        let userTemplate = vault.appendingPathComponent(".cider/memory/user.md")
        try "custom user memory".write(to: userTemplate, atomically: true, encoding: .utf8)
        let secondReport = StoragePaths.ensureVaultStructure(config: config)

        XCTAssertTrue(firstReport.isFullyInitialized)
        XCTAssertTrue(secondReport.isFullyInitialized)
        XCTAssertEqual(try String(contentsOf: userTemplate, encoding: .utf8), "custom user memory")
        for name in ["index.md", "open_loops.md", "user.md", "agent.md"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: vault.appendingPathComponent(".cider/memory/\(name)").path
                )
            )
        }
    }

    func testLegacyConversationPreviewPathLookupUsesConfiguredVaultWithoutCreatingAnything() {
        let missingVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-missing-legacy-preview-\(UUID().uuidString)", isDirectory: true)
        let config = CiderConfig(vaultDirectory: missingVault.path)

        let paths = StoragePaths.legacyConversationPreviewDirectories(config: config)

        XCTAssertEqual(
            paths.registry,
            missingVault.appendingPathComponent(".cider/agent-chats", isDirectory: true)
        )
        XCTAssertEqual(
            paths.conversations,
            missingVault.appendingPathComponent(".cider/ai-conversations", isDirectory: true)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingVault.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.registry.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.conversations.path))
    }
}
