# Cider Features

Status: canonical core doc.

This is a compact inventory of Cider's durable product surfaces. Keep summaries short. Roadmaps, bugs, QA evidence, and implementation history belong in Kanban.

During the journal-first product-scope reset, use this as the starting feature inventory, then supplement it with a code-backed view and route inventory on the North Star Kanban audit. Decide with the user whether each feature/view/route should be kept, merged, demoted, parked, or removed. Preserve user content and shared backend capability even when a dedicated visible surface is reduced.

## Floating Panel

The main Mac surface is a fast panel/window experience activated by hotkey. Cider uses AppKit where macOS behavior requires it and SwiftUI for content. It should avoid stealing focus, remember useful surface state, and support reanchoring floating work back into the main window.

Key code: `Sources/Cider/App/`, `Sources/Cider/Views/CiderPanelView.swift`, `Sources/Cider/Views/Shared/CiderPanelShell.swift`.

## Library

Library opens to the complete visual collection across active item types. It is the shared manual-browse and capture surface, not a dashboard landing page and not a second set of domain mini-apps.

Filtering should be immediate and low-clutter. Use a quiet row of multi-select pills to show or hide major content families—for example Bookmarks, Journal/Notes, Files, Tasks, Events, and People—with an obvious All/reset state. Inbox is a temporary workflow-state filter for unreviewed or unfiled captures, not a destination or content type; the Journal container is never an Inbox item. Keep Needs Review and other workflow state visually distinct from content-type pills, and expose Spaces through an entity-aware lens/selector rather than expanding the row into dozens of permanent chips. Active filters must remain obvious and easy to clear; a fresh Library opening should show the complete collection.

Journal should appear in Library as a calm container/card rather than flooding the collection with every daily entry. Grid, masonry, and list/table presentation remain useful views over the same filtered collection.

Opening a normal Library item defaults to a calm slide-out detail so browsing context stays visible. **Open Full** and **Float** are explicit secondary actions rather than equally prominent global modes. Item-specific content may add focused actions inside that hierarchy, but should not reintroduce a mode picker as the primary interaction.

Key code: `Sources/Cider/Models/WorkspaceRoute.swift`, `Sources/Cider/Models/LibraryItemV2.swift`, `Sources/Cider/Views/Shared/`, `Sources/Cider/Views/Journal/JournalLibraryViews.swift`.

## Bookmarks

Bookmarks are one captured item type inside the second-brain loop. They capture URLs, metadata, thumbnails, tags, notes, related items, source provenance, routing/review state, and vault placement. `.webloc` files are durable vault artifacts while SQLite stores canonical metadata. Bookmark detail should conserve memory: keep the active live page useful, but avoid warming every web/reader/extraction surface in the background.

For now, the visible manual browser-capture paths are the automatic copied-URL Save/Discard toast and **New → Bookmark**. Preserve the existing active-browser/Safari capture code and Option+B hotkeys, but hide/demote those entry points until real use justifies restoring them. Do not delete and later rebuild working capture capability.

Key code: `Sources/Cider/Views/Bookmarks/`, `Sources/Cider/Services/VaultBookmarkService.swift`, `Sources/Cider/Services/BookmarksStorage.swift`, `Sources/Cider/Services/BookmarkFileService.swift`.

## Capture

Capture is the lowest-friction intake path for URLs, Journal/conversation entries, notes, files/images, todos, dates/reminders, contacts/context, screen snippets, and other source material. Native/manual and agent capture must converge on the same canonical item, provenance, indexing, review, linking, and recall contracts. Capture should save source identity first, return agent-friendly JSON, acknowledge quickly, and tolerate incomplete enrichment or routing.

The global **+ New** menu stays intentionally minimal: Bookmark, Journal Entry, Note, and Task. Other supported typed creation and organization actions live under **More** or in their relevant context. `⌘K` may expose the same vocabulary as quick actions, but must not maintain a competing creation model. A Journal Entry action appends to the current daily Journal; it does not create an ordinary Note.

Key code: `Sources/Cider/Services/CiderCaptureService.swift`, `Sources/CiderCLI/CiderCLI.swift`.

## Journal

Journal is a permanent top-level destination and Cider's readable chronological life narrative. Conversation and voice may append source-backed daily entries; explicit intent may create linked bookmarks, tasks, events, places, and other typed objects. Journal must remain readable rather than becoming a raw transcript dump, while structured spans, provenance, and links support accurate recall behind the presentation.

