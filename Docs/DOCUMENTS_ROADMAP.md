# Documents Tab Roadmap

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

### Acceptance Criteria
- Cross-feature linking is optional and does not complicate base capture flow.

## Open Questions
- Should Documents support OCR/transcription in scope, or stay file-management only at first?
- Should downloads captured from browsers auto-route to Documents?
- What file size limits should be enforced for local previews/caching?
