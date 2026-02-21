# Cider Integration Design

> **Status:** Phase 1 (panel refactor) ✅ complete. Phase 2 (Obsidian vault) — foundation in place via Linked Sources; vault-specific pieces remain. Phases 3+ are future.
> **Companion to:** `PIVOT_STRATEGY.md`, `LINKED_SOURCES_VISION.md`

This document defines how Cider integrates with Obsidian and other knowledge bases, the sync adapter architecture, data format decisions, and cross-platform considerations.

---

## Architecture Overview

```
+----------------------------------+
|         Cider Application        |
|                                  |
|  +----------+    +------------+  |
|  | Bookmarks|    |   Notes    |  |
|  | Manager  |    |   Editor   |  |
|  +----+-----+    +-----+------+  |
|       |                |         |
|  +----v----------------v------+  |
|  |     Cider Local Storage    |  |
|  |  (always present, source   |  |
|  |   of truth for bookmarks)  |  |
|  +----+--------------+-------+  |
|       |              |          |
|  +----v----+   +-----v-------+  |
|  | Bookmark|   |    Note     |  |
|  | Adapters|   |   Adapters  |  |
|  +---------+   +-------------+  |
+----------------------------------+
       |                |
       v                v
  +---------+     +-----------+
  | Export   |     | Obsidian  |
  | Targets  |     | Vault     |
  | (HTML,   |     | (direct   |
  |  Notion) |     |  r/w)     |
  +---------+     +-----------+
```

### Key Principle: Bookmarks and Notes Have Different Integration Models

- **Bookmarks** are Cider's domain. Cider owns the canonical data. Adapters *export* bookmarks to other systems (as markdown files, Notion database rows, etc.) but Cider's local storage is the source of truth.

- **Notes** are bidirectional with Obsidian. When connected to a vault, Cider reads and writes vault markdown files directly. The vault is the source of truth for notes, not Cider's local storage. Cider's own `~/Documents/Cider/Notes` directory is only used when no vault is connected.

---

## Obsidian Vault Integration

> **Feb 2026:** The Linked Sources feature (see `LINKED_SOURCES_VISION.md`) provides the read/edit/watch foundation. An Obsidian vault is a Linked Source with extra requirements: nested scanning, wikilink rendering, frontmatter handling, and `.obsidian/` exclusion. The vault-specific UI (Connectors settings, onboarding flow, bookmark export) is still future work.

### Vault Discovery

Cider finds Obsidian vaults by:
1. **Scanning known locations** — `~/Documents`, `~/Obsidian`, `~/vaults`, `~/Desktop`
2. **Looking for `.obsidian/` directories** — the presence of this directory confirms a vault
3. **Reading Obsidian's config** — `~/Library/Application Support/obsidian/obsidian.json` contains a list of known vaults with paths (macOS). On Linux: `~/.config/obsidian/obsidian.json`
4. **Manual path selection** — user can always point Cider at any directory

### Vault Configuration

When Cider connects to a vault, it reads:
- `.obsidian/app.json` — attachment folder path (`attachmentFolderPath`), new file location, default folder
- `.obsidian/appearance.json` — theme info (optional, for matching appearance)

Cider stores the connected vault path in `CiderConfig`:
```swift
var obsidianVaultPath: String?     // nil = not connected
var obsidianInboxFolder: String    // default: "Cider Inbox"
var obsidianAttachmentPath: String // read from app.json, fallback: vault root
```

### File Operations

**Reading vault files:**
- Cider's notes list shows the vault's folder tree instead of `~/Documents/Cider/Notes`
- Files are read on-demand when opened, not preloaded into memory
- The palette search indexes file names and optionally file content (same approach as current notes search)
- Cider respects `.obsidian/` and other dot-directories (never displays or modifies them)

**Writing vault files:**
- Quick captures go to the inbox folder (e.g., `Cider Inbox/` at vault root)
- Images/attachments save to the vault's configured attachment folder
- File references use the format matching Obsidian's settings (shortest path, relative path, or absolute path — read from `app.json`)