Key code: `Sources/Cider/Views/Journal/`, `Sources/Cider/Models/JournalLibraryReadModel.swift`, `Sources/Cider/Services/SecondBrainStore.swift`.

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

Cider has one global search mental model across Journal, Library items, and Projects/Kanban. The visible Library search field and `⌘K` invoke the same underlying search, ranking, scopes, and result vocabulary; `⌘K` additionally exposes quick actions and creation commands. Search scope/type filters may narrow results without creating separate search products.

Recall quality should favor precise local data over vague AI summaries. Related-items/backlink surfaces should use explicit links when they exist instead of asking agents to infer relationships every time.

Second-brain recall adds structured sections, content chunks, FTS5 search, routing decisions, and agent-action provenance. Exact search stays first-class; embeddings may supplement recall later, but vector search should not become the memory authority.

Key code: `Sources/Cider/Services/SearchService.swift`, `Sources/Cider/Services/SecondBrainStore.swift`, `Sources/Cider/Services/ItemLinkService.swift`, `Sources/Cider/Views/Search/SearchPaletteView.swift`, `Sources/Cider/Views/Bookmarks/RelatedItemsView.swift`.

## Routing And Review

Routing records where Cider thinks an item belongs, why, with what confidence, and whether it needs review. Review Queue is the trust boundary for uncertain routing, enrichment gaps, duplicate candidates, stale Inbox items, reminders, and agent suggestions. Review Queue JSON exposes structured `reasonCodes` alongside prose reasons so agents can distinguish low-confidence routing, enrichment failures, stale Inbox backlog, and duplicate risk without parsing text. Approve/correct/defer actions should preserve provenance and improve future routing behavior.

Key code: `Sources/Cider/Services/CiderRoutingDecisionService.swift`, `Sources/Cider/Services/CiderReviewQueueService.swift`, `Sources/Cider/Services/CiderSpaceCaptureDashboardService.swift`.

## Kanban

Projects opens to a calm cross-project summary of **Active**, **Testing**, **Blocked**, and **Next Up** work—not one enormous combined board and not an administrative board list. The summary should help the user understand what agents are doing and what needs judgment without duplicating the compact Today view's personal reminders.

Kanban is both a user feature and Cider's development workflow. It owns roadmap, active work, QA evidence, bugs, implementation notes, review findings, failed attempts, completed plan history, and handoff context. Markdown export is explicit and one-way; cards remain the source of truth.

Card notes can be parsed into native dashboard sections and projected into the second-brain item graph for search and agent inspection. YAML still owns the card; SQLite projection is rebuildable.

Key code: `Sources/Cider/Views/Kanban/`, `Sources/Cider/Models/KanbanBoard.swift`, `Sources/Cider/Services/KanbanStorage.swift`, `Sources/Cider/Services/KanbanCardSectionParser.swift`, `Sources/Cider/Services/SecondBrainKanbanProjectionService.swift`.

## Todos, Dates, And Reminders

Todos and date cards represent tasks, events, reminders, and resurfacing. They use iCalendar-style vault files and SQLite-backed storage. Recurring notifications must not mark an entire series complete when one occurrence fires.

Key code: `Sources/Cider/Views/Todos/`, `Sources/Cider/Views/DateCards/`, `Sources/Cider/Services/TodoCardStorage.swift`, `Sources/Cider/Services/DateCardStorage.swift`.

## Contacts

Contacts store people and relationship context. The long-term goal is useful second-brain context, not just address-book fields: essentials, custom fields, notes, related items, reminders, and history.

Key code: `Sources/Cider/Views/Contacts/`, `Sources/Cider/Services/ContactStorage.swift`, `Sources/Cider/Models/ContactCard.swift`.

## Dashboard

Home is a compact **Today** view, not Cider's primary front door or an all-purpose command center. It should show only reminders, open loops, and genuinely relevant resurfacing that help the user act now. Main Brain opens first; Journal carries the chronological life narrative. Today should share the same Cider-computed relevance model used by CLI JSON and agent briefings, so its few visible cards are explainable projections of shared truth rather than a separate feed of counts and telemetry.

Key code: `Sources/Cider/Views/Dashboard/`, `Sources/Cider/Views/Home/`, `Sources/Cider/Services/Dashboard/`.

## Spaces

Spaces are entity-aware semantic hubs and lenses inside Library, not a separate top-level mini-app system and not merely saved filters. They may add domain-specific states, facets, views, and actions over shared canonical objects. A Media Space, for example, can filter movies while also tracking watched/unwatched, liked/disliked, ratings, recommendations, and linked Journal reflections or source material.

