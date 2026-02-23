# Resurf Competitive Analysis

> **Purpose:** Deep reference doc for comparing Cider and Resurf feature-by-feature. Use this when evaluating whether to adopt, adapt, or ignore patterns Resurf has solved. Updated Feb 2026 based on direct inspection of the Resurf app bundle (`/Applications/Resurf.app`).
>
> **Resurf version analyzed:** 1.107.1-beta.1
> **Resurf repo name internally:** `captureai` (the internal project name is CaptureAI)

---

## 1. Tech Stack

| | Cider | Resurf |
|---|---|---|
| **Framework** | SwiftUI + AppKit | Electron (Chromium + Node.js) |
| **Language** | Swift 6.2 | TypeScript + React |
| **Editor** | TipTap v3 (WKWebView) | TipTap v3 (Chromium WebView) |
| **Note storage** | Markdown files on disk | ProseMirror JSON blobs (proprietary vault) |
| **Data format** | Open (`.md`, Netscape HTML, JSON) | Opaque (custom vault, not human-readable) |
| **Panel behavior** | Native NSPanel, `.nonactivatingPanel` | Electron `BrowserWindow` (full focus steal) |
| **Animations** | Native SwiftUI springs | CSS transitions |
| **Acrylic/blur** | `NSVisualEffectView` | CSS `backdrop-filter` (low fidelity) |
| **Native bridge** | Pure Swift/AppKit | Thin Obj-C++ NAPI module for macOS Services |
| **Auto-update** | (not confirmed) | Squirrel |
| **Error tracking** | (not confirmed) | Sentry |
| **Analytics** | (not confirmed) | Custom telemetry + session tracking |

**Key takeaway:** Resurf's "native Mac feel" is CSS work inside Chromium. Cider's non-activating panel, spring physics, `NSVisualEffectView` acrylic, and zero-focus-steal behavior are impossible to replicate in Electron. This is a durable technical advantage.

---

## 2. Capture System

### Activation

| | Cider | Resurf |
|---|---|---|
| **Primary shortcut** | Double-tap Option | `Cmd+Shift+C` (configurable) |
| **Spotlight/search** | (planned) | `Cmd+Shift+Space` (separate window) |
| **Screenshot capture** | (planned via OCR) | `Cmd+Shift+S` (native area selection) |
| **Per-type shortcuts** | Opt+B (bookmark), Opt+N (note) | Configurable per type (note, link, media, voice) |
| **Menu bar** | No | Yes — persistent menu bar icon |
| **macOS Services** | Yes (`CiderServicesProvider`) | Yes (Obj-C++ bridge, right-click "Send to Resurf") |

### Capture Widget Flow

**Cider:** Single floating panel stays open persistently. Capture is contextual — you're already in the panel, you drop a URL or drag content in. No separate "capture mode."

**Resurf:** Dedicated capture widget that appears as a step-based flow:

```
select (300×225, centered)
    ├── note  (400×250, stays in place)
    ├── link  (400×188, stays in place)
    ├── voice (200×36, stays in place)
    └── attachment (350×433, stays in place)
→ success (260×50, centered, auto-dismisses)
```

Each step is a different Electron window size — the window physically resizes between steps. The `select` step is a type-picker; once you choose a type, the window morphs into that type's input form.

**Assessment:** Resurf's step-based capture widget is optimized for quick "get in, get out" capture without opening the full library. Cider's approach keeps everything in one persistent surface — good for power users, but there's a case for a lighter quick-capture mode that dismisses itself after saving (like Resurf's `success` step). **Worth considering for Cider:** a minimal "quick capture" mode that auto-dismisses after a successful save, distinct from the full panel.

### What Can Be Captured

