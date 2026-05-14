import Foundation
import Combine
import Yams

enum CiderSpaceStorageError: Error {
    case missingSpace(String)
}

enum CiderSpaceMetadataCodec {
    private static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }

    static func encode(_ space: CiderSpace) throws -> String {
        let metadata = CiderSpaceMetadata(space: space)
        let encoder = YAMLEncoder()
        return try encoder.encode(metadata)
    }

    static func decode(_ yaml: String) throws -> CiderSpace {
        let decoder = YAMLDecoder()
        let metadata = try decoder.decode(CiderSpaceMetadata.self, from: yaml)
        return metadata.space
    }

    private struct CiderSpaceMetadata: Codable {
        var id: String
        var name: String
        var systemImage: String
        var purpose: String
        var preset: CiderSpacePresetKind
        var isPinned: Bool
        var aiInstructions: String
        var routingHints: [String]
        var defaultViews: [CiderSpaceDefaultView]
        var rootRelativePath: String
        var createdAt: String
        var updatedAt: String

        init(space: CiderSpace) {
            id = space.id
            name = space.name
            systemImage = space.systemImage
            purpose = space.purpose
            preset = space.preset
            isPinned = space.isPinned
            aiInstructions = space.aiInstructions
            routingHints = space.routingHints
            defaultViews = space.defaultViews
            rootRelativePath = space.rootRelativePath
            let formatter = CiderSpaceMetadataCodec.makeDateFormatter()
            createdAt = formatter.string(from: space.createdAt)
            updatedAt = formatter.string(from: space.updatedAt)
        }

        var space: CiderSpace {
            CiderSpace(
                id: id,
                name: name,
                systemImage: systemImage,
                purpose: purpose,
                preset: preset,
                isPinned: isPinned,
                aiInstructions: aiInstructions,
                routingHints: routingHints,
                defaultViews: defaultViews,
                rootRelativePath: rootRelativePath,
                createdAt: CiderSpaceMetadataCodec.makeDateFormatter().date(from: createdAt) ?? Date(),
                updatedAt: CiderSpaceMetadataCodec.makeDateFormatter().date(from: updatedAt) ?? Date()
            )
        }
    }
}

@MainActor
final class CiderSpaceStorage: ObservableObject {
    static let shared = CiderSpaceStorage(defaultPinnedPresets: [.recipes])

    static let spacesRootName = StoragePaths.spacesDir
    static let metadataFileName = ".cider-space.yaml"

    @Published private(set) var spaces: [CiderSpace] = []
    @Published private(set) var loadIssues: [String] = []

    private let vaultRoot: URL
    private let fileManager: FileManager
    private let defaultPinnedPresets: [CiderSpacePresetKind]

    var spacesRootURL: URL {
        vaultRoot.appendingPathComponent(Self.spacesRootName, isDirectory: true)
    }

    var pinnedSpaces: [CiderSpace] {
        CiderSpaceSidebarModel.pinnedSpaces(from: spaces)
    }