**Editing vault files:**
- The existing TipTap editor opens vault files the same way it opens Cider notes
- Markdown round-trip rules (see below) ensure Cider doesn't mangle Obsidian-specific syntax

### Markdown Round-Trip Rules

Cider must preserve syntax it doesn't understand. When loading a vault file for editing:

| Syntax | Cider Support | Handling |
|--------|--------------|----------|
| Standard CommonMark | Full | Render and edit normally |
| `![](image.png)` | Full | Render inline, save attachments to vault path |
| `**bold**`, `*italic*` | Full | Standard formatting |
| Tables, lists, code blocks | Full | TipTap handles these |
| YAML frontmatter (`---`) | Preserve | Store raw YAML block, write it back unchanged |
| `[[wiki-links]]` | Preserve | Display as styled text, don't resolve. Write back as-is |
| `[[link\|display text]]` | Preserve | Show display text, preserve full syntax on save |
| `![[embeds]]` | Preserve | Show as placeholder block, preserve on save |
| `> [!callout]` | Preserve | Treat as blockquote, preserve callout syntax |
| `#tags` in body text | Preserve | Don't strip or modify |
| `%%comments%%` | Preserve | Hidden from view, preserved in source |
| Dataview queries | Preserve | Show as code block, don't execute |
| Templater syntax | Preserve | Treat as raw text |

**The golden rule:** if Cider doesn't understand a syntax construct, store the raw text and write it back byte-for-byte. Never silently drop or reformat unknown constructs.

### File Watching

The current notes storage already has a directory watcher (`DispatchSource.makeFileSystemObjectSource`) for detecting external changes. This same mechanism works for vault files:
- If Obsidian modifies a file while Cider has it open, detect the change and prompt "File changed externally. Reload?"
- If Cider saves a file, Obsidian picks it up automatically (Obsidian watches its own vault)
- No conflict resolution beyond the existing "Keep Mine / Reload" dialog

---

## Bookmark Integration (Export to Obsidian)

Bookmarks live in Cider (source of truth). When connected to an Obsidian vault, Cider exports bookmarks as individual markdown files with rich frontmatter, enabling beautiful card-based browsing via the DataCards/Dataview plugin ecosystem.

### How It Works

**Each bookmark becomes a `.md` file in the vault:**
```markdown
---
url: https://dribbble.com/shots/cool-design
title: Beautiful Dashboard UI
domain: dribbble.com
tags: [design, inspiration, ui]
thumbnail: Attachments/cider-thumb-a1b2c3.png
captured: 2026-02-14
cider-bookmark: true
---

# Beautiful Dashboard UI

[Open in browser](https://dribbble.com/shots/cool-design)

> User's personal notes about this bookmark go here.
```

**Cider auto-generates a "Bookmark Library" note with a DataCards query:**
````markdown
---
cider-managed: true
---

# Bookmark Library

```datacards
TABLE thumbnail, title, domain, tags, captured
FROM "Cider Bookmarks"
WHERE cider-bookmark = true
SORT captured DESC

// Settings
preset: grid
imageProperty: thumbnail
```
````

This renders as a visual card grid inside Obsidian — thumbnails, titles, domains, tags, dates — auto-updating as Cider adds new bookmarks. Users can create additional library views filtered by tag, domain, or date using the same query syntax.

### What Cider Does on Bookmark Save (When Vault Connected)

1. Saves the bookmark to Cider's own storage (source of truth, as always)
2. Copies the thumbnail image to the vault's attachment folder
3. Creates/updates a `.md` file in `Cider Bookmarks/` folder in the vault
4. Updates the bookmark library note if it exists (or creates it on first export)