| Content Type | Cider | Resurf |
|---|---|---|
| **URLs / bookmarks** | ✅ Full (metadata, thumbnail, OG data) | ✅ (OG data, screenshot, article text) |
| **Plain text / notes** | ✅ | ✅ |
| **Images** | ✅ (drag-drop, clipboard) | ✅ |
| **PDFs** | 🔲 (Documents tab, future) | ✅ (native PDF viewer) |
| **Video files** | 🔲 (vision doc only) | ✅ (attachment type) |
| **Audio files** | ❌ | ✅ |
| **Voice recording** | ❌ | ✅ (dedicated capture step) |
| **Screen area capture** | 🔲 (OCR vision doc) | ✅ (`captureAreaWithNativeTool`) |
| **Tweet embedding** | ❌ | ✅ (`react-tweet`, renders tweets natively) |
| **YouTube** | 🔲 (transcript sync vision) | ✅ (content type exists) |
| **GIFs** | 🔲 (vision doc, low effort) | ✅ |
| **Todos / tasks** | ✅ (checkboxes in notes) | ✅ (dedicated `todo` content type) |
| **Files (generic)** | 🔲 (Documents tab) | ✅ |
| **macOS Services (right-click)** | ✅ | ✅ |

### Link Processing Pipeline

**Cider:**
1. Fetch OG metadata (title, description, image)
2. Download and store thumbnail (`.thumbnails/`, `.originals/`)
3. Fallback chain if thumbnail unavailable

**Resurf:**
1. Fetch OG metadata
2. Take a **full screenshot of the rendered page** (not just OG image)
3. Extract article text via `@mozilla/readability`
4. Convert article HTML → Markdown via `turndown`
5. Run async AI pipeline: generate TLDR + compute vector embedding (if AI enabled)
6. Store all of it with the capture

**Key difference:** Resurf captures a rendered screenshot of the page, not just the OG image. This means every link capture has a visual snapshot of what the page actually looked like — immune to sites that don't set OG images. They also extract the full article body at capture time, so Reader Mode works even if the page goes offline later.

**Cider gap:** No page screenshot on capture. No article body stored at capture time. Reader Mode (planned) would need to re-fetch live. **High-value steal:** capture a page screenshot at bookmark time (using `WKWebView` screenshot API) and store the article body via Readability at capture — this makes both Reader Mode and web archival essentially free.

---

## 3. Data Model & Storage

### The Core Data Unit

**Cider:** Two separate models — `Bookmark` and `Note`. Different storage backends, different features. Unified view via `LibraryItemV2` discriminated union in the Home feed.

**Resurf:** One unified `Capture` model for everything:

```typescript
type Capture = {
  id: string           // ULID
  type: "note" | "attachment" | "link"
  contentType: "note" | "tweet" | "link" | "youtube" | "image" |
               "video" | "audio" | "recording" | "todo" | "pdf"
  title?: string
  tags: string[]
  spaceKeys: string[]
  isPinned: boolean
  isHidden: boolean
  triageStatus: "inbox" | "later" | "archive"
  snoozeUntil?: number        // timestamp — defer to resurface later
  colorPalette: ColorInfo[]   // extracted dominant colors
  tldr?: string               // AI-generated summary
  embedding?: number[]        // vector embedding for semantic search
  processingStatus: "processing" | "completed" | "failed"
  content: NoteData | LinkPreviewData | AttachmentData
}
```

**Assessment:** Resurf's unified model is cleaner for filtering and mixed-content views. Cider's split model made sense early but creates friction in the Home feed (the `LibraryItemV2` union is the workaround). Worth considering a migration toward a unified model in a future major version.

**Notable fields Cider doesn't have:**
- `triageStatus` — explicit inbox/later/archive state machine (see section 7)
- `snoozeUntil` — defer a capture to resurface at a specific time
- `colorPalette` — auto-extracted dominant colors (Cider has this in the `BOOKMARKS_VISION.md` Detail V2 spec but not implemented)
- `embedding` — vector for semantic search (AI-powered similarity)
- `processingStatus` — async enrichment pipeline with failure tracking
- `isHidden` — soft-hide without deleting

