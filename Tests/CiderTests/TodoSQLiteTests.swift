import Foundation
import Testing
@testable import Cider

@Suite("Todo SQLite Tests")
@MainActor
struct TodoSQLiteTests {

    // MARK: - Helpers

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-todo-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    /// Create and open a fresh database for testing.
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    /// Create TodoCardStorage wired to the test database.
    private func makeService(_ db: CiderDatabase) -> TodoCardStorage {
        TodoCardStorage(database: db)
    }

    // MARK: - Basic Round-Trip

    @Test("Todo round-trips through SQLite: persist and load")
    func todoRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let todo = TodoCard(
            title: "Buy groceries",
            details: "Weekly shop"
        )

        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards.count == 1)
        let loaded = service2.todoCards[0]
        #expect(loaded.id == todo.id)
        #expect(loaded.title == "Buy groceries")
        #expect(loaded.details == "Weekly shop")
    }

    // MARK: - All Fields

    @Test("Todo with all fields round-trips correctly")
    func todoAllFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Work", colorHex: "#3B82F6")
        let label2 = labelStorage.createLabel(name: "Urgent", colorHex: "#EF4444")

        let folder = VaultFolder(relativePath: "Projects")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        let created = Date(timeIntervalSince1970: 1_600_000_000)

        let checklist = [
            TodoChecklistItem(
                title: "Buy milk",
                isCompleted: true,
                completedAt: completed,
                sortOrder: 0,
                dueDate: due,
                amount: 3.50,
                urlString: "https://example.com/milk",
                subtasks: [
                    TodoSubtask(title: "Check expiry", isCompleted: true, completedAt: completed),
                    TodoSubtask(title: "Pick brand")
                ]
            ),
            TodoChecklistItem(
                title: "Buy eggs",
                sortOrder: 1,
                amount: 4.99
            )
        ]

        let todo = TodoCard(
            title: "Full Todo",
            details: "Primary description",
            checklist: checklist,
            dueDate: due,
            priority: .high,
            isCompleted: true,
            completedAt: completed,
            labelIDs: [label1.id, label2.id],
            notes: "Some supporting notes",
            linkedEntities: [],
            folderID: folder.id,
            createdAt: created,
            updatedAt: created
        )

        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards.count == 1)
        let loaded = service2.todoCards[0]
        #expect(loaded.title == "Full Todo")
        #expect(loaded.details == "Primary description")
        #expect(loaded.notes == "Some supporting notes")
        #expect(loaded.priority == .high)
        #expect(loaded.isCompleted == true)
        #expect(abs((loaded.dueDate ?? .distantPast).timeIntervalSince(due)) < 0.001)
        #expect(abs((loaded.completedAt ?? .distantPast).timeIntervalSince(completed)) < 0.001)
        #expect(loaded.folderID == folder.id)
        #expect(Set(loaded.labelIDs) == Set([label1.id, label2.id]))

        // Checklist round-trip
        #expect(loaded.checklist.count == 2)
        let first = loaded.checklist.first { $0.title == "Buy milk" }
        #expect(first != nil)
        #expect(first?.isCompleted == true)
        #expect(first?.amount == 3.50)
        #expect(first?.urlString == "https://example.com/milk")
        #expect(first?.subtasks.count == 2)
        #expect(first?.subtasks.first(where: { $0.title == "Check expiry" })?.isCompleted == true)
        #expect(first?.subtasks.first(where: { $0.title == "Pick brand" })?.isCompleted == false)
    }

    // MARK: - Nil Optionals

    @Test("Nil optional fields round-trip as nil")
    func nilOptionalsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let todo = TodoCard(
            title: "Minimal",
            dueDate: nil,
            priority: nil,
            isCompleted: false,
            completedAt: nil
        )

        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loaded = service2.todoCards[0]
        #expect(loaded.dueDate == nil)
        #expect(loaded.priority == nil)
        #expect(loaded.completedAt == nil)
        #expect(loaded.isCompleted == false)
        #expect(loaded.checklist.isEmpty)
        #expect(loaded.labelIDs.isEmpty)
        #expect(loaded.linkedEntities.isEmpty)
    }

    // MARK: - Update

    @Test("Updating an existing todo replaces its data")
    func updateTodo() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var todo = TodoCard(title: "Original", details: "Original details")
        service.persistTodoToDatabase(db, todo: todo)

        todo.title = "Updated"
        todo.details = "New details"
        todo.priority = .medium
        todo.isCompleted = true
        todo.completedAt = Date()
        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards.count == 1)
        let loaded = service2.todoCards[0]
        #expect(loaded.title == "Updated")
        #expect(loaded.details == "New details")
        #expect(loaded.priority == .medium)
        #expect(loaded.isCompleted == true)
    }

    // MARK: - Delete

    @Test("Delete todo removes items + CASCADE cleans join tables")
    func deleteTodo() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "X")

        let service = makeService(db)

        // A second todo that the first one links to.
        let targetTodo = TodoCard(title: "Target")
        service.persistTodoToDatabase(db, todo: targetTodo)

        let todo = TodoCard(
            title: "Doomed",
            labelIDs: [label.id],
            linkedEntities: [LibraryEntityRef(type: .todo, entityID: targetTodo.id)]
        )
        service.persistTodoToDatabase(db, todo: todo)

        service.deleteTodoFromDatabase(db, todoID: todo.id)

        // Items row gone
        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)
        #expect(service2.todoCards.contains(where: { $0.id == todo.id }) == false)
        #expect(service2.todoCards.contains(where: { $0.id == targetTodo.id }) == true)

        // Join tables cleaned via CASCADE
        let labelsStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelsStmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try labelsStmt.step()
        #expect(labelsStmt.int(at: 0) == 0)

        let linksStmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        linksStmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try linksStmt.step()
        #expect(linksStmt.int(at: 0) == 0)

        // Detail row gone
        let todoStmt = try db.prepare("SELECT count(*) FROM todos WHERE item_id = ?;")
        todoStmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try todoStmt.step()
        #expect(todoStmt.int(at: 0) == 0)
    }

    // MARK: - Multiple Todos

    @Test("Multiple todos persist and load correctly")
    func multipleTodos() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let t1 = TodoCard(title: "One")
        let t2 = TodoCard(title: "Two")
        let t3 = TodoCard(title: "Three")

        service.persistTodoToDatabase(db, todo: t1)
        service.persistTodoToDatabase(db, todo: t2)
        service.persistTodoToDatabase(db, todo: t3)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards.count == 3)
        let titles = Set(service2.todoCards.map(\.title))
        #expect(titles == Set(["One", "Two", "Three"]))
    }

    // MARK: - Labels

    @Test("Label IDs round-trip through item_labels and updates replace old assignments")
    func labelIDsRoundTripAndUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let l1 = labelStorage.createLabel(name: "L1")
        let l2 = labelStorage.createLabel(name: "L2")
        let l3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)
        var todo = TodoCard(title: "Labeled", labelIDs: [l1.id, l2.id])
        service.persistTodoToDatabase(db, todo: todo)

        let loaded1 = makeService(db)
        loaded1.loadTodosFromDatabase(db)
        #expect(Set(loaded1.todoCards[0].labelIDs) == Set([l1.id, l2.id]))

        // Update labels
        todo.labelIDs = [l2.id, l3.id]
        service.persistTodoToDatabase(db, todo: todo)

        let loaded2 = makeService(db)
        loaded2.loadTodosFromDatabase(db)
        #expect(Set(loaded2.todoCards[0].labelIDs) == Set([l2.id, l3.id]))
    }

    // MARK: - Folder

    @Test("Todo with folder ID round-trips")
    func todoWithFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Work")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)
        let todo = TodoCard(title: "In Folder", folderID: folder.id)
        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards[0].folderID == folder.id)
    }

    // MARK: - Empty DB

    @Test("Empty database loads empty todos array")
    func emptyDatabase() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadTodosFromDatabase(db)

        #expect(service.todoCards.isEmpty)
    }

    // MARK: - Date Precision

    @Test("Date fields survive round-trip with reasonable precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let now = Date()
        let todo = TodoCard(
            title: "Timed",
            dueDate: now,
            completedAt: now,
            createdAt: now,
            updatedAt: now
        )
        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loaded = service2.todoCards[0]
        #expect(abs(loaded.createdAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(now)) < 0.001)
        #expect(abs((loaded.dueDate ?? .distantPast).timeIntervalSince(now)) < 0.001)
        #expect(abs((loaded.completedAt ?? .distantPast).timeIntervalSince(now)) < 0.001)
    }

    // MARK: - Checklist with Subtasks

    @Test("Checklist with nested subtasks round-trips through JSON blob")
    func checklistWithSubtasks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let checklist = [
            TodoChecklistItem(
                title: "Plan trip",
                sortOrder: 0,
                subtasks: [
                    TodoSubtask(title: "Book flights"),
                    TodoSubtask(title: "Book hotel", isCompleted: true, completedAt: Date()),
                    TodoSubtask(title: "Rent car")
                ]
            ),
            TodoChecklistItem(
                title: "Pack",
                sortOrder: 1,
                subtasks: []
            )
        ]
        let todo = TodoCard(title: "Vacation", checklist: checklist)
        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loaded = service2.todoCards[0]
        #expect(loaded.checklist.count == 2)
        let plan = loaded.checklist.first { $0.title == "Plan trip" }
        #expect(plan?.subtasks.count == 3)
        #expect(plan?.subtasks.first { $0.title == "Book hotel" }?.isCompleted == true)
        #expect(plan?.subtasks.first { $0.title == "Book flights" }?.isCompleted == false)
    }

    // MARK: - linkedEntities

    @Test("linkedEntities round-trip through item_links when targets exist")
    func linkedEntitiesRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Persist target first so FK is satisfied.
        let target = TodoCard(title: "Target")
        service.persistTodoToDatabase(db, todo: target)

        let source = TodoCard(
            title: "Source",
            linkedEntities: [LibraryEntityRef(type: .todo, entityID: target.id)]
        )
        service.persistTodoToDatabase(db, todo: source)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loadedSource = service2.todoCards.first { $0.id == source.id }
        #expect(loadedSource != nil)
        #expect(loadedSource?.linkedEntities.count == 1)
        #expect(loadedSource?.linkedEntities.first?.entityID == target.id)
        #expect(loadedSource?.linkedEntities.first?.type == .todo)
    }

    @Test("linkedEntities to non-existent target are silently dropped")
    func linkedEntitiesDroppedWhenMissingTarget() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let fakeTarget = UUID()
        let todo = TodoCard(
            title: "Has dangling link",
            linkedEntities: [LibraryEntityRef(type: .todo, entityID: fakeTarget)]
        )

        // Must not throw / not produce FK error.
        service.persistTodoToDatabase(db, todo: todo)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loaded = service2.todoCards[0]
        #expect(loaded.linkedEntities.isEmpty)

        // Verify zero rows in item_links
        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    @Test("linkedEntities to non-migrated types are silently filtered")
    func linkedEntitiesNonMigratedTypesFiltered() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let todo = TodoCard(
            title: "Has session link",
            linkedEntities: [
                LibraryEntityRef(type: .session, entityID: UUID()),
                LibraryEntityRef(type: .externalFile, entityID: UUID())
            ]
        )

        service.persistTodoToDatabase(db, todo: todo)

        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)
        #expect(service2.todoCards[0].linkedEntities.isEmpty)
    }

    // MARK: - Filename / relative_path round-trip

    @Test("Uniquified filename round-trips through items.relative_path")
    func uniquifiedFilenameRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Simulate the real creation path producing a collision-suffixed filename.
        let todo = TodoCard(title: "Buy groceries")
        service._setIndexEntryForTesting(todoID: todo.id, filename: "Buy groceries (2).ics")

        service.persistTodoToDatabase(db, todo: todo)

        // Verify relative_path was persisted to the items table.
        let stmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(todo.id), at: 1)
        try stmt.step()
        let relPath = stmt.optionalString(at: 0)
        #expect(relPath == "Inbox/Todos/Buy groceries (2).ics")

        // Reload in a fresh service and verify the filename is recovered EXACTLY —
        // not the sanitized guess "Buy groceries.ics" that would orphan the real file.
        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        #expect(service2.todoCards.count == 1)
        let recovered = service2._indexFilenameForTesting(todoID: todo.id)
        #expect(recovered == "Buy groceries (2).ics")
    }

@Test("Updating linkedEntities replaces old link rows")
    func linkedEntitiesUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let a = TodoCard(title: "A")
        let b = TodoCard(title: "B")
        service.persistTodoToDatabase(db, todo: a)
        service.persistTodoToDatabase(db, todo: b)

        var source = TodoCard(
            title: "Source",
            linkedEntities: [LibraryEntityRef(type: .todo, entityID: a.id)]
        )
        service.persistTodoToDatabase(db, todo: source)

        // Replace link target
        source.linkedEntities = [LibraryEntityRef(type: .todo, entityID: b.id)]
        service.persistTodoToDatabase(db, todo: source)

        let service2 = makeService(db)
        service2.loadTodosFromDatabase(db)

        let loaded = service2.todoCards.first { $0.id == source.id }
        #expect(loaded?.linkedEntities.count == 1)
        #expect(loaded?.linkedEntities.first?.entityID == b.id)
    }
}
