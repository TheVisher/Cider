# AI & Apple Intelligence Vision

## Philosophy

Cider's AI strategy is **local-first, zero-cost, progressive enhancement**. Every AI-powered feature must have a non-AI fallback that ships first. AI makes things better, but nothing is broken without it.

- Tier 0: No AI — metadata extraction, heuristics, structural parsing
- Tier 1: Apple on-device AI — Foundation Models, NaturalLanguage, Vision, Speech (macOS 26+)
- Tier 2: Cloud AI (optional) — user-configured API keys for higher quality on complex tasks

Users who don't want AI get a fully functional app. Users on Apple Silicon get intelligent features for free. Power users can plug in cloud APIs for maximum quality.

## Business Model Implications

**Apple on-device AI = zero marginal cost per user.** Apple trained and ships the model as part of macOS. Cider calls it for free. Every AI feature powered by Tier 1 is pure margin — charge for the app, pay nothing to provide intelligence.

This means Cider can ship AI features as a **one-time purchase** rather than a subscription. No per-user API costs to recoup. The app's value proposition includes AI without the recurring infrastructure burden.

**Cloud AI (Tier 2) is optional and user-funded.** Users who want higher-quality summarization or custom prompts bring their own API keys. Cider facilitates the connection but bears no cost.

**Cross-platform implications:** If Cider ever ships on Windows/Linux, Apple frameworks aren't available. Those platforms would need:

- Bundled local models (Ollama, llama.cpp, Whisper) as the Tier 1 replacement
- Or cloud APIs as the primary intelligence layer
- This could justify a subscription model on non-Apple platforms where AI costs are real
- macOS remains the premium experience with the deepest, free-est AI integration

---

## Apple Frameworks Available to Cider

### Foundation Models (macOS 26+)

Apple's on-device LLM, shipped with macOS. Same model powering Writing Tools, Siri, notification summaries. No download, no API key, no cost.

```swift
import FoundationModels
```

`let session = LanguageModelSession() let response = try await session.respond(to: "Summarize: ...")`

**Runs on:** Apple Silicon Neural Engine (any Mac supporting Apple Intelligence)
**Strengths:** Private, instant, free, no network needed
**Limits:** Smaller model than cloud LLMs — good for summarization, extraction, classification. Not ideal for complex reasoning or long-form generation.

**Cider use cases:**

- Page summarization (Tier 1 in the tiered summary system)
- Auto-generate bookmark titles from page content
- Auto-tag bookmarks and notes with keywords/topics
- Smart search — understand intent, not just keyword matching ("find that article about React performance")
- Note title suggestions from content
- Generate transcript summaries for saved YouTube transcripts
- Higher-level content classification ("programming tutorial" vs "news article" vs "recipe")

### Speech Framework (SFSpeechRecognizer)

On-device speech-to-text. Powers Dictation and live captions on macOS.

**Cider use cases:**

- **YouTube transcription fallback** — most YouTube videos have captions available via YouTube's API (auto-generated or human-written). Pull those first — they're free, accurate, and already timestamped. For the rare video without captions, fall back to Speech framework: extract the audio stream and transcribe locally.
- Voice note capture — dictate a note into Cider via speech-to-text
- Audio bookmark annotation — record a voice memo about a bookmark

**Limits:** Good accuracy for clear speech, struggles with heavy accents or noisy audio. Not Whisper-quality, but adequate for most YouTube content. For higher accuracy on captionless videos, Whisper (bundled or via cloud) would be Tier 2.

### NaturalLanguage Framework

Mature on-device NLP. No Apple Intelligence requirement — works on any Mac.

**Capabilities:**

- Named entity recognition (extract people, places, organizations from text)
- Sentiment analysis (article tone detection)
- Language detection (auto-detect content language)
- Word/sentence embeddings (vector similarity between text)
- Tokenization and sentence segmentation
- Keyword extraction via TF-IDF scoring

**Cider use cases:**

