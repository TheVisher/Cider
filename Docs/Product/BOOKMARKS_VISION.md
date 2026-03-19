# Bookmarks Tab Vision

## Goal
Build a fast, low-friction bookmarking system in Cider with strong capture flows, high-quality metadata, and a polished visual browsing experience (List/Grid/Masonry).

## Current Status (Implemented)
- Command Palette tab and standalone Bookmarks window.
- List, Grid, and true Masonry layouts.
- Cross-browser capture flow (capture button + hotkey + clipboard + drag/drop URL).
- Browser coverage working for Chrome, Dia, Zen, and Comet capture path.
- Metadata/title enrichment and thumbnail fetching with fallback behavior.
- Shimmer placeholder while enrichment/thumbnail loads.
- Manual thumbnail assignment by dropping image/image URL/file onto a bookmark card. **This feature is self-contained in `BookmarkCard` — it calls `BookmarksStorage.shared` directly and posts the toast notification itself. No per-view wiring needed. Any view that renders `BookmarkCard` gets drag-and-drop automatically. Do not add `onAssignThumbnailFrom*` callbacks back.**
- Dual-image asset storage for bookmarks:
  - Full-size originals stored in `.originals/` for later access/export.
  - Runtime thumbnails stored in `.thumbnails/` as downsampled PNGs (currently max 720px).
  - Existing bookmarks are normalized retroactively on load (legacy large thumbnails are rewritten to the new format).
- Clipboard review toast flow (save/discard), plus capture success/error toasts.
- Window behavior parity improvements (resizing, tiling shortcuts, snap padding consistency).
- Context menus on cards/rows with Open in Browser, Show Details, Move to Folder, Delete (shared CardContextMenu component).
- **Reader Mode** — Three-mode hero area in the detail panel: thumbnail preview, Readability.js reader view, and live WKWebView. Toolbar buttons (`photo`, `doc.richtext`, `globe`) switch between modes. State resets on bookmark change; each mode is lazy-activated and kept alive on first use.
- **Dominant Color Extraction** — k-means palette extracted from bookmark thumbnails via `ColorExtractionService`. Stored as `dominantColors: [String]?` (hex). Displayed as color swatches in the detail panel's Intelligence section.
- **AI Enrichment Pipeline (Phase 1)** — On capture: NaturalLanguage keyword extraction for auto-tagging (`AutoTagService`), NLEmbedding vector computation (`EmbeddingStore`), Vision OCR text extraction (`OCRService`), color palette extraction (`ColorExtractionService`). All on-device, all background.
- **Intelligence section in detail panel** — Shows `aiSummary` text, dominant color swatches, and related items (`RelatedItemsView`, up to 3 by vector similarity). Visible for all URL bookmarks.
- **Foundation Models summary integration** — `SummaryService` (Foundation Models on macOS 26+) generates summaries from Reader Mode article text. Triggered on first reader open if no existing `aiSummary`. Stored on the Bookmark model.

## Label and Stack Integration

Bookmarks participate in the cross-entity label and stack system alongside date cards and contacts.

- The `CardLabel` system is cross-entity — labels can be assigned to bookmarks, date cards, and contacts
- Bookmarks can be included in stacks via **manual refs** (explicitly added) or **rule matches** (e.g., stack filtering for a specific label)
- Filter chips in saved views allow label-based filtering across all entity types simultaneously
- Example use cases:
  - Tag a bookmark with a "Gift Idea" label → it surfaces in a partner's birthday stack
  - Tag concert/event bookmarks with a "Tickets" label → a stack filters for upcoming events
  - Color-code bookmarks by project or person for quick visual scanning in mixed-content views

## Future: Related Links Per Bookmark (Single Product, Multiple Sources)

For product-like saves (apps, tools, services), Cider should support one bookmark with multiple source links instead of forcing users into multiple separate bookmarks.

- Keep the one-item mental model:
  - A single bookmark remains the canonical item.
  - One `primary URL` (first captured link) plus `related links` in metadata.
- Keep stacks focused on grouping multiple items:
  - Stacks remain cross-item organization.
  - Related links are per-item enrichment, not a stack substitute.

### Metadata Actions (Planned)

- `Add Related Link` (manual entry)
- `Suggest Related Content` (AI-assisted scan)

### Suggested Flow (Planned)

