# Cider Vault Vision: AI-Powered Life Dashboard

> **Status:** Vision / exploratory — not on the 1.0 roadmap. This document captures the long-term direction for Cider's architecture and philosophy.

---

## The Problem

People have files scattered everywhere — photos on their phone, bank statements in Downloads, contractor quotes in email, kids' event flyers as screenshots, grocery receipts, cell phone bills. Organizing all of this manually is tedious. Everyone is already paying for AI tools (Claude, ChatGPT, etc.) that can do this work.

## The Vision

**Cider becomes a beautiful presentation layer over a raw filesystem vault.** The vault is a single folder where users dump everything. External AI tools (CLI or desktop) do the heavy lifting — sorting, tagging, summarizing, categorizing. Cider watches the vault and renders it as a polished dashboard.

Cider remains a fast, simple, double-tap-Option floating panel. The vault doesn't change what Cider is — it changes the backend. Instead of proprietary storage, Cider reads from a folder of standard files. Same speed, same simplicity, better foundation.

### Key Principles

1. **Dump everything, organize later.** The vault accepts any file type — photos, PDFs, documents, screenshots, notes, bookmarks. No friction on capture.
2. **Filesystem is the source of truth.** Folders in the vault = folders in Cider. No proprietary metadata databases. Move a file in Finder, it moves in Cider.
3. **Bring your own AI.** Users point Claude Code, ChatGPT desktop, or any CLI tool at the vault. Tell it "organize my inbox" or "tag everything from this month."
4. **"Cider is the stage, not the stagehand."** This is the product truth. Cider's job is to present information beautifully — cards, grids, dashboards, search. The AI does the categorization, tagging, and summarization. Cider doesn't need its own intelligence. It needs to be the best place to *see* the results of intelligence. This line should guide every feature decision: if it's stagehand work, let the user's AI tools handle it. If it's stage work — making things visible, beautiful, searchable, browsable — that's Cider.
5. **No lock-in.** Users own their files in standard formats. Cider adds value through presentation, not proprietary storage. If you leave Cider, you still have a well-structured vault with all your files in normal formats.
6. **View, don't edit (for complex types).** Cider can view any file type — images, PDFs, video, audio, spreadsheets. For notes and bookmarks, Cider is the editor. For complex types (image editing, spreadsheet editing), users open their preferred external editor. Cider is a viewer + launcher, not a replacement for specialized tools.

## How It Works

### Capture Flow

```
User's life (photos, docs, bills, screenshots, memes, etc.)
    │
    ▼
Cider Vault (single folder on disk)
    │
    ├── Inbox/          ← raw dumps land here (mobile sync, drag-drop, etc.)
    ├── Photos/         ← AI-sorted by person, location, type
    ├── Finance/        ← bank statements, bills, receipts
    ├── Kids/           ← school events, activities
    ├── Projects/       ← contractor quotes, home improvement
    ├── Notes/          ← markdown files
    ├── Bookmarks/      ← .webloc files or URL lists
    └── ...             ← any folder structure the AI or user creates
```

### Organization Flow

```
1. User dumps files into vault (or Inbox/ subfolder)
2. User opens their CLI AI tool, cd's into the vault
3. "Organize everything in my inbox"
4. AI moves files into folders, writes sidecar metadata, tags content
5. User opens Cider — everything appears organized
```

### What AI Tools Can Do

- Sort photos by face, location, scene type, date
- Categorize documents (bills → Finance/, quotes → Projects/)
- Extract dates from event flyers → surface in Coming Up section
- Summarize PDFs and long documents
- Tag files with semantic labels
- Create folder structures based on content patterns
- Write sidecar `.cider-meta.json` files with extracted metadata

### Cider's Role

- **Render cards** based on file type (image → photo card, .md → note card, .pdf → document card, .webloc → bookmark card)
- **View any file type** — images, PDFs, video, audio via native macOS frameworks (PDFKit, AVKit, QuickLook). No custom editors needed for viewing.
- **Read sidecar metadata** for tags, summaries, extracted dates
- **Watch filesystem** via FSEvents for instant updates when AI tools make changes
- **Provide saved views, search, stacks** — all reading from the filesystem
- **"Open in..." button** for complex file types — launches the user's preferred external editor

### Viewing File Types

Cider leverages macOS/iOS built-in frameworks for viewing — no custom renderers needed for most types:

