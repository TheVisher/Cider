# Cider Pivot Strategy: Capture & Reference Layer

> **Status:** Implemented (Feb 2026)
> **Context:** Cider pivoted from a command palette for window management to a panel-only capture and reference tool. The command palette, window tiling, and window cycling features have been removed. The app is now a floating NSPanel with tabbed content (Home, Bookmarks, Notes), a universal folder sidebar, and title bar controls.

---

## The Pivot

### From: Window Manager Replacement
Cider's original vision — replace Dock, Stage Manager, and Spotlight with a unified palette — puts it in direct competition with the OS. macOS already manages windows. KDE already manages windows. Fighting the OS is an uphill battle with diminishing returns.

### To: Capture & Reference Layer
Cider becomes the **fastest way to get something off your screen and into your knowledge base**. A native floating overlay that's always a double-tap away, purpose-built for capturing bookmarks, snippets, images, and notes — then routing them into Obsidian, Notion, or wherever your knowledge lives.

### Why This Works
- **Fills a real gap.** Obsidian's web clipper is browser-only. Raindrop and Pocket are SaaS with subscriptions. None of them give you a native desktop overlay you can drag content into mid-flow.
- **Plays to existing strengths.** The command palette UX, the non-activating NSPanel, multi-browser capture, and the bookmark system are all production-ready today.
- **Drops the weakest part.** Window tiling and cycling are fighting the OS. Capture and reference have no OS-level competitor.
- **Standalone value + integration value.** Bookmarks work without Obsidian. Obsidian integration makes it better but isn't required.

---

## The Product

### Core Identity
**Cider is a set of floating capture and reference panels that live on top of everything.**

Double-tap Option from anywhere. Your bookmarks and notes appear alongside your work — not as a launcher that takes over, but as companion panels you can drag content into. Optionally sync everything into your Obsidian vault or other knowledge base.

### UI Model: Panels, Not a Palette

Cider is **not a command palette or launcher.** Users who want a launcher already have Raycast, Alfred, or Spotlight. Cider doesn't compete with those — it complements them.

Cider is a **floating panel** with a minimal tab bar:

```
┌─────────────────────────────────┐
│  Bookmarks │ Notes    [search]  │
├─────────────────────────────────┤
│                                 │
│   (bookmark browser or          │
│    notes list/editor)           │
│                                 │
│                                 │
└─────────────────────────────────┘
```

**Key behaviors:**
- **Double-tap Option** — Toggle the panel (show/hide). One action for everything.
- **Tab bar** — Switch between Bookmarks and Notes within the panel.
- **Tear-off tabs** — Drag a tab out to create a separate floating panel. Now you have bookmarks AND a note visible at the same time, both floating over your browser.
- **Non-activating** — Never steals focus. Your cursor stays in your document.
- **Resizable, draggable** — Position it wherever you want on screen.
- **Small search bar** — Quick filter within the active tab. For cross-tab or deep search, use Raycast/Alfred integration.

**Why not a palette?**
- Launchers (Raycast, Alfred) already do the "search bar that appears and disappears" pattern. Another one is redundant.
- Palettes disappear when you click away. Panels stay open alongside your work. That's the whole point — you need Cider visible while you drag content from the browser.
- A palette is a container for tabs. If there are only two tabs (Bookmarks, Notes), the container is unnecessary overhead. Just show the content directly.
- Users who have Raycast can invoke Cider's panels and search through Raycast commands. Users without a launcher get the double-tap hotkey. Both work.

### Two Halves

**1. Bookmarks & Web Capture (Standalone Feature)**
This is Cider's primary product surface — the thing that makes it useful even without any integrations. Cider is a native bookmark manager with:
- One-hotkey capture from any browser
- Auto-enrichment (titles, thumbnails, Open Graph metadata)
- Folders, tags, search, multiple display layouts
- Thumbnail management (drag images onto cards)
- Exportable (Netscape HTML for portability)

