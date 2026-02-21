import Foundation
import Combine

/// Owns all active `ExternalSourceScanner` instances and publishes a
/// unified `[ExternalFile]` feed from sources with `showInLibrary = true`.
/// Also provides per-source file lists for the sidebar and detail view.
@MainActor
final class ExternalSourceRegistry: ObservableObject {
    static let shared = ExternalSourceRegistry()

    /// All files from sources where `showInLibrary = true`, sorted by modifiedAt.
    @Published private(set) var libraryFiles: [ExternalFile] = []

    private var scanners: [UUID: ExternalSourceScanner] = [:]
    private var scannerCancellables: [UUID: AnyCancellable] = [:]
    private var storageCancellable: AnyCancellable?

    private init() {
        storageCancellable = ExternalSourceStorage.shared.$sources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildScanners()
            }
    }

    // MARK: - Per-Source Access

    /// All files in a specific source, regardless of `showInLibrary`.
    func files(for sourceID: UUID) -> [ExternalFile] {
        scanners[sourceID]?.files ?? []
    }

    // MARK: - Scanner Management

    private func rebuildScanners() {
        let sources = ExternalSourceStorage.shared.sources
        let activeIDs = Set(sources.map(\.id))

        // Remove scanners for deleted sources
        for id in scanners.keys where !activeIDs.contains(id) {
            scannerCancellables.removeValue(forKey: id)
            scanners.removeValue(forKey: id)
        }

        // Add or refresh scanners for current sources
        for source in sources {
            if let existing = scanners[source.id] {
                // Update display name in case of rename
                existing.updateSourceName(source.displayName)
            } else {
                let scanner = ExternalSourceScanner(source: source)
                let cancellable = scanner.$files
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.rebuildLibraryFiles() }
                scannerCancellables[source.id] = cancellable
                scanners[source.id] = scanner
            }
        }

        rebuildLibraryFiles()
    }

    private func rebuildLibraryFiles() {
        let librarySourceIDs = Set(
            ExternalSourceStorage.shared.sources
                .filter(\.showInLibrary)
                .map(\.id)
        )

        libraryFiles = scanners.values
            .filter { librarySourceIDs.contains($0.sourceID) }
            .flatMap(\.files)
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
