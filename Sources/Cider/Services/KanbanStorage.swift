import Foundation
import Yams
import os.log

/// Manages YAML-backed Kanban boards stored in the vault.
/// Both the Cider UI and AI agents can read/write to the same YAML files.
@MainActor
final class KanbanStorage: ObservableObject {
    static let shared = KanbanStorage()

    @Published var boards: [KanbanBoard] = []

    private let logger = Logger(subsystem: "com.cider.app", category: "KanbanStorage")
    private var watcher: FSEventsWatcher?
    private var isMutating = false

    private var boardsDir: URL {
        StoragePaths.directoryURL(for: .kanbanBoards)
    }

    init() {
        ensureDirectory()
        reload()
    }

    // MARK: - Directory

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: boardsDir, withIntermediateDirectories: true)
    }

    // MARK: - Load

    func reload() {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: boardsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            boards = []
            return
        }

        var loaded: [KanbanBoard] = []
        for file in files where file.pathExtension == "yaml" {
            if let board = load(from: file) {
                loaded.append(board)
            }
        }

        boards = loaded.sorted { $0.created > $1.created }
    }

    private func reloadBoard(id: String) {
        let url = boardsDir.appendingPathComponent("\(id).yaml")
        if let board = load(from: url) {
            if let index = boards.firstIndex(where: { $0.id == id }) {
                if boards[index] != board {
                    boards[index] = board
                }
            } else {
                boards.append(board)
                boards.sort { $0.created > $1.created }
            }
        } else {
            // File was deleted externally
            boards.removeAll { $0.id == id }
        }
    }

    private func load(from url: URL) -> KanbanBoard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(KanbanBoard.self, from: content)
        } catch {
            logger.error("Failed to decode \(url.lastPathComponent): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Save

    private func save(_ board: KanbanBoard) {
        do {
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(board)
            let url = boardsDir.appendingPathComponent("\(board.id).yaml")
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to save board \(board.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mutate(boardID: String, _ body: (inout KanbanBoard) -> Void) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        isMutating = true
        body(&boards[index])
        save(boards[index])
        isMutating = false
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
    }

    // MARK: - Board CRUD

    @discardableResult
    func createBoard(name: String) -> KanbanBoard {
        isMutating = true
        let board = KanbanBoard.new(name: name)
        boards.insert(board, at: 0)
        save(board)
        isMutating = false
        logger.info("Created board: \(name, privacy: .public)")
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
        return board
    }

    @discardableResult
    func deleteBoard(id: String) -> TrashItem? {
        guard let board = boards.first(where: { $0.id == id }) else { return nil }
        let url = boardsDir.appendingPathComponent("\(id).yaml")
        let yamlContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let trashItem = TrashStorage.shared.trashKanbanBoard(
            boardID: id,
            name: board.name,
            yamlContent: yamlContent
        )

        isMutating = true
        boards.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url)
        isMutating = false
        logger.info("Trashed board: \(id, privacy: .public)")
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
        return trashItem
    }

    func renameBoard(id: String, name: String) {
        mutate(boardID: id) { $0.name = name }
    }

    // MARK: - Column Operations

    @discardableResult
    func addColumn(boardID: String, name: String, isDoneColumn: Bool = false) -> KanbanColumn? {
        guard boards.contains(where: { $0.id == boardID }) else { return nil }
        let column = KanbanColumn(
            id: KanbanID.slug(from: name),
            name: name,
            isDoneColumn: isDoneColumn
        )
        mutate(boardID: boardID) { $0.columns.append(column) }
        return column
    }

    func deleteColumn(boardID: String, columnID: String) {
        mutate(boardID: boardID) { board in
            board.columns.removeAll { $0.id == columnID }
        }
    }

    func renameColumn(boardID: String, columnID: String, name: String) {
        mutate(boardID: boardID) { board in
            guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[i].name = name
        }
    }

    func reorderColumns(boardID: String, fromOffsets: IndexSet, toOffset: Int) {
        mutate(boardID: boardID) { board in
            board.columns.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func setColumnDone(boardID: String, columnID: String, isDone: Bool) {
        mutate(boardID: boardID) { board in
            guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[i].isDoneColumn = isDone
        }
    }

    // MARK: - Card Operations

    @discardableResult
    func addCard(boardID: String, columnID: String, title: String) -> KanbanCard? {
        guard boards.contains(where: { $0.id == boardID }) else { return nil }
        let card = KanbanCard(title: title)
        mutate(boardID: boardID) { board in
            guard let colIdx = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[colIdx].cards.append(card)
        }
        return card
    }

    func updateCard(boardID: String, card: KanbanCard) {
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == card.id }) {
                    board.columns[colIdx].cards[cardIdx] = card
                    return
                }
            }
        }
    }

    func deleteCard(boardID: String, cardID: String) {
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                board.columns[colIdx].cards.removeAll { $0.id == cardID }
            }
        }
    }

    func moveCard(boardID: String, cardID: String, toColumnID: String, toIndex: Int) {
        mutate(boardID: boardID) { board in
            // Find and remove card from current column
            var card: KanbanCard?
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    card = board.columns[colIdx].cards.remove(at: cardIdx)
                    break
                }
            }
            guard var movedCard = card else { return }

            // Find destination column
            guard let destIdx = board.columns.firstIndex(where: { $0.id == toColumnID }) else { return }

            // Auto-set completed date when moving to a done column
            if board.columns[destIdx].isDoneColumn && movedCard.completed == nil {
                movedCard.completed = Date()
            } else if !board.columns[destIdx].isDoneColumn {
                movedCard.completed = nil
            }

            let insertAt = min(toIndex, board.columns[destIdx].cards.count)
            board.columns[destIdx].cards.insert(movedCard, at: insertAt)
        }
    }

    func reorderCards(boardID: String, columnID: String, fromOffsets: IndexSet, toOffset: Int) {
        mutate(boardID: boardID) { board in
            guard let colIdx = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[colIdx].cards.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()
        watcher = FSEventsWatcher(path: boardsDir.path) { [weak self] _ in
            // FSEventsWatcher delivers on main queue
            MainActor.assumeIsolated {
                self?.handleFSEvent()
            }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func handleFSEvent() {
        guard !isMutating else { return }
        // Reload all boards — simple and correct for the expected board count
        reload()
    }

    // MARK: - Helpers

    /// Find a board by name (case-insensitive).
    func board(named name: String) -> KanbanBoard? {
        boards.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Find a card across all boards.
    func findCard(id: String) -> (board: KanbanBoard, column: KanbanColumn, card: KanbanCard)? {
        for board in boards {
            for column in board.columns {
                if let card = column.cards.first(where: { $0.id == id }) {
                    return (board, column, card)
                }
            }
        }
        return nil
    }

    /// Ensure every board YAML file has a corresponding SavedView tab entry.
    /// Call once at app launch after both KanbanStorage and SavedViewStorage have loaded.
    func syncTabsWithBoards() {
        let savedViewStorage = SavedViewStorage.shared
        let existingBoardIDs = Set(
            savedViewStorage.savedViews
                .compactMap { sv -> String? in
                    if case .kanban(let id) = sv.kind { return id }
                    return nil
                }
        )

        for board in boards where !existingBoardIDs.contains(board.id) {
            let savedView = savedViewStorage.createKanbanView(name: board.name, boardID: board.id)
            savedViewStorage.addToTabOrder(savedView.id)
            logger.info("Auto-created tab for board: \(board.name, privacy: .public)")
        }
    }
}