- **Auto-tagging pipeline:** On bookmark capture → NaturalLanguage extracts entities and keywords → suggest tags and folder placement. "This article mentions React, TypeScript, and Vercel → tag: web-dev, suggest: Web Dev folder."
- **"Find similar" items:** Every bookmark/note gets an embedding vector computed on save. When you open an item, Cider instantly shows related items by vector distance. No AI call needed — it's a math operation on precomputed vectors. See **Similar Items Discovery** section below for full spec.
- **Smart folder suggestions:** "You saved 12 React articles this week — create a folder?"
- **Extractive summarization:** TextRank powered by NaturalLanguage tokenization. Sentences scored by graph centrality, top N picked as summary. Real sentences from the page — never "wrong" — but selection quality is mediocre and output feels choppy compared to AI summaries.
- **Search ranking:** Weight results by semantic similarity, not just string matching. Search "performance optimization" and find articles about "speeding up React renders" even if they don't contain those exact words.

### Vision Framework

On-device image analysis and OCR. Powers **Live Text** on macOS — the feature where you can select and copy text from any image.

**OCR quality:** Genuinely excellent. Fast, handles multiple languages, works with messy fonts, complex layouts, and even handwriting. One of Apple's strongest on-device ML features.

**Cider use cases:**

- **Screenshot-to-text page capture:** Alternative to Chrome extension — screenshot the page, Vision OCR extracts all text, then summarize/index it. Works with any browser, any app, no extension needed.
- **Image search indexing:** Extract text from bookmark thumbnails and note images → make them searchable. Search "recipe" and find a bookmark whose thumbnail contains recipe text.
- **GIF Finder concept** (HOME_VISION.md): Screenshot a conversation → OCR the text → understand context → find the perfect reaction GIF.
- **Image-based note search:** Find notes containing images with specific text visible in them.

### Writing Tools (Free Integration)

Apple Intelligence Writing Tools (Summarize, Proofread, Rewrite) are available to any text view that adopts standard text input protocols. Native NSTextView/TextEditor gets this for free.

**Cider considerations:**

- TipTap editor is WKWebView-based — Writing Tools won't auto-integrate. Would need to bridge via JS or offer our own UI that calls Foundation Models.
- Any native SwiftUI text fields in the app (note titles, bookmark descriptions, search) get Writing Tools automatically.
- Could add a "Rewrite" or "Proofread" button in the notes editor that calls Foundation Models directly.

### Core Spotlight

Index Cider content into macOS system search.

**Cider use cases:**

- Bookmark titles, URLs, and summaries indexed → users find bookmarks from Spotlight
- Note titles and content previews indexed → notes searchable system-wide
- Saved transcripts searchable from Spotlight
- Deep links: Spotlight result opens Cider directly to that bookmark/note

### App Intents / Shortcuts

Expose Cider actions to Siri and the Shortcuts app.

**Potential intents:**

- "Bookmark this URL" — capture current browser URL
- "Create a note" — open Cider with a new note
- "Summarize this page" — trigger summary from Siri
- "Search my bookmarks for \[query\]" — search without opening Cider
- "Read my transcript" — speak the saved transcript of a video

---

## Similar Items Discovery

When viewing any item in Cider, show related items the user may have forgotten about or not connected mentally. This turns Cider from a passive storage tool into an active knowledge network.

### How It Works

