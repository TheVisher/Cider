# Future Tabs

> Consolidated from BOOKS_VISION.md, TODOS_VISION.md, and DOCUMENTS_VISION.md. None of these are implemented — they capture ideas for when the time comes.

---

## Books Tab

A dedicated reading tracker. Separate from bookmarks (web links) and notes (written content).

**Core features:**
- Library views: cover grid, list view, shelf view
- Book entry: manual add, ISBN/barcode lookup, import from Goodreads/StoryGraph
- Reading status: Want to Read / Currently Reading / Finished / Abandoned
- Progress tracking (page number or percentage), start/finish dates, rating
- Per-book notes, highlights, quotes. Link to Notes tab.
- Shelves/collections, tags, search, reading statistics

**Data model sketch:**
```swift
struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var author: String
    var coverImagePath: String?
    var isbn: String?
    var status: ReadingStatus       // .wantToRead, .reading, .finished, .abandoned
    var progress: Double?           // 0-1
    var currentPage: Int?
    var totalPages: Int?
    var startDate: Date?
    var finishDate: Date?
    var rating: Int?                // 1-5
    var notes: String?
    var tags: [String]
    var shelfID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
```

**Storage:** Follow per-file standard (see `STORAGE.md`). Books would likely use a JSON-based format since no standard file format exists for reading metadata.

---

## Todos Tab

A lightweight personal planner. Quick-add tasks, organize by day or project, check things off. Not a full PM tool — the digital equivalent of a to-do list on your desk.

**Core features:**
- Quick-add (type and enter), checkboxes, due dates, priority, subtasks, drag reorder
- Views: Today, Upcoming, All, Completed
- Daily lists with auto-archive and template support
- Integration with Notes tab (pull checkbox items, expand todo → note)
- Quick capture: global hotkey, clipboard, natural language date parsing

**Data model sketch:**
```swift
struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: TodoPriority?     // .low, .medium, .high
    var notes: String?
    var parentID: UUID?             // subtasks
    var sortOrder: Int
    var listID: UUID?
    var tags: [String]
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
```

**Storage:** `.ics` files (RFC 5545 VTODO). Already defined in the per-file storage standard — `~/CiderVault/Inbox/Todos/`.

---

## Documents Tab

A dedicated surface for non-URL assets (PDFs, images, files). Keeps bookmarks URL-first and avoids mixed-content complexity.

**Phases:**
1. MVP: drag-and-drop ingestion, list/grid browsing, open/reveal/delete
2. Preview & metadata: PDF first page, image thumbnails, details panel
3. Organization: collections/folders/tags, multi-select, bulk actions
4. Interop: import bundles, sync/export, "Attach to Bookmark" linking, `.webarchive` viewing
5. Filesystem watcher: watch `~/Pictures`, `~/Documents`, `~/Downloads` via FSEvents, reference files in-place (like Spotlight), full-text search via PDFKit + Vision OCR

**Window-based file capture (concept):**
- Accept proxy icon drags from document apps (already works via `NSItemProvider`)
- Frontmost window detection via Accessibility API (`kAXDocumentAttribute`) → one-tap "Capture [filename]" suggestion
- "Shake to grab" (detect rapid window movement → surface capture HUD)

**Supported file classes (MVP):** PDF, PNG/JPG/WEBP/GIF/HEIC, TXT/MD (DOCX optional)

**Storage:** Under `~/CiderVault/.cider/documents/` for metadata, with files referenced in-place for watched directories or copied into user folders for manually captured files.
