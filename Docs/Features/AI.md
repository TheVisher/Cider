# AI & Intelligence

> Consolidated from AI_VISION.md, AI_IMPLEMENTATION.md, and AI_CHAT_VISION.md. Covers philosophy, on-device frameworks, implementation details, and the AI Chat feature.

## Philosophy

Cider's AI strategy is **local-first, zero-cost, progressive enhancement**. Every AI-powered feature has a non-AI fallback. AI makes things better, but nothing is broken without it.

- **Tier 0**: No AI — metadata extraction, heuristics, structural parsing
- **Tier 1**: Apple on-device AI — NaturalLanguage, Vision, Foundation Models (macOS 26+)
- **Tier 2**: Cloud AI (optional) — user-configured API keys for higher quality

Apple on-device AI = zero marginal cost per user. Cider can ship AI as a one-time purchase. Cloud AI (Tier 2) is optional and user-funded (BYOK).

---

## Apple Frameworks

| Framework | Requirement | Used For |
|-----------|-------------|----------|
| NaturalLanguage | Any Mac (macOS 14+) | Auto-tagging, embeddings, keyword extraction, "find similar" |
| Vision | Any Mac (macOS 14+) | OCR on thumbnails/screenshots, image text indexing |
| Foundation Models | Apple Intelligence (macOS 26+, Apple Silicon) | Page summarization, title suggestions, conversational assistant |
| Speech | Any Mac | YouTube transcription fallback (when no captions) |
| Core Spotlight | Any Mac | System-wide search indexing |
| App Intents | Any Mac | Siri and Shortcuts integration |

---

## Implementation Status

### Phase 1: NaturalLanguage Foundations (Shipped)

All work on any Mac. No Apple Intelligence required.

**Auto-Tagging** — `NLPipeline.swift`
- Triggers on bookmark save via `.bookmarkDidSave` notification
- Named entity recognition (people, orgs, places) + TF-IDF keyword extraction
- Merges suggested tags with user-set tags (never overwrites)
- Gated by `CiderConfig.enableAutoTagging`

**Embeddings + Find Similar** — `EmbeddingStore.swift`, `SimilarItemsService.swift`, `RelatedItemsView.swift`
- Each bookmark/note gets an `NLEmbedding` sentence vector (~2KB per item)
- Stored in `.cider/ai/embeddings.json`, loaded lazily, kept in memory
- Cosine similarity over all vectors to find top 3 related items
- Shown in bookmark detail panel as "Related" section
- Falls back to word embeddings if sentence model unavailable
- Gated by `CiderConfig.enableEmbeddings`

**OCR Indexing** — `OCRService.swift`
- Vision framework OCR on bookmark thumbnails after `assignThumbnail()`
- Extracted text stored as `ocrText` field in bookmark metadata
- Included in search matching
- Opt-in via `CiderConfig.enableOCRIndexing`

**Screen Capture OCR** — `ScreenCaptureService.swift`, `ScreenCaptureOCRRouter.swift`
- Triggered by Opt+Cmd+2 or title bar button
- ScreenCaptureKit captures screen, NSDataDetector routes content
- Toast appears for routing to Note / Date Card / Contact

**Core Spotlight** — `SpotlightIndexer.swift`
- Bookmark titles, URLs, summaries indexed for system-wide search

**Dominant Colors** — `ColorExtractionService.swift`
- Extracted from bookmark thumbnails on capture

### Phase 2: Foundation Models (Partially Shipped)

Requires macOS 26+ with Apple Intelligence. Gated by `AIAvailability.isFoundationModelsAvailable`.

**Page Summarization** — `SummaryService.swift` (Shipped)
- Triggers from `BookmarkReaderView` after Readability extraction
- 2-3 sentence summary stored as `aiSummary` field
- Cross-checked against author's meta description
- Shown in bookmark detail metadata sidebar
- Gated by `CiderConfig.enablePageSummaries`

**Title Suggestions** (Planned)
- Detects generic titles (hostname, "Home | Site Name", etc.)
- "Suggest title" button in metadata sidebar
- One-click accept/edit/dismiss

### Phase 3: Conversational Assistant (Planned)

Foundation Models conversation sessions with library context injection. NaturalLanguage embeddings pre-filter relevant items into the context window.