**2. Notes & Knowledge Capture (Integration Feature)**
Quick notes, text snippets, clipboard captures, and OCR. This is where Obsidian integration lives:
- Cider can read/edit markdown files directly from an Obsidian vault
- Drag images from the web into a vault note without opening Obsidian
- Capture snippets into an inbox folder
- Preserve frontmatter, wiki-links, and syntax Cider doesn't understand

---

## The Bookmark Question

### Should bookmarks live in Obsidian?

**No. Bookmarks should be Cider's dedicated domain.**

Reasoning:

1. **Obsidian isn't great at bookmarks.** You can store a URL in a markdown file, but you lose thumbnails, metadata enrichment, visual grid/masonry layouts, and the browsing experience that makes bookmark managers useful. A bookmark-as-markdown-file is just a link with extra steps.

2. **Standalone value matters.** If Cider requires Obsidian to be useful, the addressable market shrinks dramatically. Bookmarks-as-a-feature work for anyone — Obsidian users, Notion users, people who use neither.

3. **Different data shape.** Bookmarks are structured data (URL, title, thumbnail, tags, folder). Notes are freeform content. Forcing bookmarks into markdown files loses the structure that makes them browsable.

4. **Export, not storage.** Cider can export/sync bookmarks *to* Obsidian (as a markdown index file, a daily digest, or individual link notes) without using Obsidian as the storage backend. The bookmarks live in Cider; derivatives can live in the vault.

### The Right Split

| Concern | Owner | Why |
|---------|-------|-----|
| Bookmark storage & browsing | Cider | Structured data needs a dedicated UI |
| Quick notes & captures | Cider (synced to vault) | Fast input, vault is the destination |
| Deep note editing & linking | Obsidian | Graph view, backlinks, plugins |
| Organization & projects | Obsidian | Folders, templates, workflows |

Cider handles **input and reference**. Obsidian handles **structure and depth**.

---

## Backend-Agnostic Architecture

### The Bigger Idea
Cider doesn't have to be an "Obsidian companion." It can be a capture tool that **pipes into any knowledge base**:

- **Obsidian** — Write markdown files directly to the vault filesystem
- **Notion** — Push via Notion API (databases for bookmarks, pages for notes)
- **Apple Notes** — AppleScript integration
- **Logseq** — Markdown files, similar to Obsidian
- **Local-only** — Cider's own storage (the default, works today)
- **Custom folder** — Any markdown-compatible tool that watches a directory

### Storage Layer Design
```
Cider Capture Layer (always present)
    |
    v
[Cider Local Storage] -----> [Sync Adapters]
    |                              |
    |- bookmarks.html              |- ObsidianAdapter (filesystem)
    |- bookmarks_metadata.json     |- NotionAdapter (API)
    |- notes/*.md                  |- LogseqAdapter (filesystem)
    |- .thumbnails/                |- AppleNotesAdapter (AppleScript)
    |- .originals/                 |- CustomFolderAdapter (filesystem)
    |- .attachments/
```

### How This Works
1. **Cider always stores locally first.** Your data exists on your machine regardless of what backends are connected.
2. **Sync adapters push content out.** Each adapter knows how to format and deliver content to its target. Obsidian adapter writes `.md` files to the vault. Notion adapter calls their API.
3. **Bookmarks stay in Cider.** They can be *exported* to backends (as markdown link pages, Notion database entries, etc.) but Cider owns the canonical copy.
4. **Notes can be bidirectional.** For Obsidian specifically, Cider can read and edit vault files directly since they're just markdown on disk. For API-based backends like Notion, it's push-only.

### Integration Priority
1. **Local-only (done)** — Works today, no setup required
2. **Obsidian** — Filesystem-based, no API needed, large enthusiast community
3. **Custom folder** — Trivial to implement, covers Logseq and similar tools
4. **Notion** — API-based, requires auth, but large user base
5. **Apple Notes** — AppleScript, niche but nice for macOS-only users

---

## What Already Exists (macOS Codebase Assessment)

### Production-Ready Today

