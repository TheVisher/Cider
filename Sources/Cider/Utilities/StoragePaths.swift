import Foundation

enum StoragePaths {
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