Spaces must not become independent storage silos. Their identity, instructions, memberships, and relations enrich the same Library items and second-brain graph that Main Brain searches and recalls.

The target backend shape is a native SQLite `spaces` table for Space identity and instructions, with `space_memberships` and owner relations carrying semantic membership. Folder paths and `.cider-space.yaml` metadata remain compatibility/export surfaces until the cutover is proven.

Key code: `Sources/Cider/Views/Spaces/`, `Sources/Cider/Services/CiderSpaceStorage.swift`, `Sources/Cider/Services/CiderSpaceMembershipStore.swift`, `Sources/Cider/Services/CiderSpaceCaptureDashboardService.swift`.

## Main Brain Chat

Main Brain is Cider's default opening experience and primary conversational front door. The native Cider chat surface preserves a stable logical Cider brain, `cider.main`, displayed as Cider, while bridging to Hermes runtime/session behavior. The visible transcript is a working surface; the vault is durable memory. Embedded and pop-out chat are two presentations of the same conversation identity, not separate products.

Key code: `Sources/Cider/Views/AIAssistant/`, `Sources/Cider/Services/Agent/`.

## AI And Enrichment

Cider uses local and external intelligence for metadata extraction, summaries, tags, OCR, embeddings, similar items, and agent tools. AI should support local truth, not replace it. User-owned fields stay protected; generated summaries and enrichment belong in AI-owned fields.

Key code: `Sources/Cider/Services/AI/`.

## Clipboard

Keep Cider's simple clipboard history panel as a useful lightweight utility, along with automatic URL and image detection that asks whether the user wants to save the copied content. Do not expand it into a heavyweight standalone clipboard-manager product or permanent top-level destination.

Unsaved clipboard history remains transient and separate from durable Library truth. When the user accepts a save prompt or explicitly saves a clipboard item, it must run through canonical Cider capture with clipboard provenance, duplicate detection, indexing, linking, and Main Brain recall parity. Promotion into durable vault objects stays explicit.

Key code: `Sources/Cider/Services/ClipboardHistoryService.swift`, `Sources/Cider/Views/Shared/ClipboardPanelView.swift`.

## Drop Zone

Park the dedicated floating Drop Zone UI because it has not demonstrated everyday use. Preserve its working capture engine and tests: it already accepts files, URLs, text, and images; routes them through canonical capture; emits receipts; and supports recent-drop state. Do not delete and later rebuild that capability. It may return as a simpler universal drop target if real use or the future shell design calls for it.

Key code: `Sources/Cider/Views/Floating/CiderDropZoneView.swift`, `Sources/Cider/App/CiderDropZoneContext.swift`, `Sources/Cider/App/CiderStatusDropTarget.swift`, `Sources/Cider/Views/CiderPanelView+URLDrop.swift`.

## Screen Capture

Park Cider's dedicated screenshot/OCR routing workflow as a visible product surface; it has not demonstrated enough real use to justify separate UI. Preserve reusable capture and OCR capability in the backend where inexpensive, but do not require OCR or entity routing before an image can be saved.

Unify screenshots with clipboard image capture instead. When any supported OS screenshot/snipping tool places an image on the clipboard, Cider's lightweight capture toast should show a thumbnail and ask whether to save it. An accepted image enters canonical capture with source provenance; optional OCR may enrich search after saving without interrupting capture or automatically creating events/contacts. macOS can use the native Cider clipboard monitor; Windows requires an equivalent local capture client/worker before the same behavior can operate there.

Key code: `Sources/Cider/Services/ScreenCapture/`, `Sources/Cider/Views/ScreenCapture/`, `Sources/Cider/Views/Shared/ScreenCaptureRoutingToast.swift`.

## Settings And Sync

Settings manage vault location, hotkeys, intelligence, storage, sync, update reminders, and connected services. Sync remains secondary to local-first safety.

Key code: `Sources/Cider/Views/Settings/`, `Sources/Cider/Services/SyncService.swift`.

## Sources

Sources and linked references explain where an item came from and how it relates to other vault objects. Active navigation should use current domains, Library routes, Spaces, and explicit Project/Kanban routes.

## Whiteboard And Browser Sessions

Whiteboard and browser/session surfaces are not current first-push promises. They may become useful Cider item types later, but active work belongs in Kanban until they are real product surfaces.
