# Notes Tab Vision

This document captures the full vision for the Notes tab, broken into phases. Phase 1 is the current focus. Later phases are documented here for future context.

---

## Phase 1: Note Cards & View Modes (Current)

Bring the Notes tab up to parity with Bookmarks in terms of browse experience. Notes get their own card design that's visually distinct from bookmark cards — text-forward with side images instead of top images.

### Card Layout

Each note card displays:
- **Title** (bold header)
- **Sub-header line** — folder name for now, tags later (see Phase 3)
- **Preview text** — first few lines of plain text, stripped of markdown/HTML formatting
- **Images** — extracted from note content, alternating left/right layout, max 3
- **Footer** — modified date (relative) + word count
- **Empty state** — notes with no content show italic "Empty note" placeholder

### Context Menu

Right-click any card or list row for:
- **Open** — opens the note in the editor
- **Rename** — inline rename directly on the card (title swaps to a focused text field, Enter to save, Escape to cancel)
- **Move to Folder** — submenu listing all folders + "No Folder" option
- **Delete** — sends the note to Trash (recoverable via Settings → Storage)

Design decision: Rename edits inline on the card rather than opening the editor. This matches user expectations for a "Rename" action.

### Image Extraction & Display

Notes embed images via `![alt](./.attachments/filename.png)` in markdown. Cards parse these references and resolve them to file URLs for display.

**Image placement rules (grid & masonry):**
- **1 image:** Always on the right side of the card, text fills the left (~65/35 split)
- **2 images:** First image on the right. Second row: image on the left, text on the right (alternating sides)
- **3 images (max):** Alternating continues — right, left, right
- **0 images:** Text preview fills the full card width

Image area is roughly 30-35% of card width. Images are displayed with aspect-fit, rounded corners matching the design system.

### View Modes

Same three modes as Bookmarks, adapted for text-forward cards:

**List mode:**
- Compact horizontal row
- Small square thumbnail on the left (first image from note, if any)
- Title, date, and preview text to the right
- Notes without images skip the thumbnail column

**Grid mode:**
- Fixed-height cards in adaptive columns
- Title + sub-header at top
- Text preview on the left, first image on the right
- Footer with date + word count at bottom
- Text truncated to fit standardized card height

**Masonry mode:**
- Variable-height cards based on content
- Full alternating image layout (up to 3 images)
- More preview text visible alongside images
- Card height grows with image count but capped at 3 images
- Notes without images are shorter, text-only cards — creates visual variety

### Card Size Slider

Reuse the same `CardSizing` infrastructure and `ViewOptionsDropdown` from Bookmarks. The slider scales:
- Card width (column count adjusts)
- Preview text area size
- Image dimensions
- Typography sizes

### Title Bar Integration

Add the same view options button to the Notes tab title bar area:
- Card size slider
- View mode toggle (list / grid / masonry icons)
- Same `ViewOptionsDropdown` component, configured for notes

---

<!-- Removed: Standalone panel resize handle bug fix — standalone NotesPanel was removed in Feb 2026 panel consolidation. Notes editor now opens inline within the main panel (push/pop navigation). -->

---

## Phase 2: Interactive Checkboxes & Pinning

### Interactive Checkboxes on Cards

Notes containing TODO items (markdown checkboxes `- [ ]` / `- [x]`) display them directly on the card. Users can check/uncheck items without opening the note.

**Implementation considerations:**
- Parse markdown for checkbox patterns
- Render as native SwiftUI toggles on the card
- On toggle: update the specific checkbox line in the note's markdown content
- Save the modified content back to disk
- Limit display to first N checkboxes to avoid overwhelming the card

### Note Pinning

- Pin notes to the top of the list/grid/masonry view
- Pinned notes always appear first, regardless of sort order
- Visual indicator (pin icon) on pinned cards
- Toggle via right-click context menu (add "Pin" / "Unpin" to existing context menu)

### Drag Reorder

- Drag notes to manually reorder within the view
- Pinned notes can be reordered among themselves
- Persist custom sort order

### Drag to Folder

- ✅ Drag note cards onto folders in the sidebar to assign them, matching the bookmark drag-and-drop pattern
- Primary method for folder organization — context menu "Move to Folder" is the secondary option
- ✅ Reuses shared `CiderDragPayload` infrastructure (`NoteDragPayload` + `ciderDraggable` modifier)
- Works across all tabs: Notes tab, Home tab, and FolderDetailView
- Note cards use `Button(action:)` wrapper (not `.onTapGesture`) to prevent NSPanel window-dragging

