import AppKit
import Combine
import Foundation
import os

@MainActor
final class CanvasViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.cider", category: "CanvasViewModel")

    // MARK: - Published State

    @Published var nodes: [CanvasNode] = []
    @Published var edges: [CanvasEdge] = []
    @Published var viewport: CanvasViewport = .default
    @Published var selectedItemIDs: Set<String> = []

    /// Backward-compatible single-selection accessor.
    /// Returns the selected ID only when exactly one item is selected.
    /// The setter replaces the entire selection with a single item (or clears it).
    var selectedItemID: String? {
        get { selectedItemIDs.count == 1 ? selectedItemIDs.first : nil }
        set {
            if let id = newValue {
                selectedItemIDs = [id]
            } else {
                selectedItemIDs.removeAll()
            }
        }
    }

    @Published private(set) var titleCache: [String: String] = [:]
    @Published private(set) var bookmarkLookup: [UUID: Bookmark] = [:]
    @Published private(set) var noteLookup: [UUID: Note] = [:]
    @Published private(set) var todoLookup: [UUID: TodoCard] = [:]

    private var saveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var hotReloadCancellables = Set<AnyCancellable>()
    private var knownItemIDs = Set<String>()

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.flushSave() } }
        loadCanvas()
        startHotReload()
    }

    // MARK: - Storage

    private var canvasesDirectory: URL {
        StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("canvases", isDirectory: true)
    }

    private var defaultCanvasFileURL: URL {
        canvasesDirectory.appendingPathComponent("default.canvas.json")
    }

    private func ensureCanvasesDirectory() {
        try? FileManager.default.createDirectory(at: canvasesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    func loadCanvas() {
        guard FileManager.default.fileExists(atPath: defaultCanvasFileURL.path),
              let data = try? Data(contentsOf: defaultCanvasFileURL) else {
            Self.logger.info("No saved canvas — generating initial layout")
            generateInitialLayout(); return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawNodes = json["nodes"] as? [[String: Any]], !rawNodes.isEmpty else {
            Self.logger.warning("Saved canvas empty or corrupt — generating fresh layout")
            generateInitialLayout(); return
        }
        if !(json["native"] as? Bool ?? false) {
            Self.logger.info("Legacy WebView canvas detected — regenerating native layout")
            generateInitialLayout(); return
        }

        var parsed: [CanvasNode] = []
        for raw in rawNodes {
            guard let id = raw["id"] as? String else { continue }
            let nodeType = raw["nodeType"] as? String ?? "bookmarkCard"
            let itemType: String
            switch nodeType {
            case "folderGroup": itemType = "folderGroup"
            case "noteCard": itemType = "note"
            case "todoCard": itemType = "todo"
            default: itemType = "bookmark"
            }
            let pos = raw["position"] as? [String: Any]
            let x = (pos?["x"] as? Double) ?? (pos?["x"] as? CGFloat).map(Double.init) ?? 0
            let y = (pos?["y"] as? Double) ?? (pos?["y"] as? CGFloat).map(Double.init) ?? 0
            let sizeDict = (raw["size"] as? [String: Any]) ?? (raw["style"] as? [String: Any])
            let w = (sizeDict?["width"] as? Double) ?? 280
            let h = (sizeDict?["height"] as? Double) ?? 260
            let metadata = raw["metadata"] as? [String: Any]
            parsed.append(CanvasNode(
                id: id, itemID: raw["itemID"] as? String, itemType: itemType,
                position: CGPoint(x: x, y: y), size: CGSize(width: w, height: h),
                parentNodeID: raw["parentNode"] as? String,
                layoutMode: metadata?["layoutMode"] as? String,
                collapsed: (metadata?["collapsed"] as? Bool) ?? false
            ))
        }

        var parsedEdges: [CanvasEdge] = []
        if let rawEdges = json["edges"] as? [[String: Any]] {
            for raw in rawEdges {
                guard let id = raw["id"] as? String,
                      let source = raw["sourceID"] as? String ?? raw["source"] as? String,
                      let target = raw["targetID"] as? String ?? raw["target"] as? String else { continue }
                parsedEdges.append(CanvasEdge(id: id, sourceID: source, targetID: target, label: raw["label"] as? String))
            }
        }

        if let vpDict = json["viewport"] as? [String: Any] {
            let ox = (vpDict["offsetX"] as? Double) ?? 0
            let oy = (vpDict["offsetY"] as? Double) ?? 0
            let z = (vpDict["zoom"] as? Double) ?? 1.0
            viewport = CanvasViewport(offset: CGPoint(x: ox, y: oy), zoom: z)
        }

        // Reconcile with current vault
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        var currentVaultIDs = Set<String>()
        for bm in bookmarks { currentVaultIDs.insert(bm.id.uuidString) }
        for note in notes { currentVaultIDs.insert(note.id.uuidString) }
        for todo in todos { currentVaultIDs.insert(todo.id.uuidString) }

        parsed = parsed.filter { node in
            if node.itemType == "folderGroup" { return true }
            guard let itemID = node.itemID else { return false }
            return currentVaultIDs.contains(itemID)
        }

        let canvasItemIDs = Set(parsed.compactMap(\.itemID))
        let missingIDs = currentVaultIDs.subtracting(canvasItemIDs)
        if !missingIDs.isEmpty {
            let maxY = parsed.map { $0.position.y + $0.size.height }.max() ?? 0
            var index = 0; let columns = 4; let spacingX: CGFloat = 300; let spacingY: CGFloat = 280; let startY = maxY + 80
            for bm in bookmarks where missingIDs.contains(bm.id.uuidString) {
                let col = index % columns; let row = index / columns
                parsed.append(CanvasNode(id: "node-\(bm.id.uuidString)", itemID: bm.id.uuidString, itemType: "bookmark",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)))
                index += 1
            }
            for note in notes where missingIDs.contains(note.id.uuidString) {
                let col = index % columns; let row = index / columns
                parsed.append(CanvasNode(id: "node-\(note.id.uuidString)", itemID: note.id.uuidString, itemType: "note",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)))
                index += 1
            }
            for todo in todos where missingIDs.contains(todo.id.uuidString) {
                let col = index % columns; let row = index / columns
                parsed.append(CanvasNode(id: "node-\(todo.id.uuidString)", itemID: todo.id.uuidString, itemType: "todo",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)))
                index += 1
            }
            Self.logger.info("Added \(index) new items to canvas")
        }

        nodes = parsed; edges = parsedEdges; knownItemIDs = currentVaultIDs
        Self.logger.info("Loaded canvas: \(parsed.count) nodes, \(parsedEdges.count) edges")
        rebuildTitleCache(); recalculateFolderSizes()
    }

    private func generateInitialLayout() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let folders = VaultFolderService.shared.folders
        struct VaultItem { let uuid: String; let type: String }
        var folderItems: [UUID: [VaultItem]] = [:]
        var unfiledItems: [VaultItem] = []
        for bm in bookmarks {
            let item = VaultItem(uuid: bm.id.uuidString, type: "bookmark")
            if let fid = bm.folderID { folderItems[fid, default: []].append(item) } else { unfiledItems.append(item) }
        }
        for note in notes {
            let item = VaultItem(uuid: note.id.uuidString, type: "note")
            if let fid = note.folderID { folderItems[fid, default: []].append(item) } else { unfiledItems.append(item) }
        }
        for todo in todos {
            let item = VaultItem(uuid: todo.id.uuidString, type: "todo")
            if let fid = todo.folderID { folderItems[fid, default: []].append(item) } else { unfiledItems.append(item) }
        }

        let columns = 4; let cardSpacingX: CGFloat = 300; let cardSpacingY: CGFloat = 280
        let folderPadding: CGFloat = 60; let folderGap: CGFloat = 80; let folderInset: CGFloat = 20
        var currentY: CGFloat = 50; var allNodes: [CanvasNode] = []

        for folder in folders {
            let items = folderItems[folder.id] ?? []
            guard !items.isEmpty else { continue }
            let groupId = "folder-\(folder.id.uuidString)"
            let actualColumns = min(columns, max(1, items.count))
            let rows = max(1, (items.count + columns - 1) / columns)
            let groupWidth = CGFloat(actualColumns) * cardSpacingX + folderInset * 2
            let groupHeight = folderPadding + CGFloat(rows) * cardSpacingY + folderInset + 20
            allNodes.append(CanvasNode(id: groupId, itemType: "folderGroup",
                position: CGPoint(x: 50, y: currentY), size: CGSize(width: groupWidth, height: groupHeight), layoutMode: "grid"))
            for (i, item) in items.enumerated() {
                let col = i % columns; let row = i / columns
                allNodes.append(CanvasNode(id: "node-\(item.uuid)", itemID: item.uuid, itemType: item.type,
                    position: CGPoint(x: CGFloat(col) * cardSpacingX + folderInset, y: folderPadding + CGFloat(row) * cardSpacingY),
                    parentNodeID: groupId))
            }
            currentY += groupHeight + folderGap
        }
        if !unfiledItems.isEmpty {
            currentY += 40
            for (i, item) in unfiledItems.enumerated() {
                let col = i % columns; let row = i / columns
                allNodes.append(CanvasNode(id: "node-\(item.uuid)", itemID: item.uuid, itemType: item.type,
                    position: CGPoint(x: CGFloat(col) * cardSpacingX + 50, y: currentY + CGFloat(row) * cardSpacingY)))
            }
        }
        nodes = allNodes; edges = []; refreshKnownItemIDs(); scheduleDebouncedSave()
        Self.logger.info("Generated initial layout: \(allNodes.count) nodes")
        rebuildTitleCache(); recalculateFolderSizes()
    }

    // MARK: - Title Cache & Lookups

    func rebuildTitleCache() {
        var titles: [String: String] = [:]; var bmL: [UUID: Bookmark] = [:]; var nL: [UUID: Note] = [:]; var tL: [UUID: TodoCard] = [:]
        for bm in VaultBookmarkService.shared.bookmarks { titles[bm.id.uuidString] = bm.title; bmL[bm.id] = bm }
        for note in NotesStorage.shared.notes { titles[note.id.uuidString] = note.title; nL[note.id] = note }
        for todo in TodoCardStorage.shared.todoCards { titles[todo.id.uuidString] = todo.title; tL[todo.id] = todo }
        for folder in VaultFolderService.shared.folders { titles["folder-\(folder.id.uuidString)"] = folder.name }
        titleCache = titles; bookmarkLookup = bmL; noteLookup = nL; todoLookup = tL
    }

    // MARK: - Save

    func flushSave() { saveTask?.cancel(); saveTask = nil; saveCanvasToDisk() }

    private func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; self?.saveCanvasToDisk()
        }
    }

    private func saveCanvasToDisk() {
        ensureCanvasesDirectory()
        var jsonNodes: [[String: Any]] = []
        for node in nodes {
            var dict: [String: Any] = [
                "id": node.id, "itemType": node.itemType,
                "position": ["x": node.position.x, "y": node.position.y],
                "size": ["width": node.size.width, "height": node.size.height],
            ]
            if let itemID = node.itemID { dict["itemID"] = itemID }
            if let parent = node.parentNodeID { dict["parentNode"] = parent }
            switch node.itemType {
            case "folderGroup": dict["nodeType"] = "folderGroup"
            case "note": dict["nodeType"] = "noteCard"
            case "todo": dict["nodeType"] = "todoCard"
            default: dict["nodeType"] = "bookmarkCard"
            }
            if node.itemType == "folderGroup" {
                var meta: [String: Any] = ["collapsed": node.collapsed]
                if let lm = node.layoutMode { meta["layoutMode"] = lm }
                if node.id.hasPrefix("folder-"),
                   let uuidStr = node.id.components(separatedBy: "folder-").last,
                   let uuid = UUID(uuidString: uuidStr),
                   let folder = VaultFolderService.shared.folders.first(where: { $0.id == uuid }) {
                    meta["folderName"] = folder.name; meta["icon"] = "📁"
                    meta["itemCount"] = nodes.filter { $0.parentNodeID == node.id }.count
                }
                dict["metadata"] = meta
            }
            jsonNodes.append(dict)
        }
        var jsonEdges: [[String: Any]] = []
        for edge in edges {
            var dict: [String: Any] = ["id": edge.id, "sourceID": edge.sourceID, "targetID": edge.targetID]
            if let label = edge.label { dict["label"] = label }; jsonEdges.append(dict)
        }
        let canvas: [String: Any] = [
            "version": 1, "native": true, "nodes": jsonNodes, "edges": jsonEdges,
            "viewport": ["offsetX": viewport.offset.x, "offsetY": viewport.offset.y, "zoom": viewport.zoom],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: canvas, options: [.sortedKeys])
            try data.write(to: defaultCanvasFileURL, options: .atomic)
            Self.logger.debug("Saved canvas (\(data.count) bytes)")
        } catch { Self.logger.error("Failed to save canvas: \(error)") }
    }

    // MARK: - Node Operations

    func moveNode(id: String, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position = position; scheduleDebouncedSave()
    }
    func addNode(_ node: CanvasNode) { nodes.append(node); scheduleDebouncedSave() }
    func removeNode(id: String) { nodes.removeAll { $0.id == id }; scheduleDebouncedSave() }

    func toggleCollapse(nodeID: String) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[index].collapsed.toggle()
        if nodes[index].collapsed {
            nodes[index].size = CGSize(width: nodes[index].size.width, height: 44)
        } else { recalculateFolderSizes() }
        scheduleDebouncedSave()
    }

    func recalculateFolderSizes() {
        let columns = 4; let cardSpacingX: CGFloat = 300; let cardSpacingY: CGFloat = 280
        let folderPadding: CGFloat = 60; let folderInset: CGFloat = 20
        for i in nodes.indices {
            guard nodes[i].itemType == "folderGroup", !nodes[i].collapsed else { continue }
            let children = nodes.filter { $0.parentNodeID == nodes[i].id }
            guard !children.isEmpty else { continue }
            let actualColumns = min(columns, max(1, children.count))
            let rows = max(1, (children.count + columns - 1) / columns)
            nodes[i].size = CGSize(
                width: CGFloat(actualColumns) * cardSpacingX + folderInset * 2,
                height: folderPadding + CGFloat(rows) * cardSpacingY + folderInset + 20)
        }
    }

    func deselectAll() { selectedItemIDs.removeAll() }

    // MARK: - Bulk Operations

    /// Trash all currently selected items via TrashStorage and remove their canvas nodes.
    func deleteSelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        var trashItems: [TrashItem] = []

        for itemID in selectedItemIDs {
            removeNode(id: itemID)
            guard let uuid = UUID(uuidString: itemID) else { continue }

            if let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == uuid }) {
                let trashItem = VaultBookmarkService.shared.remove(bookmark)
                trashItems.append(trashItem)
            } else if let note = NotesStorage.shared.notes.first(where: { $0.id == uuid }) {
                let trashItem = NotesStorage.shared.delete(note: note)
                trashItems.append(trashItem)
            } else if let _ = TodoCardStorage.shared.todoCards.first(where: { $0.id == uuid }) {
                if let trashItem = TodoCardStorage.shared.deleteTodoCard(uuid) {
                    trashItems.append(trashItem)
                }
            }
        }

        if !trashItems.isEmpty {
            CiderUndoManager.shared.record(.bulkDeletedToTrash(trashItems))
        }

        selectedItemIDs.removeAll()
        Self.logger.info("Bulk deleted \(trashItems.count) items from canvas")
    }

    /// Move all currently selected bookmark items to a folder.
    func moveSelectedToFolder(_ folderID: UUID?) {
        guard !selectedItemIDs.isEmpty else { return }
        var movedItems: [BulkMoveItem] = []

        for itemID in selectedItemIDs {
            guard let uuid = UUID(uuidString: itemID) else { continue }

            if let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == uuid }) {
                let fromFolderID = bookmark.folderID
                if VaultBookmarkService.shared.assignBookmark(uuid, toFolder: folderID) {
                    movedItems.append(BulkMoveItem(
                        itemID: uuid,
                        itemType: .bookmark,
                        title: bookmark.title,
                        fromFolderID: fromFolderID
                    ))
                }
            }
        }

        if !movedItems.isEmpty {
            let folderName: String
            if let folderID, let folder = VaultFolderService.shared.folder(for: folderID) {
                folderName = folder.name
            } else {
                folderName = "Inbox"
            }
            CiderUndoManager.shared.record(.bulkMoved(movedItems, toFolderID: folderID, folderName: folderName))
        }

        Self.logger.info("Bulk moved \(movedItems.count) items to folder")
    }

    // MARK: - Hot Reload

    func startHotReload() {
        guard hotReloadCancellables.isEmpty else { return }
        Self.logger.info("Starting canvas hot reload"); refreshKnownItemIDs()
        let bookmarkPub = VaultBookmarkService.shared.$bookmarks.map { _ in () }
        let notesPub = NotesStorage.shared.$notes.map { _ in () }
        let todosPub = TodoCardStorage.shared.$todoCards.map { _ in () }
        bookmarkPub.merge(with: notesPub, todosPub)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleVaultChanged() }
            .store(in: &hotReloadCancellables)
    }

    func stopHotReload() { hotReloadCancellables.removeAll() }

    private func refreshKnownItemIDs() {
        var ids = Set<String>()
        for bm in VaultBookmarkService.shared.bookmarks { ids.insert(bm.id.uuidString) }
        for note in NotesStorage.shared.notes { ids.insert(note.id.uuidString) }
        for todo in TodoCardStorage.shared.todoCards { ids.insert(todo.id.uuidString) }
        knownItemIDs = ids
    }

    private func handleVaultChanged() {
        Self.logger.info("Vault changed — updating canvas")
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes; let todos = TodoCardStorage.shared.todoCards
        var currentIDs = Set<String>()
        for bm in bookmarks { currentIDs.insert(bm.id.uuidString) }
        for note in notes { currentIDs.insert(note.id.uuidString) }
        for todo in todos { currentIDs.insert(todo.id.uuidString) }
        let newIDs = currentIDs.subtracting(knownItemIDs)
        let deletedIDs = knownItemIDs.subtracting(currentIDs)
        if !deletedIDs.isEmpty {
            nodes.removeAll { node in guard let itemID = node.itemID else { return false }; return deletedIDs.contains(itemID) }
        }
        if !newIDs.isEmpty {
            let maxY = nodes.map { $0.position.y + $0.size.height }.max() ?? 0
            let startY = maxY + 80; var index = 0; let columns = 4; let spacingX: CGFloat = 300; let spacingY: CGFloat = 280
            for bm in bookmarks where newIDs.contains(bm.id.uuidString) {
                let col = index % columns; let row = index / columns
                nodes.append(CanvasNode(id: "node-\(bm.id.uuidString)", itemID: bm.id.uuidString, itemType: "bookmark",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY))); index += 1
            }
            for note in notes where newIDs.contains(note.id.uuidString) {
                let col = index % columns; let row = index / columns
                nodes.append(CanvasNode(id: "node-\(note.id.uuidString)", itemID: note.id.uuidString, itemType: "note",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY))); index += 1
            }
            for todo in todos where newIDs.contains(todo.id.uuidString) {
                let col = index % columns; let row = index / columns
                nodes.append(CanvasNode(id: "node-\(todo.id.uuidString)", itemID: todo.id.uuidString, itemType: "todo",
                    position: CGPoint(x: 50 + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY))); index += 1
            }
            Self.logger.info("Added \(index) new items to canvas")
        }
        knownItemIDs = currentIDs
        if !newIDs.isEmpty || !deletedIDs.isEmpty { rebuildTitleCache(); scheduleDebouncedSave() }
    }

    // MARK: - Item Click Handling

    func handleItemClicked(itemID: String, type: String) {
        let isCommandHeld = NSEvent.modifierFlags.contains(.command)
        Self.logger.info("Item clicked: \(itemID) (\(type)), cmd=\(isCommandHeld)")

        if isCommandHeld {
            // Toggle selection — add or remove from multi-select
            if selectedItemIDs.contains(itemID) {
                selectedItemIDs.remove(itemID)
            } else {
                selectedItemIDs.insert(itemID)
            }
        } else {
            // Single select — replace entire selection
            selectedItemIDs = [itemID]
        }

        // Post notification for panel sync
        if selectedItemIDs.count == 1 {
            guard let uuid = UUID(uuidString: itemID) else { return }
            NotificationCenter.default.post(name: .canvasItemSelected, object: nil, userInfo: ["bookmarkID": uuid, "type": type])
        } else if selectedItemIDs.count == 2 {
            // When exactly 2 items are Cmd+selected, notify for split view
            let ids = Array(selectedItemIDs)
            NotificationCenter.default.post(
                name: .canvasItemSelected,
                object: nil,
                userInfo: [
                    "splitItemIDs": ids,
                    "type": "split"
                ]
            )
        }
    }

    func handleItemDoubleClicked(itemID: String, type: String) {
        Self.logger.info("Item double-clicked: \(itemID) (\(type))")
        guard type == "bookmark", let uuid = UUID(uuidString: itemID),
              let bookmark = bookmarkLookup[uuid], let url = URL(string: bookmark.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Navigation

    func panToFolder(_ folderID: UUID) {
        let groupId = "folder-\(folderID.uuidString)"
        guard let node = nodes.first(where: { $0.id == groupId }) else { return }

        NotificationCenter.default.post(
            name: .canvasPanToFolder,
            object: nil,
            userInfo: [
                "x": node.position.x + node.size.width / 2,
                "y": node.position.y + node.size.height / 2
            ]
        )
    }

    func panToItem(_ itemID: String) {
        guard let node = nodes.first(where: { $0.itemID == itemID }) else { return }
        // Card positions are relative to their parent folder group — add the parent's position
        var absX = node.position.x + node.size.width / 2
        var absY = node.position.y + node.size.height / 2
        if let parentID = node.parentNodeID,
           let parent = nodes.first(where: { $0.id == parentID }) {
            absX += parent.position.x
            absY += parent.position.y
        }
        NotificationCenter.default.post(
            name: .canvasPanToFolder,
            object: nil,
            userInfo: ["x": absX, "y": absY]
        )
    }
}
