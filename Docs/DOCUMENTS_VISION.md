# Documents Tab Vision

## Goal
Introduce a dedicated Documents surface for non-URL assets (PDFs, images, files) so Bookmarks remains URL-first and predictable.

## Why Separate From Bookmarks
- Keeps bookmark behavior clean: URL capture, metadata, browser open.
- Avoids mixed-content complexity in one model/view.
- Lets Documents optimize for file previews, local storage, and file actions.

## Phase 0: Definition
1. Define supported file classes for MVP:
- PDF
- image formats (png/jpg/webp/gif/heic)
- common docs (txt/md/docx optional)
2. Define storage strategy under `~/Documents/Cider/documents`.
3. Define metadata schema (filename, type, size, created/updated, source URL optional).

### Acceptance Criteria
- A documented schema and import behavior exists before implementation starts.

## Phase 1: MVP Surface
1. Add `Documents` tab in Command Palette and standalone panel/window.
2. Drag-and-drop file ingestion into Documents.
3. List/Grid browsing with search by filename/type.
4. Basic actions:
- open file
- reveal in Finder
- delete from library

### Acceptance Criteria
- Files can be dropped, indexed, and reopened reliably.
- UI matches panel design conventions (NSPanel behavior, spacing tokens, accessibility).

## Phase 2: Preview and Metadata
1. Inline previews:
- PDF first page
- image thumbnail
- generic icon fallback
2. Details panel:
- path
- size
- type
- created/modified dates
- optional source attribution

### Acceptance Criteria
- Preview generation is cached and non-blocking.
- Details are accurate and easy to copy/share.

## Phase 3: Organization and Actions
1. Collections/folders/tags.
2. Multi-select and bulk actions.
3. Quick-move and quick-rename flows.

### Acceptance Criteria
- Bulk operations are performant and safe.
- Search and filters remain responsive on larger libraries.

## Phase 4: Interop and Future Extensions
1. Import from common export bundles.
2. Optional sync/export strategy.
3. Optional “Attach to Bookmark” linking between Documents and Bookmarks.
4. Web archive viewing — `.webarchive` files from the bookmark archival feature (see `BOOKMARKS_VISION.md` → Web Archival) appear as viewable documents.

### Acceptance Criteria
- Cross-feature linking is optional and does not complicate base capture flow.

## Phase 5: Filesystem Watcher & Universal Organizer

**Vision:** Cider becomes the organizer for your files — not just things you manually capture, but your existing filesystem. Watch folders like Pictures, Documents, Downloads and surface their contents inside the floating panel, browsable and searchable without opening Finder.

**How it works:**
- User configures watched directories in Settings (e.g., `~/Pictures`, `~/Documents`, `~/Downloads`)
- Cider indexes file metadata (name, type, size, dates, thumbnails) via `FSEvents` or `DispatchSource`
- Files appear in the Documents tab alongside manually captured items
- No file copying — Cider references files in-place (like Spotlight, not like Photos.app)
- Full-text search across watched files (PDF text via PDFKit, image text via Vision OCR)

**Why this fits Cider:**
- Cider's floating panel is already the “quick access to everything” surface
- Finder requires a full app switch and loses your context. Cider doesn't.
- Combines with the existing folder/saved view system — create a saved view filtered to “PDFs in ~/Documents” or “Images from this week”
- External sources (`ExternalSourceRegistry`) already watch filesystem folders — this extends that pattern to richer file types with previews

**Scope control:**
- Watched folders are opt-in, not automatic
- Index metadata only by default (fast, lightweight). Full content indexing is opt-in.
- Large files are referenced, not copied. Cider's data directory stays small.
- File operations (move, rename, delete) go through Finder / filesystem — Cider is a viewer and organizer, not a file manager

## Window-Based File Capture

**Concept:** Grab the file behind any open window without hunting through Finder.

macOS has always had **proxy icons** — the small file icon in the title bar of document-based apps (Preview, TextEdit, Xcode, Word, etc.). You can drag it directly to any drop target to move or copy the underlying file. Since Monterey, proxy icons are hidden by default and only appear on hover over the filename in the title bar.

**How Cider could use this:**

1. **Accept proxy icon drops** — Cider's panel is already a drop target for files. Proxy icon drags produce the same `NSItemProvider` payload as a Finder drag, so this works today with no extra work. Users just need to know about it.

2. **Frontmost window detection** — When the Cider panel opens (double-tap Option), use the Accessibility API (`AXUIElementCopyAttributeValue` with `kAXDocumentAttribute`) to check the frontmost app's focused window for an open document path. If found, surface a one-tap "Capture [filename]" suggestion at the top of the panel — no drag required.

3. **Shake to grab (future concept)** — Detect rapid back-and-forth window movement via the Accessibility API or `NSEvent` global monitor. If a window is shaken, surface a HUD or Cider capture prompt offering to grab the file. This is a novel interaction not built into macOS — no existing utility does it. Implementation: track `NSWindow` (or `AXUIElement`) position delta over time, trigger when movement crosses a shake threshold (similar to how macOS detects cursor shake to enlarge the pointer).

**Why this matters:**
Sending a document — to Slack, email, a teammate — currently means: switch to Finder, navigate to the file, drag it out. If the file is already open in Preview or Word, that navigation is wasted. Window-based capture skips it entirely. The file is already on screen; Cider just needs a way to grab it.

**macOS API surface:**
- `AXUIElementCopyAttributeValue` with `kAXDocumentAttribute` → returns `file:///path/to/file` for most document apps
- `NSWorkspace.shared.frontmostApplication` → get the active app to target the right AX element
- Requires Accessibility permission (already needed for the double-tap Option hotkey detection)
- Proxy icon drags: standard `NSItemProvider` with `public.file-url` type — Cider already handles these

**Make proxy icons always visible** (useful tip to surface in onboarding/settings):
```bash
defaults write -g NSToolbarTitleViewRolloverDelay -float 0
```

## Open Questions
- Should Documents support OCR/transcription in scope, or stay file-management only at first?
- Should downloads captured from browsers auto-route to Documents?
- What file size limits should be enforced for local previews/caching?
- Should watched folder indexing be lazy (on-demand) or eager (background scan on launch)?
- How should Cider handle files that move or get deleted from watched folders?