1. User opens bookmark detail panel.
2. User clicks `Suggest Related Content`.
3. Cider extracts canonical entity signals (name, publisher, source domain).
4. High-confidence pass searches for official site / app store / GitHub / docs.
5. If confidence is low, run broader semantic/fuzzy pass.
6. Show candidate links with type, confidence, and short reason.
7. User explicitly selects links to attach (never auto-attach silently).

### Suggested Related Link Types (Planned)

- `official_site`
- `app_store`
- `play_store`
- `github_repo`
- `github_org`
- `docs`
- `support`
- `pricing`
- `changelog`
- `community`

### Data Shape (Planned)

Add per-bookmark related links metadata:

```swift
struct RelatedLink: Codable, Identifiable {
    var id: UUID
    var urlCanonical: String
    var type: String
    var title: String?
    var confidence: Int?          // 0...100 for AI suggestions
    var reason: String?           // why this was suggested
    var source: String            // manual | ai_suggested | accepted_ai
    var createdAt: Date
}
```

### Ranking Guardrails (Planned)

- Score exact entity/publisher/domain matches highest.
- Prefer trusted platforms (`apps.apple.com`, `github.com`, official domain).
- Canonicalize/dedupe URLs before display.
- Penalize likely collisions (same name, different publisher/category).
- Hide low-confidence results behind an explicit "show low confidence" action.
- Require user confirmation before attach.

<!-- Removed: Standalone panel resize handle bug fix — standalone BookmarksPanel was removed in Feb 2026 panel consolidation. Bookmarks are now browsed exclusively in the main panel. -->

---

## Phase 1: Capture Quality and Reliability (Next)
1. Harden metadata extraction quality.
2. Improve source-specific handling for Reddit/X edge cases.
3. Add lightweight diagnostics for failed enrichment/capture attempts.

### Acceptance Criteria
- Capture success/failure messaging is always accurate (no false positives).
- Metadata title quality is improved on major sites.
- Thumbnail fallback coverage improves without regressions in speed.

## Phase 2: Bookmark Details Surface ✅ (V1)
1. ✅ Add bookmark details panel (on thumbnail click / info action).
2. ✅ Show/edit metadata:
- ✅ canonical URL
- ✅ title
- ✅ tags
- ✅ notes
- thumbnail source/local status (partial — hero preview, no separate indicator)
3. ✅ Add actions:
- replace/remove thumbnail (drag-and-drop on card)
- set thumbnail from Reader/Browser view (right-click image → "Set as Bookmark Thumbnail")
- ✅ copy URL
- ✅ open in browser
- ✅ open original image (if local original exists, else remote fallback)

### Acceptance Criteria
- ✅ Details panel opens reliably from cards in all layouts (BookmarksTabContent, HomeDashboardView, FolderDetailView).
- ✅ Edits persist and reflect immediately in card/list views.
- ✅ Keyboard navigation and accessibility behavior match existing panel standards.

## Detail View V2 — Resurf-Inspired Redesign

Complete redesign of the detail surface, inspired by Resurf's modal system. The current V1 is a basic two-column sheet (hero preview + metadata sidebar). V2 transforms it into a flexible, content-aware detail experience with multiple view modes and richer metadata.

### Three View Modes

The detail view supports three sizes, switchable via toolbar buttons + a drag handle for manual resizing:

**1. Slide-out panel (default)**
- Slides in from the right edge of the content area (replaces the current detached popover)
- Content behind it stays visible (not blurred) — the panel overlays part of the card grid
- Toggleable: clicking a card opens it, clicking the same card or pressing Escape closes it
- Metadata sidebar is toggleable — when hidden, just the content preview fills the panel
- Metadata toggle state persists (if you prefer metadata always visible, it stays that way)
- Drag handle on the left edge to manually widen/narrow

**2. Full panel**
- Takes over the entire content area (sidebar stays, tab bar stays)
- Great for images you want to see larger, or for reading bookmark content
- Toolbar button to switch between slide-out and full panel

**3. Page view**
- Self-contained view — takes over everything including the tab bar area
- Essentially a dedicated screen for that item
- Back button or Escape to return
- Best for notes in reader mode, long articles, or when you want to focus entirely on one item

### Metadata Panel Layout

The metadata panel lives on the right side of the detail view. All sections are collapsible (disclosure triangles, state persisted per section). Order top to bottom:

**Title** — Large editable text at the top of the metadata panel (not buried under "Metadata" heading like V1)

