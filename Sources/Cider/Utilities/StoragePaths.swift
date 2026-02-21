import Foundation

enum StoragePaths {
    /// Cached base directory URL — avoids a UserDefaults decode on every access.
    /// Invalidated by `invalidateCachedDirectory()` (called from `handleConfigChanged()`).
    nonisolated(unsafe) private static var _cachedDirectoryURL: URL?
    nonisolated(unsafe) private static var _cachedNotesPath: String?

    static var cachedCiderDataDirectoryURL: URL {
        if let cached = _cachedDirectoryURL { return cached }
        let url = ciderDataDirectoryURL()
        _cachedDirectoryURL = url
        return url
    }

    /// Cached notes directory raw path string (pre-tilde-expansion not applied — caller expands).
    static var notesDirectoryPath: String {
        if let cached = _cachedNotesPath { return cached }
        let path = CiderConfig.load().notesDirectory
        _cachedNotesPath = path
        return path
    }

    static func invalidateCachedDirectory() {
        _cachedDirectoryURL = nil
        _cachedNotesPath = nil
    }

    static func ciderDataDirectoryURL(config: CiderConfig = CiderConfig.load()) -> URL {
        let expanded = NSString(string: config.ciderDataDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    static func jsonFileURL(fileName: String, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func ensureDirectory(_ directoryURL: URL) {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }
}
