# AI & Intelligence

> Consolidated from AI_VISION.md, AI_IMPLEMENTATION.md, and AI_CHAT_VISION.md. Covers philosophy, on-device frameworks, implementation details, and the local model strategy.

## Philosophy

Cider's AI strategy is **local-first, zero-cost, progressive enhancement**. Every AI-powered feature has a non-AI fallback. AI makes things better, but nothing is broken without it.

- **Tier 0**: No AI — metadata extraction, heuristics, structural parsing
- **Tier 1**: Apple on-device AI — NaturalLanguage, Vision, Foundation Models (macOS 26+)
- **Tier 2**: Local enhanced model (optional) — user downloads Qwen 3.5 via MLX Swift for better quality

All AI runs locally. No cloud APIs, no accounts, no API keys. Cider ships as a one-time purchase with zero marginal AI cost.

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

### Phase 3: Local Enhanced Model (Planned)

MLX Swift integration with Qwen 3.5 for users who want better AI. See [Local Model Strategy](#local-model-strategy) below.

### Phase 4: Deeper Intelligence (Partially Shipped)

- Find Similar UI shipped (RelatedItemsView)
- Screen capture OCR shipped
- Smart folder suggestions, auto-organize nudges, App Intents — planned

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

| Feature | Tier 0 (No AI) | Tier 1 (Apple Intelligence) | Tier 2 (Local Enhanced Model) |
|---------|----------------|--------------------------|-------------------------------|
| Page summaries | Meta description + headings | Foundation Models, cross-checked | Qwen 3.5 full summarization |
| Auto-tagging | Domain-based tags | NaturalLanguage NER + keywords | Qwen 3.5 topic classification |
| Smart search | String + fuzzy matching | NLEmbedding semantic similarity | Qwen 3.5 intent understanding |
| Find similar | Same domain/folder | NLEmbedding cosine similarity | — |
| Screenshot capture | — | Vision OCR → text extraction | — |
| Image search | — | Vision OCR on thumbnails | — |
| YouTube transcripts | YouTube API captions | Speech framework fallback | — |
| Writing assistance | — | Writing Tools / Foundation Models | Qwen 3.5 long-form writing |
| Conversational assistant | — | Basic (short outputs) | Qwen 3.5 multi-turn chat with library context |
| Organization suggestions | — | — | Qwen 3.5 folder/grouping suggestions |

---

## Local Model Strategy

### Why Local Models

- **Privacy**: All data stays on-device. No cloud calls, no telemetry.
- **Cost**: Zero marginal cost. No API keys, no accounts, no subscriptions.
- **Offline**: Works without internet after initial model download.
- **Quality upgrade**: Qwen 3.5 is meaningfully better than Apple Intelligence for conversation, complex reasoning, and long-context tasks.

### Model Selection: Qwen 3.5

| | Qwen 3.5 4B | Qwen 3.5 9B |
|---|---|---|
| **Target users** | 8GB Macs | 16GB+ Macs |
| **Download size** | ~2.5 GB | ~5.5 GB |
| **RAM while loaded** | ~2.5 GB | ~5 GB |
| **Context window** | 32K tokens | 32K tokens |
| **License** | Apache 2.0 | Apache 2.0 |
| **HF model ID** | `mlx-community/Qwen3.5-4B-MLX-4bit` | `mlx-community/Qwen3.5-9B-MLX-4bit` |

**Why Qwen 3.5 over alternatives:**
- Apache 2.0 — cleanest license for commercial use (no restrictions, no attribution requirements)
- Tops benchmarks in both size classes as of March 2026
- 32K context — critical for feeding in the user's bookmark library during conversation
- Strong instruction following (91.5 IFBench for 9B) — reliable structured output for tagging/categorization
- MLX 4-bit versions already published on Hugging Face

**Models considered and rejected:**
- Mistral 7B — outdated, Apple's own 3B beats it on several benchmarks
- Phi-4 Mini — optimized for math/reasoning, weak at conversation and structured extraction
- Gemma 2 9B — Google's license allows unilateral usage revocation, 8K context limit
- Llama 3.1 8B — custom license with naming requirements, outperformed by Qwen 3.5

### Quality: Apple Intelligence vs Qwen 3.5

**Where the upgrade is marginal (~10-15% better):**
- Simple tagging/categorization — Apple's model is already decent
- Short 2-3 sentence summaries — a strength of Apple's model
- Keyword extraction — well within Apple's 3B capabilities

**Where the upgrade is significant:**
- Multi-turn conversation — Apple's model is tuned for short structured outputs, not chat
- Library-aware context — 32K tokens vs Apple's limited context window
- Complex organization — "group these 50 bookmarks into folders" requires reasoning Apple's model struggles with
- Long-form writing assistance — noticeably better for note writing
- Instruction following at scale — reliable structured output for bulk operations

### MLX Swift Integration

**Package:** `mlx-swift-lm` (MIT license, by Apple)
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm/", .upToNextMinor(from: "2.29.1"))
```

**Core API pattern:**
```swift
import MLX
import MLXLLM
import MLXLMCommon

// Set memory limits BEFORE loading
MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)  // 20 MB — prevents buffer bloat

