import Foundation

enum FileContainment {
    static func normalizedExistingFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isContained(_ candidate: URL, in directory: URL) -> Bool {
        let candidatePath = normalizedExistingFileURL(candidate).path
        let directoryPath = normalizedExistingFileURL(directory).path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !directoryPath.isEmpty else { return false }
        let root = "/" + directoryPath
        return candidatePath == root || candidatePath.hasPrefix(root + "/")
    }

    static func isContained(_ candidate: URL, inAny directories: [URL]) -> Bool {
        directories.contains { isContained(candidate, in: $0) }
    }
}
