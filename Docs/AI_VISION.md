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

let session = LanguageModelSession()
let response = try await session.respond(to: "Summarize: ...")
```

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
- **"Find similar" items:** Every bookmark/note gets an embedding vector computed on save. When you open an item, Cider instantly shows related items by vector distance. No AI call needed — it's a math operation on precomputed vectors.
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
- "Search my bookmarks for [query]" — search without opening Cider
- "Read my transcript" — speak the saved transcript of a video

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
|---------|----------------|--------------------------|---------------------|
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

---

## Implementation Priority

**Phase 1: Non-AI foundations**
- Tier 0 page summaries (metadata + headings + first paragraph)
- Core Spotlight indexing for bookmarks and notes
- NaturalLanguage keyword extraction for auto-tagging
- NaturalLanguage embedding computation on save (prep for "find similar")

**Phase 2: Foundation Models integration**
- Page summarization via on-device LLM with author-metadata cross-check
- Smart bookmark title generation
- Note title suggestions
- Transcript summarization
- Content classification for smarter organization

**Phase 3: Deeper intelligence**
- NaturalLanguage embeddings powering "find similar" UI
- Vision OCR for screenshot-based capture and image search indexing
- Smart folder suggestions based on content patterns
- Auto-organize nudges ("You saved 12 React articles this week — create a folder?")
- App Intents for Siri and Shortcuts integration

**Phase 4: Cloud AI (optional, cross-platform prep)**
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
- Could we use Foundation Models for conversational search? ("What did I bookmark last week about Swift concurrency?")
- Writing Tools in TipTap: bridge via JS message passing, or build our own summarize/rewrite UI?
- YouTube caption fetching: use the public timedtext endpoint, or require YouTube Data API key? Public endpoint is fragile but free.