**Bookmarks** — Fully mature.
- Multi-browser capture (Safari, Chrome, Firefox, Arc, Brave, Edge, Zen) via AppleScript, AX API, and clipboard fallback
- Auto-enrichment: page titles, Open Graph thumbnails, favicons
- Folders with drag-to-organize, tags, search
- Display modes: list, grid, masonry with multiple card sizes
- Thumbnail management: drag-and-drop, auto-fetch, smart icon detection
- Dual-format export: Netscape HTML + JSON metadata
- Auto-capture copied URLs with optional confirmation dialog
- Hotkeys: Option+B (open panel), Option+Shift+B (capture active tab)

**Notes** — Solid.
- TipTap (WebKit-based) rich text editor with markdown storage
- Image drag-and-drop with attachment management
- Snapshot history (20 versions, 30-day retention)
- External file change detection with conflict resolution
- Find/replace within notes
- Hotkey: Option+N

**Command Palette Integration** — Complete.
- Three tabs: Windows, Notes, Bookmarks
- Unified search across all tabs
- Keyboard navigation throughout
- Non-activating NSPanel, appears on active monitor

### Not Yet Built

| Feature | Difficulty | Notes |
|---------|-----------|-------|
| Obsidian vault discovery | Low | Find `.obsidian/` directories, read `app.json` for attachment path |
| Obsidian file editing | Medium | Preserve frontmatter YAML, `[[wiki-links]]`, callout syntax |
| Web clipping (page-to-markdown) | Medium | Convert page content to markdown, not just bookmark the URL |
| OCR / text extraction | Medium | macOS Vision framework (`VNRecognizeTextRequest`) is built-in |
| Sync adapters (Notion API, etc.) | Medium-High | Auth flow, API mapping, rate limiting |
| Cross-referencing (bookmark <-> note) | Medium | Link a bookmark to related notes and vice versa |
| Note tagging & folders | Low | Bookmarks have this already, notes don't yet |

---

## User Experience Flows

### Capture Bookmark
1. Browsing the web, find something interesting
2. Double-tap Option → Cider panel appears alongside your browser
3. Click "Capture" (or Option+Shift+B from anywhere) → URL, title, thumbnail saved
4. Optionally tag it or drop it in a folder
5. Double-tap Option to hide, or leave it open and keep browsing

### Quick Note
1. Reading an article, want to capture a thought
2. Double-tap Option → panel appears, switch to Notes tab
3. Type the note, paste a snippet, drag in an image
4. If connected to Obsidian: saved directly to vault inbox
5. Leave the panel open while you keep reading, or hide it

### Drag Content Into a Note (Tear-Off Flow)
1. Researching a topic, want to collect images and text into a note
2. Double-tap Option → panel appears on Bookmarks tab
3. Drag the Notes tab out → now you have a separate floating notes panel
4. Position the notes panel next to your browser
5. Drag images, text, URLs from the browser directly into the note
6. Everything saves to your Obsidian vault automatically

### Search via Raycast/Alfred
1. Working in any app, need to find a saved bookmark
2. Open Raycast → type "cider swift documentation"
3. Results show matching bookmarks and notes from Cider
4. Select one → opens the URL, or opens the note in Cider's panel

### Capture via Raycast/Alfred
1. On a page you want to bookmark
2. Open Raycast → type "cider save"
3. Cider captures the active browser tab in the background
4. Confirmation appears — bookmark saved with enrichment

---

## Product Positioning

### Tagline Options
- "Capture anything. From anywhere. Instantly."
- "Your desktop's capture layer."
- "The fast lane into your knowledge base."

### Target Users
1. **Obsidian power users** who want faster capture without browser extensions
2. **Bookmark hoarders** who want a native, local-first manager (no SaaS subscriptions)
3. **Researchers & writers** who collect references while browsing
4. **Anyone who saves links** and wishes they could find them later

### Competitive Landscape

| Tool | Capture | Floating Panels | Local-First | KB Integration | Works With Launchers |
|------|---------|----------------|-------------|----------------|---------------------|
| **Cider** | Hotkey + panel | Yes | Yes | Obsidian, Notion, etc. | Yes (extends them) |
| Raindrop.io | Browser ext | No | No (cloud) | No | No |
| Pocket | Browser ext | No | No (cloud) | No | No |
| Obsidian Clipper | Browser ext | No | Yes | Obsidian only | No |
| Notion Clipper | Browser ext | No | No (cloud) | Notion only | No |
| Alfred/Raycast | Hotkey | No (dismiss on click) | Yes | No | N/A (they ARE launchers) |