| File Type | Framework | Effort |
|-----------|-----------|--------|
| Images (JPEG, PNG, etc.) | SwiftUI `Image` / `NSImage` | Trivial |
| PDFs | `PDFKit` | Trivial |
| Video/Audio | `AVKit` / `AVPlayer` | Trivial |
| Spreadsheets, Office docs | `QLPreviewPanel` (Quick Look) | Trivial |
| Everything else | Quick Look fallback → icon + metadata card | Trivial |

For files Quick Look can't preview, Cider shows a file icon, name, size, date, and tags from sidecar metadata, with an "Open in..." button.

## Cross-Platform Architecture

### The Core Model

Convex is the shared cloud database. The vault is a desktop-specific local mirror of real files.

```
Web App (full functionality)     iOS App (full functionality)
    │                                │
    ▼                                ▼
                  Convex
        (shared cloud database)
                    │
                    ▼
            Desktop App
                    │
                    ▼
              CiderVault/
        (real files on disk)
                    │
                    ▼
           AI tools (Claude Code,
           ChatGPT, Codex, etc.)
```

- **Convex** = shared cloud database, all platforms read/write here
- **CiderVault/** = desktop-only local mirror as real files (for AI tools, Finder access, offline use, no lock-in)
- **Web app** = full Cider experience, talks directly to Convex
- **iOS app** = full Cider experience, talks to Convex, has local vault in app sandbox
- **Desktop app** = full Cider experience, talks to Convex AND syncs to/from vault on disk

### Two-Way Sync

Edits can happen on any platform:

```
Web/iOS edits → saved to Convex → desktop pulls down to vault files
Desktop edits (vault files) → pushed to Convex → web/iOS see updates
AI tool edits (vault files) → desktop detects via FSEvents → pushed to Convex
```

### Web App — Full Functionality

The web app is NOT capture-only. It's a full Cider experience for scenarios like:
- Using a locked-down work computer where you can't install apps
- Accessing your vault from any browser, anywhere
- Creating/editing notes, saving bookmarks, tagging items, organizing folders

The web app reads/writes Convex directly. It doesn't need the vault — that's a desktop concept.

### iOS App — Local Vault + Sync

The iOS app maintains a local vault in its sandboxed Documents directory:
```
App Sandbox/Documents/CiderVault/
├── Inbox/
├── Notes/        ← .md files
├── Bookmarks/    ← .webloc or bookmark JSON
├── Photos/       ← actual JPEGs
└── ...
```

- Same file formats as desktop (JPEG, markdown, PDF, etc.)
- Exposed via `FileProvider` so users can browse in iOS Files app
- Syncs to/from Convex for cross-device access

### iOS Photo Capture

**Share Sheet extension** (primary method):
- User takes a photo → taps Share → taps Cider
- Photo saved as JPEG to local vault's `Inbox/`
- Syncs to Convex → downloads to Mac vault
- Opt-in per photo, no surprise data usage

**Camera roll import** (optional):
- User grants photo library access
- Cider imports selected photos when app is open
- Apple restricts true 24/7 background sync — import happens when user opens the app

**Data optimization:**
- Sync **thumbnails** through Convex (small, fast, cheap)
- Full-resolution files sync on-demand or via iCloud Drive
- Browsing vault on other devices is fast, pulling full 4K photos only happens on tap

## Sync Provider Architecture

### Abstracted Sync Layer

Users choose their sync backend. Convex is the default. Others are optional.

```swift
protocol SyncProvider {
    func push(item: VaultItem) async throws
    func pull() async throws -> [VaultItem]
    func observe(onChange: @escaping ([VaultItem]) -> Void)
}

class ConvexSyncProvider: SyncProvider { ... }  // Default
class CloudKitSyncProvider: SyncProvider { ... } // iCloud option
// Future: DropboxSyncProvider, GoogleDriveSyncProvider, FilenSyncProvider, etc.
```

The rest of the app doesn't care which provider is active. Swap backends in settings.

### Sync Provider Options

| | Convex (default) | iCloud / CloudKit | Dropbox / Google Drive / Filen |
|---|---|---|---|
| **Setup** | Cider account | Apple ID | Existing account |
| **Cost** | Free tier / paid | User's iCloud storage | User's existing plan |
| **Web app** | Email/password auth | Apple ID via CloudKit JS | OAuth |
| **Shared vaults** | Easy (multi-user DB) | Limited (CKShare) | Shared folders |
| **Non-Apple devices** | Works everywhere | Apple ecosystem + web | Works everywhere |
| **Speed** | Very fast (WebSocket) | Good (Apple-controlled) | Varies |

### iCloud / CloudKit Details

- **Desktop + iOS:** Native CloudKit frameworks, straightforward
- **Web app:** Apple provides CloudKit JS — user authenticates with Apple ID via OAuth, web app reads/writes CloudKit data
- CloudKit JS is functional but less polished than Convex — slightly slower queries, clunkier auth flow

### Adding Future Providers

Any cloud storage service that has an API can become a SyncProvider:
- **Dropbox:** REST API + webhooks for change notifications
- **Google Drive:** REST API + push notifications
- **Filen:** API for encrypted storage
- **Self-hosted:** Syncthing, WebDAV, etc.

Each just conforms to the same `SyncProvider` protocol. The vault on disk works identically regardless of which provider syncs the data.

## Shared Vaults / Family Sharing

### How It Works

Since Convex is a multi-user database, shared vaults are straightforward:

```
Your girlfriend (iOS only)     You (Desktop + iOS + Web)
    │                              │
    ▼                              ▼
        Convex (shared collection)
                  │
                  ▼
           Your CiderVault/
            ├── Your stuff/
            └── Shared/    ← her photos/notes land here
```

- Each user has their own Cider account
- Users can link accounts and create shared collections
- Shared items sync to both users' vaults
- Scoped sharing — share photos but not notes, or everything
- Phone-only users (like a partner who doesn't use a computer) get the full experience through the iOS app backed by Convex — they never need a desktop vault

### With iCloud

Shared vaults are harder with CloudKit (`CKShare` is more record-level than workspace-level). This is one reason Convex is the recommended default.

## Embedded Terminal / Chat Window

### Concept

A built-in terminal view inside Cider, pre-seeded into the vault directory. Not a custom AI chat — just a real terminal where users run whatever CLI tool they prefer.

### How It Works

- User opens chat/terminal panel in Cider
- It's a real PTY-backed terminal (using SwiftTerm or similar)
- Working directory is automatically set to `CiderVault/`
- User runs `claude`, `codex`, `chatgpt`, or any CLI tool
- AI tool has full access to vault files, organizes/tags/summarizes
- Cider picks up changes instantly via FSEvents

### Why This Fits "Bring Your Own AI"

This doesn't lock users into any AI. It's literally just a terminal. Users run whatever they want:
```
$ claude "organize my inbox"
$ codex "tag all photos from last week"
$ chatgpt "summarize the PDFs in Finance/"
$ python my_custom_script.py
```

The terminal is a convenience — same thing as opening Terminal.app and `cd`-ing to the vault, but integrated into Cider's UI.

## Metadata Strategy

### Sidecar Files

Instead of a proprietary database, metadata lives alongside files as `.cider-meta.json`:

```
Photos/
├── vacation-2026-hawaii/
│   ├── IMG_001.jpg
│   ├── IMG_002.jpg
│   └── .cider-meta.json     ← tags, descriptions, face IDs, location
├── memes/
│   ├── funny-cat.png
│   └── .cider-meta.json
```

A `.cider-meta.json` sidecar file per directory (or per file for rich items):

```json
{
  "items": {
    "IMG_001.jpg": {
      "tags": ["hawaii", "beach", "family"],
      "people": ["Dad", "Mom", "Kids"],
      "date": "2026-07-15",
      "summary": "Family at Waikiki Beach at sunset"
    }
  }
}
```

### Why Sidecar Files

- **Human-readable** — it's JSON, anyone can open it
- **AI-writable** — any CLI tool can create/update it
- **Cider-readable** — the app knows how to parse it
- **Non-destructive** — removing Cider doesn't touch your files
- **Interoperable** — Cider UI writes the same format as AI tools

### How Sidecar Works

"Sidecar" = a small metadata file that rides alongside the real files (like a sidecar on a motorcycle). When you tag a photo in Cider's UI, it writes to the `.cider-meta.json` in that folder. When an AI tool tags files, it writes to the same file. Both read the same format.

## Vault Roadmap

This is an evolution, not a rewrite. The roadmap is split into **core milestones** (the ship path) and a **backlog** (everything else, to be prioritized after core is proven).

---

### Core Milestones

#### Milestone 1: The Magical Loop
> *Prove the concept. Drop file → organize → Cider reflects it.*

- [x] Real vault folder on disk (`~/CiderVault/` or user-configured path)
- [x] Cider mirrors vault folder structure (folders = real directories on disk)
- [x] FSEvents watching — external changes reflect instantly in Cider UI
- [x] Vault index (`.cider-index.json`) for fast item lookup without scanning
- [x] Notes physically move to vault folders when assigned
- [x] Unsorted/ directory for unfiled items (hidden from Cider sidebar)
- [x] Sidecar `.cider-meta.json` reading (tags, summaries, dates rendered in UI)
- [x] Sidecar writing from Cider UI (tag/edit metadata → writes to sidecar file)
- [x] Search includes sidecar metadata tags in matching

#### Milestone 2: Universal Viewing
> *Cider can display any file type dropped into the vault.*

- [x] Card type inference from file extension
- [x] Image viewer (SwiftUI `Image` / `NSImage`)
- [x] PDF viewer (`PDFKit`)
- [x] Video/audio player (`AVKit` / `AVPlayer`)
- [x] Quick Look fallback for everything else
- [x] "Open in..." button for external editing
- [x] File icon + metadata card for unknown types
- [ ] Vault file detail panel polish — match the look/feel of bookmark/note detail panels for all file types (image, PDF, video, audio). Toolbar actions, metadata sidebar, consistent layout, proper sizing.

#### Milestone 3: AI Workspace
> *Power-user AI workspace inside Cider. Users run any CLI tool against the vault.*

- [x] SwiftTerm-based terminal view in Cider panel
- [x] Working directory pre-seeded to vault folder
- [x] Terminal panel toggle in UI
- [x] Works with Claude Code, Codex, ChatGPT CLI, custom scripts — anything the user has installed

#### Milestone 4: Data Migration (Personal)
> *Move existing Cider data into the vault format. Not a user-facing migration tool — just personal data preservation.*

- [ ] Export bookmarks from current JSON → vault files
- [ ] Export notes → `.md` files in vault
- [ ] Export folders → vault directories
- [ ] Export tags/metadata → sidecar files

#### Milestone 5: Convex Sync
> *Default sync provider. Desktop syncs vault ↔ Convex. Web and iOS consume synced data.*

Internally treated as sub-phases:

- [ ] **5A:** `SyncProvider` protocol abstraction + Convex provider (desktop vault ↔ Convex two-way sync)
- [ ] **5B:** Web app reads synced vault data from Convex
- [ ] **5C:** Web app writes to Convex (full read/write — notes, bookmarks, tags, folders)
- [ ] **5D:** iOS app reads/captures via Convex sync (browse + capture to Inbox)

#### Milestone 6: iOS Capture
> *iOS becomes a real capture point. Browse + capture via Convex, no local vault complexity yet.*

- [ ] Share Sheet extension for photo/file capture → Inbox
- [ ] Thumbnail sync through Convex (small/fast/cheap), full-res on demand
- [ ] Browse vault contents on iOS via Convex
- [ ] Create/edit notes and bookmarks on iOS

---

### Backlog (Post-Core)

> Everything below is captured so nothing gets lost. To be prioritized and scheduled after core milestones are proven and shipped. New ideas get added here.

#### Alternative Sync Providers
- [ ] iCloud/CloudKit provider (desktop + iOS native CloudKit frameworks)
- [ ] CloudKit JS integration for web app (Apple ID OAuth)
- [ ] Dropbox provider (REST API + webhooks)
- [ ] Google Drive provider (REST API + push notifications)
- [ ] Filen provider (encrypted storage API)
- [ ] Self-hosted options (Syncthing, WebDAV)

#### Shared Vaults / Family Sharing
- [ ] Account linking between Cider users
- [ ] Shared collections in Convex
- [ ] Scoped sharing (by folder, by type, or everything)
- [ ] Phone-only users get full experience via iOS app + Convex
- [ ] Shared vault permission model (granular vs. all-or-nothing)

#### iOS Local Vault
- [ ] Local vault in iOS app sandbox (same file formats as desktop)
- [ ] `FileProvider` integration (vault visible in iOS Files app)
- [ ] Local/remote reconciliation for offline edits

#### Photo Intelligence
- [ ] Face grouping / recognition
- [ ] Scene/location inference
- [ ] Photo deduplication
- [ ] Camera roll import (bulk import selected photos when app is open)

#### Advanced Vault Features
- [ ] SQLite cache for fast search/filtering across large vaults (10k+ files)
- [ ] Background auto-organize agent (watches Inbox, auto-sorts via AI)
- [ ] Default "organize" prompt/script shipped with Cider for users to run with any AI tool
- [ ] Smart folders / saved searches (virtual folders based on tags, dates, types)
- [ ] Vault statistics dashboard (storage usage, file counts by type, organization score)

#### Drop Built-In AI (Optional)
- [ ] Remove built-in auto-tagging/summarization if "bring your own AI" proves sufficient
- [ ] Or keep built-in AI as convenience layer for users without CLI tools
- [ ] Evaluate based on user feedback after AI Workspace ships

#### Distribution & Updates (Deferred from 1.0)
- [ ] Sparkle Auto-Updater — add Sparkle package to Xcode, test real update flow (code is written, needs Xcode wiring + signing test)
- [ ] Mac App Store listing — App Store Connect setup, sandboxing audit, pricing decision, dual distribution (direct + MAS)

#### New Card Types (Deferred from 1.0)
- [ ] Books card type — `Book` model, fields (title, author, cover, reading status, rating, notes), `BookStorage`, card/list views, manual entry. Full book system (ISBN lookup, Goodreads import, progress tracking, highlights, statistics, shelf display) is further backlog.
- [ ] Documents card type — `Document` model, fields (title, file path, file type, size, thumbnail), `DocumentStorage`, drag-drop ingestion, card views, open in default app / reveal in Finder. Full document system (filesystem watcher, OCR, full-text search, window-based capture) is further backlog.

#### Screen Capture (Deferred from 1.0)
- [ ] Screen capture polish — Date Card and Contact OCR routing improvements, image preview in toast, OCR noise filtering. Core functionality works, needs edge case polish.

#### Whiteboard Expansion (Deferred from 1.0)
- [ ] Drag library items onto Excalidraw canvas (bookmarks, notes, images via JS bridge)
- [ ] "Send to Whiteboard" context menu action on any card
- [ ] `cider-library-item` custom Excalidraw element type with live card data
- [ ] Canvas rename, delete with undo, theme sync, export as PNG/PDF
- [ ] Keyboard shortcut conflict prevention (Excalidraw vs panel shortcuts)

#### Video Bookmarks (Deferred from 1.0)
- [ ] Accept .mp4/.mov/.webm drag-drop as bookmark type
- [ ] Thumbnail extraction via AVAssetImageGenerator
- [ ] Video player in detail view

## FSEvents — How Filesystem Watching Works

FSEvents is the macOS API for watching a folder for changes. Like how Finder instantly shows a new file after you download something. Cider uses FSEvents to watch the vault folder, so when an AI tool (or the user in Finder) moves files, creates folders, or edits sidecar metadata, Cider updates instantly without manual refresh.

Key considerations:
- Debouncing — batch rapid changes (AI tool moving 50 files) into a single UI update
- Incremental diffing — only process what changed, not the whole vault
- Lightweight SQLite cache — read from filesystem, cache for fast search/filtering
- Scales to 10k+ files (apps like DEVONthink prove this works)

## Why This Direction

1. **Everyone's paying for AI already.** Don't rebuild what Claude Code and ChatGPT desktop already do.
2. **No lock-in.** Standard files in standard folders. If you leave Cider, you keep everything.
3. **Future-proof.** As AI tools get better, Cider automatically benefits.
4. **User owns everything.** No export needed — your files are already normal files.
5. **Simpler app architecture.** Cider reads the filesystem instead of managing complex storage layers.
6. **Cross-platform without compromise.** Full experience on web and iOS, with the vault as a desktop superpower.
7. **Flexible sync.** Users choose their cloud provider — Convex, iCloud, Dropbox, or anything else.

## Open Questions

- How to handle bookmarks (URLs aren't files)? `.webloc` files? A `bookmarks.json` index?
- Should Cider ship a default "organize" prompt/script that users can run with any AI tool?
- How to handle the transition for existing users with proprietary vault data?
- Thumbnail generation strategy for Convex sync (pre-generate on capture? on-demand?)
- SQLite cache schema for fast search across large vaults
- `FileProvider` implementation details for iOS Files app integration
- Shared vault permission model — granular sharing (by folder? by type?) vs. all-or-nothing

---

**This document is a north star, not a spec.** The 1.0 roadmap focuses on shipping what's built. This vision guides post-1.0 decisions — every architectural choice should move toward this direction, not away from it.
