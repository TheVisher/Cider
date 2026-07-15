import Foundation
import Testing
@testable import Cider

@Suite("Cider Open and Export Policy Tests")
@MainActor
struct CiderOpenAndExportPolicyTests {
    @Test("untrusted web rejects unsafe schemes without an external side effect")
    func unsafeWebFailsClosed() throws {
        let workspace = RecordingWorkspaceOpener()
        let policy = CiderOpenPolicy(workspace: workspace)

        for url in [
            URL(string: "file:///Users/private/secret.txt")!,
            URL(string: "javascript:alert(1)")!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!,
        ] {
            #expect(throws: CiderOpenError.unsupportedWebScheme) {
                try policy.open(.untrustedWeb(url))
            }
        }

        #expect(workspace.actions.isEmpty)
    }

    @Test("untrusted web requires a well formed host and rejects authority tricks")
    func malformedWebFailsClosed() throws {
        let workspace = RecordingWorkspaceOpener()
        let policy = CiderOpenPolicy(workspace: workspace)

        for raw in [
            "https:///missing-host",
            "https://user:password@example.com/private",
            "https://example.com\\@attacker.invalid/path",
        ] {
            let url = try #require(URL(string: raw))
            #expect(throws: CiderOpenError.unsupportedWebScheme) {
                try policy.open(.untrustedWeb(url))
            }
        }

        #expect(workspace.actions.isEmpty)
    }

    @Test("web local Finder Preview and system destinations remain typed")
    func typedDestinationsUseTheirOwnOperations() throws {
        let workspace = RecordingWorkspaceOpener()
        let policy = CiderOpenPolicy(workspace: workspace)
        let web = URL(string: "https://example.com/path")!
        let local = URL(fileURLWithPath: "/tmp/cider-open.txt")
        let secondLocal = URL(fileURLWithPath: "/tmp/cider-open-2.txt")

        try policy.open(.untrustedWeb(web))
        try policy.open(.localFile(local))
        try policy.open(.revealInFinder(local))
        try policy.open(.localFiles([local, secondLocal], application: .preview))
        try policy.open(.system(.accessibilityPrivacySettings))

        #expect(workspace.actions == [
            .open(web),
            .open(local),
            .reveal([local]),
            .openWithApplication(
                [local, secondLocal],
                URL(fileURLWithPath: "/System/Applications/Preview.app")
            ),
            .open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!),
        ])
    }

    @Test("local destinations cannot be smuggled through non-file URLs")
    func invalidTypedLocalDestinationFailsClosed() {
        let workspace = RecordingWorkspaceOpener()
        let policy = CiderOpenPolicy(workspace: workspace)

        #expect(throws: CiderOpenError.invalidLocalDestination) {
            try policy.open(.localFile(URL(string: "https://example.com/not-local")!))
        }
        #expect(workspace.actions.isEmpty)
    }

    @Test("export defaults to non-overwrite and preserves existing bytes")
    func exportDoesNotOverwriteByDefault() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")

        #expect(throws: CiderExportWriteError.destinationExists) {
            try CiderExportWritePolicy().writeData(Data("replacement".utf8), to: destination)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("explicit typed replacement replaces one existing file")
    func explicitOverwriteReplacesExistingFile() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")

        try CiderExportWritePolicy().writeData(
            Data("replacement".utf8),
            to: destination,
            overwrite: .replaceExisting
        )

        #expect(try String(contentsOf: destination, encoding: .utf8) == "replacement")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("failure before commit cleans staging and preserves the destination")
    func preCommitFailureRollsBack() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")
        let policy = CiderExportWritePolicy(hooks: .init(checkpoint: { checkpoint in
            if checkpoint == .beforeCommit { throw InjectedExportFailure.expected }
        }))

        #expect(throws: CiderExportWriteError.writeFailed) {
            try policy.writeData(
                Data("replacement".utf8),
                to: destination,
                overwrite: .replaceExisting
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("failure after replacement swaps the original back deterministically")
    func postReplacementFailureRollsBack() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")
        let policy = CiderExportWritePolicy(hooks: .init(checkpoint: { checkpoint in
            if checkpoint == .afterReplacement { throw InjectedExportFailure.expected }
        }))

        #expect(throws: CiderExportWriteError.writeFailed) {
            try policy.writeData(
                Data("replacement".utf8),
                to: destination,
                overwrite: .replaceExisting
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("a concurrent create wins and is never replaced by default")
    func concurrentWriterIsNotReplaced() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = fixture.root.appendingPathComponent("raced.txt")
        let policy = CiderExportWritePolicy(hooks: .init(checkpoint: { checkpoint in
            if checkpoint == .beforeCommit {
                try Data("concurrent".utf8).write(to: destination, options: .withoutOverwriting)
            }
        }))

        #expect(throws: CiderExportWriteError.destinationExists) {
            try policy.writeData(Data("cider".utf8), to: destination)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "concurrent")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("stale replacement identity fails without replacing the newer writer")
    func staleReplacementIdentityFailsClosed() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")
        let policy = CiderExportWritePolicy(hooks: .init(checkpoint: { checkpoint in
            if checkpoint == .beforeCommit {
                try Data("newer-writer".utf8).write(to: destination, options: .atomic)
            }
        }))

        #expect(throws: CiderExportWriteError.destinationChanged) {
            try policy.writeData(
                Data("cider".utf8),
                to: destination,
                overwrite: .replaceExisting
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "newer-writer")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("parent redirects between validation and commit fail closed")
    func parentRedirectFailsClosed() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let firstParent = fixture.root.appendingPathComponent("first", isDirectory: true)
        let secondParent = fixture.root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstParent, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: secondParent, withIntermediateDirectories: false)
        let parentLink = fixture.root.appendingPathComponent("selected", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: firstParent)
        let destination = parentLink.appendingPathComponent("export.txt")
        let policy = CiderExportWritePolicy(hooks: .init(checkpoint: { checkpoint in
            if checkpoint == .beforeCommit {
                try FileManager.default.removeItem(at: parentLink)
                try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: secondParent)
            }
        }))

        #expect(throws: CiderExportWriteError.unsafeDestination) {
            try policy.writeData(Data("cider".utf8), to: destination)
        }

        #expect(!FileManager.default.fileExists(atPath: firstParent.appendingPathComponent("export.txt").path))
        #expect(!FileManager.default.fileExists(atPath: secondParent.appendingPathComponent("export.txt").path))
        #expect(try fixture.temporaryArtifacts(in: firstParent).isEmpty)
    }

    @Test("cancellation before commit removes staging and preserves the destination")
    func cancellationPreservesDestination() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.write("existing.txt", "original")
        var cancellationChecks = 0
        let policy = CiderExportWritePolicy(hooks: .init(isCancelled: {
            cancellationChecks += 1
            return cancellationChecks >= 2
        }))

        #expect(throws: CiderExportWriteError.cancelled) {
            try policy.writeData(
                Data("replacement".utf8),
                to: destination,
                overwrite: .replaceExisting
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("symlink destinations fail closed without changing their targets")
    func symlinkDestinationFailsClosed() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let target = try fixture.write("target.txt", "original")
        let destination = fixture.root.appendingPathComponent("redirect.txt")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        #expect(throws: CiderExportWriteError.unsafeDestination) {
            try CiderExportWritePolicy().writeData(
                Data("replacement".utf8),
                to: destination,
                overwrite: .replaceExisting
            )
        }

        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
    }

    @Test("partial package failures remove only policy-owned staging")
    func partialPackageFailureCleansUp() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = fixture.root.appendingPathComponent("Room.cider-room", isDirectory: true)

        #expect(throws: CiderExportWriteError.writeFailed) {
            try CiderExportWritePolicy().writeDirectory(to: destination) { staging in
                try Data("markdown".utf8).write(
                    to: staging.appendingPathComponent("conversation.md"),
                    options: .withoutOverwriting
                )
                throw InjectedExportFailure.expected
            }
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }

    @Test("partial file failures remove only policy-owned staging")
    func partialFileFailureCleansUp() throws {
        let fixture = try ExportPolicyFixture()
        defer { fixture.cleanup() }
        let destination = fixture.root.appendingPathComponent("export.txt")

        #expect(throws: CiderExportWriteError.writeFailed) {
            try CiderExportWritePolicy().writeFile(to: destination) { staging in
                try Data("partial".utf8).write(to: staging, options: .withoutOverwriting)
                throw InjectedExportFailure.expected
            }
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try fixture.temporaryArtifacts().isEmpty)
    }
}

@MainActor
private final class RecordingWorkspaceOpener: CiderWorkspaceOpening {
    enum Action: Equatable {
        case open(URL)
        case reveal([URL])
        case openWithApplication([URL], URL)
    }

    private(set) var actions: [Action] = []

    func open(_ url: URL) -> Bool {
        actions.append(.open(url))
        return true
    }

    func revealInFinder(_ urls: [URL]) {
        actions.append(.reveal(urls))
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        actions.append(.openWithApplication(urls, applicationURL))
    }
}

private enum InjectedExportFailure: Error {
    case expected
}

private struct ExportPolicyFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-export-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    func write(_ name: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    func temporaryArtifacts() throws -> [URL] {
        try temporaryArtifacts(in: root)
    }

    func temporaryArtifacts(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".cider-export-") }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
