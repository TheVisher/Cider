# Cider Features

Status: canonical core doc.

This is a compact inventory of what Cider has. Keep summaries short. Roadmaps, bugs, QA evidence, and implementation history belong in Kanban.

## Floating Panel

The main Mac surface is a fast panel/window experience activated by hotkey. Cider uses AppKit where macOS behavior requires it and SwiftUI for content. It should avoid stealing focus, remember useful surface state, and support reanchoring floating work back into the main window.

Key code: `Sources/Cider/App/`, `Sources/Cider/Views/CiderPanelView.swift`, `Sources/Cider/Views/Shared/CiderPanelShell.swift`.

## Bookmarks

Bookmarks capture URLs, metadata, thumbnails, tags, notes, related items, and vault placement. `.webloc` files are durable vault artifacts while SQLite stores canonical metadata. Bookmark detail should conserve memory: keep the active live page useful, but avoid warming every web/reader/extraction surface in the background.

Key code: `Sources/Cider/Views/Bookmarks/`, `Sources/Cider/Services/VaultBookmarkService.swift`, `Sources/Cider/Services/BookmarksStorage.swift`, `Sources/Cider/Services/BookmarkFileService.swift`.

## Notes

Notes are local-first Markdown knowledge objects. Cider supports inline editing, rich TipTap editing, image drops, find, snapshots, and vault routing. The rich editor must preserve safe Markdown round-trips, image serialization, external modification checks, and deny-by-default navigation in its WKWebView layer.

Key code: `Sources/Cider/Views/Notes/`, `Sources/Cider/Services/NotesStorage.swift`, `Sources/Cider/Services/NotesMarkdownPathCodec.swift`, `Sources/Cider/Services/CiderVaultSchemeHandler.swift`.

## Files

Vault files let Cider track non-bookmark, non-note artifacts with metadata, thumbnails where possible, detail views, and search/index support.

Key code: `Sources/Cider/Services/VaultFileService.swift`, `Sources/Cider/Services/VaultFileStorage.swift`, `Sources/Cider/Views/Shared/VaultFileCardView.swift`.

## Folders And Tags

Folders and tags organize vault items. Folder movement must preserve item identity and should avoid destructive filesystem behavior.

Key code: `Sources/Cider/Services/VaultFolderService.swift`, `Sources/Cider/Views/Shared/FolderSidebarView.swift`, `Sources/Cider/Services/CardLabelStorage.swift`.

## Search And Recall

Search lets the user find saved items across vault types. Recall quality should favor precise local data over vague AI summaries. Related-items/backlink surfaces should use explicit links when they exist instead of asking agents to infer relationships every time.

Key code: `Sources/Cider/Services/SearchService.swift`, `Sources/Cider/Services/ItemLinkService.swift`, `Sources/Cider/Views/Search/SearchPaletteView.swift`, `Sources/Cider/Views/Bookmarks/RelatedItemsView.swift`.

## Kanban

Kanban is both a user feature and Cider's development workflow. It owns roadmap, active work, QA evidence, bugs, implementation notes, review findings, failed attempts, completed plan history, and handoff context. Markdown export is explicit and one-way; cards remain the source of truth.

Key code: `Sources/Cider/Views/Kanban/`, `Sources/Cider/Models/KanbanBoard.swift`, `Sources/Cider/Services/KanbanStorage.swift`.

## Todos, Dates, And Reminders

Todos and date cards represent tasks, events, reminders, and resurfacing. They use iCalendar-style vault files and SQLite-backed storage. Recurring notifications must not mark an entire series complete when one occurrence fires.

Key code: `Sources/Cider/Views/Todos/`, `Sources/Cider/Views/DateCards/`, `Sources/Cider/Services/TodoCardStorage.swift`, `Sources/Cider/Services/DateCardStorage.swift`.

## Contacts

Contacts store people and relationship context. The long-term goal is useful second-brain context, not just address-book fields: essentials, custom fields, notes, related items, reminders, and history.

Key code: `Sources/Cider/Views/Contacts/`, `Sources/Cider/Services/ContactStorage.swift`, `Sources/Cider/Models/ContactCard.swift`.

## Dashboard

Dashboard/Home should become the user's command center: current work, vault pulse, reminders, resurfacing, docs health, inbox health, and agent summaries. It should be personal, explainable, and actionable. The quality bar is whether a card answers: why does this matter to me?

Key code: `Sources/Cider/Views/Dashboard/`, `Sources/Cider/Views/Home/`, `Sources/Cider/Services/Dashboard/`.

## Main Brain Chat

Main Brain is the native Cider chat surface for the user's primary agent. It preserves a stable logical Cider brain, `cider.main`, displayed as Cider, while bridging to Hermes runtime/session behavior. The visible transcript is a working surface; the vault is durable memory.

Key code: `Sources/Cider/Views/AIAssistant/`, `Sources/Cider/Services/Agent/`.

## AI And Enrichment

Cider uses local and external intelligence for metadata extraction, summaries, tags, OCR, embeddings, similar items, and agent tools. AI should support local truth, not replace it. User-owned fields stay protected; generated summaries and enrichment belong in AI-owned fields.

Key code: `Sources/Cider/Services/AI/`.

## Clipboard

Clipboard history supports capture and recall from copied text, URLs, and images. It can act as a lightweight inbox, but promotion into durable vault objects should stay explicit.

Key code: `Sources/Cider/Services/ClipboardHistoryService.swift`, `Sources/Cider/Views/Shared/ClipboardPanelView.swift`.

## Screen Capture

Screen capture saves images and OCR-derived context into the vault. Routing should be explicit and visible when possible.

Key code: `Sources/Cider/Services/ScreenCaptureService.swift`, `Sources/Cider/Views/ScreenCapture/`.

## Settings And Sync

Settings manage vault location, hotkeys, intelligence, storage, sync, update reminders, and connected services. Sync remains secondary to local-first safety.

Key code: `Sources/Cider/Views/Settings/`, `Sources/Cider/Services/SyncService.swift`.

## Saved Views And Sources

Saved views are reusable lenses over Cider data, not separate storage containers. Sources and linked references help explain where an item came from and how it relates to other vault objects.

Key code: `Sources/Cider/Views/SavedViews/`, `Sources/Cider/Models/SavedView.swift`, `Sources/Cider/Services/SavedViewStorage.swift`.

## Whiteboard And Browser Sessions

Whiteboard and browser/session surfaces are not current first-push promises. They may become useful Cider item types later, but active work belongs in Kanban until they are real product surfaces.
