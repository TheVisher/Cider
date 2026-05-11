import Foundation
import Yams

enum MediaItemYAMLCodec {
    private static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }

    static func encode(_ item: MediaItem) throws -> String {
        let encoder = YAMLEncoder()
        return try encoder.encode(MediaItemMetadata(item: item))
    }

    static func decode(_ yaml: String) throws -> MediaItem {
        let decoder = YAMLDecoder()
        return try decoder.decode(MediaItemMetadata.self, from: yaml).item
    }

    private struct MediaItemMetadata: Codable {
        var id: String
        var type: MediaItemType
        var title: String
        var canonicalTitle: String
        var year: Int?
        var releaseDate: String?
        var externalIDs: [String: String]
        var posterImagePath: String?
        var coverImageURL: String?
        var genres: [String]
        var categories: [String]
        var status: MediaItemStatus
        var sourceBookmarkIDs: [String]
        var sourceRelativePaths: [String]
        var sourceURLs: [String]
        var confidence: Double
        var identificationReason: String?
        var rawProviderPayloadPath: String?
        var createdAt: String
        var updatedAt: String

        init(item: MediaItem) {
            id = item.id
            type = item.type
            title = item.title
            canonicalTitle = item.canonicalTitle
            year = item.year
            releaseDate = item.releaseDate
            externalIDs = item.externalIDs
            posterImagePath = item.posterImagePath
            coverImageURL = item.coverImageURL
            genres = item.genres
            categories = item.categories
            status = item.status
            sourceBookmarkIDs = item.sourceBookmarkIDs.map(\.uuidString)
            sourceRelativePaths = item.sourceRelativePaths
            sourceURLs = item.sourceURLs
            confidence = item.confidence
            identificationReason = item.identificationReason
            rawProviderPayloadPath = item.rawProviderPayloadPath
            let formatter = MediaItemYAMLCodec.makeDateFormatter()
            createdAt = formatter.string(from: item.createdAt)
            updatedAt = formatter.string(from: item.updatedAt)
        }

        var item: MediaItem {
            let formatter = MediaItemYAMLCodec.makeDateFormatter()
            return MediaItem(
                id: id,
                type: type,
                title: title,
                canonicalTitle: canonicalTitle,
                year: year,
                releaseDate: releaseDate,
                externalIDs: externalIDs,
                posterImagePath: posterImagePath,
                coverImageURL: coverImageURL,
                genres: genres,
                categories: categories,
                status: status,
                sourceBookmarkIDs: sourceBookmarkIDs.compactMap(UUID.init(uuidString:)),
                sourceRelativePaths: sourceRelativePaths,
                sourceURLs: sourceURLs,
                confidence: confidence,
                identificationReason: identificationReason,
                rawProviderPayloadPath: rawProviderPayloadPath,
                createdAt: formatter.date(from: createdAt) ?? Date(),
                updatedAt: formatter.date(from: updatedAt) ?? Date()
            )
        }
    }
}

@MainActor
final class MediaItemStorage: ObservableObject {
    static let mediaSpaceRelativePath = "Spaces/Media"
    static let mediaItemsRelativePath = "Spaces/Media/.cider/media-items"
    static let providerPayloadsRelativePath = "Spaces/Media/.cider/provider-payloads"

    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var loadIssues: [String] = []

    private let vaultRoot: URL
    private let fileManager: FileManager

    var mediaItemsDirectoryURL: URL {
        vaultRoot.appendingPathComponent(Self.mediaItemsRelativePath, isDirectory: true)
    }

    var providerPayloadsDirectoryURL: URL {
        vaultRoot.appendingPathComponent(Self.providerPayloadsRelativePath, isDirectory: true)
    }

    init(
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.vaultRoot = vaultRoot
        self.fileManager = fileManager
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func upsert(_ item: MediaItem) throws -> MediaItem {
        try ensureDirectories()
        let now = Date()
        let finalItem: MediaItem
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            finalItem = items[index].mergingSources(from: item, now: now)
            items[index] = finalItem
        } else {
            var created = item
            created.updatedAt = now
            if created.createdAt > now { created.createdAt = now }
            finalItem = created
            items.append(created)
        }
        try write(finalItem)
        sortItems()
        return finalItem
    }

    func item(id: String) -> MediaItem? {
        items.first { $0.id == id }
    }

    private func load() {
        guard fileManager.fileExists(atPath: mediaItemsDirectoryURL.path) else {
            items = []
            loadIssues = []
            return
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: mediaItemsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [MediaItem] = []
        var issues: [String] = []
        for url in urls where url.pathExtension == "yaml" || url.pathExtension == "yml" {
            do {
                let yaml = try String(contentsOf: url, encoding: .utf8)
                loaded.append(try MediaItemYAMLCodec.decode(yaml))
            } catch {
                issues.append("Failed to load \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        items = loaded.sorted(by: Self.sort)
        loadIssues = issues
    }

    private func write(_ item: MediaItem) throws {
        let yaml = try MediaItemYAMLCodec.encode(item)
        try yaml.write(
            to: mediaItemsDirectoryURL.appendingPathComponent("\(Self.safeFileStem(for: item.id)).yaml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: mediaItemsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providerPayloadsDirectoryURL, withIntermediateDirectories: true)
    }

    private func sortItems() {
        items.sort(by: Self.sort)
    }

    private static func sort(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func safeFileStem(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return filtered.isEmpty ? UUID().uuidString.lowercased() : filtered
    }
}
