# macOS Native AI — Implementation Spec

> **Branch:** `feature/macos-native-ai`
> **Vision doc:** `Docs/AI_VISION.md`
> **Scope:** Phase 1 + Phase 2 from the vision — on-device foundations using Apple frameworks only. No cloud APIs, no API keys, no network calls for AI.

---

## What This Branch Builds

| Feature | Framework | Requirement |
|---------|-----------|-------------|
| Auto-tagging on bookmark capture | `NaturalLanguage` | Any Mac (macOS 14+) |
| Embedding vectors for "find similar" | `NaturalLanguage` | Any Mac (macOS 14+) |
| Related items in bookmark detail | `NaturalLanguage` | Any Mac (macOS 14+) |
| Page summarization | `FoundationModels` | Apple Intelligence (macOS 26+, Apple Silicon) |
| Smart bookmark title generation | `FoundationModels` | Apple Intelligence (macOS 26+, Apple Silicon) |
| Image/thumbnail OCR indexing | `Vision` | Any Mac (macOS 14+) |

All features degrade gracefully: if the required framework isn't available, the app works exactly as before. AI features are progressive enhancement, never load-bearing.

---

## File Structure

```
Sources/Cider/Services/AI/
├── AIAvailability.swift          # Capability detection (Foundation Models, Apple Intelligence)
├── NLPipeline.swift              # NaturalLanguage: tagging, embeddings, keyword extraction
├── SummaryService.swift          # Foundation Models: page summaries + title suggestions
├── OCRService.swift              # Vision: thumbnail OCR → searchable text
├── EmbeddingStore.swift          # Persist + query NLEmbedding vectors (JSON on disk)
└── SimilarItemsService.swift     # Cosine similarity query over EmbeddingStore

Sources/Cider/Views/Bookmarks/
└── RelatedItemsView.swift        # "Related" row in bookmark detail panel

Sources/Cider/Models/
└── ItemEmbedding.swift           # Codable struct: id + vector + modifiedAt
```

New `CiderConfig` keys added during this branch:
```swift
var enableAutoTagging: Bool        // default: true
var enableEmbeddings: Bool         // default: true
var enablePageSummaries: Bool      // default: true (silently off on unsupported hardware)
var enableOCRIndexing: Bool        // default: false (opt-in — disk write on every capture)
```

---

## Phase 1: NaturalLanguage Foundations

These features work on any Mac and ship first.

### 1a. Auto-Tagging Pipeline

**Trigger:** `BookmarksStorage.save()` → post `.bookmarkDidSave` notification → `NLPipeline.extractTags(from:)`

**Input:** `title + hostDisplay + notes` concatenated (page content not yet available at save time — Reader Mode provides it later)

**Implementation:**
```swift
// NLPipeline.swift
import NaturalLanguage

struct NLPipeline {

    // Named entity recognition: extracts people, orgs, places
    static func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var results: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .joinNames]) { tag, tokenRange in
            if let tag, [.personalName, .organizationName, .placeName].contains(tag) {
                results.append(String(text[tokenRange]).lowercased())
            }
            return true
        }
        return Array(Set(results))
    }

    // TF-IDF-style keyword extraction via NLTagger lexical class
    static func extractKeywords(from text: String, maxCount: Int = 8) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var nouns: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            if tag == .noun {
                let word = String(text[tokenRange]).lowercased()
                if word.count > 3 { nouns.append(word) }
            }
            return true
        }
        // Frequency count → top N
        let freq = Dictionary(nouns.map { ($0, 1) }, uniquingKeysWith: +)
        return freq.sorted { $0.value > $1.value }.prefix(maxCount).map(\.key)
    }

    // Combined: entities + keywords, deduplicated, max 10
    static func suggestTags(from text: String) -> [String] {
        let entities = extractEntities(from: text)
        let keywords = extractKeywords(from: text)
        return Array(Set(entities + keywords)).prefix(10).map { $0 }
    }
}
```

**Wiring in BookmarksViewModel:**
```swift
// After save, merge suggested tags (don't overwrite user-set tags)
if CiderConfig.load().enableAutoTagging {
    let text = "\(bookmark.title) \(bookmark.hostDisplay) \(bookmark.notes)"
    let suggested = NLPipeline.suggestTags(from: text)
    let merged = Array(Set(bookmark.tags + suggested))
    // Update quietly — no undo event, no toast
    BookmarksStorage.shared.updateTags(for: bookmark.id, tags: merged)
}
```

