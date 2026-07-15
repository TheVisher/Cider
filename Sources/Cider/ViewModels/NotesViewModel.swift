import SwiftUI
import Combine
import WebKit
import AppKit
import os

private let logger = Logger(subsystem: "com.cider.app", category: "NotesViewModel")

struct EditorFormatState: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var highlight = false
    var highlightColor: String? = nil
    var code = false
    var link = false
    var bulletList = false
    var orderedList = false
    var taskList = false
    var blockquote = false
    var codeBlock = false
    var inTable = false
    var heading: Int = 0       // 0=paragraph, 1=H1, 2=H2, 3=H3
    var textAlign: String = "left"
}

struct NotesExternalChangeState: Equatable {
    let modifiedAt: Date
}

struct NotesEditorImageTransactionSnapshot: Equatable {
    let editorMarkdown: String
    let persistedDiskContent: String
    let selectedNote: Note
    let editingContent: String
    let charCount: Int
    let lastSyncedDiskContent: String
    let lastLoadedEditorNormalizedContent: String?
    let pendingExternalDiskContent: String?
    let ignoredExternalDiskContent: String?
    let externalChangeState: NotesExternalChangeState?
    let hasPendingSave: Bool
    let isLoadingNote: Bool
    let hadScheduledSave: Bool
    let lastRichEditorPushedMarkdown: String?

    func replacing(
        editorMarkdown: String? = nil,
        persistedDiskContent: String? = nil,
        selectedNote: Note? = nil,
        editingContent: String? = nil,
        charCount: Int? = nil,
        lastSyncedDiskContent: String? = nil,
        lastLoadedEditorNormalizedContent: String?? = nil,
        pendingExternalDiskContent: String?? = nil,
        ignoredExternalDiskContent: String?? = nil,
        externalChangeState: NotesExternalChangeState?? = nil,
        hasPendingSave: Bool? = nil,
        isLoadingNote: Bool? = nil,
        hadScheduledSave: Bool? = nil,
        lastRichEditorPushedMarkdown: String?? = nil
    ) -> Self {
        .init(
            editorMarkdown: editorMarkdown ?? self.editorMarkdown,
            persistedDiskContent: persistedDiskContent ?? self.persistedDiskContent,
            selectedNote: selectedNote ?? self.selectedNote,
            editingContent: editingContent ?? self.editingContent,
            charCount: charCount ?? self.charCount,
            lastSyncedDiskContent: lastSyncedDiskContent ?? self.lastSyncedDiskContent,
            lastLoadedEditorNormalizedContent: lastLoadedEditorNormalizedContent ?? self.lastLoadedEditorNormalizedContent,
            pendingExternalDiskContent: pendingExternalDiskContent ?? self.pendingExternalDiskContent,
            ignoredExternalDiskContent: ignoredExternalDiskContent ?? self.ignoredExternalDiskContent,
            externalChangeState: externalChangeState ?? self.externalChangeState,
            hasPendingSave: hasPendingSave ?? self.hasPendingSave,
            isLoadingNote: isLoadingNote ?? self.isLoadingNote,
            hadScheduledSave: hadScheduledSave ?? self.hadScheduledSave,
            lastRichEditorPushedMarkdown: lastRichEditorPushedMarkdown ?? self.lastRichEditorPushedMarkdown
        )
    }
}

enum NotesEditorDiskTruthPolicy {
    static func hasUnsavedLocalChanges(
        editingContent: String,
        lastSyncedDiskContent: String,
        lastLoadedEditorNormalizedContent: String?
    ) -> Bool {
        editingContent != lastSyncedDiskContent
            && editingContent != lastLoadedEditorNormalizedContent
    }
}

enum NotesEditorRenderRefreshPlan {
    static let delays: [TimeInterval] = [0, 0.15, 0.35]
}

struct NotesRecoverySnapshotChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let snapshotDate: Date
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var hasPendingSave: Bool = false
    @Published var displayMode: NoteDisplayMode
    @Published var cardSizeScale: Double
    @Published var selectedNote: Note?
    @Published var editingContent: String = ""
    @Published var searchText: String = ""
    @Published var pendingNoteToOpen: UUID?
    @Published var editingTitle: String = ""
    @Published var charCount: Int = 0
    @Published var externalChangeState: NotesExternalChangeState?
    @Published var isFindBarVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var findMatchCount: Int = 0
    @Published var findMatchIndex: Int = 0
    @Published var findFocusToken = UUID()
    @Published private(set) var richDisplayContentOverride: String?
    @Published private(set) var notesEditorTextSize: NotesEditorTextSize
    @Published private(set) var noteEditorMode: NoteEditorMode
    @Published var editorFormatState = EditorFormatState()
    @Published var isMetadataPanelVisible: Bool = false
    @Published private(set) var hasSnapshots: Bool = false

    /// The singleton editor WebView, created on first access via `ensureEditorWebView()`.
    private(set) var editorWebView: WKWebView?
    private var editorCoordinator: TipTapEditorCoordinator?
    private var editorIsReady = false

    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncedDiskContent: String = ""
    /// TipTap's first parse/serialize result may differ from disk without being a
    /// user edit. Keep that editor baseline separate from exact disk truth.
    private var lastLoadedEditorNormalizedContent: String?
    /// True while waiting for TipTap's first `contentChanged` after loading a note.
    /// TipTap normalizes markdown on parse; we absorb that round-trip without writing to disk.
    private var isLoadingNote = false
    private var pendingExternalDiskContent: String?
    private var ignoredExternalDiskContent: String?
    private var lastRichEditorPushedMarkdown: String?
    private let relativeAssetIntake: NotesRelativeAssetIntakeService
    private let imageTransactionCoordinator: NotesEditorImageTransactionCoordinator
    private var imageTransactionIsActive = false
    var richEditorMarkdownForCurrentSelection: String {
        richDisplayContentOverride ?? editingContent
    }
    var notes: [Note] {
        NotesStorage.shared.notes.filter { !$0.isProjectArtifact }
    }

    @discardableResult
    func assignNote(_ note: Note, toFolder folderID: UUID?) -> Bool {
        let oldFolderID = note.folderID
        do {
            let result = try CiderItemMutationService(database: .shared).move(
                ref: LibraryEntityRef(type: .note, entityID: note.id),
                toFolder: folderID,
                actor: "ui",
                source: "ui.notes.assign",
                reason: "Moved from note UI."
            )
            guard result.ok else { return false }
            let folderName = VaultFolderService.shared.folder(for: folderID ?? UUID())?.name ?? "Unfiled"
            CiderUndoManager.shared.record(.movedToFolder(
                itemType: .note,
                itemID: note.id,
                title: note.title,
                fromFolderID: oldFolderID,
                toFolderID: folderID,
                folderName: folderName
            ))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func toggleNotePinned(_ note: Note) -> Bool {
        NotesStorage.shared.togglePin(note.id)
    }

    var filteredNotes: [Note] {
        guard !searchText.isEmpty else {
            return notes.filter { !$0.isDailyJournalNote }
        }
        let query = searchText.lowercased()
        // Filter by title only — content search requires disk I/O (loadContent reads from disk)
        // which must not run synchronously on @MainActor in a frequently-rendered computed
        // property. Full-text search across note content is handled by LibraryViewModel
        // (which caches reads) in the library/search tab.
        return notes.filter {
            $0.title.lowercased().contains(query)
        }
    }

    var recoverySnapshotChoices: [NotesRecoverySnapshotChoice] {
        guard let note = selectedNote else { return [] }
        let snapshots = NotesStorage.shared.snapshots(for: note)
        guard !snapshots.isEmpty else { return [] }

        let now = Date()
        let targetAges: [(TimeInterval, String)] = [
            (5 * 60, "5 min"),
            (15 * 60, "15 min"),
            (30 * 60, "30 min"),
            (60 * 60, "1 hour"),
            (24 * 60 * 60, "24 hours"),
        ]

        var choices: [NotesRecoverySnapshotChoice] = []
        var usedSnapshotIDs = Set<String>()

        func appendChoice(from snapshot: NoteSnapshotInfo, title: String) {
            guard usedSnapshotIDs.insert(snapshot.id).inserted else { return }
            choices.append(
                NotesRecoverySnapshotChoice(
                    id: snapshot.id,
                    title: title,
                    snapshotDate: snapshot.modifiedAt
                )
            )
        }

        if let latest = snapshots.first {
            appendChoice(from: latest, title: "Latest")
        }

        for (age, title) in targetAges {
            let cutoff = now.addingTimeInterval(-age)
            if let match = snapshots.first(where: { $0.modifiedAt <= cutoff }) {
                appendChoice(from: match, title: title)
            }
        }

        return choices
    }

    var allRecoverySnapshotChoices: [NotesRecoverySnapshotChoice] {
        guard let note = selectedNote else { return [] }
        return NotesStorage.shared.snapshots(for: note).map { snapshot in
            NotesRecoverySnapshotChoice(
                id: snapshot.id,
                title: snapshot.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                snapshotDate: snapshot.modifiedAt
            )
        }
    }

    init(
        relativeAssetIntake: NotesRelativeAssetIntakeService = NotesRelativeAssetIntakeService(),
        imageTransactionCoordinator: NotesEditorImageTransactionCoordinator = NotesEditorImageTransactionCoordinator()
    ) {
        self.relativeAssetIntake = relativeAssetIntake
        self.imageTransactionCoordinator = imageTransactionCoordinator
        let config = CiderConfig.load()
        self.displayMode = config.notesDefaultViewMode
        self.cardSizeScale = config.notesCardSizeScale ?? 1.0
        self.notesEditorTextSize = config.notesEditorTextSize
        self.noteEditorMode = config.noteEditorMode

        // Observe storage changes
        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileSelectedNote()
                self.detectExternalChangeIfNeeded()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let config = CiderConfig.load()
                let newMode = config.notesDefaultViewMode
                let newScale = config.notesCardSizeScale ?? 1.0
                if self.displayMode != newMode { self.displayMode = newMode }
                if self.cardSizeScale != newScale { self.cardSizeScale = newScale }
                if self.noteEditorMode != config.noteEditorMode {
                    self.noteEditorMode = config.noteEditorMode
                }
                if self.notesEditorTextSize != config.notesEditorTextSize {
                    self.notesEditorTextSize = config.notesEditorTextSize
                    self.applyNotesEditorTextSize()
                }
            }
            .store(in: &cancellables)

        // Cache snapshot availability so toolbar .disabled() doesn't hit disk on every render
        $selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let note {
                    self.hasSnapshots = !NotesStorage.shared.snapshots(for: note).isEmpty
                } else {
                    self.hasSnapshots = false
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - WebView Lifecycle

    /// Creates the singleton WKWebView on first access. Subsequent calls return
    /// the same instance. The WebView is owned by this ViewModel and outlives
    /// any individual TipTapEditorView mount.
    @discardableResult
    func ensureEditorWebView() -> WKWebView {
        if let existing = editorWebView {
            return existing
        }

        let coordinator = TipTapEditorCoordinator(viewModel: self)
        editorCoordinator = coordinator

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CiderVaultSchemeHandler(), forURLScheme: "cider-vault")
        let contentController = config.userContentController
        contentController.add(coordinator, name: "contentChanged")
        contentController.add(coordinator, name: "editorReady")
        contentController.add(coordinator, name: "imageDropped")
        contentController.add(coordinator, name: "slashCommandImage")
        contentController.add(coordinator, name: "slashPopupState")
        contentController.add(coordinator, name: "editorFormatState")
        contentController.add(coordinator, name: "editorError")
        contentController.add(coordinator, name: "editorRequestClose")
        contentController.add(coordinator, name: "linkClicked")

        let webView = TipTapWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.viewModel = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.onFindRequested = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFindShortcut()
            }
        }

        if let resourceURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "TipTapEditor") {
            // Grant read access to the TipTapEditor bundle directory (for JS/CSS).
            // Vault images are served via the cider-vault:// custom URL scheme instead,
            // which avoids the constraint that allowingReadAccessTo must cover both
            // the app bundle and the vault simultaneously.
            let readAccessRoot = resourceURL.deletingLastPathComponent()
            webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessRoot)
        }

        editorWebView = webView
        return webView
    }

    /// Called when a .md/.txt file is dropped onto the editor. Reads the content
    /// with correct UTF-8 encoding (bypassing WKWebView's DOM drop handler which
    /// may interpret files as Latin-1).
    func handleDroppedTextFileContent(_ content: String, provenance: NoteEditorImportProvenance) {
        if let note = selectedNote {
            recordEditorImportAudit(
                action: "editor_import_text",
                note: note,
                provenance: provenance,
                extraMetadata: [
                    "importedCharacterCount": String(content.count),
                    "previousCharacterCount": String(editingContent.count),
                ]
            )
        }
        pushContentToEditor(content)
    }

    func handleDroppedTextFile(at url: URL, provenance: NoteEditorImportProvenance) {
        guard selectedNote != nil, externalChangeState == nil else { return }
        do {
            let imported = try relativeAssetIntake.loadLocalText(at: url)
            handleDroppedTextFileContent(imported.content, provenance: provenance)
        } catch let error as NotesRelativeAssetIntakeError {
            logger.error("Note text import failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            logger.error("Note text import failed.")
        }
    }

    // MARK: - Editor Bridge

    /// Called when the TipTap editor signals it is ready.
    func editorDidBecomeReady() {
        editorIsReady = true
        hasPendingSave = false
        applyNotesEditorTextSize()

        // If a note is already selected, push its content to the editor
        if let note = selectedNote {
            let content = loadPersistedContent(for: note)
            editingContent = content
            lastSyncedDiskContent = content
            lastLoadedEditorNormalizedContent = nil
            isLoadingNote = true
            pushContentToEditor(richEditorMarkdownForCurrentSelection)
            if isFindBarVisible, !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateFindQuery(findQuery)
            }
        }
    }

    /// Push markdown content to the TipTap editor via JS.
    private func pushContentToEditor(_ markdown: String, force: Bool = false) {
        guard editorIsReady, let webView = editorWebView else {
            logger.warning("pushContentToEditor: editor not ready or webView nil")
            return
        }
        if !force, lastRichEditorPushedMarkdown == markdown {
            reapplyFindQueryAfterEditorContentLoad()
            return
        }
        let editorMarkdown: String
        if let note = selectedNote {
            editorMarkdown = NotesStorage.shared.markdownForEditor(markdown, note: note)
        } else {
            editorMarkdown = NotesStorage.shared.markdownForEditor(markdown)
        }
        // Use JSON encoding for safe string transport — handles all special
        // characters (newlines, quotes, backslashes, unicode) correctly.
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: editorMarkdown, options: .fragmentsAllowed
        ), let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("pushContentToEditor: JSON encoding failed")
            return
        }
        lastRichEditorPushedMarkdown = markdown
        webView.evaluateJavaScript("window.editorAPI.setContent(\(jsonString))") { [weak self] _, error in
            if let error {
                logger.error("pushContentToEditor JS failed: \(error.localizedDescription)")
                return
            }
            Task { @MainActor [weak self] in
                self?.reapplyFindQueryAfterEditorContentLoad()
            }
        }
    }

    func pushCurrentContentToEditorIfReady() {
        guard selectedNote != nil else { return }
        pushContentToEditor(richEditorMarkdownForCurrentSelection)
    }

    func setRichDisplayContentOverride(_ content: String?) {
        guard richDisplayContentOverride != content else { return }
        richDisplayContentOverride = content
        guard noteEditorMode == .rich else { return }
        isLoadingNote = content != nil
        pushContentToEditor(richEditorMarkdownForCurrentSelection)
    }

    /// Focus the TipTap editor.
    /// In a non-activating NSPanel, JavaScript focus alone isn't enough —
    /// the WKWebView must also become the window's first responder.
    func focusEditor() {
        guard editorIsReady, let webView = editorWebView else { return }
        // Make the WKWebView the first responder at the AppKit level.
        // Delay is required for non-activating panels (see CLAUDE.md).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard let window = webView.window else { return }
            window.makeKey()
            window.makeFirstResponder(webView)
            _ = try? await webView.evaluateJavaScript("window.editorAPI.focus()")
        }
    }

    /// Focus editor unless the find UI is currently active.
    func focusEditorIfFindBarHidden() {
        guard !isFindBarVisible else { return }
        focusEditor()
    }

    // MARK: - Image Handling

    func handleImageDrop(data: Data, filename: String, provenance: NoteEditorImportProvenance) {
        guard let note = selectedNote, externalChangeState == nil else { return }
        let noteDirectory = note.absoluteFileURL.deletingLastPathComponent()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await relativeAssetIntake.importImageData(
                    data,
                    filename: filename,
                    noteID: note.id,
                    noteDirectoryURL: noteDirectory
                ) { [weak self] asset in
                    guard let self, self.selectedNote?.id == note.id, self.externalChangeState == nil else {
                        throw NotesRelativeAssetIntakeError(.payloadFailed)
                    }
                    try await self.insertAndPersistPreparedImage(asset, alt: filename, note: note)
                    self.recordEditorImportAudit(
                        action: "editor_import_image",
                        note: note,
                        provenance: provenance,
                        extraMetadata: [
                            "byteCount": String(asset.metadata.byteSize),
                            "storedFilename": asset.fileURL.lastPathComponent,
                            "storedReference": asset.persistedReference,
                        ]
                    )
                }
            } catch let error as NotesRelativeAssetIntakeError {
                logger.error("Note image import failed: \(error.localizedDescription, privacy: .public)")
            } catch {
                logger.error("Note image import failed.")
            }
        }
    }

    func handleLocalImageImport(at url: URL, provenance: NoteEditorImportProvenance) {
        guard let note = selectedNote, externalChangeState == nil else { return }
        let noteDirectory = note.absoluteFileURL.deletingLastPathComponent()
        let filename = url.lastPathComponent
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await relativeAssetIntake.importLocalImage(
                    at: url,
                    noteID: note.id,
                    noteDirectoryURL: noteDirectory,
                    displayName: filename
                ) { [weak self] asset in
                    guard let self, self.selectedNote?.id == note.id, self.externalChangeState == nil else {
                        throw NotesRelativeAssetIntakeError(.payloadFailed)
                    }
                    try await self.insertAndPersistPreparedImage(asset, alt: filename, note: note)
                    self.recordEditorImportAudit(
                        action: "editor_import_image",
                        note: note,
                        provenance: provenance,
                        extraMetadata: [
                            "byteCount": String(asset.metadata.byteSize),
                            "storedFilename": asset.fileURL.lastPathComponent,
                            "storedReference": asset.persistedReference,
                        ]
                    )
                }
            } catch let error as NotesRelativeAssetIntakeError {
                logger.error("Note image import failed: \(error.localizedDescription, privacy: .public)")
            } catch {
                logger.error("Note image import failed.")
            }
        }
    }

    private func insertPreparedImage(_ asset: NotesRelativeAsset, alt: String) async throws {
        guard let webView = editorWebView else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        let src = asset.editorReference
        guard let srcData = try? JSONSerialization.data(withJSONObject: src, options: .fragmentsAllowed),
              let altData = try? JSONSerialization.data(withJSONObject: alt, options: .fragmentsAllowed),
              let srcJSON = String(data: srcData, encoding: .utf8),
              let altJSON = String(data: altData, encoding: .utf8) else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript("window.editorAPI.insertImage(\(srcJSON), \(altJSON))") { _, error in
                if error != nil {
                    continuation.resume(throwing: NotesRelativeAssetIntakeError(.payloadFailed))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func insertAndPersistPreparedImage(
        _ asset: NotesRelativeAsset,
        alt: String,
        note: Note
    ) async throws {
        try await imageTransactionCoordinator.perform(
            asset: asset,
            alt: alt,
            operations: .init(
                captureSnapshot: { [weak self] in
                    guard let self else { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                    return try await self.captureImageTransactionSnapshot(for: note)
                },
                prepareForMutation: { [weak self] _ in
                    guard let self else { return }
                    self.saveWorkItem?.cancel()
                    self.saveWorkItem = nil
                    self.imageTransactionIsActive = true
                },
                validateCurrentState: { [weak self] snapshot in
                    guard let self else { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                    try self.validateImageTransactionState(snapshot)
                },
                insertImage: { [weak self] asset, alt in
                    guard let self else { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                    try await self.insertPreparedImage(asset, alt: alt)
                },
                capturePostInsertMarkdown: { [weak self] in
                    guard let self else { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                    return try await self.currentEditorMarkdown()
                },
                portableMarkdown: { editorMarkdown, snapshot in
                    let persisted = NotesStorage.shared.markdownForPersistence(
                        editorMarkdown,
                        note: snapshot.selectedNote
                    )
                    let noteDirectory = snapshot.selectedNote.absoluteFileURL.deletingLastPathComponent().path
                    guard !persisted.contains("file://"), !persisted.contains(noteDirectory) else {
                        throw NotesRelativeAssetIntakeError(.payloadFailed)
                    }
                    return persisted
                },
                persist: { [weak self] persisted, snapshot in
                    guard let self else { throw NotesRelativeAssetIntakeError(.payloadFailed) }
                    try self.validateImageTransactionState(snapshot)
                    var current = snapshot.selectedNote
                    current.content = persisted
                    _ = try NotesStorage.shared.persistImageTransaction(
                        note: current,
                        expected: .init(
                            noteID: snapshot.selectedNote.id,
                            fileURL: NotesStorage.shared.noteFileURL(for: snapshot.selectedNote),
                            previousFile: .bytes(Data(snapshot.persistedDiskContent.utf8))
                        )
                    )
                },
                applySuccess: { [weak self] persisted, snapshot in
                    guard let self else { return }
                    var current = NotesStorage.shared.notes.first(where: { $0.id == snapshot.selectedNote.id })
                        ?? snapshot.selectedNote
                    current.content = persisted
                    self.selectedNote = current
                    self.editingContent = persisted
                    self.charCount = persisted.count
                    self.lastSyncedDiskContent = persisted
                    self.lastLoadedEditorNormalizedContent = nil
                    self.pendingExternalDiskContent = nil
                    self.ignoredExternalDiskContent = nil
                    self.externalChangeState = nil
                    self.hasPendingSave = false
                    self.isLoadingNote = false
                    self.saveWorkItem = nil
                    self.imageTransactionIsActive = false
                },
                pushAfterLocalChange: {
                    SyncService.shared.pushAfterLocalChange()
                },
                restoreEditor: { [weak self] markdown, insertCompleted in
                    await self?.restoreExactEditorMarkdown(markdown, undoInsert: insertCompleted)
                },
                restoreState: { [weak self] snapshot in
                    self?.restoreImageTransactionSnapshot(snapshot)
                },
                refreshExternalChangeState: { [weak self] _ in
                    self?.detectExternalChangeIfNeeded()
                }
            )
        )
    }

    private func captureImageTransactionSnapshot(for note: Note) async throws -> NotesEditorImageTransactionSnapshot {
        guard !imageTransactionIsActive,
              !isLoadingNote,
              selectedNote?.id == note.id,
              externalChangeState == nil else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        let editorMarkdown = try await currentEditorMarkdown()
        guard let current = selectedNote,
              current.id == note.id,
              externalChangeState == nil else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        let diskContent = try exactDiskContent(for: current)
        guard diskContent == lastSyncedDiskContent else {
            pendingExternalDiskContent = diskContent
            externalChangeState = NotesExternalChangeState(modifiedAt: current.modifiedAt)
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        return .init(
            editorMarkdown: editorMarkdown,
            persistedDiskContent: diskContent,
            selectedNote: current,
            editingContent: editingContent,
            charCount: charCount,
            lastSyncedDiskContent: lastSyncedDiskContent,
            lastLoadedEditorNormalizedContent: lastLoadedEditorNormalizedContent,
            pendingExternalDiskContent: pendingExternalDiskContent,
            ignoredExternalDiskContent: ignoredExternalDiskContent,
            externalChangeState: externalChangeState,
            hasPendingSave: hasPendingSave,
            isLoadingNote: isLoadingNote,
            hadScheduledSave: saveWorkItem != nil,
            lastRichEditorPushedMarkdown: lastRichEditorPushedMarkdown
        )
    }

    private func validateImageTransactionState(_ snapshot: NotesEditorImageTransactionSnapshot) throws {
        guard imageTransactionIsActive,
              selectedNote?.id == snapshot.selectedNote.id,
              externalChangeState == snapshot.externalChangeState,
              try exactDiskContent(for: snapshot.selectedNote) == snapshot.persistedDiskContent else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
    }

    private func restoreImageTransactionSnapshot(_ snapshot: NotesEditorImageTransactionSnapshot) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        selectedNote = snapshot.selectedNote
        editingContent = snapshot.editingContent
        charCount = snapshot.charCount
        lastSyncedDiskContent = snapshot.lastSyncedDiskContent
        lastLoadedEditorNormalizedContent = snapshot.lastLoadedEditorNormalizedContent
        pendingExternalDiskContent = snapshot.pendingExternalDiskContent
        ignoredExternalDiskContent = snapshot.ignoredExternalDiskContent
        externalChangeState = snapshot.externalChangeState
        hasPendingSave = snapshot.hasPendingSave
        isLoadingNote = snapshot.isLoadingNote
        lastRichEditorPushedMarkdown = snapshot.lastRichEditorPushedMarkdown
        imageTransactionIsActive = false
        if snapshot.hadScheduledSave {
            scheduleRestoredImageTransactionSave(snapshot)
        }
    }

    private func scheduleRestoredImageTransactionSave(_ snapshot: NotesEditorImageTransactionSnapshot) {
        let exactPersistedEditorMarkdown = NotesStorage.shared.markdownForPersistence(
            snapshot.editorMarkdown,
            note: snapshot.selectedNote
        )
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.imageTransactionIsActive,
                      var current = self.selectedNote,
                      current.id == snapshot.selectedNote.id,
                      self.externalChangeState == snapshot.externalChangeState,
                      (try? self.exactDiskContent(for: current)) == snapshot.persistedDiskContent else {
                    self?.detectExternalChangeIfNeeded()
                    return
                }
                current.content = exactPersistedEditorMarkdown
                guard NotesStorage.shared.save(note: current) else {
                    self.hasPendingSave = true
                    return
                }
                self.editingContent = exactPersistedEditorMarkdown
                self.charCount = exactPersistedEditorMarkdown.count
                self.lastSyncedDiskContent = exactPersistedEditorMarkdown
                self.lastLoadedEditorNormalizedContent = nil
                self.pendingExternalDiskContent = nil
                self.ignoredExternalDiskContent = nil
                self.externalChangeState = nil
                self.hasPendingSave = false
                self.saveWorkItem = nil
                SyncService.shared.pushAfterLocalChange()
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func exactDiskContent(for note: Note) throws -> String {
        try String(contentsOf: note.absoluteFileURL, encoding: .utf8)
    }

    private func restoreExactEditorMarkdown(_ markdown: String, undoInsert: Bool) async {
        guard let webView = editorWebView else { return }
        if undoInsert {
            _ = try? await webView.evaluateJavaScript("window.editorAPI.undo()")
        }
        if (try? await currentEditorMarkdown()) == markdown { return }
        guard let data = try? JSONSerialization.data(withJSONObject: markdown, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await webView.evaluateJavaScript("window.editorAPI.setContent(\(json))")
    }

    private func currentEditorMarkdown() async throws -> String {
        guard let webView = editorWebView else {
            throw NotesRelativeAssetIntakeError(.payloadFailed)
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("window.editorAPI.getContent()") { result, error in
                guard error == nil, let markdown = result as? String else {
                    continuation.resume(throwing: NotesRelativeAssetIntakeError(.payloadFailed))
                    return
                }
                continuation.resume(returning: markdown)
            }
        }
    }

    func openImagePicker() {
        guard noteEditorMode == .rich else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleLocalImageImport(at: url, provenance: .imagePicker(url))
    }

    private func recordEditorImportAudit(
        action: String,
        note: Note,
        provenance: NoteEditorImportProvenance,
        extraMetadata: [String: String]
    ) {
        var metadata = provenance.auditMetadata
        extraMetadata.forEach { key, value in metadata[key] = value }
        MutationAuditService.shared.record(
            action: action,
            itemType: "note",
            itemID: note.id,
            before: MutationAuditSnapshots.note(note),
            after: MutationAuditSnapshots.note(note),
            metadata: metadata
        )
    }

    // MARK: - Note Selection

    func selectNote(_ note: Note) {
        selectNote(note, richDisplayContentOverride: nil)
    }

    func selectNote(_ note: Note, richDisplayContentOverride displayContentOverride: String?) {
        // Save current note before switching
        flushSave()
        isLoadingNote = false

        var loaded = note
        loaded.content = loadPersistedContent(for: note)
        selectedNote = loaded
        editingContent = loaded.content
        editingTitle = loaded.title
        charCount = loaded.content.count
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = loaded.content
        lastLoadedEditorNormalizedContent = nil
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false
        isLoadingNote = true
        lastRichEditorPushedMarkdown = nil
        richDisplayContentOverride = displayContentOverride

        pushContentToEditor(richEditorMarkdownForCurrentSelection)
        scheduleEditorRenderRefresh(for: loaded.id)
    }

    private func scheduleEditorRenderRefresh(for noteID: UUID) {
        for delay in NotesEditorRenderRefreshPlan.delays {
            Task { @MainActor [weak self] in
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard let self, self.selectedNote?.id == noteID else { return }
                self.pushCurrentContentToEditorIfReady()
                self.forceEditorDisplayRefresh()
            }
        }
    }

    private func forceEditorDisplayRefresh() {
        guard let webView = editorWebView else { return }
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()
        webView.setNeedsDisplay(webView.bounds)
    }

    // MARK: - CRUD

    func createNewNote() {
        flushSave()
        guard let result = try? CiderCaptureService().addNoteCapture(
            title: nil,
            content: "",
            folderID: nil
        ),
              let note = NotesStorage.shared.notes.first(where: { $0.id == result.item.id })
        else {
            return
        }
        postCaptureToast(result: result, successMessage: "Created note")
        selectedNote = note
        editingContent = ""
        editingTitle = note.title
        charCount = 0
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = ""
        lastLoadedEditorNormalizedContent = nil
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        // Clear editor and focus
        if editorIsReady, let webView = editorWebView {
            webView.evaluateJavaScript("window.editorAPI.clear()")
            // Delay + AppKit first responder needed for non-activating panel
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard let window = webView.window else { return }
                window.makeKey()
                window.makeFirstResponder(webView)
                _ = try? await webView.evaluateJavaScript("window.editorAPI.focus()")
            }
        }
    }

    private func postCaptureToast(result: CiderCaptureResult, successMessage: String) {
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "receipt": UICaptureReceipt(result: result),
                "successMessage": successMessage,
            ]
        )
    }

    func deleteCurrentNote() {
        guard let note = selectedNote else { return }
        deleteNotes([note])
    }

    func deleteNotes(_ notes: [Note]) {
        guard !notes.isEmpty else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil

        let idsToDelete = Set(notes.map(\.id))
        if let selected = selectedNote, idsToDelete.contains(selected.id) {
            clearSelectedNote()
        }

        var trashItems: [TrashItem] = []
        for note in notes {
            let trashItem = NotesStorage.shared.delete(note: note)
            trashItems.append(trashItem)
        }
        if !trashItems.isEmpty {
            CiderUndoManager.shared.record(.bulkDeletedToTrash(trashItems))
        }
    }

    func renameCurrentNote(to newTitle: String) {
        guard let note = selectedNote, !newTitle.isEmpty else { return }
        NotesStorage.shared.rename(note: note, to: newTitle)
        // Refresh selected note
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            selectedNote = updated
            editingTitle = updated.title
        }
    }

    // MARK: - Auto-save

    func contentChanged(_ newContent: String) {
        guard richDisplayContentOverride == nil else {
            isLoadingNote = false
            hasPendingSave = false
            return
        }
        let persistedContent: String
        if let note = selectedNote {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent, note: note)
        } else {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent)
        }
        applyEditedContent(persistedContent)
    }

    func sourceContentChanged(_ newContent: String) {
        if richDisplayContentOverride != nil {
            isLoadingNote = false
        }
        let persistedContent: String
        if let note = selectedNote {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent, note: note)
        } else {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent)
        }
        applyEditedContent(persistedContent)
    }

    private func applyEditedContent(_ persistedContent: String) {
        // The image coordinator reads TipTap directly and owns the only save while
        // an insert is in flight. TipTap's insert callback must not enqueue a second
        // delayed save that can race or overwrite the transaction.
        guard !imageTransactionIsActive else { return }
        if isLoadingNote, richDisplayContentOverride != nil {
            isLoadingNote = false
            hasPendingSave = false
            return
        }

        editingContent = persistedContent
        charCount = persistedContent.count
        hasPendingSave = true

        // Absorb the TipTap normalization round-trip on initial note load.
        // TipTap re-serializes on parse; we update the reference to the normalized
        // content without writing to avoid overwriting disk content (e.g. centered
        // images losing their <p style="text-align: center"> wrapper).
        if isLoadingNote {
            isLoadingNote = false
            lastLoadedEditorNormalizedContent = persistedContent
            hasPendingSave = false
            return
        }

        if persistedContent == lastLoadedEditorNormalizedContent {
            hasPendingSave = false
            return
        }
        lastLoadedEditorNormalizedContent = nil

        guard var note = selectedNote else { return }
        note.content = persistedContent

        // Don't save if content hasn't changed from what we loaded from disk
        guard persistedContent != lastSyncedDiskContent else {
            hasPendingSave = false
            return
        }

        scheduleCurrentContentSave()
    }

    private func scheduleCurrentContentSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, var current = self.selectedNote else { return }
                current.content = self.editingContent
                guard NotesStorage.shared.save(note: current) else {
                    self.hasPendingSave = true
                    return
                }
                self.lastSyncedDiskContent = current.content
                self.lastLoadedEditorNormalizedContent = nil
                self.pendingExternalDiskContent = nil
                self.ignoredExternalDiskContent = nil
                self.externalChangeState = nil
                SyncService.shared.pushAfterLocalChange()
                self.hasPendingSave = false
                self.saveWorkItem = nil
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// Immediately save any pending content by fetching current markdown from editor.
    func flushSave() {
        guard !imageTransactionIsActive else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil

        guard var note = selectedNote else { return }

        // Safety: don't save if the editor never confirmed loading the note.
        // isLoadingNote stays true until the first contentChanged round-trip
        // completes. If JS crashes, this prevents overwriting disk content.
        guard !isLoadingNote else {
            hasPendingSave = false
            return
        }

        // Save the latest known content immediately.
        if editingContent == lastLoadedEditorNormalizedContent, !hasPendingSave {
            return
        }
        note.content = editingContent
        guard NotesStorage.shared.save(note: note) else {
            hasPendingSave = true
            return
        }
        lastSyncedDiskContent = editingContent
        lastLoadedEditorNormalizedContent = nil
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        SyncService.shared.pushAfterLocalChange()
        hasPendingSave = false

        guard richDisplayContentOverride == nil else { return }

        // Then ask the editor for current content to catch any final keystrokes
        // that haven't crossed the JS->Swift bridge yet.
        syncContentFromEditor(noteID: note.id)
    }


    private func syncContentFromEditor(noteID: UUID) {
        guard editorIsReady, let webView = editorWebView else { return }

        webView.evaluateJavaScript("window.editorAPI.getContent()") { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let markdown = result as? String,
                      var current = self.selectedNote,
                      current.id == noteID else { return }

                let persistedMarkdown = NotesStorage.shared.markdownForPersistence(markdown, note: current)
                if persistedMarkdown == self.lastLoadedEditorNormalizedContent {
                    hasPendingSave = false
                    return
                }
                editingContent = persistedMarkdown
                charCount = persistedMarkdown.count
                pendingExternalDiskContent = nil
                ignoredExternalDiskContent = nil
                externalChangeState = nil
                guard persistedMarkdown != self.lastSyncedDiskContent else {
                    hasPendingSave = false
                    return
                }
                current.content = persistedMarkdown
                guard NotesStorage.shared.save(note: current) else {
                    hasPendingSave = true
                    return
                }
                lastSyncedDiskContent = persistedMarkdown
                lastLoadedEditorNormalizedContent = nil
                hasPendingSave = false
            }
        }
    }

    // MARK: - External Change Handling

    func reloadFromDiskAfterExternalChange() {
        guard let selected = selectedNote,
              let pendingExternalDiskContent,
              let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            return
        }

        applyDiskContent(pendingExternalDiskContent, from: updated)
    }

    func keepMineAfterExternalChange() {
        guard let pendingExternalDiskContent,
              var current = selectedNote else {
            return
        }

        current.content = editingContent
        guard NotesStorage.shared.save(note: current) else {
            hasPendingSave = true
            return
        }
        ignoredExternalDiskContent = pendingExternalDiskContent
        self.pendingExternalDiskContent = nil
        externalChangeState = nil
        lastSyncedDiskContent = editingContent
        lastLoadedEditorNormalizedContent = nil
        hasPendingSave = false
    }

    private func detectExternalChangeIfNeeded() {
        guard let selected = selectedNote,
              let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            return
        }

        let diskContent = loadPersistedContent(for: updated)

        if diskContent == lastSyncedDiskContent {
            if pendingExternalDiskContent == diskContent {
                pendingExternalDiskContent = nil
                externalChangeState = nil
            }
            return
        }

        if diskContent == editingContent {
            lastSyncedDiskContent = diskContent
            lastLoadedEditorNormalizedContent = nil
            pendingExternalDiskContent = nil
            ignoredExternalDiskContent = nil
            externalChangeState = nil
            return
        }

        let hasUnsavedLocalChanges = NotesEditorDiskTruthPolicy.hasUnsavedLocalChanges(
            editingContent: editingContent,
            lastSyncedDiskContent: lastSyncedDiskContent,
            lastLoadedEditorNormalizedContent: lastLoadedEditorNormalizedContent
        )
        if hasUnsavedLocalChanges {
            if ignoredExternalDiskContent == diskContent {
                return
            }
            pendingExternalDiskContent = diskContent
            externalChangeState = NotesExternalChangeState(modifiedAt: updated.modifiedAt)
            return
        }

        applyDiskContent(diskContent, from: updated)
    }

    private func applyDiskContent(_ diskContent: String, from note: Note) {
        guard var selected = selectedNote else { return }

        selected.title = note.title
        selected.relativePath = note.relativePath
        selected.modifiedAt = note.modifiedAt
        selected.content = diskContent
        selectedNote = selected

        editingContent = diskContent
        editingTitle = note.title
        charCount = diskContent.count
        lastSyncedDiskContent = diskContent
        lastLoadedEditorNormalizedContent = nil
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        isLoadingNote = true
        pushContentToEditor(diskContent)

        if isFindBarVisible, !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateFindQuery(findQuery)
        }
    }

    private func loadPersistedContent(for note: Note) -> String {
        NotesStorage.shared.loadContent(for: note)
    }

    // MARK: - In-note Find

    func showFindBar() {
        guard selectedNote != nil else { return }
        isFindBarVisible = true
        findFocusToken = UUID()
        if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateFindQuery(findQuery)
        }
    }

    func hideFindBar() {
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        runEditorCommand("findClear")
        focusEditor()
    }

    func updateFindQuery(_ query: String) {
        findQuery = query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetFindResults()
            runEditorCommand("findClear")
            return
        }

        runFindCommand("findSetQuery", stringArgument: query)
    }

    private func reapplyFindQueryAfterEditorContentLoad() {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFindBarVisible, !query.isEmpty else { return }
        runFindCommand("findSetQuery", stringArgument: query)
    }

    func findNextResult() {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runFindCommand("findNext")
    }

    func findPreviousResult() {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runFindCommand("findPrevious")
    }

    func handleFindShortcut() {
        showFindBar()
    }

    // MARK: - Editor Formatting

    func editorUndo() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("undo")
    }

    func editorRedo() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("redo")
    }

    func editorToggleBold() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBold")
    }

    func editorToggleItalic() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleItalic")
    }

    func editorToggleUnderline() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleUnderline")
    }

    func editorSetTextSizeSmall() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "12px")
    }

    func editorSetTextSizeNormal() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "14px")
    }

    func editorSetTextSizeLarge() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "18px")
    }

    func editorSetTextSizeExtraLarge() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "24px")
    }

    func editorResetTextSize() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("unsetFontSize")
    }

    func setNotesEditorTextSize(_ textSize: NotesEditorTextSize) {
        guard notesEditorTextSize != textSize else {
            applyNotesEditorTextSize()
            return
        }

        notesEditorTextSize = textSize

        var config = CiderConfig.load()
        config.notesEditorTextSize = textSize
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)

        applyNotesEditorTextSize()
    }

    func setNoteEditorMode(_ mode: NoteEditorMode) {
        guard noteEditorMode != mode else { return }

        if mode == .source, richDisplayContentOverride == nil, let noteID = selectedNote?.id {
            syncContentFromEditor(noteID: noteID)
        }

        noteEditorMode = mode

        var config = CiderConfig.load()
        config.noteEditorMode = mode
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)

        if mode == .rich {
            isLoadingNote = true
            pushContentToEditor(richEditorMarkdownForCurrentSelection)
            focusEditor()
        }
    }

    func editorAlignLeft() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "left")
    }

    func editorAlignCenter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "center")
    }

    func editorAlignRight() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "right")
    }

    func editorToggleBulletList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBulletList")
    }

    func editorToggleOrderedList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleOrderedList")
    }

    func editorToggleTaskList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleTaskList")
    }

    func editorInsertTable(rows: Int = 3, cols: Int = 3) {
        guard noteEditorMode == .rich else { return }
        guard editorIsReady, let webView = editorWebView else { return }
        webView.evaluateJavaScript("window.editorAPI.insertTable(\(rows), \(cols));")
    }

    func editorAddRowBefore() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addRowBefore")
    }

    func editorAddRowAfter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addRowAfter")
    }

    func editorDeleteRow() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteRow")
    }

    func editorAddColumnBefore() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addColumnBefore")
    }

    func editorAddColumnAfter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addColumnAfter")
    }

    func editorDeleteColumn() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteColumn")
    }

    func editorMergeCells() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("mergeCells")
    }

    func editorSplitCell() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("splitCell")
    }

    func editorToggleHeaderRow() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleHeaderRow")
    }

    func editorToggleHeaderColumn() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleHeaderColumn")
    }

    func editorDeleteTable() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteTable")
    }

    func editorPromptForLink() {
        guard noteEditorMode == .rich else { return }
        guard let rawValue = promptForLinkURL() else { return }
        runEditorCommand("setLink", stringArgument: normalizeLinkURL(rawValue))
    }

    func editorRemoveLink() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("unsetLink")
    }

    func editorToggleStrike() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleStrike")
    }

    func editorToggleBlockquote() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBlockquote")
    }

    func editorInsertHorizontalRule() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setHorizontalRule")
    }

    func editorToggleHighlight(color: String? = nil) {
        guard noteEditorMode == .rich else { return }
        if let color {
            runEditorCommand("toggleHighlight", stringArgument: color)
        } else {
            runEditorCommand("toggleHighlight")
        }
    }

    func editorToggleCode() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleCode")
    }

    func editorIndent() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("indent")
    }

    func editorOutdent() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("outdent")
    }

    func editorClearFormatting() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("clearFormatting")
    }

    func editorSetHeading(_ level: Int) {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setHeading", intArgument: level)
    }

    func editorSetParagraph() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setParagraph")
    }

    func editorToggleCodeBlock() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleCodeBlock")
    }

    func updateEditorFormatState(_ payload: [String: Any]) {
        var state = EditorFormatState()
        state.bold = payload["bold"] as? Bool ?? false
        state.italic = payload["italic"] as? Bool ?? false
        state.underline = payload["underline"] as? Bool ?? false
        state.strike = payload["strike"] as? Bool ?? false
        state.highlight = payload["highlight"] as? Bool ?? false
        state.highlightColor = payload["highlightColor"] as? String
        state.code = payload["code"] as? Bool ?? false
        state.link = payload["link"] as? Bool ?? false
        state.bulletList = payload["bulletList"] as? Bool ?? false
        state.orderedList = payload["orderedList"] as? Bool ?? false
        state.taskList = payload["taskList"] as? Bool ?? false
        state.blockquote = payload["blockquote"] as? Bool ?? false
        state.codeBlock = payload["codeBlock"] as? Bool ?? false
        state.inTable = payload["inTable"] as? Bool ?? false
        state.heading = payload["heading"] as? Int ?? 0
        state.textAlign = payload["textAlign"] as? String ?? "left"
        editorFormatState = state
    }

    @discardableResult
    func restoreMostRecentSnapshot() -> Bool {
        guard let choice = recoverySnapshotChoices.first else { return false }
        return restoreSnapshot(choice)
    }

    @discardableResult
    func restoreSnapshot(_ choice: NotesRecoverySnapshotChoice) -> Bool {
        guard var current = selectedNote else {
            return false
        }

        guard let snapshot = NotesStorage.shared.snapshots(for: current).first(where: { $0.id == choice.id }),
              let snapshotContent = NotesStorage.shared.loadSnapshotContent(at: snapshot.url) else {
            return false
        }

        saveWorkItem?.cancel()
        saveWorkItem = nil

        let persistedContent = NotesStorage.shared.markdownForPersistence(snapshotContent, note: current)
        current.content = persistedContent
        guard NotesStorage.shared.save(note: current, createSnapshot: false) else {
            hasPendingSave = true
            return false
        }

        if let updated = NotesStorage.shared.notes.first(where: { $0.id == current.id }) {
            applyDiskContent(loadPersistedContent(for: updated), from: updated)
        } else {
            editingContent = persistedContent
            charCount = persistedContent.count
            lastSyncedDiskContent = persistedContent
            lastLoadedEditorNormalizedContent = nil
            pendingExternalDiskContent = nil
            ignoredExternalDiskContent = nil
            externalChangeState = nil
            selectedNote = current
            hasPendingSave = false
            isLoadingNote = true
            pushContentToEditor(persistedContent)
        }

        return true
    }

    private func runEditorCommand(_ command: String, stringArgument: String? = nil, intArgument: Int? = nil) {
        guard editorIsReady, let webView = editorWebView else { return }

        if let stringArgument {
            guard let argumentData = try? JSONSerialization.data(
                withJSONObject: stringArgument, options: .fragmentsAllowed
            ), let argumentJSON = String(data: argumentData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.editorAPI.\(command)(\(argumentJSON));")
            return
        }

        if let intArgument {
            webView.evaluateJavaScript("window.editorAPI.\(command)(\(intArgument));")
            return
        }

        webView.evaluateJavaScript("window.editorAPI.\(command)();")
    }

    private func runFindCommand(_ command: String, stringArgument: String? = nil) {
        guard editorIsReady, let webView = editorWebView else { return }

        let script: String
        if let stringArgument {
            guard let argumentData = try? JSONSerialization.data(
                withJSONObject: stringArgument, options: .fragmentsAllowed
            ), let argumentJSON = String(data: argumentData, encoding: .utf8) else { return }
            script = "window.editorAPI.\(command)(\(argumentJSON));"
        } else {
            script = "window.editorAPI.\(command)();"
        }

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                self?.applyFindResult(result)
            }
        }
    }

    private func applyFindResult(_ result: Any?) {
        guard let payload = result as? [String: Any] else {
            return
        }

        findMatchCount = intValue(payload["count"])
        findMatchIndex = intValue(payload["index"])
    }

    private func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return 0
    }

    private func resetFindResults() {
        findMatchCount = 0
        findMatchIndex = 0
    }

    private func promptForLinkURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "Enter a URL to insert or apply to the selected text."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        field.stringValue = "https://"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizeLinkURL(_ value: String) -> String {
        guard !value.contains("://") else { return value }
        return "https://\(value)"
    }

    // MARK: - Metadata Sidebar Actions

    func updateNoteTitle(_ newTitle: String) {
        guard let note = selectedNote, !newTitle.isEmpty else { return }
        NotesStorage.shared.rename(note: note, to: newTitle)
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            selectedNote = updated
            editingTitle = updated.title
        }
    }

    func updateNoteFolder(_ folderID: UUID?) {
        guard let note = selectedNote else { return }
        guard assignNote(note, toFolder: folderID) else { return }
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            selectedNote = updated
        }
    }

    func toggleNoteLabel(_ labelID: UUID) {
        guard let note = selectedNote else { return }
        if note.labelIDs.contains(labelID) {
            NotesStorage.shared.removeLabel(note.id, labelID: labelID)
        } else {
            NotesStorage.shared.assignLabel(note.id, labelID: labelID)
        }
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            var refreshed = selectedNote ?? updated
            refreshed.labelIDs = updated.labelIDs
            selectedNote = refreshed
        }
    }

    func toggleNotePin() {
        guard let note = selectedNote else { return }
        NotesStorage.shared.togglePin(note.id)
        if var updated = selectedNote {
            updated.isPinned.toggle()
            selectedNote = updated
        }
    }

    var extractedLinks: [URL] {
        let content = editingContent
        guard !content.isEmpty else { return [] }
        var urls: [URL] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(content.startIndex..., in: content)
        detector?.enumerateMatches(in: content, range: range) { result, _, _ in
            guard let url = result?.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return }
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: - Display Options

    func setDisplayMode(_ mode: NoteDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode

        var config = CiderConfig.load()
        config.notesDefaultViewMode = mode
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    func setCardSizeScale(_ scale: Double) {
        let clamped = min(max(scale, 0), 3)
        cardSizeScale = clamped

        var config = CiderConfig.load()
        config.notesCardSizeScale = clamped
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    func clearSelectedNote() {
        selectedNote = nil
        editingContent = ""
        editingTitle = ""
        charCount = 0
        richDisplayContentOverride = nil
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = ""
        lastLoadedEditorNormalizedContent = nil
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        lastRichEditorPushedMarkdown = nil
        externalChangeState = nil
        hasPendingSave = false

        if editorIsReady, let webView = editorWebView {
            webView.evaluateJavaScript("window.editorAPI.clear()")
        }
    }

    private func reconcileSelectedNote() {
        guard let selected = selectedNote else { return }

        guard let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            clearSelectedNote()
            return
        }

        if selected.title != updated.title || selected.relativePath != updated.relativePath || selected.modifiedAt != updated.modifiedAt {
            var refreshed = selected
            refreshed.title = updated.title
            refreshed.relativePath = updated.relativePath
            refreshed.modifiedAt = updated.modifiedAt
            selectedNote = refreshed
            editingTitle = refreshed.title
        }
    }

    private func applyNotesEditorTextSize() {
        runEditorCommand("setEditorBaseFontSize", stringArgument: notesEditorTextSize.cssFontSize)
    }
}
