# AI & Intelligence

> Single source of truth for Cider's AI architecture, tools, and roadmap.

## Philosophy

Cider's AI strategy is **local-first, zero-cost, progressive enhancement**. Every AI-powered feature has a non-AI fallback. AI makes things better, but nothing is broken without it.

- **Tier 0**: No AI — metadata extraction, heuristics, structural parsing
- **Tier 1**: Apple on-device AI — NaturalLanguage, Vision, Foundation Models (macOS 26+)
- **Tier 2**: Local enhanced model (optional) — user downloads Qwen 2.5 via MLX Swift for better conversation quality

All AI runs locally. No cloud APIs, no accounts, no API keys. Cider ships as a one-time purchase with zero marginal AI cost.

---

## Apple Frameworks

| Framework | Requirement | Used For |
|-----------|-------------|----------|
| NaturalLanguage | Any Mac (macOS 14+) | Auto-tagging, embeddings, keyword extraction, "find similar" |
| Vision | Any Mac (macOS 14+) | OCR on thumbnails/screenshots, image text indexing |
| Foundation Models | Apple Intelligence (macOS 26+, Apple Silicon) | Page summarization, tool calling, conversational assistant |
| Speech | Any Mac | YouTube transcription fallback (when no captions) |
| Core Spotlight | Any Mac | System-wide search indexing |
| App Intents | Any Mac | Siri and Shortcuts integration |

---

## AI Services (Background — Always Running)

### Phase 1: NaturalLanguage Foundations (Shipped)

**Auto-Tagging** — `NLPipeline.swift`
- Named entity recognition + TF-IDF keyword extraction on bookmark save
- Gated by `CiderConfig.enableAutoTagging`

**Embeddings + Find Similar** — `EmbeddingStore.swift`, `SimilarItemsService.swift`
- NLEmbedding sentence vectors, cosine similarity, top 3 related items
- Gated by `CiderConfig.enableEmbeddings`

**OCR Indexing** — `OCRService.swift`
- Vision framework OCR on bookmark thumbnails, stored as `ocrText`
- Opt-in via `CiderConfig.enableOCRIndexing`

**Screen Capture OCR** — `ScreenCaptureService.swift`, `ScreenCaptureOCRRouter.swift`
- Opt+Cmd+2 capture, NSDataDetector routing to Note / Date Card / Contact

**Core Spotlight** — `SpotlightIndexer.swift`
- System-wide search indexing of bookmarks

**Dominant Colors** — `ColorExtractionService.swift`
- Extracted from bookmark thumbnails

### Phase 2: Foundation Models Summarization (Shipped)

**Page Summarization** — `SummaryService.swift`
- 2-3 sentence summary via Foundation Models, stored as `aiSummary`
- Gated by `CiderConfig.enablePageSummaries`

---

## AI Chat Assistant (Shipped)

### Architecture

Two swappable backends behind the `AIAssistantProvider` protocol:

| Backend | Model | Context | Tool Calling | Best For |
|---------|-------|---------|-------------|----------|
| **Apple Intelligence** | Apple 3B (on-device) | 4,096 tokens | Yes (23 tools via Foundation Models Tool API) | Querying data, taking actions |
| **Local Model (MLX)** | Qwen 2.5 7B (downloadable) | 32K tokens | Not yet (conversation only) | Longer conversations, reasoning, writing |

Users switch between them via the model picker pill in the title bar.

### Key Files

