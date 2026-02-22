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

## Label and Stack Integration

Bookmarks participate in the cross-entity label and stack system alongside date cards and contacts.

- The `CardLabel` system is cross-entity — labels can be assigned to bookmarks, date cards, and contacts
- Bookmarks can be included in stacks via **manual refs** (explicitly added) or **rule matches** (e.g., stack filtering for a specific label)
- Filter chips in saved views allow label-based filtering across all entity types simultaneously
- Example use cases:
  - Tag a bookmark with a "Gift Idea" label → it surfaces in a partner's birthday stack
  - Tag concert/event bookmarks with a "Tickets" label → a stack filters for upcoming events
  - Color-code bookmarks by project or person for quick visual scanning in mixed-content views

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

## Phase 2: Bookmark Details Surface ✅
1. ✅ Add bookmark details panel (on thumbnail click / info action).
2. ✅ Show/edit metadata:
- ✅ canonical URL
- ✅ title
- ✅ tags
- ✅ notes
- thumbnail source/local status (partial — hero preview, no separate indicator)
3. ✅ Add actions:
- replace/remove thumbnail (drag-and-drop on card)
- ✅ copy URL
- ✅ open in browser
- ✅ open original image (if local original exists, else remote fallback)

### Acceptance Criteria
- ✅ Details panel opens reliably from cards in all layouts (BookmarksTabContent, HomeDashboardView, FolderDetailView).
- ✅ Edits persist and reflect immediately in card/list views.
- ✅ Keyboard navigation and accessibility behavior match existing panel standards.

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

**Concept:** When a YouTube video is playing in Chrome, Cider shows a live-scrolling transcript in the panel. Words/sentences highlight in real-time as the video plays. No embedded video player — the video stays in Chrome, the transcript lives in Cider.

**Why not an embedded player?**
- macOS already has Picture-in-Picture for mini players
- Video eats panel real estate in a floating panel
- Cider's identity is "companion to your browser," not "replacement for your browser"
- The transcript-only approach is something no one else does

**Core experience:**
- Open a YouTube video in Chrome → Cider detects it and offers to show the transcript
- Transcript scrolls automatically, highlighting the current sentence/word
- Click any line in the transcript → seeks the video to that timestamp
- Search within the transcript while the video plays
- Copy/highlight passages directly into Cider notes
- Transcript persists as a bookmark artifact — even after closing the video tab, you have the full text

**Technical approach:**
- Lightweight Chrome extension (or piggyback on existing MCP/extension pattern) reads `document.querySelector('video').currentTime` and video metadata
- Extension sends playback state to Cider via WebSocket or local IPC
- Cider fetches transcript data via YouTube's caption/subtitle API (or scrapes the timedtext endpoint)
- Timestamps in transcript data map to highlight positions
- Bidirectional: Cider click → extension seeks video; video plays → Cider scrolls

**Optional future: detach mode**
- If someone wants to close the Chrome tab but keep watching, offer to pull the video into a small embedded WKWebView player within Cider
- This is the escape hatch, not the primary experience

**Open questions:**
- Should transcript auto-appear when a YouTube tab is detected, or require a manual "Show Transcript" action?
- Should transcripts be saved automatically with the bookmark, or only on explicit save?
- Support for other video platforms (Vimeo, Twitch VODs) — same pattern, different caption APIs?
- Could we generate transcripts via local Whisper for videos without captions?

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

**Concept:** Open saved links in a clean, distraction-free reading view inside Cider's panel — no ads, no navigation chrome, no cookie banners. Read articles, blog posts, and documentation without leaving Cider or opening a browser tab.

**Core experience:**
- Click "Read" on a bookmark card (or a dedicated button in the detail popover)
- Cider fetches the page content and runs it through a Readability parser (strip ads, nav, sidebars → extract article body)
- Clean article renders in a reader view inside the panel — title, author, date, body text, images
- Typography and spacing match Cider's design system (CiderFont, CiderColors)
- Reader view can be scrolled, text selected, passages highlighted or copied to a note

**Why this fits Cider:**
- Cider is already a reading companion — it saves links. Reader mode makes it a reading *tool*, not just a link repository.
- The floating panel is the perfect surface for focused reading alongside your browser
- Reader content can be saved as a permanent offline copy (see Web Archival below)
- Future integration with the Books tab — reader mode is the core reading experience for both web articles and longer-form content

**Technical approach:**
- Readability.js (Mozilla's open-source parser) runs in a lightweight WKWebView — same pattern as the TipTap editor
- Alternatively, use the existing enrichment pipeline to fetch HTML and parse article content server-side (no extra WebView)
- Reader view renders in the DetailPopoverPanel or inline in the content area (push/pop like the notes editor)
- CSS theme matches the panel aesthetic (dark mode, acrylic-compatible)

**Open questions:**
- Should reader mode be a separate view or replace the detail popover?
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

## Open Questions
- Should clipboard auto-capture default to review mode or instant-save mode?
- Should there be per-site metadata adapters for high-value domains?
- What is the preferred UX for failed/blocked thumbnail fetches (badge vs details warning)?