// Load model (downloads on first use, cached after)
let model = try await loadModel(id: "mlx-community/Qwen3.5-4B-4bit")

// Streaming response
let session = ChatSession(model)
for try await text in session.streamResponse(to: "Summarize this bookmark") {
    self.output += text  // update UI incrementally
}

// Multi-turn — session maintains KV cache automatically
let response2 = try await session.respond(to: "What else is similar?")

// Unload — just nil out references, ARC handles deallocation
self.session = nil
self.modelContainer = nil
```

**Key technical details:**
- Models use safetensors format (not GGUF) — MLX-specific
- `ModelContainer` has a `perform {}` closure for thread-safe exclusive access
- `ChatSession` manages KV cache for efficient multi-turn (no re-processing prior turns)
- Download progress available via callback for UI progress bar
- Works on all Apple Silicon (M1+), macOS 14+

### Memory Management (Critical for Cider)

Cider is a floating panel that runs alongside other apps — memory discipline is essential.

**The buffer bloat problem:** MLX's Metal allocator pools GPU buffers for reuse. Without cache limits, a 4B model can balloon from ~2GB to ~10GB during inference. Always set:
```swift
MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)  // 20 MB cache limit
```

**Load/unload strategy:**
- Load model only when user opens AI chat or triggers an AI feature
- Keep model loaded during active use (loading takes a few seconds)
- Unload (nil out references) when user closes AI chat or after idle timeout
- KV cache grows with conversation length — long conversations on 8GB machines will eventually hit pressure

**Performance expectations (7B Q4):**
- M1/M2 base: ~10-15 tokens/sec
- M3 Pro/Max: ~20-40 tokens/sec
- Thermal throttling on MacBook Air is manageable for bursty chat (question → answer → pause)

### User Experience

**Settings UI:**
- "AI Model" section in Cider preferences
- Toggle: "Use Apple Intelligence" (on by default)
- Button: "Download Enhanced AI Model" with size estimate and disk space check
- Auto-detects available RAM and recommends 4B vs 9B
- Progress bar during download, pause/resume support
- "Remove Model" button to free disk space, falls back to Apple Intelligence

**Behavior:**
- If enhanced model is downloaded, it's used for all AI features (replacing Apple Intelligence for those tasks)
- Apple frameworks (NaturalLanguage, Vision, Core Spotlight) continue to run regardless — they handle different tasks
- If model fails to load (memory pressure, etc.), silently falls back to Apple Intelligence

---

## AI Chat

> **Status:** v1 shipped — floating panel with Foundation Models backend. CLI wrapper removed.

### What's Built

- Floating NSPanel with acrylic background, draggable, resizable, position persisted
- `AIAssistantProvider` protocol — swappable backends (Foundation Models now, MLX later)
- `FoundationModelsProvider` — streaming responses with context-aware instructions
- `AIAssistantViewModel` — conversation state, typewriter text reveal
- Chat bubble UI with streaming indicator (bouncing dots)
- Option+A global hotkey to toggle panel
- Sidebar "AI Assistant" button in footer
- Escape to close, trash to clear conversation

### Key Files

| File | Role |
|------|------|
| `Services/AI/AIAssistantProvider.swift` | Protocol, message model, context model |
| `Services/AI/AIAssistantTools.swift` | All 18 tools (read + write) for data access and actions |
| `Services/AI/FoundationModelsProvider.swift` | Apple Intelligence backend with tool registration |
| `ViewModels/AIAssistantViewModel.swift` | Conversation state, streaming, typewriter |
| `Views/AIAssistant/AIAssistantPanelView.swift` | Root panel view |
| `Views/AIAssistant/AIAssistantBubbleView.swift` | Message bubbles, bouncing dots |
| `Views/AIAssistant/AIAssistantInputView.swift` | Text input with send/stop |
| `App/AIAssistantPanel.swift` | NSPanel subclass with dragging |
| `App/AppDelegate+AIAssistantPanel.swift` | Panel lifecycle, show/hide |
| `Services/AIAssistantHotkeyDetector.swift` | Option+A hotkey |

---

## AI Chat Roadmap

### Tool Reference (Shipped)

All tools are defined in `Services/AI/AIAssistantTools.swift` and registered in `FoundationModelsProvider`. The model decides which tool to call based on the user's message.

**Read Tools — Query Cider's Data:**

| Tool | Example Query | What It Does |
|------|--------------|-------------|
| `countItems` | "How many bookmarks do I have?" | Counts any entity type or gives a full library summary |
| `searchItems` | "Find bookmarks about shoes" | Keyword search across bookmarks, notes, events, todos, contacts |
| `listFolders` | "What folders do I have?" | Lists all folders with item counts per type |
| `listTags` | "Show me my tags" | Lists all tags/labels with usage counts |
| `getRecentItems` | "What did I save this week?" | Items created/modified in the last N days |
| `getItemsByTag` | "What's tagged as Important?" | All items with a specific tag across all types |
| `getUpcomingEvents` | "What's coming up this month?" | Upcoming events in the next N days |
| `getOverdueTodos` | "Any overdue tasks?" | Incomplete todos past due date + high-priority items |
| `getFolderContents` | "What's in my Applications folder?" | Lists everything inside a specific folder |
| `getBrowserSessions` | "Show my saved sessions" | Saved browser tab groups with tab counts |
| `findSimilar` | "Find bookmarks similar to this one" | Cosine similarity via `EmbeddingStore` vectors |
| `getCurrentItem` | "Tell me about this" / "Summarize this" | Returns full details of whatever item the user is currently viewing |

**Write Tools — Organize & Create:**

| Tool | Example Query | What It Does |
|------|--------------|-------------|
| `createFolder` | "Create a Products folder" | Creates a new folder, optionally inside a parent |
| `moveToFolder` | "Move shoe bookmarks to Products" | Searches by keyword, moves matching items to a folder |
| `applyTag` | "Tag shoe bookmarks as Footwear" | Searches by keyword, applies tag (creates tag if needed) |
| `removeTag` | "Remove the Footwear tag from Vans" | Searches by keyword, removes specified tag |
| `renameBookmark` | "Rename 'Untitled' to 'Vans Store'" | Finds bookmark by current title, sets new title |
| `createNote` | "Create a note called Meeting Notes" | Creates note with title/content, optionally in a folder |
| `addBookmark` | "Save this URL as a bookmark" | Saves URL with optional title, folder, and tag |
| `summarizeText` | "Summarize this and save as a note" | Summarizes text via AI, optionally saves as a note in a folder |
| `deleteItem` | "Delete the Untitled bookmark" | Moves bookmark or note to trash (recoverable via undo) |
| `renameFolder` | "Rename Products to Shopping" | Renames an existing folder |
| `unfileItems` | "Remove Vans from its folder" | Moves items out of their folder back to root level |

**How tool calling works:**
1. User asks "how many bookmarks do I have?"
2. Model decides to call `countItems(itemType: "bookmarks")`
3. Tool executes on MainActor, queries `BookmarksStorage.shared.bookmarks.count`
4. Tool returns `"The user has 92 bookmarks."`
5. Model formats a natural response: "You have 92 bookmarks."

**Data sources for tools:**
- `BookmarksStorage.shared` — URLs, titles, tags, AI summaries, folders, dates
- `NotesStorage.shared` — titles, content, folders, labels
- `DateCardStorage.shared` — events with dates, location, recurrence, completion
- `TodoCardStorage.shared` — tasks with due dates, priority, checklists
- `ContactStorage.shared` — names, email, phone, relationship
- `CardLabelStorage.shared` — tags with colors, usage counts, `findOrCreate`
- `VaultFolderService.shared` — folder hierarchy with paths
- `ClipboardStorage.shared` — clipboard history
- `BrowserSessionStorage.shared` — saved browser tab groups
- `EmbeddingStore.shared` — vector embeddings for semantic similarity
- `SummaryService.shared` — AI text summarization

### Phase 1: Chat UI Polish (Next)

**Markdown rendering** — render bold, italics, lists, code blocks in assistant responses. Currently plain text only.

**Citations** — when the AI references a bookmark or note, show a clickable card/link the user can tap to open it. Users need to verify what the AI tells them.

**Conversation persistence** — save conversations as JSONL files in the vault (see [Conversation Storage](#conversation-storage)). One file per conversation, append-only.

**Message actions:**
- Copy button on messages
- Regenerate/retry button on assistant messages
- Timestamp display

**Conversation management:**
- Conversation list sidebar or popover
- Resume previous conversations
- Delete/archive conversations

### Phase 2: Confirmation UI for Write Actions

Add a confirm/cancel step before write tools execute, so the model proposes an action and the user approves.

```
AI: I'll create a "Products" folder and move 3 shoe-related
    bookmarks into it:
    - Vans Old Skool
    - Nike Air Max 90
    - Adidas Superstar

    [Confirm] [Cancel]