| File | Role |
|------|------|
| `Services/AI/AIAssistantProvider.swift` | Protocol, message model, context model |
| `Services/AI/AIAssistantTools.swift` | All 23 tools (read + write) for data access and actions |
| `Services/AI/FoundationModelsProvider.swift` | Apple Intelligence backend with tool calling + context management |
| `Services/AI/MLXProvider.swift` | Local Qwen 2.5 backend via MLX Swift |
| `Services/AI/MLXModelManager.swift` | Model download, load, unload, idle timeout, memory management |
| `Services/AI/AIConversationStorage.swift` | JSONL conversation persistence |
| `ViewModels/AIAssistantViewModel.swift` | Conversation state, streaming, typewriter, provider switching |
| `Views/AIAssistant/AIAssistantPanelView.swift` | Root panel view with model picker, history, context indicator |
| `Views/AIAssistant/AIAssistantBubbleView.swift` | Message bubbles with markdown, bouncing dots, timestamps, copy |
| `Views/AIAssistant/AIAssistantInputView.swift` | Text input with send/stop |
| `Views/AIAssistant/AIDetailActionsButton.swift` | AI sparkles button in detail panel toolbars |
| `App/AIAssistantPanel.swift` | Floating NSPanel with dragging, resizing |
| `App/AppDelegate+AIAssistantPanel.swift` | Panel lifecycle, show/hide/toggle |
| `Services/AIAssistantHotkeyDetector.swift` | Option+A global hotkey |

### Chat UI Features

- **Floating NSPanel** — acrylic background, draggable, resizable, position persisted
- **Option+A hotkey** — toggle panel from anywhere
- **Model picker** — pill in title bar to switch Apple Intelligence ↔ Local Model
- **Markdown rendering** — bold, italic, code blocks, lists, links in assistant responses
- **Streaming** — responses appear progressively (typewriter effect)
- **Bouncing dots** — animated indicator while waiting for response
- **Timestamps + copy button** — on every message
- **Context badge** — shows when viewing an item (bookmark, note, folder, etc.)
- **Context window indicator** — progress bar showing token usage (Apple Intelligence only)
- **Auto-summarize** — conversation summarized at 70% context to prevent overflow
- **Conversation persistence** — JSONL files in `~/CiderVault/.cider/ai-conversations/`
- **Conversation history** — clock icon popover, resume past chats, delete, export as markdown
- **Auto-resume** — most recent conversation loads on app launch
- **New conversation** — pencil icon starts fresh chat
- **Escape to close** — keyboard shortcut in panel
- **Error display** — actual error messages shown instead of generic failure text

### Context Injection

The AI automatically knows what the user is viewing in Cider:

| Item Type | Context Provided | Triggered By |
|-----------|-----------------|-------------|
| Bookmark | Title, URL, AI summary | Opening bookmark detail |
| Note | Title, first 200 chars of content | Opening note detail |
| Event | Title, date, location | Opening date card detail |
| Contact | Name, email | Opening contact detail |
| Todo | Title, completion status | Opening todo detail |
| Folder | Folder name, item count | Navigating to a folder |

Context clears when details close. The "Context" badge appears in the AI panel title bar when active.

### Quick Actions

**Sidebar AI section** (above footer):
- Collapsible section with sparkles icon
- General actions: Library Summary, Recent Activity, Overdue Tasks
- "Open Chat (⌥A)" button with keyboard shortcut hint

**Detail panel toolbar** (sparkles icon → popover):
- Bookmark: Summarize, Find Similar, Suggest Tags, Suggest Folder
- Note: Summarize, Suggest Tags
- Event/Contact/Todo: Details
- Folder: Organize, List Contents

---

## Tool Calling (Apple Intelligence Only)

23 tools defined in `Services/AI/AIAssistantTools.swift`, registered in `FoundationModelsProvider`. The model decides which tool to call based on the user's message. All tools use `nonisolated func call` with `await MainActor.run` for thread-safe storage access.

### Read Tools (12)

