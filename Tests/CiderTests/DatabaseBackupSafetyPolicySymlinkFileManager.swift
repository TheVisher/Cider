import Foundation

final class IntermediatePolicySymlinkFileManager: FileManager, @unchecked Sendable {
    private let sourceRoot: URL
    private let redirectedRoot: URL
    private(set) var didInstallSymlink = false

    init(sourceRoot: URL, redirectedRoot: URL) {
        self.sourceRoot = sourceRoot
        self.redirectedRoot = redirectedRoot
        super.init()
    }

    func installSymlink() throws {
        guard !didInstallSymlink else { return }
        try super.createSymbolicLink(
            at: sourceRoot.appendingPathComponent("backups", isDirectory: true),
            withDestinationURL: redirectedRoot
        )
        didInstallSymlink = true
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        let expectedPrefix = sourceRoot.appendingPathComponent("backups", isDirectory: true).path + "/"
        if !didInstallSymlink, createIntermediates, url.path.hasPrefix(expectedPrefix) {
            try super.createSymbolicLink(
                at: sourceRoot.appendingPathComponent("backups", isDirectory: true),
                withDestinationURL: redirectedRoot
            )
            didInstallSymlink = true
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}