    init(
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        fileManager: FileManager = .default,
        defaultPinnedPresets: [CiderSpacePresetKind] = []
    ) {
        self.vaultRoot = vaultRoot
        self.fileManager = fileManager
        self.defaultPinnedPresets = defaultPinnedPresets
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func createSpace(
        name: String,
        preset: CiderSpacePresetKind = .blank,
        isPinned: Bool = true
    ) throws -> CiderSpace {
        try ensureSpacesRoot()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = CiderSpacePreset.defaults(for: preset)
        let finalName = trimmedName.isEmpty ? defaults.title : trimmedName
        let folderName = uniqueFolderName(for: finalName)
        let rootRelativePath = "\(Self.spacesRootName)/\(folderName)"
        let now = Date()
        let space = CiderSpace(
            name: finalName,
            systemImage: defaults.systemImage,
            purpose: defaults.purpose,
            preset: preset,
            isPinned: isPinned,
            aiInstructions: defaults.aiInstructions,
            routingHints: defaults.routingHints,
            defaultViews: defaults.defaultViews,
            rootRelativePath: rootRelativePath,
            createdAt: now,
            updatedAt: now
        )
        try fileManager.createDirectory(
            at: rootURL(for: space),
            withIntermediateDirectories: true
        )
        try write(space)
        spaces.append(space)
        sortSpaces()
        return space
    }

    func updateSpace(_ space: CiderSpace) throws {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else {
            throw CiderSpaceStorageError.missingSpace(space.id)
        }
        var updated = space
        updated.updatedAt = Date()
        try fileManager.createDirectory(
            at: rootURL(for: updated),
            withIntermediateDirectories: true
        )
        try write(updated)
        spaces[index] = updated
        sortSpaces()
    }

    func setPinned(_ isPinned: Bool, for spaceID: String) throws {
        guard var space = spaces.first(where: { $0.id == spaceID }) else {
            throw CiderSpaceStorageError.missingSpace(spaceID)
        }
        space.isPinned = isPinned
        try updateSpace(space)
    }

    func space(id: String) -> CiderSpace? {
        spaces.first { $0.id == id }
    }

    func rootURL(for space: CiderSpace) -> URL {
        vaultRoot.appendingPathComponent(space.rootRelativePath, isDirectory: true)
    }

    func routingContexts() -> [CiderSpaceRoutingContext] {
        spaces.map(CiderSpaceRoutingContext.init(space:))
    }

    private func load() {
        var loaded: [CiderSpace] = []
        var issues: [String] = []

        guard fileManager.fileExists(atPath: spacesRootURL.path) else {
            for preset in defaultPinnedPresets {
                do {
                    loaded.append(try makeDefaultPinnedSpace(for: preset))
                } catch {
                    issues.append("Failed to create default \(CiderSpacePreset.defaults(for: preset).title) Space: \(error.localizedDescription)")
                }
            }
            spaces = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadIssues = issues
            return
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: spacesRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let metadataURL = url.appendingPathComponent(Self.metadataFileName)
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                issues.append("Missing metadata for \(url.lastPathComponent)")
                continue
            }
            do {
                let yaml = try String(contentsOf: metadataURL, encoding: .utf8)
                loaded.append(try CiderSpaceMetadataCodec.decode(yaml))
            } catch {
                issues.append("Failed to load \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        for preset in defaultPinnedPresets where loaded.contains(where: { $0.preset == preset }) == false {
            do {
                loaded.append(try makeDefaultPinnedSpace(for: preset))
            } catch {
                issues.append("Failed to create default \(CiderSpacePreset.defaults(for: preset).title) Space: \(error.localizedDescription)")
            }
        }

        spaces = loaded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        loadIssues = issues
    }

    private func makeDefaultPinnedSpace(for preset: CiderSpacePresetKind) throws -> CiderSpace {
        try ensureSpacesRoot()
        let defaults = CiderSpacePreset.defaults(for: preset)
        let folderName = uniqueFolderName(for: defaults.title)
        let now = Date()
        let space = CiderSpace(
            name: defaults.title,
            systemImage: defaults.systemImage,
            purpose: defaults.purpose,
            preset: preset,
            isPinned: true,
            aiInstructions: defaults.aiInstructions,
            routingHints: defaults.routingHints,
            defaultViews: defaults.defaultViews,
            rootRelativePath: "\(Self.spacesRootName)/\(folderName)",
            createdAt: now,
            updatedAt: now
        )
        try fileManager.createDirectory(
            at: rootURL(for: space),
            withIntermediateDirectories: true
        )
        try write(space)
        return space
    }

    private func write(_ space: CiderSpace) throws {
        let yaml = try CiderSpaceMetadataCodec.encode(space)
        try yaml.write(
            to: rootURL(for: space).appendingPathComponent(Self.metadataFileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func ensureSpacesRoot() throws {
        try fileManager.createDirectory(at: spacesRootURL, withIntermediateDirectories: true)
    }

    private func sortSpaces() {
        spaces.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func uniqueFolderName(for name: String) -> String {
        let base = Self.filesystemSafeName(for: name)
        var candidate = base
        var suffix = 2
        while fileManager.fileExists(atPath: spacesRootURL.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func filesystemSafeName(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let scalars = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : " "
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Untitled Space" : collapsed
    }
}