### Vault Folder Structure for Bookmarks
```
~/path/to/obsidian-vault/
├── Cider Bookmarks/               # One .md per bookmark
│   ├── Beautiful Dashboard UI.md
│   ├── Swift Documentation.md
│   └── Interesting Article.md
├── Cider Bookmark Library.md      # Auto-generated DataCards query view
├── Attachments/                   # Vault's attachment folder
│   ├── cider-thumb-a1b2c3.png
│   └── cider-thumb-d4e5f6.png
└── ...
```

### Plugin Compatibility

The visual card library relies on the Obsidian plugin ecosystem:

| Plugin | Purpose | Install Base |
|--------|---------|-------------|
| **Dataview** | Query frontmatter across files | ~5M+ installs, near-universal |
| **DataCards** | Render Dataview queries as card grids | Growing, purpose-built for this |
| **Minimal Theme** | Built-in card view CSS for Dataview | Very popular theme |

Without these plugins, bookmark files are still fully functional markdown — just rendered as plain notes instead of visual cards. Cider can include a setup guide or prompt users to install DataCards for the best experience.

### Why One-File-Per-Bookmark (Not a Single Index)

- **DataCards/Dataview require individual files** — queries work by reading frontmatter across separate notes
- **Each bookmark can have personal notes** — annotations, related links, project context
- **Obsidian search, graph view, and backlinks work** — a bookmark can be linked from project notes
- **Cider manages file lifecycle** — creating, updating, and deleting bookmark files as the user manages bookmarks in Cider

### Notion Bookmark Export (Future)

