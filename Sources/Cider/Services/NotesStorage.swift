import Foundation
import Combine

/// Manages notes as .md files on disk with a lightweight JSON index for UUID mapping.
@MainActor
final class NotesStorage: ObservableObject {
    static let shared = NotesStorage()

    @Published private(set) var notes: [Note] = []

    private var directoryURL: URL
    private var directoryFileDescriptor: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var saveWorkItem: DispatchWorkItem?
    private let indexFileName = "_cider_notes_index.json"

    /// UUID-to-filename mapping persisted on disk
    private var index: [UUID: String] = [:]

    private init() {
        let config = CiderConfig.load()
        let path = NSString(string: config.notesDirectory).expandingTildeInPath
        self.directoryURL = URL(fileURLWithPath: path)
        ensureDirectory()
        loadIndex()
        scanNotes()
        startDirectoryWatcher()
    }

    // MARK: - Directory Management

    func updateDirectory(to newPath: String) {
        stopDirectoryWatcher()
        let expanded = NSString(string: newPath).expandingTildeInPath
        directoryURL = URL(fileURLWithPath: expanded)
        ensureDirectory()
        loadIndex()
        scanNotes()
        startDirectoryWatcher()
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Index (UUID mapping)

    private var indexURL: URL {
        directoryURL.appendingPathComponent(indexFileName)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            index = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        } catch {
            index = [:]
        }
    }

    private func saveIndex() {
        let encoded = Dictionary(uniqueKeysWithValues: index.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Scanning

    func scanNotes() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]) else {
            notes = []
            return
        }

        // Reverse map: filename -> UUID
        let filenameToUUID = Dictionary(uniqueKeysWithValues: index.map { ($0.value, $0.key) })

        var scannedNotes: [Note] = []
        for fileURL in files {
            guard fileURL.pathExtension == "md" else { continue }
            let filename = fileURL.lastPathComponent
            guard filename != indexFileName else { continue }

            let title = String(filename.dropLast(3)) // Remove .md
            let uuid = filenameToUUID[filename] ?? UUID()

            // Register in index if new
            if filenameToUUID[filename] == nil {
                index[uuid] = filename
            }

            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let createDate = attrs?[.creationDate] as? Date ?? Date()

            // Lazy: don't load content during scan
            scannedNotes.append(Note(
                id: uuid,
                title: title,
                content: "",
                createdAt: createDate,
                modifiedAt: modDate,
                relativePath: filename
            ))
        }

        // Sort by most recently modified
        scannedNotes.sort { $0.modifiedAt > $1.modifiedAt }
        notes = scannedNotes
        saveIndex()
    }

    // MARK: - CRUD

    func createNew() -> Note {
        let title = uniqueTitle("Untitled")
        let filename = "\(title).md"
        let fileURL = directoryURL.appendingPathComponent(filename)
        let uuid = UUID()

        // Write empty file
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)

        index[uuid] = filename
        saveIndex()

        let note = Note(id: uuid, title: title, content: "", relativePath: filename)
        notes.insert(note, at: 0)
        return note
    }

    func loadContent(for note: Note) -> String {
        let fileURL = directoryURL.appendingPathComponent(note.relativePath)
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(note: Note) {
        let fileURL = directoryURL.appendingPathComponent(note.relativePath)
        try? note.content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Update in-memory list
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].modifiedAt = Date()
            notes[idx].content = note.content
        }
    }

    func scheduleSave(note: Note) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.save(note: note)
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func rename(note: Note, to newTitle: String) {
        let sanitized = newTitle.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !sanitized.isEmpty else { return }

        let oldPath = directoryURL.appendingPathComponent(note.relativePath)
        let newFilename = "\(sanitized).md"
        let newPath = directoryURL.appendingPathComponent(newFilename)

        guard !FileManager.default.fileExists(atPath: newPath.path) else { return }

        do {
            try FileManager.default.moveItem(at: oldPath, to: newPath)
            index[note.id] = newFilename
            saveIndex()

            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].title = sanitized
                notes[idx].relativePath = newFilename
            }
        } catch {
            NSLog("[NotesStorage] Rename failed: \(error)")
        }
    }

    func delete(note: Note) {
        let fileURL = directoryURL.appendingPathComponent(note.relativePath)
        try? FileManager.default.removeItem(at: fileURL)
        index.removeValue(forKey: note.id)
        saveIndex()
        notes.removeAll { $0.id == note.id }
    }

    // MARK: - Directory Watcher

    private func startDirectoryWatcher() {
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
                self?.scanNotes()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func stopDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }

    // MARK: - Image Storage

    /// Save image data to the `.attachments` subdirectory, returning the file URL.
    func saveImage(data: Data, filename: String, for note: Note) -> URL {
        let attachmentsDir = directoryURL.appendingPathComponent(".attachments")
        let fm = FileManager.default
        if !fm.fileExists(atPath: attachmentsDir.path) {
            try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        }

        // Prefix with short UUID to avoid collisions
        let uniqueName = "\(UUID().uuidString.prefix(8))-\(filename)"
        let fileURL = attachmentsDir.appendingPathComponent(uniqueName)
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Helpers

    private func uniqueTitle(_ base: String) -> String {
        let existingTitles = Set(notes.map(\.title))
        if !existingTitles.contains(base) { return base }
        for i in 2...100 {
            let candidate = "\(base) \(i)"
            if !existingTitles.contains(candidate) { return candidate }
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    deinit {
        directorySource?.cancel()
    }
}