**Folders** — Current folder assignment with picker (same as V1 but moved up in priority)

**Tags** — Tag chips with inline "Add tag..." field. Tap a tag to filter by it. (Currently comma-separated text — upgrade to chip UI)

**Notes** — Expandable text area for free-form notes about the bookmark. "Add note" button when empty.

**Source** — URL display with open/copy actions. For image bookmarks, shows "Saved from clipboard" or the source app.

**Colors** — Dominant color palette extracted from the thumbnail/image. Shows 5-7 color swatches as filled circles or rounded rectangles. "Extract Colors" button if not yet computed. Color values copyable (hex, RGB). Technical approach: `CGImage` → `CIFilter` (CIAreaAverage for regions) or k-means clustering on downsampled pixel data. Store extracted colors on the Bookmark model as `[String]?` (hex values). See "Dominant Color Extraction" below.

**Properties** (bottom) — Read-only metadata grid:
- Created: date
- Updated: date
- Type: Bookmark / Image / (future: Video, GIF)
- Size: file size for images, or "Web page" for URL bookmarks

### Content-Specific Tabs (URL Bookmarks)

URL bookmarks get hero mode buttons in the detail panel toolbar (implemented as icon toggles, not traditional tabs):

**Preview** (`photo` icon) ✅ — Shows the thumbnail image. Default mode.

**Reader** (`doc.richtext` icon) ✅ — Clean Readability.js article view, styled to match Cider's dark aesthetic. Triggers Foundation Models summary on first open. Links open in system browser.

**Web** (`globe` icon) ✅ — Embedded WKWebView showing the live page. Loaded on demand; stays alive once activated so toggling back is instant.

### Dominant Color Extraction

✅ Implemented: dominant color palette extracted on capture from bookmark thumbnails.

**Technical approach:**
- Load the thumbnail (not original — already downsampled, fast to process)
- ✅ k-means clustering on downsampled pixel buffer (resize to ~50x50, run k-means with k=6) — implemented in `ColorExtractionService`

**Storage:** `dominantColors: [String]?` on the Bookmark model — array of hex strings (e.g., `["#FC3434", "#1A1A2E", "#E94560"]`). Extracted lazily (on first detail view open) or eagerly (on capture, in background).

**Display:** Row of filled circles or rounded-rect swatches. Tap to copy hex value. Could also be used for:
- Tinting the card border/background subtly in grid view
- Filtering bookmarks by color ("show me all blue-dominant images")
- Color-based sorting or grouping

### Shared Pattern

