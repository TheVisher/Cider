import Foundation
import Testing
@testable import Cider

/// Tests for `VaultReconciler`, the startup coordinator that reconciles the
/// SQLite database with the vault filesystem.
///
/// The reconciler is a thin delegator — it mostly triggers each service's
/// existing rescan logic. These tests verify the entry point behaves correctly
/// in isolation; per-service scan semantics are covered by the individual
/// service test suites.
///
/// Note: The reconciler touches `CiderDatabase.shared` and service singletons,
/// so this suite is serialized and integration coverage redirects storage to a
/// temporary vault/database before calling the real startup entry point.
@Suite("VaultReconciler Tests", .serialized)
@MainActor
struct VaultReconcilerTests {

    @Test("reconcile() is a no-op when CiderDatabase.shared is not open")
    func reconcileNoOpWhenClosed() {
        // The shared DB should not be open in the test process (tests use
        // injected CiderDatabase instances, not the shared singleton).
        #expect(CiderDatabase.shared.isOpen == false)

        // Should return without throwing and without side effects.
        VaultReconciler.reconcile()

        // Still closed afterwards.
        #expect(CiderDatabase.shared.isOpen == false)
    }

    @Test("reconcile() is idempotent — multiple calls produce no errors")
    func reconcileIdempotent() {
        #expect(CiderDatabase.shared.isOpen == false)

        // Calling reconcile() multiple times in the DB-closed state must be
        // safe and must not change shared state.
        VaultReconciler.reconcile()
        VaultReconciler.reconcile()
        VaultReconciler.reconcile()

        #expect(CiderDatabase.shared.isOpen == false)
    }

    /// Smoke test for the Task 12 bug fix: `NotesStorage.rescan()` must exist
    /// as a public entry point so VaultReconciler can force a filesystem
    /// rescan on startup (init alone short-circuits on any non-empty DB load).
    ///
    /// This test only verifies the method is callable and returns without
    /// crashing — full round-trip coverage lives in manual/integration tests
    /// because `NotesStorage.rescan()` scans the real vault directory.
    @Test("NotesStorage.rescan() is callable without crashing")
    func notesStorageRescanIsCallable() {
        // Touches the shared singleton (tests do not open CiderDatabase.shared
        // so the DB-less fallback path is exercised).
        #expect(CiderDatabase.shared.isOpen == false)
        NotesStorage.shared.rescan()
        NotesStorage.shared.rescan() // idempotent
    }