1. **On save:** Compute a text embedding vector for each bookmark/note using `NLEmbedding` (Apple's on-device sentence embeddings)
   - Bookmarks: embed `title + description + tags + notes`
   - Notes: embed `title + first 500 chars of body`
   - Store the vector alongside the item (compact float array, ~2KB per item)

2. **On view:** When the user opens a bookmark detail or note editor, compute cosine similarity between that item's vector and all other stored vectors
   - Return the top 3-5 most similar items
   - Exclude items in the same folder (the user already knows those are related)
   - Computation is pure math on local vectors — instant, no network, no AI API call

3. **Display:** "Related items" section in the detail popover or a sidebar panel
   - Small card previews with title + thumbnail
   - Click to navigate directly to the related item
   - Builds serendipitous connections: "I forgot I saved that React performance article when I'm looking at this webpack config bookmark"

### Integration with Resurfacing

Similar items discovery complements the resurfacing system (see `HOME_VISION.md` → Resurfacing & Rediscovery):
- Resurfacing surfaces **forgotten** items proactively (low engagement score)
- Similar items surfaces **related** items contextually (when you're already looking at something)
- Together they keep the library feeling alive and interconnected

### Card Metadata Enrichment

With Foundation Models (macOS 26+), AI can go further:
- Auto-generate a "related to" field in each item's metadata listing similar item IDs
- Pre-compute relationships on save (background task), not just on view
- Enable a "knowledge graph" view showing clusters of related content (future visualization)

### Implementation Priority

This is a Tier 1 feature (NaturalLanguage framework, no Apple Intelligence required):
- `NLEmbedding.wordEmbedding(for: .english)` is available on any Mac
- Sentence-level embeddings via `NLEmbedding.sentenceEmbedding(for: .english)` for better quality
- No API keys, no cloud, no privacy concerns
- Only dependency: embedding model download on first use (~50MB)

---

## Related Link Suggestion (Entity-Scoped)

This is distinct from "Similar Items Discovery." Similar items finds relationships between items already in Cider. Related link suggestion enriches a single bookmark with additional URLs about the same entity (for example: App Store page + GitHub repo + official site for one app).

### Product Direction (Planned)

- Keep one canonical bookmark per product/entity.
- Add related links as metadata on that bookmark.
- Provide two entry points in detail view:
  - `Add Related Link` (manual)
  - `Suggest Related Content` (AI-assisted)
- Suggestions are always user-confirmed before attachment.

### Suggested Pipeline (Planned)

1. Extract entity signals from the current bookmark:
   - normalized name
   - publisher/developer/org
   - source domain
2. Run high-confidence discovery first:
   - official site
   - App Store / Play Store listing
   - GitHub repo/org
   - docs/support pages
3. Run broader semantic/fuzzy discovery only if needed.
4. Rank with confidence and include a short reason string.
5. Dedupe/canonicalize URLs and present top candidates for selection.

### Ranking Signals (Planned)

- Positive:
  - exact entity name match
  - publisher/developer match
  - trusted platform match
  - path/type match (`/docs`, GitHub org/repo pattern)
  - official root-domain alignment
- Negative:
  - conflicting publisher/category
  - weak common-term-only matches
  - already-saved duplicates
  - low-trust/suspicious domains

---

## The Auto-Enrichment Pipeline

When a user captures a bookmark, this happens automatically — all on-device, all instant:

```
URL captured
├─ Tier 0: Fetch metadata (title, meta description, OG tags, headings)
├─ Tier 0: Fetch/generate thumbnail
├─ Tier 1: NaturalLanguage extracts entities and keywords → auto-tags
├─ Tier 1: NaturalLanguage computes embedding vector → enables "find similar"
├─ Tier 1: Vision OCR indexes text in thumbnail → image search
├─ Tier 1: Foundation Models generates 2-sentence summary (if page content available)
│          Cross-checked against author's meta description for accuracy
└─ Index in Core Spotlight → searchable from macOS Spotlight
```

The **hybrid summary validation** approach: when the page has a human-written meta description, use it as a ground truth anchor. Foundation Models generates its summary, then we compare — if the AI summary contradicts the author's description, weight the author's version. Display both: author's one-liner at top, AI deeper summary below.

For YouTube bookmarks, the pipeline extends:

```
YouTube URL captured
├─ All standard bookmark enrichment (above)
├─ Fetch captions via YouTube API (preferred — already timestamped)
├─ If no captions: Speech framework transcription (fallback)
├─ Foundation Models summarizes transcript → bullet points
└─ Transcript stored as bookmark artifact → searchable, browsable
```

---

## Feature Integration Map

| Feature | Tier 0 (No AI) | Tier 1 (Apple On-Device) | Tier 2 (Cloud API) |
| --- | --- | --- | --- |
| **Page summaries** | Meta description + headings + first paragraph | Foundation Models summarization, cross-checked against author metadata | Claude/GPT full summarization with custom prompts |
| **Auto-tagging** | Domain-based tags (youtube.com → "Video") | NaturalLanguage NER + keyword extraction | LLM-powered topic classification |
| **Smart search** | String matching + fuzzy search | NaturalLanguage embeddings for semantic similarity | LLM intent understanding ("what did I save last week about...") |
| **Note suggestions** | — | Foundation Models title/tag generation | — |
| **YouTube transcripts** | Pull captions from YouTube API | Speech framework fallback for captionless videos | Whisper API for high-accuracy transcription |
| **Transcript summaries** | — | Foundation Models bullet-point summary | Cloud LLM detailed analysis |
| **Find similar** | Same domain / same folder | NaturalLanguage embedding vector similarity | — |
| **Screenshot capture** | — | Vision OCR → text extraction → summarize | — |
| **Image search** | — | Vision OCR indexes text in images/thumbnails | — |
| **Writing assistance** | — | Writing Tools / Foundation Models | Cloud LLM for complex editing |
| **Conversational assistant** | — | Foundation Models with library context | Cloud LLM for complex reasoning over large libraries |

---

## Conversational AI Assistant

Foundation Models supports full conversational interaction — sessions with memory, system instructions, and structured output. This means Cider can have a **chat interface that knows your entire library**.

### Concept

A chat bar or conversational surface in the panel where you talk to your collection in natural language. The model runs locally, responds instantly, and never sends your data off-device.

### How It Works

Foundation Models supports:

- **Conversation sessions** — back-and-forth where the model remembers prior messages
- **System instructions** — tell the model its role and what data it has access to
- **Structured output** — model returns typed Swift objects, not just text (e.g., returns a `[BookmarkID]` array)

```swift
let session = LanguageModelSession(instructions: """
You are Cider's library assistant. The user has (bookmarkCount) bookmarks
and (noteCount) notes. Here are their folders: (folderList).
Answer questions about their saved content.
""")
```

<p></p>

`// Feed it context about the user's library let response = try await session.respond(to: "What sci-fi movies do I have saved?") // Model responds based on the library data in its context`

### Example Interactions

**Querying your collection:**

- "What did I save last week?"
- "Find bookmarks about Swift concurrency"
- "What recipes do I have that use chicken and take under 30 minutes?"
- "Show me movies in my watchlist rated above 80% on Rotten Tomatoes"
- "How many unread articles do I have in my Web Dev folder?"

**Acting on your collection:**

- "Move all React articles to my Frontend folder"
- "Tag these 5 bookmarks as 'research'"
- "Create a new folder called Travel and move my trip bookmarks there"
- "Summarize all the notes I wrote this week into one paragraph"
- "What bookmarks do I have that are similar to this one?"

**Cross-referencing:**

- "Do I have any notes that reference the same topics as this bookmark?"
- "What's the overlap between my Work folder and my Learning folder?"
- "Which of my saved recipes use ingredients I bookmarked from that grocery site?"

### UX Options

**Option A: Chat bar in panel**

- Persistent text field at the bottom of the panel (like Spotlight but conversational)
- Responses appear inline above the input, push content up
- Tap a result to navigate to that item
- Conversation clears when panel closes (ephemeral, not a chat history)

**Option B: Chat overlay**

- Triggered by hotkey (Cmd+L or similar) or a button
- Slides up as an overlay within the panel
- Fullscreen conversational surface with the library as context
- Dismiss to return to normal browsing

**Option C: Integrated into search**

- Enhance the existing Cmd+K search palette with conversational mode
- Simple queries → standard search results (as today)
- Natural language queries → Foundation Models interprets and responds
- The model decides whether to show items, answer a question, or take an action

### Context Window Management

The on-device model has a limited context window (smaller than cloud LLMs). Strategy for fitting the user's library:

- **Don't dump everything in.** Feed relevant slices based on the query.
- Use NaturalLanguage embeddings to find the most relevant bookmarks/notes for a query, then feed only those into the conversation context.
- System instructions describe the library structure (folder names, item counts, tags). Detailed content loaded on demand.
- For themed folders (Media Hub, Recipes), feed structured metadata (titles, scores, tags) rather than full page content — much more compact.

```
User asks: "What sci-fi movies do I have?"
```

<p></p>

1. `NaturalLanguage embedding search: find items tagged/classified as sci-fi`
2. `Feed those 15 results into Foundation Models context`
3. `Model responds with a natural language list + structured IDs`
4. `Cider renders the referenced items as tappable cards below the response`

### Structured Output for Actions

Foundation Models can return typed Swift structs, not just text. This means the model can return actionable data:

```swift
@Generable
struct LibraryAction {
let intent: ActionIntent  // .search, .move, .tag, .summarize, .create
let targetIDs: [String]   // bookmark/note IDs to act on
let destination: String?  // folder name for .move
let tags: [String]?       // tags for .tag
}
```

`// "Move my React articles to Frontend folder" // → LibraryAction(intent: .move, targetIDs: [...], destination: "Frontend")`

This bridges natural language input to concrete app actions — the model understands intent, Cider executes it.

---

## Implementation Priority

**Phase 1: Non-AI foundations**

- Tier 0 page summaries (metadata + headings + first paragraph)
- ✅ Core Spotlight indexing for bookmarks and notes (`SpotlightIndexer`)
- ✅ NaturalLanguage keyword extraction for auto-tagging (`AutoTagService`)
- ✅ NaturalLanguage embedding computation on save (`EmbeddingStore`, persisted to disk)
- ✅ Vision OCR indexing for image search (`OCRService`)
- ✅ Dominant color extraction on capture (`ColorExtractionService`)

**Phase 2: Foundation Models integration**

- ✅ Page summarization via Foundation Models — `SummaryService` triggered from `BookmarkReaderView` after Readability extraction. Guards on Apple Intelligence availability and existing `aiSummary`.
- Smart bookmark title generation
- Note title suggestions
- Transcript summarization
- Content classification for smarter organization

**Phase 3: Conversational assistant**

- Chat bar / overlay UI in the panel
- Foundation Models session with library context injection
- NaturalLanguage embedding pre-search to scope context for queries
- Structured output for actionable responses (move, tag, create)
- Natural language queries over themed folders (media, recipes)

**Phase 4: Deeper intelligence**

- ✅ "Find similar" UI — `RelatedItemsView` in bookmark detail panel (up to 3 related items via `SimilarItemsService` + cosine similarity on `EmbeddingStore`)
- ✅ Screen capture OCR — `ScreenCaptureService` (ScreenCaptureKit), `ScreenCaptureOCRRouter` (NSDataDetector), routing toast (Note / Date Card / Contact). Triggered by Opt+Cmd+2 hotkey or title bar button. Toast appears before Cider restores so it's never hidden behind the panel.
- Smart folder suggestions based on content patterns
- Auto-organize nudges ("You saved 12 React articles this week — create a folder?")
- App Intents for Siri and Shortcuts integration

**Phase 5: Cloud AI (optional, cross-platform prep)**

- User-configurable API provider (OpenAI, Anthropic, Ollama)
- Higher-quality summarization for complex content
- Custom prompt support ("Summarize for a 5-year-old", "Extract action items")
- Settings UI for API key management
- Whisper integration for high-accuracy transcription
- This phase also establishes the abstraction layer needed for non-Apple platforms

---

## Open Questions

- Foundation Models availability: what happens on Macs that don't support Apple Intelligence (Intel Macs, older Apple Silicon)? Tier 0 fallback is critical. NaturalLanguage framework still works on all Macs.
- Should AI features be behind a toggle in settings, or just work silently?
- Embedding storage: compute on save and store in a local vector index? Or compute on-demand? Pre-computing enables instant "find similar" but increases storage.
- Writing Tools in TipTap: bridge via JS message passing, or build our own summarize/rewrite UI?
- YouTube caption fetching: use the public timedtext endpoint, or require YouTube Data API key? Public endpoint is fragile but free.

<p></p>
