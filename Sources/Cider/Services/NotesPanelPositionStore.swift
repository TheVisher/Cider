import AppKit

@MainActor
final class NotesPanelPositionStore {
    static let shared = NotesPanelPositionStore()

    private let storageKey = "NotesPanelPositionByNoteID"
    private var cachedFrames: [UUID: NSRect] = [:]

    private init() {
        loadFromDefaults()
    }

    func frame(for noteID: UUID) -> NSRect? {
        cachedFrames[noteID]
    }

    func setFrame(_ frame: NSRect, for noteID: UUID) {
        cachedFrames[noteID] = frame
        saveToDefaults()
    }

    func removeFrame(for noteID: UUID) {
        cachedFrames.removeValue(forKey: noteID)
        saveToDefaults()
    }

    // Backward-compatible wrappers for callers that only care about origin.
    func origin(for noteID: UUID) -> NSPoint? {
        cachedFrames[noteID]?.origin
    }

    func setOrigin(_ origin: NSPoint, for noteID: UUID) {
        if var frame = cachedFrames[noteID] {
            frame.origin = origin
            setFrame(frame, for: noteID)
        } else {
            let defaultFrame = NSRect(
                x: origin.x,
                y: origin.y,
                width: NotesDesign.panelDefaultWidth,
                height: NotesDesign.panelDefaultHeight
            )
            setFrame(defaultFrame, for: noteID)
        }
    }

    func removeOrigin(for noteID: UUID) {
        removeFrame(for: noteID)
    }

    private func loadFromDefaults() {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String: Double]] else {
            cachedFrames = [:]
            return
        }

        var decoded: [UUID: NSRect] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key),
                  let x = value["x"],
                  let y = value["y"] else {
                continue
            }

            let width = value["width"] ?? NotesDesign.panelDefaultWidth
            let height = value["height"] ?? NotesDesign.panelDefaultHeight
            decoded[id] = NSRect(x: x, y: y, width: width, height: height)
        }

        cachedFrames = decoded
    }

    private func saveToDefaults() {
        let encoded: [String: [String: Double]] = Dictionary(
            uniqueKeysWithValues: cachedFrames.map { id, frame in
                (id.uuidString, [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.size.width,
                    "height": frame.size.height
                ])
            }
        )
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}