---

### 1b. Embedding Vectors + Find Similar

**Goal:** Each bookmark and note gets an `NLEmbedding` vector. When a user opens an item, show the top 3 most similar items from their library.

**Embedding model:** `NLEmbedding.sentenceEmbedding(for: .english)` — sentence-level, ~50MB download on first use. Falls back to `NLEmbedding.wordEmbedding(for: .english)` (always available, no download).

#### ItemEmbedding.swift
```swift
struct ItemEmbedding: Codable, Identifiable {
    let id: UUID            // bookmark or note ID
    let vector: [Double]    // NLEmbedding float vector
    let modifiedAt: Date    // used for invalidation
    let itemType: ItemType  // .bookmark | .note

    enum ItemType: String, Codable { case bookmark, note }
}
```

#### EmbeddingStore.swift
- File: `{ciderDataDirectory}/.ai/embeddings.json`
- Loaded lazily, kept in memory, written async on background thread
- Invalidated per-item: if `modifiedAt` differs from stored, recompute
- Thread safety: `@MainActor` for reads, `Task.detached` for compute

```swift
@MainActor
final class EmbeddingStore: ObservableObject {
    static let shared = EmbeddingStore()

    private var cache: [UUID: ItemEmbedding] = [:]

    func vector(for id: UUID) -> [Double]? { cache[id]?.vector }

    func computeAndStore(id: UUID, text: String, type: ItemEmbedding.ItemType, modifiedAt: Date) {
        Task.detached(priority: .utility) { [weak self] in
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english)
                               ?? NLEmbedding.wordEmbedding(for: .english) else { return }
            var vector = [Double](repeating: 0, count: embedding.dimension)
            embedding.enumerateNeighbors(for: text, maximumCount: 1) { _, _ in return false }
            // Use getVector for the text
            if let v = embedding.vector(for: text) {
                vector = v
            }
            await MainActor.run { [weak self] in
                let item = ItemEmbedding(id: id, vector: vector, modifiedAt: modifiedAt, itemType: type)
                self?.cache[id] = item
                self?.persistAsync()
            }
        }
    }

    private func persistAsync() {
        let snapshot = cache
        Task.detached(priority: .background) {
            // encode + write to disk
        }
    }
}
```

#### SimilarItemsService.swift
```swift
struct SimilarItemsService {

    static func findSimilar(to id: UUID, in store: EmbeddingStore, limit: Int = 3) -> [UUID] {
        guard let target = store.vector(for: id) else { return [] }
        return store.allVectors()
            .filter { $0.id != id }
            .map { ($0.id, cosineSimilarity(target, $0.vector)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
```

#### RelatedItemsView.swift
- Shown in `BookmarkMetadataSidebar` as a new collapsible section below Notes
- Uses `.task(id: bookmark.id)` to recompute on item change
- Shows up to 3 small cards: favicon + title + host
- Tap navigates to that bookmark (post `.openBookmarkDetail` notification)
- Hidden if no similar items found or embeddings not ready

---

### 1c. OCR Indexing (opt-in)

**Trigger:** After thumbnail is written to disk by `BookmarksStorage.assignThumbnail()`

**Implementation:**
```swift
// OCRService.swift
import Vision

struct OCRService {

    static func extractText(from imageURL: URL) async -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        return await Task.detached(priority: .background) {
            guard let cgImage = CGImageSourceCreateWithURL(imageURL as CFURL, nil)
                .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return nil }
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }.value
    }
}
```

**Storage:** OCR text stored as a new optional field in bookmark metadata JSON (`ocrText: String?`). Included in `SearchService` text matching and `LibraryViewModel.matchesTextQuery`.

---

## Phase 2: Foundation Models

These features require Apple Intelligence (macOS 26+, Apple Silicon with Neural Engine). Gated by `AIAvailability.isFoundationModelsAvailable`.

### AIAvailability.swift
```swift
import FoundationModels

struct AIAvailability {
    static var isFoundationModelsAvailable: Bool {
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }
}
```

---

### 2a. Page Summarization

**When:** User opens a bookmark detail that has `ReaderMode` content available (the Reader pipeline already fetched the article HTML). Summarization triggers in the background after reader content loads.

**Input:** Reader-extracted article text (stripped HTML) — already available from `BookmarkReaderView`'s Readability.js output.