Cider's unique position: **native floating panels + local-first + extends your existing launcher + multi-backend sync.** Not another launcher — a companion layer that launchers can't provide.

---

## What Gets Dropped / Disabled

### Removed
- **Command palette** — Replaced by floating panel with tab bar. The palette was a container for tabs; the panel shows content directly.
- **Pinned apps row** — No longer needed. Users have their dock or launcher for app launching.
- **Palette search bar** — Replaced by a small inline search within each tab + Raycast/Alfred integration for power search.
- **Palette footer bar** — Actions move into the panel's tab-specific UI.

### Disabled (Code Stays)
- **Window tiling** — Disabled via `enableDragToTile`, `enableTilingHotkeys`, `enableDynamicTiling` flags. Can re-enable later.
- **Option+Tab window cycling** — Disabled via `enableOptionTabCycling` flag. Cleanly isolated.
- **Window list tab** — Removed from default tabs. Could return as an optional third tab if users request it.

---

## Resolved Decisions

### 1. UI Model — Floating panel with tear-off tabs, not a command palette

The command palette is replaced by a simpler floating panel with a `Bookmarks | Notes` tab bar. Double-tap Option toggles visibility. Tabs can be dragged out into separate panels for side-by-side use. No pinned apps row, no complex search bar, no footer. Window management features (tiling, cycling) are disabled via existing feature flags.

**Launcher integration:** Cider exposes Raycast/Alfred extensions for search and capture commands. Users who have a launcher search through it. Users who don't get the panel's inline search + double-tap hotkey.

**Codebase impact:** Significant simplification. The palette view, palette search, palette footer, and apps row can be removed. The existing BookmarksPanel and NotesPanel become the primary (and only) UI surfaces, unified under a shared panel with a tab bar.

### 2. Obsidian Integration — Full vault browsing

If we're in the vault filesystem to save notes, everything is already accessible. Cider can browse the vault folder structure, open/edit any file, and search vault contents through the palette. The TipTap editor already handles markdown — extending it to read vault files is natural.

**See:** `INTEGRATION_DESIGN.md` for full architecture.

### 3. Web Clipping — Snippet capture, not full-page clipping

No full-page article clipping. No browser extension. Cider's capture philosophy is **quick and small**:
- Drag-and-drop snippets (text, images) into Cider panels
- Clipboard paste (text, URLs)
- OCR via macOS Vision framework (`VNRecognizeTextRequest`) for non-selectable text, screenshots, images
- Bookmark capture for URLs (already built)

This aligns with the "never break flow" principle — you capture the piece you care about, not the whole page.

### 4. Linux — Mac first, design for cross-platform

macOS is the priority. Linux development continues in parallel as a side project. All architectural decisions (data formats, storage layout, sync protocols) must account for cross-platform compatibility. With window management deprioritized, the Linux version gets much simpler — no KWin/DBus needed, just the capture palette + storage.

### 5. Monetization — Free now, mobile sync later

Cider is **free and open-source** for desktop. No paywalls on any current feature. Future revenue path: a paid mobile companion app that syncs bookmarks and captures across devices. This keeps the desktop product accessible while monetizing the hardest engineering problem (cross-device sync). Architecture should be sync-ready from the start even though mobile is not immediate.

### 6. Launcher Integration — Extend Raycast/Alfred, don't compete

Cider is not a launcher. It extends existing launchers with capture and reference capabilities they can't provide (floating panels, drag-and-drop). Cider exposes:
- **Raycast extension** — Search bookmarks/notes, capture active tab, open Cider panel
- **Alfred workflow** — Same capabilities via Alfred's workflow system
- **URL scheme** — `cider://capture`, `cider://search?q=...`, `cider://show` for universal integration
- Users without a launcher use the double-tap hotkey + panel's inline search
