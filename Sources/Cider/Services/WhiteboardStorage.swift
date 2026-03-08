import Combine
import Foundation
import os

private struct WhiteboardsSnapshot: Codable {
    var canvases: [WhiteboardCanvas]
}

@MainActor
final class WhiteboardStorage: ObservableObject {
    static let shared = WhiteboardStorage()

    private static let logger = Logger(subsystem: "com.cider", category: "WhiteboardStorage")

    @Published private(set) var canvases: [WhiteboardCanvas] = []

    private let indexFileName = "_cider_whiteboards.json"
    private var indexFileURL: URL {
        let dir = StoragePaths.directoryURL(for: .whiteboards)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: indexFileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func createCanvas(name: String) -> WhiteboardCanvas {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Whiteboard" : trimmed
        let canvas = WhiteboardCanvas(name: finalName)

        // Write an empty Excalidraw scene to disk
        let emptyScene = Self.emptyExcalidrawScene
        let sceneURL = sceneFileURL(for: canvas.id)
        do {
            try emptyScene.write(to: sceneURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write initial Excalidraw scene: \(error)")
        }

        canvases.append(canvas)
        persistIndex()
        return canvas
    }

    func canvas(for id: UUID) -> WhiteboardCanvas? {
        canvases.first { $0.id == id }
    }

    /// Loads the raw Excalidraw JSON for a canvas.
    func loadScene(canvasID: UUID) -> Data? {
        let url = sceneFileURL(for: canvasID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            Self.logger.error("Failed to load scene for \(canvasID): \(error)")
            return nil
        }
    }

    /// Saves raw Excalidraw JSON for a canvas and updates its timestamp.
    func updateScene(canvasID: UUID, excalidrawJSON: Data) {
        let url = sceneFileURL(for: canvasID)
        do {
            try excalidrawJSON.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to save scene for \(canvasID): \(error)")
            return
        }

        if let idx = canvases.firstIndex(where: { $0.id == canvasID }) {
            canvases[idx].updatedAt = Date()
            persistIndex()
        }
    }

    @discardableResult
    func renameCanvas(_ id: UUID, to name: String) -> Bool {
        guard let idx = canvases.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        canvases[idx].name = trimmed
        canvases[idx].updatedAt = Date()
        persistIndex()
        return true
    }

    @discardableResult
    func deleteCanvas(_ id: UUID) -> TrashItem? {
        guard let canvas = canvases.first(where: { $0.id == id }) else { return nil }
        let whiteboardsDir = StoragePaths.cachedDirectoryURL(for: .whiteboards)
        let trashItem = TrashStorage.shared.trashWhiteboard(canvas, whiteboardsDir: whiteboardsDir)

        // Move the scene file into the trash directory
        let sceneURL = sceneFileURL(for: id)
        let trashDir = whiteboardsDir.appendingPathComponent(".Trash")
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trashSceneURL = trashDir.appendingPathComponent("\(id.uuidString).excalidraw")
        try? FileManager.default.moveItem(at: sceneURL, to: trashSceneURL)

        canvases.removeAll { $0.id == id }
        persistIndex()
        return trashItem
    }

    func restoreFromTrash(_ canvas: WhiteboardCanvas) {
        guard !canvases.contains(where: { $0.id == canvas.id }) else { return }

        // Move scene file back from trash
        let whiteboardsDir = StoragePaths.cachedDirectoryURL(for: .whiteboards)
        let trashDir = whiteboardsDir.appendingPathComponent(".Trash")
        let trashSceneURL = trashDir.appendingPathComponent("\(canvas.id.uuidString).excalidraw")
        let sceneURL = sceneFileURL(for: canvas.id)
        if FileManager.default.fileExists(atPath: trashSceneURL.path) {
            try? FileManager.default.moveItem(at: trashSceneURL, to: sceneURL)
        }

        canvases.append(canvas)
        persistIndex()
    }

    // MARK: - Helpers

    private func sceneFileURL(for canvasID: UUID) -> URL {
        let dir = StoragePaths.directoryURL(for: .whiteboards)
        StoragePaths.ensureDirectory(dir)
        return dir.appendingPathComponent("\(canvasID.uuidString).excalidraw")
    }

    private static let emptyExcalidrawScene: Data = {
        let json = """
        {
          "type": "excalidraw",
          "version": 2,
          "source": "cider",
          "elements": [],
          "appState": {
            "viewBackgroundColor": "transparent"
          },
          "files": {}
        }
        """
        return Data(json.utf8)
    }()

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WhiteboardsSnapshot.self, from: data)
            canvases = snapshot.canvases
        } catch {
            Self.logger.error("Failed to decode whiteboards index: \(error)")
            canvases = []
        }
    }

    private func persistIndex() {
        let snapshot = WhiteboardsSnapshot(canvases: canvases)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist whiteboards index: \(error)")
        }
    }
}