**Output:** 2–3 sentence summary stored in bookmark metadata as `aiSummary: String?`

```swift
// SummaryService.swift
import FoundationModels

@available(macOS 26, *)
struct SummaryService {

    private static let session = LanguageModelSession(instructions: """
    You are a bookmark summarizer. Given article text, write a 2-sentence summary
    that captures the main point and why someone might want to read it.
    Be concise and factual. Never start with "This article".
    """)

    static func summarize(articleText: String) async throws -> String {
        let truncated = String(articleText.prefix(4000)) // stay within context window
        let response = try await session.respond(to: truncated)
        return response.content
    }

    static func suggestTitle(from articleText: String, currentTitle: String) async throws -> String {
        let prompt = """
        Current title: \(currentTitle)
        Article excerpt: \(String(articleText.prefix(1000)))
        If the current title is vague or auto-generated, suggest a clearer title (max 80 chars).
        If the current title is already good, return it unchanged.
        Return only the title text, no quotes.
        """
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Display:**
- Summary shown as a new section in `BookmarkMetadataSidebar` below the source section
- Appears with a subtle "Summarized" label and sparkle icon
- Only shown if `aiSummary` is non-nil and non-empty
- "Regenerate" button re-runs summarization
- Stored in bookmark metadata JSON so it persists across sessions

---

### 2b. Title Suggestions

**When:** Bookmark has a generic title (detected heuristics: title == hostname, or title matches `document.title` patterns like "Home | Site Name", or title is all-caps/URL-fragment).

**UX:** Small "Suggest title" button next to the title field in `BookmarkMetadataSidebar`. Tapping shows a loading state, then offers the AI-suggested title as a one-click apply. User can accept, edit, or dismiss.

---

## Integration Points

### BookmarksStorage
- `save()` → trigger `NLPipeline.suggestTags` (async, non-blocking)
- `save()` → trigger `EmbeddingStore.computeAndStore` (async, background)
- `assignThumbnail()` → trigger `OCRService.extractText` if `enableOCRIndexing` (async, background)

### BookmarkReaderView
- After `showReader()` success → post `.readerContentReady` notification with article text
- `SummaryService` listens and summarizes in background

### SearchService + LibraryViewModel.matchesTextQuery
- Both include `bookmark.ocrText` in their field matching once OCR is in place

### Settings
New **AI** category in `SettingsCategory` between Bookmarks and Appearance:
- **Auto-tagging** toggle + explanation
- **Page summaries** toggle (shown only on supported hardware, grayed out otherwise)
- **Embedding vectors** toggle + "Recompute all" button
- **OCR indexing** toggle + estimated storage impact
- Hardware badge: green "Apple Intelligence available" or gray "Not available on this device"

---

## Build Sequence

1. `AIAvailability.swift` — capability detection, no dependencies
2. `NLPipeline.swift` — tagging + keyword extraction, no dependencies
3. `ItemEmbedding.swift` + `EmbeddingStore.swift` — data model + persistence
4. `SimilarItemsService.swift` — depends on EmbeddingStore
5. Wire tagging into `BookmarksStorage` + `BookmarksViewModel`
6. `RelatedItemsView.swift` — depends on SimilarItemsService
7. Wire RelatedItemsView into `BookmarkMetadataSidebar`
8. `OCRService.swift` — standalone Vision wrapper
9. Wire OCR into `assignThumbnail` + search
10. `SummaryService.swift` (macOS 26 only) — Foundation Models
11. Wire summaries into reader flow + bookmark metadata
12. Settings AI category

Each step should compile and run independently — no half-wired features.

---

## Testing Notes

- **NaturalLanguage:** Always available, test on any Mac in the project
- **FoundationModels:** Requires macOS 26 + Apple Silicon + Apple Intelligence enabled in System Settings. Wrap all usage in `if #available(macOS 26, *) { if AIAvailability.isFoundationModelsAvailable { ... } }`.
- **Embedding download:** `NLEmbedding.sentenceEmbedding(for: .english)` triggers a ~50MB model download on first call. This is asynchronous and managed by the OS — handle `nil` return by falling back to `wordEmbedding`.
- **Context window limits:** Foundation Models' on-device context is smaller than cloud LLMs. Always truncate input to 4000 chars max before summarization calls.
- Never block the main thread — all NL, Vision, and Foundation Models calls use `Task.detached(priority: .utility/.background)`.
