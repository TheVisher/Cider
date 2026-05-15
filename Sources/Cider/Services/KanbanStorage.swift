import Foundation
import Yams
import Darwin
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

    private func boardFileURL(for boardID: String) -> URL {
        boardsDir.appendingPathComponent("\(boardID).yaml")
    }

    private func boardLockURL(for boardID: String) -> URL {
        boardsDir.appendingPathComponent("\(boardID).yaml.lock")
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

    private func load(from url: URL) -> KanbanBoard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(KanbanBoard.self, from: content)
        } catch {
            logger.error("Failed to decode \(url.lastPathComponent): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Save

    private func save(_ board: KanbanBoard) {
        _ = withExclusiveBoardFileLock(boardID: board.id) {
            saveUnlocked(board)
            upsertInMemory(board)
            return true
        }
    }

    private func saveUnlocked(_ board: KanbanBoard) {
        do {
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(board)
            let url = boardFileURL(for: board.id)
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to save board \(board.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func withExclusiveBoardFileLock<T>(boardID: String, _ body: () -> T) -> T? {
        ensureDirectory()
        let lockURL = boardLockURL(for: boardID)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd != -1 else {
            logger.error("Failed to open Kanban lock \(lockURL.lastPathComponent, privacy: .public)")
            return nil
        }

        defer { close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            logger.error("Failed to acquire Kanban lock \(lockURL.lastPathComponent, privacy: .public)")
            return nil
        }

        defer { flock(fd, LOCK_UN) }
        return body()
    }

    private func upsertInMemory(_ board: KanbanBoard) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            boards[index] = board
        } else {
            boards.append(board)
        }
        boards.sort { $0.created > $1.created }
    }

    private func mutate(boardID: String, _ body: (inout KanbanBoard) -> Void) {
        isMutating = true
        defer { isMutating = false }

        var didMutate = false
        _ = withExclusiveBoardFileLock(boardID: boardID) {
            guard var board = load(from: boardFileURL(for: boardID)) ?? boards.first(where: { $0.id == boardID }) else {
                return
            }
            body(&board)
            saveUnlocked(board)
            upsertInMemory(board)
            didMutate = true
        }

        guard didMutate else { return }
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
    }

    // MARK: - Board CRUD

    @discardableResult
    func createBoard(name: String) -> KanbanBoard {
        isMutating = true
        defer { isMutating = false }
        let board = KanbanBoard.new(name: name)
        boards.insert(board, at: 0)
        save(board)
        logger.info("Created board: \(name, privacy: .public)")
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
        return board
    }

    @discardableResult
    func deleteBoard(id: String) -> TrashItem? {
        isMutating = true
        defer { isMutating = false }

        var trashItem: TrashItem?
        _ = withExclusiveBoardFileLock(boardID: id) {
            guard let board = load(from: boardFileURL(for: id)) ?? boards.first(where: { $0.id == id }) else { return }
            let url = boardFileURL(for: id)
            let yamlContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

            trashItem = TrashStorage.shared.trashKanbanBoard(
                boardID: id,
                name: board.name,
                yamlContent: yamlContent
            )

            boards.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: url)
            logger.info("Trashed board: \(id, privacy: .public)")
        }

        guard let trashItem else { return nil }
        NotificationCenter.default.post(name: .kanbanBoardsChanged, object: nil)
        return trashItem
    }

    func renameBoard(id: String, name: String) {
        mutate(boardID: id) { $0.name = name }
    }

    // MARK: - Column Operations

    @discardableResult
    func addColumn(boardID: String, name: String, isDoneColumn: Bool = false) -> KanbanColumn? {
        var createdColumn: KanbanColumn?
        mutate(boardID: boardID) { board in
            var columnID = KanbanID.slug(from: name)
            let existingIDs = Set(board.columns.map(\.id))
            if existingIDs.contains(columnID) {
                var counter = 2
                while existingIDs.contains("\(columnID)_\(counter)") { counter += 1 }
                columnID = "\(columnID)_\(counter)"
            }
            let column = KanbanColumn(
                id: columnID,
                name: name,
                isDoneColumn: isDoneColumn
            )
            board.columns.append(column)
            createdColumn = column
        }
        return createdColumn
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
    func addCard(
        boardID: String,
        columnID: String,
        title: String,
        notes: String? = nil,
        priority: KanbanPriority? = nil,
        color: KanbanCardColor? = nil,
        tags: [String] = [],
        parentCardID: String? = nil
    ) -> KanbanCard? {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = KanbanCard(
            title: title,
            notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil,
            color: color,
            priority: priority,
            tags: tags,
            parentCardID: parentCardID
        )
        var didAdd = false
        mutate(boardID: boardID) { board in
            guard parentCardID == nil || board.card(id: parentCardID ?? "") != nil else { return }
            guard let colIdx = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[colIdx].cards.append(card)
            didAdd = true
        }
        if didAdd {
            schedulePreviewSummaryRefresh(boardID: boardID, cardID: card.id)
        }
        return didAdd ? card : nil
    }

    func updateCard(boardID: String, card: KanbanCard) {
        let baseline = boards.flatMap(\.allCards).first { $0.id == card.id }
        let shouldRefreshSummary = baseline.map {
            $0.title != card.title || $0.notes != card.notes
        } ?? false
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == card.id }) {
                    let current = board.columns[colIdx].cards[cardIdx]
                    var merged = mergeCardUpdate(card, baseline: baseline, into: current)
                    if shouldRefreshSummary {
                        merged.aiSummary = nil
                    }
                    guard board.canAssignParent(cardID: merged.id, parentCardID: merged.parentCardID) else { return }
                    board.columns[colIdx].cards[cardIdx] = merged
                    return
                }
            }
        }
        if shouldRefreshSummary {
            schedulePreviewSummaryRefresh(boardID: boardID, cardID: card.id)
        }
    }

    private func mergeCardUpdate(_ incoming: KanbanCard, baseline: KanbanCard?, into current: KanbanCard) -> KanbanCard {
        guard let baseline else { return incoming }

        var merged = current
        if incoming.title != baseline.title { merged.title = incoming.title }
        if incoming.notes != baseline.notes { merged.notes = incoming.notes }
        if incoming.aiSummary != baseline.aiSummary { merged.aiSummary = incoming.aiSummary }
        if incoming.color != baseline.color { merged.color = incoming.color }
        if incoming.priority != baseline.priority { merged.priority = incoming.priority }
        if incoming.agent != baseline.agent { merged.agent = incoming.agent }
        if incoming.tags != baseline.tags { merged.tags = incoming.tags }
        if incoming.linkedEntities != baseline.linkedEntities { merged.linkedEntities = incoming.linkedEntities }
        if incoming.relatedCardIDs != baseline.relatedCardIDs { merged.relatedCardIDs = incoming.relatedCardIDs }
        if incoming.parentCardID != baseline.parentCardID { merged.parentCardID = incoming.parentCardID }
        if incoming.historyEntries != baseline.historyEntries { merged.historyEntries = incoming.historyEntries }
        if incoming.completed != baseline.completed { merged.completed = incoming.completed }
        return merged
    }

    private func schedulePreviewSummaryRefresh(boardID: String, cardID: String) {
        Task { @MainActor [weak self] in
            guard let self,
                  let detail = self.findCard(id: cardID),
                  detail.board.id == boardID else { return }
            guard detail.card.aiSummary == nil,
                  let summary = await SummaryService.shared.summarizeKanbanCardPreview(
                    title: detail.card.title,
                    notes: detail.card.notes
                  ) else { return }

            self.mutate(boardID: boardID) { board in
                for colIdx in board.columns.indices {
                    if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                        let current = board.columns[colIdx].cards[cardIdx]
                        guard current.aiSummary == nil else { return }
                        board.columns[colIdx].cards[cardIdx].aiSummary = summary
                        return
                    }
                }
            }
        }
    }

    func deleteCard(boardID: String, cardID: String) {
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                board.columns[colIdx].cards.removeAll { $0.id == cardID }
            }
            board.clearParentReferences(to: cardID)
        }
    }

    @discardableResult
    func setCardParent(boardID: String, cardID: String, parentCardID: String?) -> Bool {
        var didUpdate = false
        mutate(boardID: boardID) { board in
            guard board.canAssignParent(cardID: cardID, parentCardID: parentCardID) else { return }
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    board.columns[colIdx].cards[cardIdx].parentCardID = parentCardID
                    didUpdate = true
                    return
                }
            }
        }
        return didUpdate
    }

    func moveCard(
        boardID: String,
        cardID: String,
        toColumnID: String,
        toIndex: Int,
        includeDescendants: Bool = false
    ) {
        mutate(boardID: boardID) { board in
            // Validate destination column exists before removing from source
            guard board.columns.contains(where: { $0.id == toColumnID }) else { return }

            guard let rootCard = board.card(id: cardID) else { return }
            let sourceColumnID = board.columnID(containing: cardID)
            let cardsToMove = includeDescendants
                ? [rootCard] + board.descendantCards(of: cardID).filter { descendant in
                    board.columnID(containing: descendant.id) == sourceColumnID
                }
                : [rootCard]
            let movingIDs = Set(cardsToMove.map(\.id))

            for colIdx in board.columns.indices {
                board.columns[colIdx].cards.removeAll { movingIDs.contains($0.id) }
            }

            // Find destination column
            guard let destIdx = board.columns.firstIndex(where: { $0.id == toColumnID }) else { return }

            let movedCards = cardsToMove.map { card in
                var movedCard = card
                // Auto-set completed date when moving to a done column
                if board.columns[destIdx].isDoneColumn && movedCard.completed == nil {
                    movedCard.completed = Date()
                } else if !board.columns[destIdx].isDoneColumn {
                    movedCard.completed = nil
                }
                return movedCard
            }

            let insertAt = min(toIndex, board.columns[destIdx].cards.count)
            board.columns[destIdx].cards.insert(contentsOf: movedCards, at: insertAt)
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
