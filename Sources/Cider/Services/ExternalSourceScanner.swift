import Foundation

/// Scans a single Linked Source directory for `.md` files and watches
/// for filesystem changes. One instance per `ExternalSource`.
@MainActor
final class ExternalSourceScanner: ObservableObject {
    let sourceID: UUID

    @Published private(set) var files: [ExternalFile] = []

    private let directoryURL: URL
    private var sourceName: String
    private var directoryFileDescriptor: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?

    init(source: ExternalSource) {
        self.sourceID = source.id
        self.sourceName = source.displayName
        self.directoryURL = URL(fileURLWithPath: source.path)
        scan()
        startWatcher()
    }

    /// Updates the display name used in file footers when the source is renamed.
    func updateSourceName(_ name: String) {
        sourceName = name
        scan()
    }

    // MARK: - Scanning

    func scan() {
        let fm = FileManager.default
        // CH-S04: Block symlink traversal — only scan regular files
        guard let fileURLs = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }

        files = fileURLs
            .filter { url in
                guard url.pathExtension.lowercased() == "md" else { return false }
                let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
                return !isSymlink
            }
            .compactMap { url -> ExternalFile? in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                let createDate = attrs?[.creationDate] as? Date ?? Date()
                return ExternalFile(
                    id: ExternalFile.stableID(for: url.path),
                    title: url.deletingPathExtension().lastPathComponent,
                    path: url,
                    sourceID: sourceID,
                    sourceName: sourceName,
                    createdAt: createDate,
                    modifiedAt: modDate
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Watching

    private func startWatcher() {
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func stopWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }

    deinit {
        directorySource?.cancel()
        if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
        }
    }
}