This detail view pattern is shared across all content types — not just bookmarks. Notes, date cards, contacts, and future types (documents, whiteboard items) should all use the same three-mode detail surface with content-specific tabs and a consistent metadata panel. The metadata sections vary by type (notes don't have URL/Colors, date cards have date/time/location, etc.) but the shell is identical.

Update `DESIGN_SYSTEM.md` (section 18, Component Catalog) when implementing to document the shared detail view container.

## Phase 3: Library Management
1. **Multi-select** ✓ — Shift-click range, Cmd-click toggle, Cmd+A select all. Bulk move/delete implemented. Multi-drag with fanned preview implemented. Bulk tag future. See `WORKSPACES_VISION.md`.
2. **Sorting controls** — newest, oldest, title A-Z, domain. Per-tab persistence.
3. **Trash integration** ✓ — Delete sends to trash (30-day retention), not permanent delete. See `WORKSPACES_VISION.md` for trash system spec.
4. **Undo** ✓ — Transient toast with "Undo" button for destructive/organizational actions.
5. Filter chips (has thumbnail, no thumbnail, recent, tagged).
6. Duplicate management improvements.

### Acceptance Criteria
- Bulk actions perform safely with undo support.
- Deleted items go to trash, not permanent deletion.
- Sorting/filtering is stable across List/Grid/Masonry and search.

## Phase 4: Portability and Interop
1. Finalize storage layout under `~/Documents/Cider/bookmarks` (with migration support).
2. Continue Netscape HTML import/export compatibility.
3. Add richer import feedback for malformed/partial bookmark files.
4. **Drag-out to external apps** — register `public.url` on bookmark drag providers so dragging a bookmark onto a browser opens the URL, onto Finder creates a `.webloc`, etc. See `WORKSPACES_VISION.md` → "Drag Out to External Apps" for full spec.

### Acceptance Criteria
- Existing users migrate safely.
- Imports/exports round-trip with mainstream browser bookmark files.
- Dragging a bookmark out of Cider onto a browser/Finder works as expected.

## Phase 5: Polish and Performance
1. ✅ Async thumbnail loading via `.task(id: fingerprint)` + `Task.detached` + `CGImageSourceCreateWithURL` — no main-thread image decoding during scroll.
2. ✅ `Bookmark.thumbnailFileURL` / `originalImageFileURL` use `StoragePaths.cachedCiderDataDirectoryURL` instead of per-access `CiderConfig.load()`.
3. Smarter thumbnail invalidation/retry policy.
4. Large-library performance pass (scrolling, filtering, search latency).

### Acceptance Criteria
- ✅ Smooth interaction at high bookmark counts — async loading prevents scroll jank in masonry/grid.
- ✅ No layout jank in masonry during enrichment updates — `.task(id: fingerprint)` auto-cancels and re-fires on enrichment changes.
- Thumbnail memory/perf can be tuned without code changes (future settings toggle target).

### Thumbnail Dimension Options (Documented for Future Settings)
These are intentionally documented as operational profiles for a future user-facing settings toggle:

- `720px` max dimension (current default): best visual quality, moderate memory use.
- `512px` max dimension: balanced quality/performance profile.
- `360px` max dimension: aggressive memory savings for very large libraries.

Potential settings UX:
- `High Quality (720)`
- `Balanced (512)`
- `Memory Saver (360)`

---

## Browser Companion Features

These features lean into Cider's unique position as a floating panel open alongside your browser. Rather than replacing the browser, Cider augments it — providing surfaces the browser doesn't have.

### Live YouTube Transcript Sync

**Concept:** When a YouTube video is playing — either in Chrome or in Cider's built-in web view — Cider shows a live-scrolling transcript. Words/sentences highlight in real-time as the video plays.

**Two modes:**

*Chrome companion mode (future):*
- Detect YouTube tab in Chrome via the existing browser extension pattern
- Extension reads `video.currentTime` and sends playback state to Cider via local IPC
- Cider fetches captions and renders them in the panel alongside the browser

*In-app mode (closer, more feasible):*
- User opens a YouTube bookmark in the Web view tab of the detail panel
- Cider injects a `WKScriptMessageHandler` into the WKWebView
- JS polls `video.currentTime` every ~500ms and posts it back to Swift
- Cider fetches the caption track from YouTube's timedtext endpoint, extracts the URL from `ytInitialPlayerResponse.captions.playerCaptionsTracklistRenderer.captionTracks[*].baseUrl`
- Current line is highlighted in a transcript panel below or alongside the video
- Click any line → inject JS to seek: `document.querySelector('video').currentTime = timestamp`
- Transcript stored as a bookmark artifact on save

**Core experience (both modes):**
- Transcript scrolls automatically, highlighting the current sentence/word
- Click any line in the transcript → seeks the video to that timestamp
- Search within the transcript while the video plays
- Copy/highlight passages directly into Cider notes
- Transcript persists as a bookmark artifact — even after closing the video, you have the full text

**Open questions:**
- Should transcript auto-appear for YouTube bookmarks in web view, or require a manual "Show Transcript" button?
- Should transcripts be saved automatically with the bookmark, or only on explicit save?
- Support for other video platforms (Vimeo, Twitch VODs) — same pattern, different caption APIs?
- Could we generate transcripts via local Whisper for videos without captions?

---

### Picture-in-Picture Video Player

**Concept:** When the bookmark detail panel is closed while a YouTube video is playing in the web view, instead of killing the audio, pop out the video into a small floating mini-player — like browsers' PiP mode. Put it back in the panel when you return to that bookmark.

**Core experience:**
- Video playing in web view → user closes the detail panel → Cider detects active video playback
- Small floating panel appears with the video still playing (no reload, no audio gap)
- User can dismiss the mini-player to stop the video entirely
- User opens the same YouTube bookmark → web view resumes from the mini-player seamlessly
- Timestamp is preserved throughout — the video state is never interrupted

**Why this fits:**
- Cider is already a floating panel app — a second floating mini-player is a natural extension
- Users already have the video in Cider's web view; PiP is a logical "continue watching while you do something else" action
- Much better UX than the current behavior (audio orphaned with no controls)

**Technical approach:**
- `BookmarkWebViewManager` singleton — owns `WKWebView` instances keyed by URL (same pattern as `NotesViewModel` owning the TipTap `WKWebView`)
- On panel close: detect `!video.paused` via JS injection. If playing, reparent the `WKWebView` (`NSView` subclass) into a new floating `NSPanel` instead of discarding it
- `NSView.addSubview()` reparents cleanly — the video process continues uninterrupted
- On panel reopen for the same bookmark: reparent the WKWebView back into the detail panel hero area
- Mini-player panel: borderless, floating level, resizable, shows only the video — no Cider chrome
- Dismiss button: calls `video.pause()` JS and closes the panel

**Timestamp persistence (prerequisite):**
- Before any navigation or close, inject JS to capture `video.currentTime`
- Store as `lastWatchedTimestamp: TimeInterval?` on the `Bookmark` model
- On reopen: use the YouTube `&t=Ns` URL parameter (more reliable than JS-seeking a React-managed player)
- Show a small "Resume from X:XX" indicator in the web view toolbar when a saved timestamp exists
- Minimum viable first version: timestamp persistence alone (no reparented mini-player) — close kills audio, but reopening resumes from where you left off

**Open questions:**
- Should PiP be automatic (always pop out when closing with video playing) or optional (ask once, configurable)?
- Should the mini-player appear adjacent to the main Cider panel, or freely positioned?

---

### AI Page Summaries

**Concept:** Click "Summarize" in Cider and get an AI-generated summary of the page you're currently browsing. The summary lives in the panel alongside the page. Optionally save it as a bookmark annotation.

**Core experience:**
- User is browsing any webpage → clicks Summarize in Cider (or hotkey)
- Cider extracts the page content (via Chrome extension reading the DOM / Readability)
- Sends to AI for summarization → displays result in a summary card in the panel
- "Save" button captures the URL as a bookmark with the summary attached
- Summaries persist with bookmarks — when you revisit a saved bookmark, the summary is already there

**Why this fits Cider:**
- Cider already captures URLs and metadata — summaries are a natural enrichment layer
- The floating panel is the perfect surface for "glanceable info about the current page"
- Summaries become part of your bookmark library — searchable, browsable, organized in folders
- Doesn't require switching context — you stay on the page, summary appears alongside

**Variations:**
- **On-demand:** Click to summarize the current page (primary flow)
- **Auto-summary on bookmark:** When you capture a URL, optionally auto-generate a summary as metadata
- **Saved summary library:** Browse all your summaries in the bookmarks tab — effectively a personal knowledge base of everything you've read
- **Key points mode:** Bullet-point extraction instead of prose summary
- **Custom prompts:** "Summarize for a 5-year-old" / "Extract action items" / "What are the counterarguments?"

**Tiered approach — ship without AI, enhance with it:**

*Tier 0: Metadata extraction (no AI, ship first)*
- Pull `<meta name="description">`, Open Graph `og:description`, Twitter card description
- Extract `<h1>`–`<h3>` headings as a structural outline
- Grab the first paragraph of Readability-parsed article text
- This is already useful — most well-structured pages have human-written summaries in their metadata
- Costs nothing, runs instantly, works offline

*Tier 1: Extractive summarization (no AI, local algorithms)*
- TextRank — graph-based sentence ranking (like PageRank for sentences). Scores sentences by similarity to other sentences, picks top N. Works well on long articles, poorly on short/conversational pages.
- TF-IDF sentence scoring — rank by keyword density relative to the document. Picks sentences with the most "distinctive" terms.
- Apple NaturalLanguage framework — on-device tokenization, NER, sentence segmentation. Combine with TextRank for a fully local pipeline.
- Output: real sentences from the page (never "wrong"), but selection quality is mediocre and summaries feel choppy since they can't synthesize.

*Tier 2: AI summarization (optional, user-configured)*
- Apple Foundation Models framework (macOS 26+) — on-device LLM, no cloud dependency, no API costs, private by default. Best of both worlds.
- Cloud APIs (OpenAI, Anthropic, etc.) — higher quality for complex pages, but requires API key and sends content off-device.
- Local LLM (Ollama, llama.cpp) — power-user option, runs locally but needs model download.
- User chooses their provider in settings. Tier 0/1 is always available as fallback.

**Technical approach:**
- Chrome extension extracts page content (innerText or Readability-parsed article text)
- Sends to Cider via same IPC bridge as transcript sync
- Cider runs Tier 0 instantly, Tier 1 locally, Tier 2 on request
- Summary stored as a field on the Bookmark model (or as a linked Note)
- Summary card shows which tier generated it (metadata vs extractive vs AI)

**Open questions:**
- Should summaries be stored on the Bookmark model directly, or as linked Notes?
- Privacy: some users won't want page content sent to cloud APIs — local-first tiers solve this
- Could summaries update when a page changes (re-summarize stale bookmarks)?
- Should Tier 0 metadata extraction happen automatically on every bookmark capture?

---

### Reader Mode

✅ **Implemented:** Clean distraction-free reading view inside the detail panel's hero area. Accessed via the `doc.richtext` toolbar button.

**Core experience:**
- Click `doc.richtext` in the detail panel toolbar
- Cider fetches the page content and runs it through a Readability parser (strip ads, nav, sidebars → extract article body)
- Clean article renders in the hero area — title, byline, body text, images
- Typography and spacing match Cider's design system
- Reader view can be scrolled; links open in system browser
- After article extraction, Foundation Models summary is triggered and saved to the bookmark (if no existing summary)

**Why this fits Cider:**
- Cider is already a reading companion — it saves links. Reader mode makes it a reading *tool*, not just a link repository.
- The floating panel is the perfect surface for focused reading alongside your browser
- Reader content can be saved as a permanent offline copy (see Web Archival below)
- Future integration with the Books tab — reader mode is the core reading experience for both web articles and longer-form content

**Technical approach:**
- ✅ `BookmarkReaderView.swift`: Swift fetches raw HTML via URLSession → `loadHTMLString` into WKWebView → Readability.js evaluated after `didFinish` → parsed JSON → styled HTML loaded in second pass
- Phase state machine (`loadingRaw` → `extracting` → `displaying` / `error`) prevents re-entrant extraction
- CSS in `Resources/ReaderMode/reader.css` — dark mode, `color-scheme: dark`, matches panel aesthetic

**Open questions / future:**
- Should reader content be cached locally for offline access?
- Support for multi-page articles (auto-pagination)?

---

### Web Archival

**Concept:** Save a full snapshot of a web page locally so it survives if the original goes offline. The archived version is viewable inside Cider forever.

**Core experience:**
- Right-click a bookmark → "Archive Page" (or auto-archive on capture, configurable)
- Cider saves a complete snapshot of the page (HTML, CSS, images)
- Badge on the card indicates "Archived" — the bookmark is now immune to link rot
- Click to view the archived version inside Cider, even if the live URL is dead

**Technical approach:**
- `WKWebView.createWebArchiveData()` — macOS native API that saves a `.webarchive` bundle (HTML + all assets)
- Store alongside bookmark data in the Cider data directory (`.archives/{bookmark-id}.webarchive`)
- View archived pages in a WKWebView inside the detail popover or a dedicated viewer
- Storage could be significant — make archival opt-in per bookmark or per folder, with a storage indicator in Settings → Data

**Tiered approach:**
- *Tier 0:* Reader-mode text only (Readability-parsed article body saved as HTML/markdown — tiny, fast)
- *Tier 1:* Full `.webarchive` snapshot (complete page with styles and images — larger but faithful)
- *Tier 2:* Screenshot fallback (PNG of the rendered page — works for any page, even SPAs)

**Relationship to Documents tab:**
- Archived web pages could appear in the Documents tab as a "Web Archive" file type
- Or they stay attached to the bookmark as metadata — viewable via the bookmark's detail view

---

## Rich Media Capture

Extending image bookmarks beyond static images to support richer media types. Three tiers of increasing complexity:

### GIF Support (Low Effort)

GIF bookmarks are nearly supported already — most of the pipeline handles them:

- Add `public.gif` to `BookmarksClipboardMonitor.imageTypes` array
- GIF stored as original in `.originals/{id}.gif`, thumbnail is first-frame PNG extracted via `CGImageSourceCreateThumbnailAtIndex` (already works with GIF sources)
- `normalizedImageFileExtension` already handles `.gif` → no storage path changes needed
- Also add GIF support to `CiderServicesProvider.sendImageToCider` for macOS Services integration
- Card display: static first-frame thumbnail (no animation in grid/masonry — animation would be distracting and memory-heavy)
- Optional future: play GIF on hover in detail popover or reader view

### Video Bookmarks (Medium Effort, Clipboard Limitation)

Short video clips from Reddit, Instagram, TikTok, etc.:

- **Clipboard limitation:** Browsers don't put video data on the clipboard — only URLs. So clipboard capture can't grab video content directly.
- **Drag-drop of local files** is more feasible: accept `.mp4`/`.mov`/`.webm` drops onto bookmark cards (same pattern as image drops)
- Store short clips in `.originals/` with video thumbnail extraction via `AVAssetImageGenerator` (first frame or mid-point frame)
- **Card display:** Static thumbnail with play icon overlay — no inline video playback in grid/masonry
- **Playback:** Click to play in DetailPopoverPanel using `AVPlayerView` or embedded `WKWebView`
- **Storage implications:** Videos are orders of magnitude larger than images — needs size limits (e.g., 50MB max) or explicit opt-in
- **URL-based video bookmarks:** For Reddit/Instagram/TikTok URLs, could use yt-dlp or similar to download the video on capture — but this adds external dependencies and raises storage concerns

### Multi-Image Bookmarks / Carousels (Larger Effort)

Instagram posts, product comparisons, design inspiration boards — content that's naturally multi-image:

- **Model change:** `thumbnailRelativePaths: [String]?` and `originalImageRelativePaths: [String]?` (arrays alongside existing single-image fields for backward compat)
- **Storage naming:** `{bookmarkID}_0.png`, `{bookmarkID}_1.png`, etc. in both `.thumbnails/` and `.originals/`
- **Card UI:** Carousel with dot indicators or horizontal swipe gesture. Cover image (first by default, user-selectable) shown in grid/masonry.
- **Drag-drop:** Accept multiple images in a single drop (currently stops after first image). Could also support dropping a folder of images.
- **Use cases:** Instagram posts, product comparison screenshots, design inspiration boards, step-by-step tutorials, before/after pairs
- **Migration:** Existing single-image bookmarks continue to work unchanged — array fields are optional and nil by default

---

## Future Ideas

### Clipboard Viewer

Since Cider relies heavily on the clipboard for capturing bookmarks, images, and text, a dedicated clipboard viewer gives users a safety net — a way to see what's there and act on it when auto-capture misses something.

**V1 — Basic viewer:**

- Shows current clipboard contents in a scrollable feed: URLs, images, GIFs, text snippets, rich text, file references
- Single-column layout at default panel width; expands to multi-column when the panel is wider (same responsive pattern as masonry/grid)
- Each clipboard item has action buttons: "Save as Bookmark", "Save as Note", etc. — one click to route content to the right place
- Drag-and-drop from clipboard items to the library feed, folders in the sidebar, or specific tabs — same drag patterns as existing cards
- Clipboard history: show the last N items (macOS `NSPasteboard` tracks change count but not history natively — would need our own ring buffer, capturing snapshots on each `changeCount` increment)
- Accessible from the capture button area (popover or inline section) or as a dedicated tab

**Future — Privacy & safety:**

- App exclusion list: skip capturing clipboard changes from specific apps (password managers, banking apps, 1Password, etc.)
- Sensitive content detection: auto-redact or skip items that look like passwords, API keys, credit card numbers
- Configurable in Settings — off by default so the basic version ships without complexity
- Could also auto-expire clipboard history items after a configurable duration

---

## Open Questions
- Should clipboard auto-capture default to review mode or instant-save mode?
- Should there be per-site metadata adapters for high-value domains?
- What is the preferred UX for failed/blocked thumbnail fetches (badge vs details warning)?

## Known Issues — Content Capture
- **Opt+B hotkey only works in Chrome** — `ActiveBrowserCaptureService` AppleScript needs work for Safari, Arc, Firefox, Zen, and other browsers. Each browser has different AppleScript/JXA support for getting the frontmost tab URL.
- **Reader view right-click thumbnail** — Allow right-clicking an image in the reader/browser view and setting it as the bookmark's thumbnail (noted above in detail panel actions).
- **Reddit image CDN** — `external-preview.redd.it` returns HTTP 403 on direct download (hotlink protection). No known workaround — users can drag replacement thumbnails from the browser.
- **Instagram oEmbed deprecated** — Meta deprecated `api.instagram.com/oembed` (2025). Falls through to WebView/screenshot, which captures login wall. Would need Graph API credentials for real support.
