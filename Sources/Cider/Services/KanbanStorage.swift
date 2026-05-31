import Foundation
import Yams
import Darwin
import os.log

struct KanbanBoardLoadIssue {
    var fileName: String
    var boardID: String
    var message: String
}

enum KanbanBoardRepairIssueKind: String, Equatable, Sendable {
    case readFailed
    case decodeFailed
}

struct KanbanBoardRepairIssue: Equatable, Sendable {
    var boardID: String
    var fileURL: URL
    var kind: KanbanBoardRepairIssueKind
    var message: String
    var recoveryCommand: String
}

/// Manages YAML-backed Kanban boards stored in the vault.
/// Both the Cider UI and AI agents can read/write to the same YAML files.
@MainActor
final class KanbanStorage: ObservableObject {
    static let shared = KanbanStorage()

    @Published var boards: [KanbanBoard] = []
    @Published private(set) var lastRepairIssue: KanbanBoardRepairIssue?

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

    func loadIssues() -> [KanbanBoardLoadIssue] {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: boardsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "yaml" }
            .compactMap { file in
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    return KanbanBoardLoadIssue(
                        fileName: file.lastPathComponent,
                        boardID: file.deletingPathExtension().lastPathComponent,
                        message: "Could not read board YAML file '\(file.lastPathComponent)'."
                    )
                }
                do {
                    _ = try YAMLDecoder().decode(KanbanBoard.self, from: content)
                    return nil
                } catch {
                    return KanbanBoardLoadIssue(
                        fileName: file.lastPathComponent,
                        boardID: file.deletingPathExtension().lastPathComponent,
                        message: "Could not decode board YAML file '\(file.lastPathComponent)': \(error.localizedDescription)"
                    )
                }
            }
    }

    private func load(from url: URL) -> KanbanBoard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            let decoder = YAMLDecoder()
            var board = try decoder.decode(KanbanBoard.self, from: content)
            board.assignMissingDisplayKeys()
            return board
        } catch {
            logger.error("Failed to decode \(url.lastPathComponent): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func loadFreshBoardForWrite(boardID: String) -> KanbanBoard? {
        let url = boardFileURL(for: boardID)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            lastRepairIssue = repairIssue(
                boardID: boardID,
                fileURL: url,
                kind: .readFailed,
                message: "Could not read board YAML file '\(url.lastPathComponent)': \(error.localizedDescription)"
            )
            logger.error("Blocked Kanban write for \(boardID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            var board = try YAMLDecoder().decode(KanbanBoard.self, from: content)
            board.assignMissingDisplayKeys()
            lastRepairIssue = nil
            return board
        } catch {
            lastRepairIssue = repairIssue(
                boardID: boardID,
                fileURL: url,
                kind: .decodeFailed,
                message: "Could not decode board YAML file '\(url.lastPathComponent)': \(error.localizedDescription)"
            )
            logger.error("Blocked Kanban write for \(boardID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func repairIssue(
        boardID: String,
        fileURL: URL,
        kind: KanbanBoardRepairIssueKind,
        message: String
    ) -> KanbanBoardRepairIssue {
        KanbanBoardRepairIssue(
            boardID: boardID,
            fileURL: fileURL,
            kind: kind,
            message: message,
            recoveryCommand: "cider-cli board audit --json"
        )
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
            var boardToSave = board
            boardToSave.assignMissingDisplayKeys()
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(boardToSave)
            let url = boardFileURL(for: boardToSave.id)
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
            guard var board = loadFreshBoardForWrite(boardID: boardID) else {
                return
            }
            body(&board)
            board.assignMissingDisplayKeys()
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
            let url = boardFileURL(for: id)
            guard let board = loadFreshBoardForWrite(boardID: id) else { return }
            guard let yamlContent = try? String(contentsOf: url, encoding: .utf8) else { return }

            trashItem = TrashStorage.shared.trashKanbanBoard(
                boardID: id,
                name: board.name,
                yamlContent: yamlContent
            )

            boards.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: url)
            deleteSecondBrainBoardProjectionIfAvailable(boardID: id)
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
    func addColumn(boardID: String, name: String, isDoneColumn: Bool = false, isHiddenColumn: Bool = false) -> KanbanColumn? {
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
                isDoneColumn: isDoneColumn,
                isHiddenColumn: isHiddenColumn
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

    func setColumnHidden(boardID: String, columnID: String, isHidden: Bool) {
        mutate(boardID: boardID) { board in
            guard let i = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            board.columns[i].hiddenColumnState = isHidden
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
        parentCardID: String? = nil,
        afterCardID: String? = nil
    ) -> KanbanCard? {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        var card = KanbanCard(
            title: title,
            notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil,
            color: color,
            priority: priority,
            tags: tags,
            parentCardID: parentCardID
        )
        var didAdd = false
        mutate(boardID: boardID) { board in
            card.displayKey = board.nextDisplayKey()
            guard parentCardID == nil || board.card(id: parentCardID ?? "") != nil else { return }
            guard let colIdx = board.columns.firstIndex(where: { $0.id == columnID }) else { return }
            if let afterCardID {
                guard let afterIndex = board.columns[colIdx].cards.firstIndex(where: { $0.id == afterCardID }) else { return }
                if let parentCardID,
                   board.columns[colIdx].cards[afterIndex].parentCardID != parentCardID {
                    return
                }
                board.columns[colIdx].cards.insert(card, at: afterIndex + 1)
            } else {
                board.columns[colIdx].cards.append(card)
            }
            didAdd = true
        }
        if didAdd {
            schedulePreviewSummaryRefresh(boardID: boardID, cardID: card.id)
            refreshSecondBrainProjectionIfAvailable(boardID: boardID, card: card)
        }
        return didAdd ? card : nil
    }

    func updateCardTags(boardID: String, cardID: String, tags: [String]) {
        let normalizedTags = KanbanCardTagTaxonomy.normalizedTags(from: tags)
        var updatedCard: KanbanCard?
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    let current = board.columns[colIdx].cards[cardIdx]
                    guard current.tags != normalizedTags else { return }
                    board.columns[colIdx].cards[cardIdx].tags = normalizedTags
                    board.columns[colIdx].cards[cardIdx].markActivity("updated")
                    updatedCard = board.columns[colIdx].cards[cardIdx]
                    return
                }
            }
        }
        if let updatedCard {
            refreshSecondBrainProjectionIfAvailable(boardID: boardID, card: updatedCard)
        }
    }

    func updateCard(boardID: String, card: KanbanCard) {
        let baseline = boards.flatMap(\.allCards).first { $0.id == card.id }
        let shouldRefreshSummary = baseline.map {
            $0.title != card.title || $0.notes != card.notes
        } ?? false
        var didUpdate = false
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == card.id }) {
                    let current = board.columns[colIdx].cards[cardIdx]
                    var merged = mergeCardUpdate(card, baseline: baseline, into: current)
                    if shouldRefreshSummary {
                        merged.aiSummary = nil
                    }
                    guard board.canAssignParent(cardID: merged.id, parentCardID: merged.parentCardID) else { return }
                    guard merged != current else { return }
                    if !isReviewOnlyChange(from: current, to: merged), merged.updatedAt == current.updatedAt {
                        merged.markActivity("updated")
                    }
                    board.columns[colIdx].cards[cardIdx] = merged
                    didUpdate = true
                    return
                }
            }
        }
        if shouldRefreshSummary {
            schedulePreviewSummaryRefresh(boardID: boardID, cardID: card.id)
        }
        if didUpdate {
            refreshSecondBrainProjectionIfAvailable(boardID: boardID, card: card)
        }
    }

    @discardableResult
    func updateCardSection(boardID: String, cardID: String, title: String, body: String) -> KanbanCard? {
        mutateCardNotes(boardID: boardID, cardID: cardID) { notes in
            KanbanCardSectionParser.updatingSection(in: notes, title: title, body: body)
        }
    }

    @discardableResult
    func appendCardEvidence(boardID: String, cardID: String, text: String, source: String?) -> KanbanCard? {
        mutateCardNotes(boardID: boardID, cardID: cardID) { notes in
            KanbanCardSectionParser.appendingEvidence(to: notes, text: text, source: source)
        }
    }

    @discardableResult
    func appendCardHistory(boardID: String, cardID: String, type: String, text: String, source: String?) -> KanbanCard? {
        var wasInvalidType = false
        let updatedCard = mutateCardNotes(boardID: boardID, cardID: cardID) { notes in
            guard let nextNotes = KanbanCardSectionParser.appendingHistory(
                to: notes,
                type: type,
                text: text,
                source: source
            ) else {
                wasInvalidType = true
                return notes
            }
            return nextNotes
        }
        return wasInvalidType ? nil : updatedCard
    }

    private func mutateCardNotes(
        boardID: String,
        cardID: String,
        transform: (String?) -> String?
    ) -> KanbanCard? {
        var updatedCard: KanbanCard?
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    let current = board.columns[colIdx].cards[cardIdx]
                    let nextNotes = transform(current.notes)
                    guard nextNotes != current.notes else {
                        updatedCard = current
                        return
                    }
                    board.columns[colIdx].cards[cardIdx].notes = nextNotes
                    board.columns[colIdx].cards[cardIdx].aiSummary = nil
                    board.columns[colIdx].cards[cardIdx].markActivity("updated")
                    updatedCard = board.columns[colIdx].cards[cardIdx]
                    return
                }
            }
        }
        if let updatedCard {
            schedulePreviewSummaryRefresh(boardID: boardID, cardID: cardID)
            refreshSecondBrainProjectionIfAvailable(boardID: boardID, card: updatedCard)
        }
        return updatedCard
    }

    private func mergeCardUpdate(_ incoming: KanbanCard, baseline: KanbanCard?, into current: KanbanCard) -> KanbanCard {
        guard let baseline else { return incoming }

        var merged = current
        if incoming.title != baseline.title { merged.title = incoming.title }
        if incoming.notes != baseline.notes { merged.notes = incoming.notes }
        if incoming.aiSummary != baseline.aiSummary { merged.aiSummary = incoming.aiSummary }
        if incoming.displayKey != baseline.displayKey { merged.displayKey = incoming.displayKey }
        if incoming.color != baseline.color { merged.color = incoming.color }
        if incoming.priority != baseline.priority { merged.priority = incoming.priority }
        if incoming.agent != baseline.agent { merged.agent = incoming.agent }
        if incoming.tags != baseline.tags { merged.tags = incoming.tags }
        if incoming.linkedEntities != baseline.linkedEntities { merged.linkedEntities = incoming.linkedEntities }
        if incoming.relatedCardIDs != baseline.relatedCardIDs { merged.relatedCardIDs = incoming.relatedCardIDs }
        if incoming.parentCardID != baseline.parentCardID { merged.parentCardID = incoming.parentCardID }
        if incoming.historyEntries != baseline.historyEntries { merged.historyEntries = incoming.historyEntries }
        if incoming.comments != baseline.comments { merged.comments = incoming.comments }
        if incoming.completed != baseline.completed { merged.completed = incoming.completed }
        if incoming.updatedAt != baseline.updatedAt { merged.updatedAt = incoming.updatedAt }
        if incoming.lastActivityKind != baseline.lastActivityKind { merged.lastActivityKind = incoming.lastActivityKind }
        if incoming.reviewedAt != baseline.reviewedAt { merged.reviewedAt = incoming.reviewedAt }
        return merged
    }

    private func isReviewOnlyChange(from current: KanbanCard, to merged: KanbanCard) -> Bool {
        var normalized = merged
        normalized.reviewedAt = current.reviewedAt
        return normalized == current
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

    private func refreshSecondBrainProjectionIfAvailable(boardID: String, card: KanbanCard) {
        guard CiderDatabase.shared.isOpen else { return }
        do {
            try SecondBrainKanbanProjectionService().refreshCard(boardID: boardID, card: card)
        } catch {
            logger.error("Failed to refresh item graph projection for card \(card.id): \(String(describing: error), privacy: .public)")
        }
    }

    func refreshSecondBrainProjectionIfAvailable(boardID: String) {
        guard CiderDatabase.shared.isOpen else { return }
        guard let board = boards.first(where: { $0.id == boardID }) else { return }
        let projector = SecondBrainKanbanProjectionService()
        for card in board.allCards {
            do {
                try projector.refreshCard(boardID: boardID, card: card)
            } catch {
                logger.error("Failed to refresh item graph projection for restored card \(card.id): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func deleteSecondBrainCardProjectionIfAvailable(boardID: String, cardID: String) {
        guard CiderDatabase.shared.isOpen else { return }
        do {
            let owner = SecondBrainKanbanProjectionService.owner(boardID: boardID, cardID: cardID)
            try SecondBrainStore().deleteProjection(for: owner)
        } catch {
            logger.error("Failed to delete item graph projection for card \(cardID): \(String(describing: error), privacy: .public)")
        }
    }

    private func deleteSecondBrainBoardProjectionIfAvailable(boardID: String) {
        guard CiderDatabase.shared.isOpen else { return }
        do {
            try SecondBrainStore().deleteProjections(ownerType: "kanban_card", ownerIDPrefix: "\(boardID)/")
        } catch {
            logger.error("Failed to delete item graph projections for board \(boardID): \(String(describing: error), privacy: .public)")
        }
    }

    func markCardReviewed(boardID: String, cardID: String, at date: Date = Date()) {
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    board.columns[colIdx].cards[cardIdx].reviewedAt = date
                    return
                }
            }
        }
    }

    @discardableResult
    func addComment(boardID: String, cardID: String, comment: KanbanCardComment) -> KanbanCardComment? {
        var appended: KanbanCardComment?
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                if let cardIdx = board.columns[colIdx].cards.firstIndex(where: { $0.id == cardID }) {
                    if let parentID = comment.parentCommentID,
                       !board.columns[colIdx].cards[cardIdx].comments.contains(where: { $0.id == parentID }) {
                        return
                    }
                    board.columns[colIdx].cards[cardIdx].comments.append(comment)
                    board.columns[colIdx].cards[cardIdx].markActivity("comment", at: comment.createdAt)
                    appended = comment
                    return
                }
            }
        }
        if let appended,
           let card = findCard(id: cardID)?.card {
            refreshSecondBrainProjectionIfAvailable(boardID: boardID, card: card)
            return appended
        }
        return nil
    }

    func deleteCard(boardID: String, cardID: String) {
        var didDelete = false
        mutate(boardID: boardID) { board in
            for colIdx in board.columns.indices {
                let before = board.columns[colIdx].cards.count
                board.columns[colIdx].cards.removeAll { $0.id == cardID }
                if board.columns[colIdx].cards.count != before {
                    didDelete = true
                }
            }
            board.clearParentReferences(to: cardID)
        }
        if didDelete {
            deleteSecondBrainCardProjectionIfAvailable(boardID: boardID, cardID: cardID)
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
                if board.columns[destIdx].isDoneLikeColumn && movedCard.completed == nil {
                    movedCard.completed = Date()
                    movedCard.markActivity("completed")
                } else if !board.columns[destIdx].isDoneLikeColumn {
                    movedCard.completed = nil
                    movedCard.markActivity("moved")
                } else {
                    movedCard.markActivity("moved")
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
        for board in boards {
            _ = savedViewStorage.ensureKanbanView(name: board.name, boardID: board.id)
            logger.info("Ensured tab for board: \(board.name, privacy: .public)")
        }
    }
}