| Tool | Example Query | What It Does |
|------|--------------|-------------|
| `countItems` | "How many bookmarks do I have?" | Counts any entity type or gives full library summary |
| `searchItems` | "Find bookmarks about shoes" | Keyword search across all types (titles, URLs, content, tags) |
| `listFolders` | "What folders do I have?" | Lists all folders with item counts per type |
| `listTags` | "Show me my tags" | Lists all tags/labels with usage counts |
| `getRecentItems` | "What did I save this week?" | Items created/modified in last N days |
| `getItemsByTag` | "What's tagged as Important?" | All items with a specific tag across all types |
| `getUpcomingEvents` | "What's coming up this month?" | Upcoming events in next N days |
| `getOverdueTodos` | "Any overdue tasks?" | Incomplete todos past due date + high-priority items |
| `getFolderContents` | "What's in my Applications folder?" | Lists everything inside a specific folder |
| `getBrowserSessions` | "Show my saved sessions" | Saved browser tab groups with tab counts |
| `findSimilar` | "Find bookmarks similar to this one" | Cosine similarity via `EmbeddingStore` vectors |
| `getCurrentItem` | "Tell me about this" | Full details of whatever item user is currently viewing |

### Write Tools (11)

| Tool | Example Query | What It Does |
|------|--------------|-------------|
| `createFolder` | "Create a Products folder" | Creates folder, optionally inside a parent |
| `moveToFolder` | "Move shoe bookmarks to Products" | Searches by keyword, moves matching items |
| `applyTag` | "Tag shoe bookmarks as Footwear" | Searches by keyword, applies tag (creates if needed) |
| `removeTag` | "Remove the Footwear tag from Vans" | Searches by keyword, removes specified tag |
| `renameBookmark` | "Rename 'Untitled' to 'Vans Store'" | Finds by current title, sets new title |
| `renameFolder` | "Rename Products to Shopping" | Renames an existing folder |
| `createNote` | "Create a note called Meeting Notes" | Creates note with title/content, optionally in folder |
| `addBookmark` | "Save vans.com as a bookmark" | Saves URL with optional title, folder, tag |
| `summarizeText` | "Summarize this and save as a note" | AI summarization, optionally saves as note |
| `deleteItem` | "Delete the Untitled bookmark" | Moves to trash (recoverable via CiderUndoManager) |
| `unfileItems` | "Remove Vans from its folder" | Moves items out of folder back to root |

### How Tool Calling Works

1. User asks "how many bookmarks do I have?"
2. Model decides to call `countItems(itemType: "bookmarks")`
3. Tool executes on MainActor, queries `BookmarksStorage.shared.bookmarks.count`
4. Tool returns `"The user has 50 bookmarks."`
5. Model formats natural response: "You have 50 bookmarks."

The Foundation Models framework handles the tool call loop automatically — model generates tool call arguments, framework executes the tool, feeds results back, model generates final response.

### Data Sources

| Storage | What Tools Access |
|---------|------------------|
| `BookmarksStorage.shared` | URLs, titles, tags, AI summaries, folders, dates |
| `NotesStorage.shared` | Titles, content preview, folders, labels |
| `DateCardStorage.shared` | Events with dates, location, recurrence, completion |
| `TodoCardStorage.shared` | Tasks with due dates, priority, checklists |
| `ContactStorage.shared` | Names, email, phone, relationship |
| `CardLabelStorage.shared` | Tags with colors, usage counts, `findOrCreate` |
| `VaultFolderService.shared` | Folder hierarchy with paths |
| `ClipboardStorage.shared` | Clipboard history |
| `BrowserSessionStorage.shared` | Saved browser tab groups |
| `EmbeddingStore.shared` | Vector embeddings for semantic similarity |
| `SummaryService.shared` | AI text summarization |

---

## Local Model (MLX Swift)

### Current Status

**Shipped:** Qwen 2.5 via MLX Swift. Conversation only (no tool calling yet).

**Why Qwen 2.5 instead of 3.5:** Qwen 3.5 architecture (`qwen3_5`) is not yet supported by mlx-swift-lm 2.29.x. Will upgrade when support lands.

### Model Tiers

