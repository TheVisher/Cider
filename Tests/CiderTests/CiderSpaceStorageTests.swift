import XCTest
@testable import Cider

final class CiderSpaceStorageTests: XCTestCase {
    private func makeTempRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-space-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    func testSpaceMetadataYAMLRoundTripsHumanReadableFields() throws {
        let space = CiderSpace(
            id: "space-media",
            name: "Media",
            systemImage: "play.rectangle",
            purpose: "Movies, shows, games, books, and entertainment tracking.",
            preset: .media,
            isPinned: true,
            aiInstructions: "Route trailers, reviews, Steam pages, and watchlists here.",
            routingHints: ["Prefer Games for Steam pages.", "Prefer Movies for trailers."],
            defaultViews: [.overview, .inbox, .recent],
            rootRelativePath: "Spaces/Media",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let yaml = try CiderSpaceMetadataCodec.encode(space)
        XCTAssertTrue(yaml.contains("name: Media"))
        XCTAssertTrue(yaml.contains("preset: media"))
        XCTAssertTrue(yaml.contains("aiInstructions:"))

        let decoded = try CiderSpaceMetadataCodec.decode(yaml)

        XCTAssertEqual(decoded.id, space.id)
        XCTAssertEqual(decoded.name, "Media")
        XCTAssertEqual(decoded.preset, .media)
        XCTAssertEqual(decoded.defaultViews, [.overview, .inbox, .recent])
        XCTAssertEqual(decoded.routingHints.count, 2)
        XCTAssertEqual(decoded.rootRelativePath, "Spaces/Media")
    }

    @MainActor
    func testCreateSpaceWritesFolderAndMetadataThenReloads() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = CiderSpaceStorage(vaultRoot: tempRoot)

        let created = try storage.createSpace(name: "Media", preset: .media, isPinned: true)

        let spaceRoot = tempRoot.appendingPathComponent("Spaces/Media", isDirectory: true)
        let metadataURL = spaceRoot.appendingPathComponent(".cider-space.yaml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: spaceRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))

        let metadataText = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertTrue(metadataText.contains("name: Media"))
        XCTAssertTrue(metadataText.contains("preset: media"))
        XCTAssertTrue(metadataText.contains("rootRelativePath: Spaces/Media"))

        let reloaded = CiderSpaceStorage(vaultRoot: tempRoot)
        XCTAssertEqual(reloaded.spaces.map(\.id), [created.id])
        XCTAssertEqual(reloaded.spaces.first?.name, "Media")
        XCTAssertEqual(reloaded.spaces.first?.isPinned, true)
    }

    @MainActor
    func testCreateSpaceUsesUniqueFilesystemSafePaths() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = CiderSpaceStorage(vaultRoot: tempRoot)

        let first = try storage.createSpace(name: "Media / Watch List?", preset: .media)
        let second = try storage.createSpace(name: "Media / Watch List?", preset: .media)

        XCTAssertEqual(first.rootRelativePath, "Spaces/Media Watch List")
        XCTAssertEqual(second.rootRelativePath, "Spaces/Media Watch List 2")
        XCTAssertNotEqual(first.id, second.id)
    }

    @MainActor
    func testUpdateSpacePreservesIDAndRootPath() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = CiderSpaceStorage(vaultRoot: tempRoot)
        var space = try storage.createSpace(name: "Media", preset: .media)
        let originalID = space.id
        let originalPath = space.rootRelativePath

        space.name = "Entertainment"
        space.purpose = "A renamed media space."
        space.isPinned = true

        try storage.updateSpace(space)

        let reloaded = CiderSpaceStorage(vaultRoot: tempRoot)
        let updated = try XCTUnwrap(reloaded.spaces.first)
        XCTAssertEqual(updated.id, originalID)
        XCTAssertEqual(updated.rootRelativePath, originalPath)
        XCTAssertEqual(updated.name, "Entertainment")
        XCTAssertTrue(updated.isPinned)
    }

    @MainActor
    func testPinnedSpacesAreSortedAndUnpinnedSpacesStayOutOfSidebarList() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = CiderSpaceStorage(vaultRoot: tempRoot)
        _ = try storage.createSpace(name: "Zeta", preset: .blank, isPinned: true)
        _ = try storage.createSpace(name: "Hidden", preset: .blank, isPinned: false)
        _ = try storage.createSpace(name: "Alpha", preset: .blank, isPinned: true)

        XCTAssertEqual(storage.pinnedSpaces.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(CiderSpaceSidebarModel.pinnedSpaces(from: storage.spaces).map(\.name), ["Alpha", "Zeta"])
    }

    func testPresetDefaultsProvideStarterMetadata() {
        let media = CiderSpacePreset.defaults(for: .media)
        let project = CiderSpacePreset.defaults(for: .project)

        XCTAssertEqual(media.systemImage, "play.rectangle")
        XCTAssertTrue(media.aiInstructions.localizedCaseInsensitiveContains("movies"))
        XCTAssertTrue(media.defaultViews.contains(.overview))
        XCTAssertEqual(project.systemImage, "shippingbox")
        XCTAssertTrue(project.routingHints.contains { $0.localizedCaseInsensitiveContains("kanban") })
    }

    @MainActor
    func testDefaultPinnedPresetsAreDeferredInsteadOfCreatedAndShownInSidebar() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let storage = CiderSpaceStorage(vaultRoot: tempRoot, defaultPinnedPresets: [.recipes])

        XCTAssertTrue(storage.spaces.isEmpty)
        XCTAssertTrue(storage.pinnedSpaces.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("Spaces/Recipes/.cider-space.yaml").path))

        let reloaded = CiderSpaceStorage(vaultRoot: tempRoot, defaultPinnedPresets: [.recipes])
        XCTAssertTrue(reloaded.spaces.isEmpty)
        XCTAssertTrue(reloaded.pinnedSpaces.isEmpty)
    }

    @MainActor
    func testInvalidMetadataIsSkippedWithoutCrashing() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let spacesRoot = tempRoot.appendingPathComponent("Spaces", isDirectory: true)
        let invalidRoot = spacesRoot.appendingPathComponent("Broken", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        try "name: [not valid".write(
            to: invalidRoot.appendingPathComponent(".cider-space.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let storage = CiderSpaceStorage(vaultRoot: tempRoot)

        XCTAssertTrue(storage.spaces.isEmpty)
        XCTAssertEqual(storage.loadIssues.count, 1)
    }

    func testLibraryRoutesKeepFoldersVisibleAndNestSpacesBelowPermanentRoots() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .browse).map(\.kind),
            [.inbox, .bookmarks, .notes, .files, .folders, .tags, .spaces]
        )
        XCTAssertEqual(
            WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: nil),
            [.mainDashboard, .journal, .browse, .projects]
        )
        XCTAssertFalse(WorkspaceNavigationDomain.spaces.isPrimaryRoot)
    }
}