### Storage Format

| | Cider | Resurf |
|---|---|---|
| **Notes** | `.md` files (human-readable) | ProseMirror JSON (opaque) |
| **Bookmarks** | Netscape HTML + JSON sidecar | Same vault (opaque) |
| **Vault** | Standard filesystem (no special format) | Custom "vault" directory with schema versioning |
| **iCloud sync** | ❌ | ✅ (`useICloud` flag, migration tooling built in) |
| **Obsidian compatible** | ✅ (primary integration) | ❌ |
| **Human-readable** | ✅ (any text editor can read it) | ❌ (app-dependent) |
| **Backup/export** | ❌ (planned) | ✅ (vault export, auto-backup, configurable frequency) |
| **Schema migration** | ❌ | ✅ (`_version` field, reindex pipeline) |
| **Data portability** | ✅ (open formats) | ❌ (proprietary) |

**Cider advantage:** Open formats are a genuine differentiator. Resurf's data is trapped in their app. Cider's notes are `.md` files that Obsidian, VS Code, or any editor can open. This is the correct long-term strategy — lean into it in marketing.

**Resurf advantage:** iCloud sync is built in. Cider has no sync story yet. This is a real gap for users with multiple Macs.

---

## 4. Organization System

### Hierarchy

**Cider:**
```
Folders (hierarchical, user-defined)
  └── Items (bookmarks, notes, date cards, contacts)
Tags (flat, cross-folder)
Saved views (filter + layout configs, optionally pinned as tabs)
Stacks (dynamic query objects that surface in the feed)
```

**Resurf:**
```
Areas (groups of spaces — top-level organizer)
  └── Spaces (named collections, with icon + 20 color options, pinnable)
        └── Captures (items)
Tags (flat, cross-space)
Triage status (inbox / later / archive — orthogonal to spaces)
```

**Assessment:** Resurf's Area → Space hierarchy is roughly equivalent to Cider's folder hierarchy. The difference: Resurf's Spaces have first-class color + icon assignment (20 preset colors). Cider's folders don't have colors yet — this is low-hanging fruit for visual organization.

**Resurf's triage system** is worth a deeper look (see section 7).

### Filters

| | Cider | Resurf |
|---|---|---|
| **By type** | ✅ (saved views can filter by entity type) | ✅ |
| **By tag** | ✅ | ✅ |
| **By folder/space** | ✅ | ✅ |
| **By date range** | 🔲 (planned in saved views) | ✅ |
| **By pinned** | ✅ | ✅ |
| **By triage status** | ❌ | ✅ |
| **Sort: random** | ❌ | ✅ (good for rediscovery) |
| **Sort: relevance** | ❌ | ✅ (AI-powered) |
| **Hidden items** | ❌ | ✅ (`isHidden` filter) |
| **Inbox only** | ❌ | ✅ |
| **Space item counts** | ❌ | ✅ (per-type counts per space) |

---

## 5. Triage System

This is one of Resurf's most thoughtful design decisions and deserves its own section.

**Resurf's model:** Every capture has a `triageStatus`:
- `inbox` — newly captured, needs attention
- `later` — acknowledged but deferred
- `archive` — processed, out of the way

Combined with `snoozeUntil` (a timestamp), captures can be deferred to resurface at a specific time — like email snooze applied to anything you save.

**Cider's current model:** No triage. Items land in the library and stay there. The Home tab's "Continue" section (8 most recent items) approximates an inbox but isn't explicit.

**Assessment:** The inbox/later/archive model is simple but powerful — it gives every capture an explicit lifecycle state. Combined with snooze, it turns Resurf into a "capture now, process later" system. This maps directly to Cider's planned `HOME_VISION.md` resurfacing concepts (engagement-based resurfacing, date card surfacing) but Resurf's approach is simpler and more explicit.