---

## Phase 3: Tags & Metadata

### Multi-Folder Membership

Notes should support belonging to multiple folders simultaneously. This requires changing `folderID: UUID?` to `folderIDs: [UUID]` on the Note model.

**Card display options (needs design decision):**
- **Compact row with overflow:** Show first 2-3 folder pills inline, then a "+N" badge for remaining folders
- **Tags-style row at bottom:** Move folders to the card footer area, displayed as pills in a wrapping row — similar to how tags would appear
- **Open question:** If both folders and tags are shown on cards, how do they coexist? Separate rows? Mixed pills with different styling? Folders may need a folder icon prefix to distinguish from tags.

**Clickable folder pills:** Clicking a folder name on a card should navigate to that folder in the sidebar (select the folder, scroll sidebar to it). Provides quick navigation without right-click menus.

### Tags on Notes

Add a `tags: [String]` field to the Note model. Tags appear as the sub-header line on cards (replacing folder name as the sole sub-header content).

**Tag features:**
- Assign tags when editing a note
- Filter notes by tag in the sidebar or via search
- Tag pills displayed on cards with subtle color coding
- Auto-suggest existing tags when adding new ones

**Relationship with folders on cards:** Both folders and tags are metadata shown on cards. Design needs to decide whether they share the same visual row (mixed pills) or have distinct locations (folders in sub-header, tags in footer — or vice versa). Consider that folders are structural (where the note lives) while tags are descriptive (what the note is about).

---

## Phase 4: Split View & Advanced Layout

### Split View (Panel Width Dependent)

Once the Whiteboard tab is implemented as its own dedicated tab, the Notes tab focuses purely on structured note browsing and editing. The split view becomes the primary layout at wide widths.

**Layout:**
- **Left side:** Card browser (list/grid/masonry)
- **Right side:** Inline note editor for the selected note

Click a note in the browser to open it in the adjacent editor without leaving the panel. This provides a browse-and-edit workflow similar to Apple Notes / Bear / Obsidian.

**Width behavior:**
- **Narrow panel (< ~500pt):** Card browser only. Click opens note in inline editor (push/pop navigation)
- **Wide panel (> ~500pt):** Split view with resizable divider

**Empty state (no note selected):**
- Clean placeholder: "Select a note or create one" with a + button
- No scratchpad or capture area — that's what the Whiteboard tab is for
- The Notes tab stays focused on structured reading and writing

<!-- Previous: "This is distinct from the Opt+B dedicated notes panel" — standalone panel removed in Feb 2026 consolidation. Opt+B now captures a bookmark from the active browser. -->

### What Differentiates Notes Cards from Bookmark Cards

Notes and Bookmarks share card infrastructure but should feel visually distinct:
- **Bookmark cards:** Image-heavy, portrait-oriented, thumbnail dominates the card
- **Note cards:** Text-heavy, wider/landscape-oriented, body preview dominates
- **Color coding:** Subtle background tinting of note cards by folder, tag, or user-picked color (inspired by Google Keep). Helps visual scanning without adding UI clutter.
- Notes without images should feel like the natural default, not a missing-thumbnail state

### Advanced Image Treatment

- **Fanned/angled image stacks:** When a card has 2-3 images, the additional images fan out at slight angles behind the primary image, creating a layered stack effect
- **Click-to-cycle:** Clicking the image stack cycles through images in the fan
- **Image zoom preview:** Hover or long-press on card images for a larger preview

---

## Compact Formatting Toolbar (Upcoming)

Replace the current flat icon strip (15+ icons in a scrollable row) with a compact grouped toolbar inspired by Apple Notes. 5-6 icon buttons in the title bar area, each opening a dropdown/popover with related actions.

### Toolbar Layout (left to right)