    @Test("Startup reconcile scans temp vault through shared database")
    func startupReconcileScansTempVaultThroughSharedDatabase() throws {
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent(
            "cider-startup-reconcile-\(UUID().uuidString)",
            isDirectory: true
        )
        let dbURL = vault
            .appendingPathComponent(".cider", isDirectory: true)
            .appendingPathComponent("cider.db")
        let previousOverride = StoragePaths.vaultOverride

        if CiderDatabase.shared.isOpen {
            CiderDatabase.shared.close()
        }
        defer {
            CiderDatabase.shared.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            VaultFileService.shared._resetIDMapForTesting()
            VaultFileService.shared._setFilesForTesting([])
            try? fm.removeItem(at: vault)
        }

        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CiderDatabase.shared.open(at: dbURL)
        NotesStorage.shared.updateDirectory(to: StoragePaths.directoryURL(for: .notes).path)
        VaultFileService.shared._resetIDMapForTesting()

        let bookmarksDir = StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks)
        let todosDir = StoragePaths.cachedInboxSubdirectoryURL(for: .todos)
        let eventsDir = StoragePaths.cachedInboxSubdirectoryURL(for: .dateCards)
        let contactsDir = StoragePaths.cachedInboxSubdirectoryURL(for: .contacts)
        let notesDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        for dir in [bookmarksDir, todosDir, eventsDir, contactsDir, notesDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let movedBookmark = Bookmark(
            title: "Moved Startup Bookmark",
            urlString: "https://example.com/moved-startup",
            relativePath: "Inbox/Bookmarks/Missing Startup Bookmark.webloc"
        )
        VaultBookmarkService.shared.persistBookmarkToDatabase(CiderDatabase.shared, bookmark: movedBookmark)
        _ = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                id: movedBookmark.id,
                title: "Moved Startup Bookmark",
                urlString: movedBookmark.urlString
            ),
            toDirectory: bookmarksDir,
            dirRelativePath: "Inbox/Bookmarks"
        )

        let duplicateBookmark = Bookmark(
            title: "Canonical Startup Bookmark",
            urlString: "https://example.com/duplicate-startup",
            relativePath: "Inbox/Bookmarks/Canonical Startup Bookmark.webloc"
        )
        VaultBookmarkService.shared.persistBookmarkToDatabase(CiderDatabase.shared, bookmark: duplicateBookmark)
        _ = try BookmarkFileService.shared.write(
            bookmark: duplicateBookmark,
            toDirectory: bookmarksDir,
            dirRelativePath: "Inbox/Bookmarks"
        )
        _ = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Example.Com (2)",
                urlString: "https://example.com/duplicate-startup?utm_source=test#frag"
            ),
            toDirectory: bookmarksDir,
            dirRelativePath: "Inbox/Bookmarks"
        )

        let prunedBookmark = Bookmark(
            title: "Missing Startup Bookmark",
            urlString: "https://example.com/pruned-startup",
            relativePath: "Inbox/Bookmarks/Definitely Missing Startup Bookmark.webloc"
        )
        VaultBookmarkService.shared.persistBookmarkToDatabase(CiderDatabase.shared, bookmark: prunedBookmark)
        VaultBookmarkService.shared.loadBookmarksFromDatabase(CiderDatabase.shared)
        VaultBookmarkService.shared._resetAdoptionDebounceForTesting()

        let todo = TodoCard(title: "Startup Orphan Todo", details: "adopt me")
        #expect(TodoCardStorage.shared.writeICSFile(
            for: todo,
            to: todosDir.appendingPathComponent("Startup Orphan Todo.ics")
        ))
        let event = DateCard(title: "Startup Orphan Event", startAt: Date(timeIntervalSince1970: 1_820_000_000))
        #expect(DateCardStorage.shared.writeICSFile(
            for: event,
            to: eventsDir.appendingPathComponent("Startup Orphan Event.ics")
        ))
        let contact = ContactCard(displayName: "Startup Orphan Contact", email: "startup@example.com")
        #expect(ContactStorage.shared.writeVCardFile(
            for: contact,
            to: contactsDir.appendingPathComponent("Startup Orphan Contact.vcf")
        ))

        try "# Startup dropped note\nGeneric markdown dropped while closed."
            .write(to: notesDir.appendingPathComponent("Startup Dropped Note.md"), atomically: true, encoding: .utf8)
        let projectQA = vault.appendingPathComponent("Projects/Cider/QA/Startup Harness QA.md")
        try fm.createDirectory(at: projectQA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Startup Harness QA\nProject artifact must survive reconcile."
            .write(to: projectQA, atomically: true, encoding: .utf8)

        let nativeMarkdownID = UUID()
        let nativeMarkdownPath = "Research/Native Vault File.md"
        let nativeMarkdownURL = vault.appendingPathComponent(nativeMarkdownPath)
        try fm.createDirectory(at: nativeMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Native Vault File\nThis markdown is explicitly owned as a vault file."
            .write(to: nativeMarkdownURL, atomically: true, encoding: .utf8)
        VaultFileStorage.shared.persistVaultFileToDatabase(
            CiderDatabase.shared,
            file: VaultFile(
                id: nativeMarkdownID,
                filename: nativeMarkdownURL.lastPathComponent,
                relativePath: nativeMarkdownPath,
                fileType: .unknown,
                fileSize: Int64((try? Data(contentsOf: nativeMarkdownURL).count) ?? 0),
                createdAt: Date(timeIntervalSince1970: 1_820_000_100),
                modifiedAt: Date(timeIntervalSince1970: 1_820_000_100),
                folderID: nil,
                title: "Native Vault File"
            )
        )
        let staleVaultFileID = UUID()
        VaultFileStorage.shared.persistVaultFileToDatabase(
            CiderDatabase.shared,
            file: VaultFile(
                id: staleVaultFileID,
                filename: "Missing Startup.pdf",
                relativePath: "Research/Missing Startup.pdf",
                fileType: .pdf,
                fileSize: 1,
                createdAt: Date(timeIntervalSince1970: 1_820_000_200),
                modifiedAt: Date(timeIntervalSince1970: 1_820_000_200),
                folderID: nil
            )
        )
        VaultFileService.shared._setIDMapEntryForTesting(path: nativeMarkdownPath, id: nativeMarkdownID)
        VaultFileService.shared._setIDMapEntryForTesting(path: "Research/Missing Startup.pdf", id: staleVaultFileID)

        VaultReconciler.reconcile()

        #expect(try itemCount(type: "bookmark") == 4)
        #expect(try itemCount(type: "todo") == 1)
        #expect(try itemCount(type: "event") == 1)
        #expect(try itemCount(type: "contact") == 1)
        #expect(try itemCount(type: "note") == 2)
        #expect(try itemCount(type: "vaultFile") == 1)

        let bookmarkPaths = try itemRelativePaths(type: "bookmark")
        #expect(bookmarkPaths.contains("Inbox/Bookmarks/Moved Startup Bookmark.webloc"))
        #expect(bookmarkPaths.contains("Inbox/Bookmarks/Canonical Startup Bookmark.webloc"))
        #expect(bookmarkPaths.contains("Inbox/Bookmarks/Example.Com (2).webloc"))
        #expect(bookmarkPaths.contains("Inbox/Bookmarks/Definitely Missing Startup Bookmark.webloc"))
        #expect(fm.fileExists(atPath: bookmarksDir.appendingPathComponent("Example.Com (2).webloc").path))

        let notePaths = try itemRelativePaths(type: "note")
        #expect(notePaths.contains("Inbox/Notes/Startup Dropped Note.md"))
        #expect(notePaths.contains("Projects/Cider/QA/Startup Harness QA.md"))
        let vaultFilePaths = try itemRelativePaths(type: "vaultFile")
        #expect(vaultFilePaths.contains(nativeMarkdownPath))
        #expect(!vaultFilePaths.contains("Research/Missing Startup.pdf"))
        #expect(VaultFileService.shared._idMapEntryForTesting(path: nativeMarkdownPath) == nativeMarkdownID)
        #expect(VaultFileService.shared._idMapEntryForTesting(path: "Research/Missing Startup.pdf") == nil)

        let auditEntries = MutationAuditService(database: CiderDatabase.shared).loadEntries()
        #expect(auditEntries.contains { $0.action == "scanner.vaultFile.prune_missing_file" && $0.itemID == staleVaultFileID })
        #expect(auditEntries.contains { $0.action == "scanner.todo.adopt" && $0.itemID == todo.id })
        #expect(auditEntries.contains { $0.action == "scanner.dateCard.adopt" && $0.itemID == event.id })
        #expect(auditEntries.contains { $0.action == "scanner.contact.adopt" && $0.itemID == contact.id })

        let duplicates = VaultDuplicateAuditor.findDuplicateBookmarks(VaultBookmarkService.shared.bookmarks)
        let hasDuplicateBookmarkFinding = duplicates.contains(where: { finding in
            guard finding.kind == .canonicalURL else { return false }
            let paths = Set(finding.items.compactMap(\.path))
            return paths.contains("Inbox/Bookmarks/Canonical Startup Bookmark.webloc")
                && paths.contains("Inbox/Bookmarks/Example.Com (2).webloc")
        })
        #expect(hasDuplicateBookmarkFinding)
    }

    private func itemCount(type: String) throws -> Int {
        let stmt = try CiderDatabase.shared.prepare("SELECT COUNT(*) FROM items WHERE type = ?;")
        stmt.bind(type, at: 1)
        try stmt.step()
        return stmt.int(at: 0)
    }

    private func itemRelativePaths(type: String) throws -> [String] {
        let stmt = try CiderDatabase.shared.prepare("""
            SELECT relative_path FROM items
            WHERE type = ?
            ORDER BY relative_path;
            """)
        stmt.bind(type, at: 1)
        var paths: [String] = []
        while try stmt.step() {
            if let path = stmt.optionalString(at: 0) {
                paths.append(path)
            }
        }
        return paths
    }
}