### Phase 4: Deeper Intelligence (Partially Shipped)

- Find Similar UI shipped (RelatedItemsView)
- Screen capture OCR shipped
- Smart folder suggestions, auto-organize nudges, App Intents — planned

### Phase 5: Cloud AI (Planned)

User-configurable API provider (OpenAI, Anthropic, Ollama). BYOK model.

---

## File Structure

```
Sources/Cider/Services/AI/
├── AIAvailability.swift          # Capability detection
├── NLPipeline.swift              # Tagging, embeddings, keyword extraction
├── SummaryService.swift          # Foundation Models page summaries
├── OCRService.swift              # Vision OCR
├── EmbeddingStore.swift          # Persist + query NLEmbedding vectors
├── SimilarItemsService.swift     # Cosine similarity over EmbeddingStore
├── AutoTagService.swift          # Auto-tagging orchestration
├── ColorExtractionService.swift  # Dominant color extraction
├── ScreenCaptureService.swift    # ScreenCaptureKit integration
├── ScreenCaptureOCRRouter.swift  # NSDataDetector routing
└── SpotlightIndexer.swift        # Core Spotlight indexing
```

### CiderConfig Keys

```swift
var enableAutoTagging: Bool        // default: true
var enableEmbeddings: Bool         // default: true
var enablePageSummaries: Bool      // default: true (silently off on unsupported hardware)
var enableOCRIndexing: Bool        // default: false (opt-in)
```

---

## Feature Integration Map

| Feature | Tier 0 (No AI) | Tier 1 (Apple On-Device) | Tier 2 (Cloud API) |
|---------|----------------|--------------------------|---------------------|
| Page summaries | Meta description + headings | Foundation Models, cross-checked | Claude/GPT full summarization |
| Auto-tagging | Domain-based tags | NaturalLanguage NER + keywords | LLM topic classification |
| Smart search | String + fuzzy matching | NLEmbedding semantic similarity | LLM intent understanding |
| Find similar | Same domain/folder | NLEmbedding cosine similarity | — |
| Screenshot capture | — | Vision OCR → text extraction | — |
| Image search | — | Vision OCR on thumbnails | — |
| YouTube transcripts | YouTube API captions | Speech framework fallback | Whisper API |
| Writing assistance | — | Writing Tools / Foundation Models | Cloud LLM |

---

## AI Chat

> **Status:** v1 built and working. Conversation persistence in progress.

A native chat interface embedded in Cider that talks to CLI-based AI tools (Claude, Gemini, Codex). No browser tabs, no separate apps — AI access from the floating panel.

### What's Built

- Native SwiftUI chat bubble interface (no SwiftTerm dependency)
- Model selector pills: Claude, Gemini, Codex. Shell via chevron expander.
- **One-shot mode**: Runs `claude -p "message"`, captures stdout, displays as bubble. Each message = independent process.
- **Shell mode**: Persistent shell session for terminal usage.
- **Dock/Undock**: Works as a tab (docked) or floating window (undocked). Shared `AIChatViewModel.shared` singleton.
- PATH resolution for homebrew, nvm, npm global, cargo.
- ANSI escape code stripping.

### Key Files

| File | Role |
|------|------|
| `Models/AIChatMessage.swift` | Message model |
| `Models/AIModelOption.swift` | Model definitions with CLI commands |
| `Services/AI/AIChatProcessService.swift` | Process management, PATH, ANSI stripping |
| `ViewModels/AIChatViewModel.swift` | Shared singleton, message list |
| `Views/AIChat/AIChatView.swift` | Main view |
| `Views/AIChat/AIChatBubbleView.swift` | Bubble rendering |
| `Views/AIChat/AIChatInputView.swift` | Text input |
| `App/AIChatPanel.swift` | Floating NSPanel for undocked mode |

### Planned

- **Conversation history** — JSON files in `.cider/ai-chat/`, resumable via `--resume <session-id>`
- **Conversation selector** — slide-out panel to browse/resume past chats
- **Markdown export** — clean markdown from any conversation
- **Custom agent support** — user-defined CLI backends in the model picker
- **Streaming markdown rendering** — code blocks, links, etc. in bubbles
- **Tool use visualization** — show file reads/edits in chat