**Steal candidate:** Add `triageStatus` to both `Bookmark` and `Note` models. Create a dedicated "Inbox" sidebar entry that filters to `triageStatus == .inbox`. Make new captures default to inbox. "Archive" action moves to `.archive`. This solves the "library grows forever and becomes noise" problem without requiring AI.

---

## 6. In-App Viewing

This is the area where Resurf has the most to teach Cider.

### Web Viewer

**Cider:** No in-app web viewer. All URL opens go to the system browser.

**Resurf:** Full embedded web viewer — an Electron `BrowserView`/`WebContentsView` that renders live pages inside the app. You can browse the web without leaving Resurf.

**Assessment:** An embedded web viewer is a natural fit for Cider's bookmark tab. When you click "Open" on a bookmark, instead of launching the full browser, the link opens in a lightweight WKWebView inside the panel (same technology Cider already uses for the TipTap editor). The panel becomes a reading surface, not just a link list. This is the "Cider as a browser companion that is also a mini-browser" concept.

**Implementation path for Cider:** This is the "Web tab" in the Detail V2 spec (`BOOKMARKS_VISION.md` Phase 2). Already planned, just needs to be prioritized. WKWebView is already embedded in the app for TipTap — adding a second WKWebView for page viewing is low additional complexity.

### Reader Mode

| | Cider | Resurf |
|---|---|---|
| **Status** | 🔲 Planned (vision doc) | ✅ Beta feature |
| **Parser** | `@mozilla/readability` (planned) | `@mozilla/readability` |
| **Rendering** | WKWebView (planned) | Chromium WebView |
| **Stored at capture** | ❌ (would re-fetch) | ✅ (`articleContent` + `articleHtml` stored) |
| **Offline capable** | ❌ | ✅ (content stored at capture time) |

**Key difference:** Resurf stores the Readability-parsed article body at capture time. Reader Mode is instant and works offline because there's nothing to fetch. Cider's planned Reader Mode would need to re-fetch and re-parse the live URL. **High-value steal:** store `articleContent` and `articleHtml` at bookmark capture time (add to the enrichment pipeline). No extra work at reading time.

### PDF Viewer

| | Cider | Resurf |
|---|---|---|
| **Status** | 🔲 Planned (Documents tab) | ✅ Beta feature (native PDF viewer) |
| **Implementation** | `PDFKit` (Apple native, planned) | Chromium's built-in PDF renderer |

**Assessment:** Cider's PDFKit path will produce a higher-quality native viewer. Chromium's PDF renderer is functional but it's not a native PDF experience. Cider has the advantage here once it ships.

### Screenshot / Screen Capture

**Cider:** `VNRecognizeTextRequest` (OCR) is in the AI vision doc but not implemented. No area-select screenshot tool exists yet.

**Resurf:**
```typescript
captureAreaWithNativeTool: () => Promise<string | null>
captureNativeScreenshot: () => Promise<string | null>
hasScreenPermission: () => Promise<boolean>
```

They have a working native area-select screenshot capture that saves the image as an attachment. Requires Screen Recording permission.

**Assessment:** This is a genuine gap. Resurf ships screenshot capture. Cider has it in a vision doc. The implementation is clear — macOS provides `CGWindowListCreateImage` or `SCScreenshotManager` (newer, ScreenCaptureKit). Combined with `VNRecognizeTextRequest` for OCR, this becomes a "capture anything visible on screen" feature. **Prioritize this over OCR — screenshot is more broadly useful than OCR-only.**

### Tweet Embedding

**Resurf:** Uses `react-tweet` to render tweets as styled embeds inside the app — not just a URL card but the actual tweet layout with avatar, text, metrics. Content type `tweet` is first-class in their schema.

**Cider:** Treats Twitter/X URLs as standard bookmarks with OG metadata.

**Assessment:** Tweet embedding is a niche feature but signals that Resurf thinks carefully about content-type-specific rendering. Cider's vision for content-aware rendering (the Detail V2 tabs: Preview, Reader, Web) can handle this implicitly via the Web tab — no need to special-case tweets.