1. **Undo / Redo** — two small buttons, always visible (no dropdown)
2. **Aa (Text Style)** — dropdown showing:
   - Top row: **B** / *I* / U / ~~S~~ / highlight marker / text color dot
   - Below: Title, Heading, Subheading, Body, Monostyled (checkmark on the active style)
   - Below: Bulleted List, Dashed List, Numbered List
   - Below: Block Quote
   - **Active state indicator:** When text is selected, the dropdown shows which styles are currently applied (checkmark next to "Title" if it's an H1, bold icon highlighted if bold is active, etc.)
3. **Lists** — task list, bullet list, numbered list (or fold into Aa dropdown)
4. **Table** — insert table (with row/column controls in a sub-menu or inline after insertion)
5. **Attach** — insert image from file picker, attach files
6. **Link** — add/remove link (or fold into Aa dropdown)

### Key Feature: Active Formatting State

The Aa dropdown must reflect the current selection's formatting. When the user selects text and opens the dropdown:
- Checkmark appears next to the active paragraph style (Title / Heading / Body)
- Inline style icons (B, I, U, S) show highlighted/active state
- This helps users understand what formatting is applied, especially distinguishing heading levels

### Missing Formatting (add alongside toolbar)

- **Block quotes** — the TipTap extension and CSS exist but no toolbar button currently
- **Strikethrough** — standard text decoration, missing from toolbar
- **Highlight** — background color on selected text
- **Horizontal rule / divider** — useful for section breaks

### Relationship to Pinned Toolbar

The current "pin toolbar" toggle becomes unnecessary — the compact toolbar is always visible in the title bar since it's only 5-6 icons wide. The old scrollable strip is removed entirely.

---

<!-- Standalone Panel Sidebar section — standalone NotesPanel was removed in Feb 2026 panel consolidation.
The inline editor now lives inside the main panel, which already has the full sidebar.
Keeping the sidebar vision below for reference in case a future dedicated editor surface is added.

## Standalone Panel Sidebar (Archived — panel removed)

**Prerequisite:** Redesign the main app's sidebar first, then reuse the same component in the standalone notes panel.

Replace the dropdown note-switcher menu in the standalone panel with a proper collapsible sidebar, matching the main app's sidebar pattern.

### Sidebar Layout

- **Toggle:** Show/hide button in the title bar (same pattern as main panel)
- **Search bar** at top — searches within the open note first (incremental/in-note find), but also shows contextual results from other notes that match the query (with preview snippets showing matching text in context)
- **Notes list** — all notes, sorted by modified date (or user preference)
- **Selected state** — current note highlighted in the sidebar
- **Create new** — button or keyboard shortcut to create a note

### Tree Structure (future enhancement)

Notes expand in a tree to show:
- **Attachments** — images and files embedded in that note, listed as children
- **Backlinks** — other notes that reference this note (e.g., contain a `[[Note Title]]` link), shown as linked children

This makes the sidebar a quick-reference navigation tool, not just a flat list.

### Search Behavior

The search bar in the standalone sidebar has two modes:
1. **In-note search** (primary) — highlights matches within the currently open note, with next/previous navigation
2. **Cross-note search** — below the in-note results, shows other notes containing the query with context snippets (the matching line with surrounding text). Clicking a result switches to that note and scrolls to the match.

This is sometimes called "universal search" or "omnisearch" (Obsidian's pattern).
End of archived standalone panel sidebar section. -->

---

## Future Ideas (Not Yet Prioritized)

### Plain Text Note Format (.txt)

Support `.txt` files alongside `.md`. Some users prefer plain text — no formatting, universal, lightweight.

**Design (planned):**
- `NoteFormat` enum (`.markdown`, `.plainText`) derived from file extension — no new stored field
- `NotesStorage` scans both `.md` and `.txt` files; `createNew(format:)` uses correct extension
- Plain text editor: `NSTextView` wrapper (no TipTap) — no formatting toolbar, no image embeds
- `InlineNoteEditorView` switches between TipTap and plain text editor based on `note.format`
- `CiderConfig.notesDefaultFormat` setting with picker in Settings → Notes → Behavior
- +New popover: segmented picker (Markdown / Plain Text), defaults from config
- `strippedContent` skips markdown regex for plain text; `imageURLs` returns `[]`
- Screen captures always create `.md` (embed `<img>` tags)
- Rename preserves existing extension
- Full plan was in `.claude/plans/encapsulated-splashing-harbor.md` (since deleted)

### Drag Out to External Apps
✅ **Implemented (R-11).** Drag a note card out of Cider onto Finder, a text editor, or a CLI and it drops the actual `.md` file via `public.file-url`. Full spec in `WORKSPACES_VISION.md` → "Drag Out to External Apps".

### UX Ideas from Note App Research

Patterns worth stealing from other note apps:
- **Bear's search tokens** — typing `@todo`, `@today`, `@images` in the search bar instantly filters notes by type. Zero UI footprint, very power-user friendly.
- **Ulysses auto-titling** — first line of the note automatically becomes the title. Reduces friction when creating notes quickly.
- **Per-folder sort persistence** (Evernote, UpNote) — each folder remembers its own preferred sort order and view mode independently.
- **Agenda's "flagged" concept** — a single-bit flag that creates a cross-folder "active now" virtual list. Could be a "Starred" or "Flagged" filter in the sidebar.

### Relationship to Whiteboard Tab

The Notes and Whiteboard tabs serve different mental modes:

| Aspect | Notes | Whiteboard |
|--------|-------|------------|
| Structure | Linear documents with titles | Freeform spatial canvas |
| Creation | Deliberate — create, title, write | Impulsive — click and dump |
| Organization | Folders and tags | Spatial positioning |
| Content | Long-form text, rich formatting | Fragments: short text, images, links, quotes |
| Output | Finished thoughts | Raw material that becomes notes |

The promotion flow: **Whiteboard blocks → select → "Create Note" → Notes tab**

### Screen Capture → Note

Screen capture (Opt+Cmd+2) is a first-class note creation path. When the routing toast's "Create Note" action fires:
- Title: first meaningful OCR line (≤ 60 chars), fallback "Screen Capture"
- Body: full OCR text from Vision framework
- Screenshot saved as `{notesDir}/Attachments/{uuid}.png` and embedded in the note

This means any visible text on screen — a chat message, a document, a code snippet — can become a searchable, editable note in one gesture.

### Todos / Planner Tab

Now has its own vision doc: `Docs/_archive/TODOS_VISION.md`. The core idea remains: separate actionable items (todos) from captured thoughts (notes) and freeform brainstorming (whiteboard).

---

## Model Changes Required

### Phase 1
- Add computed properties to `Note` for image extraction (parse markdown for image references)
- Add `NoteDisplayMode` enum (`.list`, `.grid`, `.masonry`)
- Add note-specific card sizing to `CiderConfig` persistence
- Word count computed property on `Note`

### Phase 2
- Add `isPinned: Bool` to `Note` model
- Add `sortOrder: Int?` to `Note` model for manual ordering
- Checkbox parsing utilities for markdown content

### Phase 3
- Add `tags: [String]` to `Note` model
- Tag storage and indexing in `NotesStorage`

---

## Post-1.0 Editor Features

### Toggle List (Collapsible Sections)
- TipTap `Details` extension (`<details>/<summary>` HTML)
- Toolbar button to insert a collapsible block
- Useful for long notes with sections you want to collapse

### Block Drag Handles
- Notion-style drag handles on paragraph/block hover
- Allows reordering blocks (paragraphs, headings, lists, code blocks) by dragging
- "Paragraph" insert button creates a new block at cursor position

### Comments / Annotations
- Select text → add comment → text highlighted with distinct comment color
- Comments listed in the info/metadata sidebar panel
- Click a comment in sidebar → scrolls to highlighted text in editor
- TipTap custom `Comment` mark with comment ID attribute
- Comment storage: array of `{id, text, author, createdAt}` persisted with note metadata
- Serialization: `<mark data-comment="id">text</mark>` in HTML

### Editor Background Themes
- Preset background colors for the editor in page view: dark (default), cream/sepia, paper white, soft gray
- Applied as a CSS class on the TipTap editor body element
- Persisted in CiderConfig (`noteEditorBackground: String`)
- Toggle in the note toolbar or view options dropdown

### Per-Type Detail View Mode
- Each content type remembers its own preferred detail view mode (slideOut, fullPanel, page)
- `CiderConfig.bookmarkDetailViewMode`, `noteDetailViewMode`, `dateCardDetailViewMode`, etc.
- CiderPanelView reads the appropriate mode based on what's being opened
- Mode picker updates only the relevant type's setting
- Users who prefer notes full-page but bookmarks in slideout get exactly that

### Columns Layout
- Multi-column content layout within a note
- Would need a custom TipTap node extension
- Low priority — uncertain value in a notes app