| | Qwen 2.5 3B | Qwen 2.5 7B |
|---|---|---|
| **Target** | 8GB Macs | 16GB+ Macs |
| **Download** | ~1.8 GB | ~4.0 GB |
| **HF model ID** | `mlx-community/Qwen2.5-3B-Instruct-4bit` | `mlx-community/Qwen2.5-7B-Instruct-4bit` |
| **Context** | 32K tokens | 32K tokens |
| **License** | Apache 2.0 | Apache 2.0 |

Auto-detected by system RAM. Stored in Hugging Face cache (first download only).

### MLX Integration

**Package:** `mlx-swift-lm` v2.29.x (MIT license, by Apple)

**Memory management:**
- `MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)` — prevents buffer bloat
- Auto-loads on first message, auto-unloads after 5 min idle
- `ModelContainer.perform {}` for thread-safe inference

**Architecture:**
- `MLXModelManager` — singleton, handles download/load/unload lifecycle
- `MLXProvider` — conforms to `AIAssistantProvider`, manages conversation history
- Multi-turn via conversation history in prompt (last 10 exchanges)

### Model Picker UI

Pill in AI panel title bar: "Apple" (blue dot) or "Local" (green dot).

Popover shows:
- Apple Intelligence: on-device, 4K context
- Local Model: 32K context, download size, loaded/loading status
- Download progress bar during first-time setup

---

## Conversation Storage

**Format:** JSONL (one JSON object per line, one file per conversation)
**Location:** `~/CiderVault/.cider/ai-conversations/`
**Filename:** `{date}-{title-slug}-{short-id}.jsonl`

```jsonl
{"id":"conv-550e8400","title":"Bookmark organization","created":"2026-03-19T14:20:00Z","model":"apple-intelligence","type":"metadata"}
{"id":"msg-1","role":"user","content":"How many bookmarks do I have?","timestamp":"2026-03-19T14:20:00Z"}
{"id":"msg-2","role":"assistant","content":"You have 50 bookmarks across 5 folders.","timestamp":"2026-03-19T14:20:03Z"}
```

**Why JSONL:** AI responses contain markdown formatting — storing markdown inside markdown creates parsing nightmares. JSONL is append-only, crash-safe, unambiguous, and human-readable.

**Markdown export:** Right-click conversation in history → "Export as Markdown" saves a clean `.md` file.

---

## Context Window Management (Apple Intelligence)

Apple's on-device model has a **4,096 token** context window. With 23 tools (~1,450 tokens for definitions), ~2,600 tokens remain for conversation — roughly 4-6 exchanges.

**Monitoring:** Character count heuristic (~4 chars/token) estimates usage. Progress bar in title bar shows percentage.

**Auto-summarize at 70%:** When nearing the limit, a separate LanguageModelSession summarizes the conversation. A fresh session starts with the summary as context. Conversation continues seamlessly.

**Error recovery:** If `exceededContextWindowSize` fires, auto-summarizes and retries.

This limitation is why the Local Model (32K context) is a major upgrade for conversation.

---

## Roadmap

### Next: Tool Calling for Local Model

Give the MLX/Qwen model the same 23 tools as Apple Intelligence via prompt-based tool use:
- Include tool descriptions in system prompt
- Model outputs tool calls in structured JSON format
- Parse and execute tool calls
- Feed results back for final response

This is the highest-priority next step — it makes the local model actually useful for organizing data, not just chatting.

### Next: Confirmation UI for Write Actions

Add confirm/cancel before write tools execute. Model proposes action, user approves.

### Next: Citations

Clickable item cards in responses — tap to open the referenced bookmark/note in Cider's detail panel.

### Future

- **Qwen 3.5 upgrade** — when mlx-swift-lm adds `qwen3_5` architecture support
- **RAG** — vector search across all items for semantic queries
- **Custom instructions** — user personality/behavior preferences
- **Screen context** — feed screenshot OCR into chat via `ScreenCaptureService`
- **Streaming for MLX** — token-by-token output instead of full response dump