---

## 7. Detail / Metadata Panel

### Resurf's Approach
Based on their schema and window system, captures open in a dedicated detail view within the main app window. The metadata panel shows: title (editable), spaces, tags, notes field, source URL, color palette, TLDR (AI), creation/update dates. All sections are likely togglable or collapsible given the schema breadth.

### Cider's Current Approach (V1)
`DetailPopoverPanel` — a secondary floating NSPanel that appears to the right of the main panel. Two-column: hero preview on left, metadata fields on right. Expands the main panel if needed (`expandCiderPanelForDetailModal`).

### Cider's Planned Approach (V2, `BOOKMARKS_VISION.md`)
Three modes:
1. **Slide-out panel** — slides in from the right edge, content stays visible behind it
2. **Full panel** — takes over the entire content area
3. **Page view** — takes over everything including the tab bar

This is more sophisticated than anything Resurf shows. The V2 spec is already well-designed — it just needs to be built.

### Side-by-Side Metadata Panel

| Metadata Field | Cider V1 | Cider V2 (planned) | Resurf |
|---|---|---|---|
| Title (editable) | ✅ | ✅ | ✅ |
| Folders/Spaces | ✅ | ✅ | ✅ |
| Tags | ✅ (comma text) | ✅ (chip UI) | ✅ (chip UI) |
| Notes/annotation | ✅ | ✅ | ✅ |
| Source URL | ✅ | ✅ | ✅ |
| Dominant colors | ❌ | ✅ (planned) | ✅ |
| TLDR / AI summary | ❌ | ✅ (planned) | ✅ (AI-generated) |
| Triage status | ❌ | ❌ | ✅ |
| Snooze | ❌ | ❌ | ✅ |
| Pin | ✅ | ✅ | ✅ |
| Hidden toggle | ❌ | ❌ | ✅ |
| Created / Updated | ✅ | ✅ | ✅ |
| Content tabs (Preview/Reader/Web) | ❌ | ✅ (planned) | ✅ (web viewer) |
| Reprocess / refresh | ❌ | ❌ | ✅ |

---

## 8. Editor

Both apps use TipTap v3. The architecture is nearly identical — a WKWebView/Chromium WebView running a TipTap instance with a JS↔native bridge.

| | Cider | Resurf |
|---|---|---|
| **Editor** | TipTap v3 | TipTap v3 |
| **Storage format** | Markdown (`.md` files) | ProseMirror JSON |
| **Serialization** | Custom markdown↔HTML round-trip | `@tiptap/markdown` |
| **Extensions** | Custom (hardbreak, link, highlight, tasks, underline, etc.) | Same set via `@captureai/shared` |
| **Image handling** | `<img>` tags in HTML paragraphs (avoids CommonMark HTML block edge case) | Not confirmed |
| **Singleton WebView** | ✅ (one WebView shared, moved between containers) | Not confirmed |
| **Formatting toolbar** | ✅ (flat strip, compact version planned) | Not confirmed |

**Notable:** Resurf stores notes as ProseMirror JSON, not markdown. This means their notes are not portable — you can't open them in Obsidian or any text editor. Cider's markdown-on-disk approach is strictly better for users who care about data ownership.

---

## 9. AI Features