- Notion API creates database entries in a designated database
- Fields: Title, URL, Tags (multi-select), Thumbnail (file), Captured date
- Requires OAuth setup in Cider settings
- Push-only (Cider doesn't read back from Notion)

### Other Adapters (Future)

- **Custom folder** — Write bookmark index markdown to any folder. Covers Logseq, any markdown tool.
- **Apple Notes** — AppleScript to create notes with bookmark content.
- **JSON/CSV export** — For data portability.

---

## Capture Mechanisms

### What Gets Captured and How

| Capture Type | Trigger | What's Saved | Destination |
|-------------|---------|-------------|-------------|
| **Bookmark** | Option+Shift+B, paste URL, drag URL | URL + title + thumbnail + metadata | Cider bookmark storage |
| **Text snippet** | Drag selected text into palette, paste | Raw text as note content | Cider note or vault inbox |
| **Image** | Drag image into palette or note | Image file + reference | Cider attachments or vault attachment folder |
| **Clipboard** | Option+V in palette (future) | Whatever's on clipboard | Cider note or vault inbox |
| **OCR text** | Capture region, extract text | Extracted text as note | Cider note or vault inbox |
| **Screenshot** | Capture region (future) | Image + optional OCR text | Cider attachments or vault |

### OCR Implementation (macOS)

macOS provides `VNRecognizeTextRequest` in the Vision framework:
```
User triggers OCR capture
    -> Screen region selection (similar to macOS screenshot)
    -> Capture image of region
    -> Run VNRecognizeTextRequest on the image
    -> Present extracted text in a new note (editable before saving)
    -> Save note to Cider or vault inbox
```

The captured image can optionally be saved alongside the extracted text as an attachment.

**Linux equivalent:** Tesseract OCR (open-source), invoked via command line. Same UX, different backend.

### Auto-Capture (Existing Feature)

The clipboard monitor (`BookmarksClipboardMonitor`) already watches for copied URLs and offers to save them as bookmarks. This continues unchanged — it's one of Cider's most useful capture features.

---

## Storage Layout

### Cider Local Storage (always present)

```
~/Documents/Cider/
├── Bookmarks/
│   ├── bookmarks.html                    # Netscape HTML (portable)
│   ├── _cider_bookmarks_metadata.json    # Extended metadata
│   ├── .thumbnails/                      # Downsampled runtime thumbnail images
│   └── .originals/                       # Full-size bookmarked images
├── Notes/                                # Only used when no vault connected
│   ├── *.md                              # Individual note files
│   ├── _cider_notes_index.json           # UUID-to-filename index
│   ├── .attachments/                     # Note attachments
│   └── .history/                         # Note snapshots
└── Config/
    └── cider.json                        # App configuration (CiderConfig)
```

Bookmark image behavior:
- UI cards/lists should render from `.thumbnails/` for predictable memory use.
- `.originals/` is retained for explicit open/export workflows.

### When Connected to an Obsidian Vault

```
~/Documents/Cider/
├── Bookmarks/                # Unchanged — Cider owns bookmarks
│   └── ...
├── Notes/                    # Dormant — vault is the note source
│   └── ...
└── Config/
    └── cider.json            # Contains obsidianVaultPath

~/path/to/obsidian-vault/     # Vault is the note source of truth
├── .obsidian/                # Obsidian config (Cider reads, never writes)
├── Cider Inbox/              # Cider's quick-capture destination
│   ├── 2026-02-14 Quick note.md
│   └── 2026-02-14 Snippet.md
├── Cider Bookmarks/          # One .md per bookmark (managed by Cider)
│   ├── Beautiful Dashboard UI.md
│   └── Swift Documentation.md
├── Cider Bookmark Library.md # Auto-generated DataCards query view
├── Attachments/              # Vault's attachment folder
│   └── image-from-cider.png  # Images dragged in via Cider
└── ... (rest of vault)       # User's existing vault structure
```

### Data Format Decisions for Cross-Platform

These formats must work on both macOS and Linux:

| Data | Format | Why |
|------|--------|-----|
| Bookmarks | Netscape HTML + JSON sidecar | HTML is the universal bookmark format. JSON holds Cider-specific metadata (tags, folders, thumbnails). |
| Notes | Markdown files + JSON index | Markdown is universal. The index maps UUIDs to filenames for stable references. |
| Thumbnails | PNG/JPEG files | Standard image formats. |
| Configuration | JSON | Simple, human-readable, works everywhere. |
| Attachments | Original format | Preserve whatever format the user saved (PNG, JPEG, PDF, etc). |

**No SQLite, no Core Data, no platform-specific storage.** Everything is files on disk in standard formats. This makes cross-platform trivial and lets users inspect/modify their data directly.

---

## Vault Onboarding (Cider Sets Up Obsidian For You)

### The Problem Cider Solves

Obsidian's biggest barrier is the blank canvas. New users face:
- **No structure** — empty vault, no folders, no guidance on where things go
- **Plugin overload** — hundreds of community plugins, no clarity on which ones matter
- **No starting content** — nothing to search, link, or organize until you manually create it
- **Unclear workflow** — "second brain" sounds great but what do you actually *do* day one?

Most people bounce off Obsidian because of this. Cider solves it by being the easy on-ramp: **you don't start in Obsidian, you start in Cider.** Cider captures your bookmarks and notes, builds your vault behind the scenes, and when you eventually open Obsidian, it's already populated, organized, and useful.

### What Happens When You Connect a Vault

**First-time vault connection (new or empty vault):**

Cider creates a starter structure:
```
~/path/to/vault/
├── Inbox/                        # Quick captures land here
├── Bookmarks/                    # Cider-managed bookmark files
├── Notes/                        # Your notes (moved from Cider local)
├── Projects/                     # Stub folder for project organization
├── Templates/                    # Starter templates (see below)
│   ├── Bookmark.md               # Frontmatter template for bookmarks
│   ├── Quick Note.md             # Timestamped note template
│   └── Project.md                # Project template with sections
├── Attachments/                  # Images, thumbnails, files
├── Cider Bookmark Library.md     # Auto-generated DataCards view
└── Getting Started with Cider.md # Workflow guide (see below)
```

**Existing vault with content:**

Cider is respectful — it only creates its own folders (`Cider Bookmarks/`, `Cider Inbox/`) and the library note. It never modifies or reorganizes existing vault content.

### Starter Templates

Cider creates a few templates that work with Obsidian's built-in Templates plugin:

**Bookmark template** (used internally by Cider, but visible to users):
```markdown
---
url:
title:
domain:
tags: []
thumbnail:
captured: {{date}}
cider-bookmark: true
---

# {{title}}

[Open in browser]({{url}})

## Notes

```

**Project template** (for users to copy when starting a project):
```markdown
---
status: active
created: {{date}}
---

# Project Name

## Overview


## Bookmarks & References
<!-- Drag bookmarks from Cider here, or link to vault bookmark files -->

## Notes


## Tasks
- [ ]
```

### Plugin Guidance

Cider can't install Obsidian plugins (that's Obsidian's domain), but it can:

1. **Detect installed plugins** — read `.obsidian/community-plugins.json`
2. **Recommend essential plugins** — show a checklist in Cider's settings:
   - Dataview (required for bookmark library queries)
   - DataCards (required for visual card layouts)
   - Templates (core plugin, for note templates)
   - Calendar (optional, for daily notes)
3. **Show setup status** — green checkmarks for installed, prompts for missing
4. **Link to install instructions** — deep links to Obsidian's plugin browser

If DataCards isn't installed, the Bookmark Library note still works — it just shows a raw code block instead of cards. Cider can display a non-intrusive banner: "Install the DataCards plugin in Obsidian for a visual bookmark library."

### Getting Started Note

Cider creates a `Getting Started with Cider.md` in the vault root:

```markdown
# Getting Started with Cider + Obsidian

## How This Works

**Cider** is your capture tool — bookmarks, quick notes, snippets.
**Obsidian** is your organization tool — projects, linking, deep writing.

You don't need to learn Obsidian to start. Just use Cider the way you
normally do, and your vault fills up automatically.

## Your Workflow

1. **Browsing the web?** Double-tap Option → save a bookmark instantly
2. **Had a thought?** Double-tap Option → Notes tab → jot it down
3. **Found something useful?** Drag text/images into Cider's panel
4. **Working on a project?** Open Obsidian, your captures are already here

## Your Vault Structure

- **Inbox/** — Quick captures from Cider land here. Review and move them
  into project folders when you're ready.
- **Bookmarks/** — Your saved bookmarks with thumbnails and metadata.
  Open "Cider Bookmark Library" to browse them visually.
- **Notes/** — Your notes, accessible from both Cider and Obsidian.
- **Projects/** — Create a folder per project. Link to bookmarks and
  notes as you work.

## Recommended Plugins

For the best experience, install these in Obsidian's Community Plugins:
- [ ] **Dataview** — Powers the bookmark library queries
- [ ] **DataCards** — Renders bookmarks as visual cards
```

### The Payoff

The user's journey:
1. Install Cider. Start capturing bookmarks and notes. No Obsidian needed.
2. Eventually connect to a vault. Cider scaffolds the structure.
3. Existing captures sync to the vault. It's already populated.
4. Open Obsidian — there's content, organization, and a visual bookmark library waiting.
5. Start using Obsidian for deeper work, with Cider as the fast capture layer.

**Cider turns Obsidian from "intimidating blank canvas" into "already useful."**

---

## Two User Journeys

Cider needs to handle two very different onboarding paths gracefully.

### Journey 1: Long-time Cider User Adds Obsidian

**Situation:** User has been using Cider for months. Has 50+ bookmarks organized in folders, a dozen notes. Decides to try Obsidian.

**What Cider does:**
1. User goes to Settings → Connectors → Obsidian → Connect Vault
2. They either browse to an existing vault or create a new one
3. Cider detects it's a new/empty vault → full scaffolding (folders, templates, getting started guide)
4. Cider shows a migration panel:

```
Import Existing Content
─────────────────────────────────
Your Cider library has:
  47 bookmarks (in 5 folders)
  12 notes

What would you like to bring into your vault?

  [x] Bookmarks
      ( ) All bookmarks
      (x) Select folders...
          [x] Development (12 bookmarks)
          [x] Design (8 bookmarks)
          [ ] Recipes (3 bookmarks)
          [x] Research (15 bookmarks)
          [x] Unsorted (9 bookmarks)

  [x] Notes
      (x) All notes
      ( ) Select notes...

  [ ] Start fresh (sync new captures only)

  [Import Selected]  [Skip for Now]
```

5. Cider exports selected content to the vault (bookmarks as `.md` files with frontmatter + thumbnails, notes as `.md` files)
6. Going forward, new captures auto-sync to the vault

**Key detail:** Cider's local storage is unchanged. The vault export is additive. If the user disconnects the vault later, their bookmarks and notes are still in Cider.

### Journey 2: Long-time Obsidian User Installs Cider

**Situation:** Power user with a carefully organized vault — custom folder structure, dozens of plugins, everything just so. They install Cider for fast capture.

**What Cider does NOT do:**
- Does NOT create a bunch of new folders
- Does NOT drop a "Getting Started" guide (they know what they're doing)
- Does NOT reorganize anything
- Does NOT assume they want the default Cider folder structure

**What Cider does:**
1. User goes to Settings → Connectors → Obsidian → Connect Vault
2. Cider detects the vault has existing content (checks for files beyond `.obsidian/`)
3. Shows a minimal setup flow:

```
Connect to Existing Vault
─────────────────────────────────
Vault: ~/Documents/MyVault (342 notes)

Where should Cider put things?

  Bookmarks folder:  [Cider Bookmarks    ] [Browse]
  Quick captures:    [Inbox              ] [Browse]
  Attachments:       [Attachments        ] (from vault config)

  [x] Create bookmark library view (DataCards)
  [ ] Import existing Cider bookmarks into vault

  Detected plugins:
    ✅ Dataview
    ✅ DataCards
    ✅ Templater
    ❌ Templates (core) — not needed, Templater covers this

  [Connect]  [Cancel]
```

4. Cider creates only the Cider Bookmarks folder (or uses whatever folder the user chose)
5. No scaffolding, no templates, no getting started note
6. New captures from Cider go to the user's chosen folders
7. Cider respects the vault's existing attachment path setting

### How Cider Tells the Difference

Simple heuristic: count non-hidden files in the vault root (excluding `.obsidian/`).

- **0-2 files** → New vault → Full scaffolding
- **3+ files** → Existing vault → Minimal setup, ask where things go

User can always override — a "Set up folder structure" button in settings lets someone with an existing vault opt into scaffolding if they want it.

---

## Settings: Connectors Panel

The Settings window gets a new **Connectors** section (in the sidebar, alongside General, Appearance, etc.):

```
Connectors
─────────────────────────────────

Obsidian                                    [Connected ✓]
  Vault: ~/Documents/MyVault
  Bookmarks folder: Cider Bookmarks/
  Inbox folder: Inbox/
  Sync bookmarks to vault: On
  Bookmark library note: Cider Bookmark Library.md

  Plugin Status:
    ✅ Dataview    ✅ DataCards

  [Import Cider Library...]  [Disconnect]

──────────────────────────────────

Notion                                      [Not Connected]
  Connect your Notion workspace to push
  bookmarks and captures.
  [Connect Notion...]                       (Coming Soon)

──────────────────────────────────

Custom Folder                               [Not Connected]
  Sync to any folder (Logseq, etc.)
  [Choose Folder...]                        (Coming Soon)
```

### New CiderConfig Properties

```swift
// Obsidian
var obsidianVaultPath: String?
var obsidianBookmarksFolder: String    // default: "Cider Bookmarks"
var obsidianInboxFolder: String        // default: "Inbox"
var obsidianSyncBookmarks: Bool        // default: true (when connected)
var obsidianBookmarkLibraryFile: String // default: "Cider Bookmark Library.md"

// Panel
var defaultPanelTab: PanelTab          // default: .bookmarks
var lastPanelPosition: CGPoint?        // remember where the user put it
var lastPanelSize: CGSize?             // remember panel dimensions

// Capture
var enableOCRCapture: Bool             // default: true (macOS only initially)
```

---

## Panel UI Design

### Replaces the Command Palette

The command palette is replaced by a simpler floating panel. Instead of a full launcher-style UI (search bar + apps row + content area + footer), Cider shows a single panel with a minimal tab bar.

### Panel Structure

```
┌──────────────────────────────────────────┐
│  Bookmarks │ Notes              [search] │
├──────────────────────────────────────────┤
│                                          │
│   Tab content:                           │
│   - Bookmarks: folder sidebar + browser  │
│   - Notes: file list or editor           │
│                                          │
│                                          │
└──────────────────────────────────────────┘
```

### Tab Bar Behaviors

- **Click a tab** — Switch content within the panel
- **Drag a tab out** — Tear off into a separate floating panel. Now both surfaces are visible. User can have bookmarks on one side and a note editor on the other.
- **Drag a torn-off panel back** — Re-dock the tab into the main panel
- **Double-tap Option** — Toggle ALL Cider panels (show/hide everything at once)

### Bookmarks Tab

The existing BookmarksBrowserView, mostly unchanged:
- Folder sidebar (collapsible)
- Grid / list / masonry display modes
- Drag-and-drop content in
- Inline search filter
- Capture button for active browser tab

### Notes Tab

When no vault connected:
- List of Cider notes
- Click to open in TipTap editor (inline in panel or torn-off)
- New note button

When vault connected:
- Vault folder tree in sidebar
- File list for selected folder
- Click to open in TipTap editor
- New note creates in vault inbox folder
- Search across file names and content

---

## Sync Adapter Interface

For future adapters (Notion, Logseq, custom folder), a common protocol:

```swift
protocol CiderSyncAdapter {
    /// Display name for settings UI
    var name: String { get }

    /// Whether this adapter is configured and ready
    var isConnected: Bool { get }

    /// Push a note to the target system
    func pushNote(_ note: Note, attachments: [Attachment]) async throws

    /// Push bookmark index to the target system
    func pushBookmarkIndex(_ bookmarks: [Bookmark]) async throws

    /// Optional: read notes from the target (for bidirectional sync)
    func fetchNotes() async throws -> [Note]?
}
```

### Adapter Implementations (Priority Order)

1. **ObsidianAdapter** — Filesystem read/write. No API, no auth. Ships first.
2. **CustomFolderAdapter** — Write markdown to any directory. Trivial. Covers Logseq.
3. **NotionAdapter** — Notion API. OAuth flow, database creation. Future.
4. **AppleNotesAdapter** — AppleScript. macOS only. Niche. Future.

---

## Cross-Platform Considerations

### What's Shared Between macOS and Linux

| Layer | macOS | Linux | Shared |
|-------|-------|-------|--------|
| UI Framework | SwiftUI + AppKit | Qt 6 / QML | No (different toolkits) |
| Hotkey Detection | CGEvent tap | KDE global shortcuts / libinput | No |
| Panel Behavior | NSPanel + nonactivating | KWin window rules | No |
| Bookmark Storage | Netscape HTML + JSON | Netscape HTML + JSON | **Yes** |
| Note Storage | Markdown + JSON index | Markdown + JSON index | **Yes** |
| Vault Integration | Read `.obsidian/` config | Read `.obsidian/` config | **Yes** |
| OCR | Vision framework | Tesseract | No (same UX, different engine) |
| Browser Capture | AppleScript + AX API | DBus + xdotool / wlr protocols | No |

### What This Means

- **Data formats are fully portable.** A Cider bookmark collection or note library created on macOS can be opened on Linux and vice versa. No migration needed.
- **UI and platform integration are completely separate.** No shared code between macOS and Linux beyond data formats. This is fine — the platforms are too different to share UI code.
- **Obsidian vault format is the same everywhere.** `.obsidian/app.json` has the same structure on all platforms. Vault integration logic is portable.
- **Design documents apply to both platforms.** This integration design, the data formats, and the UX flows are platform-agnostic. Implementation details differ.

---

## Implementation Phases

### Phase 1: Panel Refactor ✅ Complete
- [x] Replace command palette with floating panel + tab bar (Bookmarks | Notes | Home)
- [x] Double-tap Option toggles panel visibility (show/hide all)
- [x] Bookmarks tab: BookmarksBrowserView with folder sidebar
- [x] Notes tab: NotesBrowserView + TipTap editor
- [x] Home tab: library feed (bookmarks + notes + date cards + contacts) + Continue section
- [x] Saved views as custom tabs, folder sidebar, workspace organization
- [x] Inline search within each tab
- [x] Trash + undo system, acrylic panel, custom shadows, resize handles

### Phase 2: Obsidian Vault Connection

**Foundation already in place via Linked Sources (Feb 2026):**
- [x] Open/edit any `.md` file in the TipTap editor via `NotesViewModel.openExternalFile`
- [x] Filesystem watching — live updates when external tools modify files
- [x] Sort by filesystem mtime — most recently touched file floats to top
- [x] mtime integrity — opening/closing a file in Cider never bumps the filesystem timestamp
- [x] Files save back to their original path in place (no copying, no importing)
- [x] Source detail view — browse a folder's `.md` files in card/grid/masonry layout
- [x] Right-click → "Open in Default App" for files that need native Obsidian features

**Still needed for Obsidian specifically:**
- [ ] `[[wikilinks]]` — TipTap renders them as raw text; needs an extension to style + resolve them
- [ ] YAML frontmatter (`---`) — should be hidden or rendered cleanly, not shown as raw text
- [ ] Nested folder scanning — `ExternalSourceScanner` is likely flat; Obsidian vaults have arbitrary depth
- [ ] `.obsidian/` folder exclusion — config directory must be filtered from file lists
- [ ] Vault discovery (scan known paths + read `~/Library/Application Support/obsidian/obsidian.json`)
- [ ] Read `.obsidian/app.json` — attachment folder path, new file location settings
- [ ] Vault path setting in CiderConfig + Connectors settings panel
- [ ] Vault onboarding: scaffold folder structure for new/empty vaults
- [ ] Existing vault detection: minimal setup, ask where to put things
- [ ] Create "Getting Started" note and starter templates (new vaults only)
- [ ] Detect installed plugins, show recommendations in settings
- [ ] Save images/attachments to vault attachment folder
- [ ] Migration flow: import existing Cider library into vault (selective)

### Phase 3: Bookmark Library in Vault
- [ ] Export bookmarks as individual .md files with frontmatter
- [ ] Copy thumbnail images to vault attachment folder
- [ ] Auto-generate Bookmark Library note with DataCards query
- [ ] Sync bookmark changes (create/update/delete) to vault files
- [ ] Detect DataCards plugin, prompt if missing

### Phase 4: Launcher Integration
- [ ] URL scheme: `cider://capture`, `cider://search?q=...`, `cider://show`
- [ ] Raycast extension: search bookmarks/notes, capture active tab, toggle panel
- [ ] Alfred workflow: equivalent capabilities

### Phase 5: Capture Enhancements
- [ ] OCR text extraction via Vision framework
- [ ] Quick snippet capture from clipboard
- [ ] Vault inbox folder for quick captures

### Phase 6: Polish & Parity
- [ ] Cross-reference bookmarks and notes
- [ ] Note tagging (parity with bookmarks)
- [ ] Note folders in Cider's local storage (for non-vault users)
- [ ] Search across bookmarks + notes in unified results

### Phase 7: Expansion (Future)
- [ ] Notion sync adapter
- [ ] Custom folder adapter
- [ ] Mobile companion app (iOS/Android)
- [ ] Cross-device bookmark sync