```

### Phase 3: MLX / Qwen 3.5 Integration

Add the downloadable local model as an alternative backend. Only after tool calling is solid — tools are what make the AI capable, the model quality makes conversations smoother.

- `MLXProvider` conforming to `AIAssistantProvider`
- Model download UI in settings (see [Local Model Strategy](#local-model-strategy))
- Auto-detect RAM and recommend 4B vs 9B
- Load/unload model on demand for memory discipline

### Phase 5: Advanced Features

- **RAG (Retrieval Augmented Generation)** — vector search across all items for semantic queries. Use existing `EmbeddingStore` or Apple's `NLContextualEmbedder`.
- **Custom instructions** — let users set personality/behavior preferences
- **Quick actions in sidebar** — context-sensitive buttons above the chat (Summarize, Auto-Tag, Organize)
- **Screen context** — feed screenshot OCR into chat (existing `ScreenCaptureService`)

---

## Conversation Storage

Conversations are stored as **JSONL files** (one JSON object per line) in the vault. Each conversation is a file the user owns on disk.

**Location:** `~/CiderVault/.cider/ai-conversations/`

**Format:** Each line is a self-contained JSON object — one per message.

```jsonl
{"id":"conv-550e8400","title":"Bookmark organization","created":"2026-03-19T14:20:00Z","model":"apple-intelligence","type":"metadata"}
{"id":"msg-1","role":"user","content":"How many bookmarks do I have?","timestamp":"2026-03-19T14:20:00Z"}
{"id":"msg-2","role":"assistant","content":"You have 92 bookmarks across 4 folders.","timestamp":"2026-03-19T14:20:03Z"}
{"id":"msg-3","role":"user","content":"Which ones are about shoes?","timestamp":"2026-03-19T14:21:10Z"}
{"id":"msg-4","role":"assistant","content":"I found 3 bookmarks about shoes:\n- **Vans Old Skool** (vans.com)\n- **Nike Air Max 90** (nike.com)\n- **Phone Rebel Cases** (phonerebel.com)","timestamp":"2026-03-19T14:21:15Z"}
```

**Why JSONL over markdown:**
- AI responses contain markdown formatting (bold, code blocks, lists) — storing markdown inside markdown creates unparseable escaping nightmares
- JSONL is append-only — each new message is one line appended to the file. Crash-safe (partial write only corrupts the last line, not the whole conversation)
- Unambiguous parsing — no delimiter confusion, no content-vs-formatting ambiguity
- Still human-readable — open the file and each line is a clear message object
- Used by Claude Code, Gemini CLI, and other production AI tools

**Why JSONL over SQLite:**
- File-on-disk — consistent with Cider's philosophy (users own their data)
- Portable — copy the file, done
- No database overhead for what amounts to sequential message logs

**Markdown export:** Users can export any conversation as a clean `.md` file for sharing or use in other tools. This is a one-way export, not the storage format.

**Filename:** `{date}-{auto-title}.jsonl` — e.g. `2026-03-19-bookmark-organization.jsonl`

**Auto-titling:** First user message (truncated) or AI-generated summary becomes the filename slug.

**Context window management:** For long conversations, older messages are summarized into a compact block prepended to the system prompt. The full JSONL history is preserved on disk but only the summary + recent messages are sent to the model.
