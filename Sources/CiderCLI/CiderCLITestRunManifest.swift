import Foundation
@testable import Cider

struct CiderCLITestRunManifest: Codable {
    struct Item: Codable {
        var type: String
        var id: String
        var title: String
        var relativePath: String?
        var captureEventID: String?
        var sourceKind: String?
        var sourceURL: String?
        var sourceFile: String?
        var recordedAt: String
        var cleanupStatus: String?
        var trashItemID: String?
    }

    var runID: String
    var marker: String?
    var createdAt: String
    var updatedAt: String
    var cleanupStatus: String
    var items: [Item]
}

enum CiderCLITestRunManifestStore {
    enum ManifestError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message): message
            }
        }
    }

    static let relativeDirectory = ".cider/test-runs"

    static func validateRunID(_ runID: String) throws {
        let trimmed = runID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == runID else {
            throw ManifestError.message("test-run id must be non-empty and must not contain surrounding whitespace.")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard runID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ManifestError.message("test-run id may contain only letters, numbers, dot, underscore, and dash.")
        }
    }

    static func manifestRelativePath(runID: String) -> String {
        "\(relativeDirectory)/\(runID).json"
    }

    static func manifestURL(runID: String) throws -> URL {
        try validateRunID(runID)
        return StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(relativeDirectory, isDirectory: true)
            .appendingPathComponent("\(runID).json", isDirectory: false)
    }

    static func exists(runID: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try manifestURL(runID: runID).path)
    }

    static func load(runID: String) throws -> CiderCLITestRunManifest {
        let url = try manifestURL(runID: runID)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CiderCLITestRunManifest.self, from: data)
    }

    static func save(_ manifest: CiderCLITestRunManifest) throws {
        let url = try manifestURL(runID: manifest.runID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    static func recordCapture(
        runID: String,
        marker: String?,
        result: CiderCaptureResult,
        finalTitle: String? = nil,
        finalRelativePath: String? = nil
    ) throws -> [String: Any] {
        try recordItem(
            runID: runID,
            marker: marker,
            type: result.item.type,
            id: result.item.id.uuidString,
            title: finalTitle ?? result.item.title,
            relativePath: finalRelativePath ?? result.item.relativePath,
            captureEventID: result.captureEventID?.uuidString,
            sourceKind: result.source.kind,
            sourceURL: result.source.url,
            sourceFile: result.source.file
        )
    }

    static func recordItem(
        runID: String,
        marker: String?,
        type: String,
        id: String,
        title: String,
        relativePath: String?,
        captureEventID: String?,
        sourceKind: String?,
        sourceURL: String? = nil,
        sourceFile: String? = nil
    ) throws -> [String: Any] {
        try validateRunID(runID)
        let now = ISO8601DateFormatter().string(from: Date())
        var manifest: CiderCLITestRunManifest
        if try exists(runID: runID) {
            manifest = try load(runID: runID)
            if manifest.marker == nil {
                manifest.marker = marker
            }
        } else {
            manifest = CiderCLITestRunManifest(
                runID: runID,
                marker: marker,
                createdAt: now,
                updatedAt: now,
                cleanupStatus: "not_started",
                items: []
            )
        }

        let item = CiderCLITestRunManifest.Item(
            type: type,
            id: id,
            title: title,
            relativePath: relativePath,
            captureEventID: captureEventID,
            sourceKind: sourceKind,
            sourceURL: sourceURL,
            sourceFile: sourceFile,
            recordedAt: now,
            cleanupStatus: nil,
            trashItemID: nil
        )
        if let index = manifest.items.firstIndex(where: { $0.type == item.type && $0.id == item.id }) {
            manifest.items[index] = item
        } else {
            manifest.items.append(item)
        }
        manifest.updatedAt = now
        try save(manifest)

        var dict: [String: Any] = [
            "runID": runID,
            "manifestPath": manifestRelativePath(runID: runID),
            "itemCount": manifest.items.count,
            "cleanupCommand": "cider-cli test-run cleanup \(runID) --dry-run --json",
        ]
        if let marker {
            dict["marker"] = marker
        }
        return dict
    }
}