| | Cider | Resurf |
|---|---|---|
| **AI model** | Apple Foundation Models (on-device, macOS 26+) + tiered fallback | OpenAI via Vercel AI SDK (BYOK only) |
| **Privacy model** | On-device first, cloud optional | Always off-device (BYOK, their servers aren't involved but OpenAI is) |
| **TLDR/summaries** | 🔲 Planned (tiered: metadata → extractive → AI) | ✅ |
| **Vector embeddings** | ❌ | ✅ (stored per capture, enables semantic search) |
| **Auto-tagging** | 🔲 (AI vision doc) | ❌ |
| **Semantic search** | ❌ | ✅ (via embeddings, sort by relevance) |
| **AI key required** | No (on-device works without) | Yes (BYOK, feature is off without a key) |
| **Space instructions** | N/A | ✅ (`instruction` field on Space — AI can use this as context) |

**Notable:** Resurf's `Space.instruction` field lets users give each space an AI instruction (e.g., "This space is for work research — always tag with project names"). This is a clever way to make AI behavior configurable without building a full prompt editor.

**Notable:** Resurf stores vector embeddings per capture (`embedding: number[]`). This enables semantic search (find things by meaning, not keywords) and similarity features ("related items"). These embeddings are computed at capture time in the background — no latency at search time.

**Cider advantage:** Cider's tiered AI approach (no-AI → Apple on-device → cloud API) is a better long-term strategy. Apple Foundation Models (macOS 26+) will provide AI features to all users without any API key or cost. Resurf's BYOK model means AI is only available to users willing to pay for OpenAI. This is a major adoption barrier.

---

## 10. Search

| | Cider | Resurf |
|---|---|---|
| **Keyword search** | ✅ (token-based, `localizedStandardContains`) | ✅ |
| **Semantic search** | ❌ | ✅ (via vector embeddings) |
| **Full content search** | ✅ (notes: full file content; bookmarks: title + URL + tags) | ✅ |
| **Filter by type** | ✅ | ✅ |
| **Filter by tag** | ✅ | ✅ |
| **Filter by date** | 🔲 | ✅ |
| **Sort by relevance** | ❌ | ✅ (AI-powered) |
| **Sort by random** | ❌ | ✅ (rediscovery use case) |
| **Spotlight integration** | ✅ (`SpotlightIndexer`, dormant in dev builds) | Not confirmed |
| **Search palette** | ✅ (`SearchService` + search tab) | ✅ (separate Spotlight window, `Cmd+Shift+Space`) |
| **Search snippets** | ✅ (`SearchSnippet` with prefix/match/suffix) | Not confirmed |

**Notable:** Resurf's "sort by random" is a simple but clever resurfacing tool. No AI required — just shuffle the library and surface things you've forgotten. Cider's `HOME_VISION.md` has a more sophisticated engagement-based resurfacing plan, but random sort could be added as a zero-effort first step.

---

## 11. Business Model

| | Cider | Resurf |
|---|---|---|
| **Current status** | Private, in development | Beta, publicly available |
| **Pricing** | TBD | License key (one-time or subscription, tiers confirmed in code) |
| **Free tier limits** | N/A | Yes — `FreeTierLimits: { captures: number, spaces: number }` |
| **Distribution** | TBD | Direct download (resurf.so), not yet on App Store |
| **Auto-update** | TBD | Squirrel (built in) |

**Notable:** Resurf has a license validation system with a cache token and failure count — suggesting they've dealt with offline validation edge cases. They also have `licenseValidationFailureCount` — after N failures the app presumably degrades gracefully rather than hard-locking.

---

## 12. Canvas / Whiteboard

**Resurf:** Canvas feature exists in the schema (with nodes, connections, annotations — text, rectangle, circle, arrow) but is behind a feature flag (`canvas: false` by default). Not shipped to users yet.

```typescript
type Canvas = {
  id: string
  name: string
  nodes: CanvasNode[]           // captures placed on a 2D canvas
  connections: CanvasConnection[] // links between nodes with labels
  annotations: CanvasAnnotation[] // text, shapes, arrows
}
```

**Cider:** Whiteboard tab is in the vision doc (`WHITEBOARD_VISION.md`), also not shipped.

**Assessment:** Both apps have whiteboard/canvas as a future feature. Neither has shipped it. Resurf's Canvas model shows captures as nodes (their unified model makes this natural — any capture can be placed on a canvas). Cider's Whiteboard will likely be freeform fragments (blocks of text, images, links) that can be promoted to notes.

---

## 13. What Resurf Does That Cider Should Steal

Ranked by implementation value vs. effort:

### High Value, Low Effort

1. **Screenshot capture at capture time** — Store a page screenshot when bookmarking a URL. Makes thumbnails work for every site regardless of OG image. Immediate value, one WKWebView call. See `captureAreaWithNativeTool` pattern.

2. **Article body stored at capture time** — Run Readability at bookmark capture and store `articleContent` + `articleHtml`. Reader Mode becomes instant and offline-capable. Cider is already planning Readability — the only change is running it eagerly at capture vs. lazily at read time.

3. **Sort by random** — One line of code. Surfaces forgotten items without any AI. Fits directly into the `LibrarySortMode` enum.

4. **Capture triage: inbox/later/archive** — Add `triageStatus` to Bookmark and Note models. Default new captures to `.inbox`. Add an "Inbox" entry to the sidebar. This gives the library an explicit lifecycle that prevents it becoming a graveyard. Resurf's app name literally means "resurface" — this is their core product loop.

5. **Snooze on any item** — `snoozeUntil: Date?` on any item. Items with a future snooze date are hidden from the main feed until that time. Surfaces automatically when the time arrives. Powerful for "I'll deal with this on Monday" workflows.

6. **Space/folder color + icon** — Resurf has 20 color options per space with an icon picker. Cider's folders are uncolored. Color-coded folders are an immediate visual improvement for library navigation.

### High Value, Medium Effort

7. **In-app web viewer** — Open bookmarks in an embedded WKWebView inside the panel instead of launching the full browser. Cider already has WKWebView infrastructure. This is the "Web tab" in the Detail V2 spec — it just needs to be built and prioritized.

8. **Area screenshot capture (Cmd+Shift+S equivalent)** — Select an area of the screen and capture it as an image capture. Requires Screen Recording permission. Uses `SCScreenshotManager` or `CGWindowListCreateImage`. Resurf ships this, Cider doesn't.

9. **Processing status on captures** — `processingStatus: "processing" | "completed" | "failed"` gives users feedback that enrichment is happening. Currently Cider shows a shimmer but has no explicit "failed" state — failed enrichments are silently incomplete.

10. **Backup + auto-backup** — `autoBackup: true`, `backupFrequencyDays: 7`, `maxBackupCount: 1`. A periodic vault export to a zip file. Low complexity, high user trust. Resurf has this built in.

### Lower Priority / Different Direction

11. **Voice recording capture** — Resurf has voice as a first-class capture type (dedicated widget step, 200×36 mini window). This is a meaningful differentiator but would require significant work (audio recording, transcription, playback). Worth tracking but not stealing immediately.

12. **Vector embeddings** — Store a vector embedding per capture for semantic search. Requires AI integration. Cider's Apple Foundation Models path will enable this more elegantly (on-device, no API key) — wait for Foundation Models rather than copying Resurf's OpenAI approach.

13. **Space AI instructions** — `Space.instruction` field that gives AI context about what the space is for. Only relevant once AI is working. Low effort to add the field now, high value once AI is live.

14. **`isHidden` flag** — Soft-hide captures without deleting them. Different from archiving. Useful for suppressing items you don't want to see but don't want to lose.

---

## 14. What Cider Has That Resurf Doesn't

These are genuine Cider advantages — not features to copy but reasons why users should choose Cider:

1. **Open data format** — Notes are `.md` files, bookmarks are Netscape HTML. Readable in any editor, importable/exportable to anything. Resurf's data is locked in a proprietary vault.

2. **Obsidian integration** — Bidirectional vault sync, wikilinks, frontmatter preservation. Resurf has no Obsidian integration and cannot have one without a significant architecture change (their data model doesn't produce Obsidian-compatible files).

3. **Non-activating panel** — Cider never steals focus. The panel floats over your work without interrupting it. Electron apps always steal focus on window activation — this is a physical limitation of the platform, not a design choice.

4. **True native animations** — Spring physics, `NSVisualEffectView` acrylic, Core Animation. Not achievable in Electron.

5. **Spotlight indexing** — `SpotlightIndexer` integrates Cider's content with macOS Spotlight, Raycast, and Alfred. Resurf doesn't confirm this.

6. **Mixed content model** — Cider's `LibraryItemV2` handles bookmarks, notes, date cards, contacts, and stacks in a unified feed with calendar projection. Resurf is captures-only (no calendar, contacts, or structured date items).

7. **Stacks / smart surfacing** — Cider's stacks (dynamic query objects with surfacing rules, pin-until-done, remind-before) have no equivalent in Resurf. Resurf has `snoozeUntil` on individual items but no concept of a smart collection with surfacing logic.

8. **Bookmark-first identity** — Cider has deep bookmark features (masonry, thumbnails, Netscape HTML export, DataCards Obsidian export) that Resurf doesn't match. Resurf treats links as just another capture type — no special treatment for bookmark-specific workflows.

9. **Reader Mode + Web Archival planned as native** — When built, Cider's Reader Mode will use native `WKWebView` + Swift APIs. Web archival uses `WKWebView.createWebArchiveData()`. These will outperform Resurf's Chromium-based equivalents in memory and battery usage.

10. **Apple on-device AI (roadmap)** — Foundation Models will provide free, private, on-device AI to all Cider users on macOS 26+. Resurf's AI requires a paid OpenAI key and sends content off-device.

---

## 15. Summary Table

| Feature Area | Cider | Resurf | Notes |
|---|---|---|---|
| Panel behavior | ✅ Native, non-activating | ⚠️ Electron, focus-stealing | Durable Cider advantage |
| Animations/feel | ✅ Native springs + acrylic | ⚠️ CSS | Durable Cider advantage |
| Data portability | ✅ Open formats | ❌ Proprietary vault | Durable Cider advantage |
| Obsidian integration | ✅ | ❌ | Durable Cider advantage |
| Mixed content (notes + bookmarks + calendar) | ✅ | ⚠️ Captures only | Cider advantage |
| Screenshot at capture | ❌ | ✅ | Steal this |
| Article body at capture | ❌ | ✅ | Steal this |
| In-app web viewer | 🔲 Planned | ✅ | Prioritize |
| Area screenshot capture | 🔲 Planned | ✅ | Prioritize |
| Reader Mode | 🔲 Planned | ✅ Beta | Prioritize |
| PDF viewer | 🔲 Planned | ✅ Beta | Planned path is better (PDFKit) |
| Voice recording | ❌ | ✅ | Different direction |
| Triage (inbox/later/archive) | ❌ | ✅ | Steal this |
| Snooze | ❌ | ✅ | Steal this |
| Folder/space colors | ❌ | ✅ | Low effort, steal |
| Color extraction from images | 🔲 Planned (Detail V2) | ✅ | On roadmap |
| Tweet embedding | ❌ | ✅ | Skip (Web tab covers it) |
| iCloud sync | ❌ | ✅ | Major gap, different problem |
| Auto-backup | ❌ | ✅ | Low effort, high trust signal |
| AI summaries | 🔲 Planned (tiered) | ✅ BYOK | Cider's approach is better |
| Semantic/vector search | ❌ | ✅ | Wait for Foundation Models |
| Sort by random | ❌ | ✅ | One-line steal |
| Processing status feedback | ⚠️ Shimmer only | ✅ Explicit states | Improve feedback |
| Canvas / Whiteboard | 🔲 Planned | 🔲 Behind flag | Both future |
| Stacks / smart surfacing | ✅ | ❌ | Cider advantage |
| Calendar / date cards | ✅ | ❌ | Cider advantage |
| Spotlight integration | ✅ (dormant) | Not confirmed | Cider advantage |
| macOS 14+ | ✅ | ✅ | Parity |
| Menu bar icon | ❌ | ✅ | Different philosophy |
