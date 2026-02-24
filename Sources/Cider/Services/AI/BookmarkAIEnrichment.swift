import Foundation

/// Orchestrates all AI enrichment for a bookmark — tagging, embeddings,
/// OCR, color extraction, and summarization. Runs in the background after
/// the primary enrichment (title + thumbnail) completes.
@MainActor
final class BookmarkAIEnrichment {
    static let shared = BookmarkAIEnrichment()

    /// Tracks in-flight tasks so we don't double-enrich the same bookmark.
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Public API

    /// Schedule AI enrichment for a bookmark. Safe to call multiple times —
    /// cancels any existing in-flight task for the same ID first.
    func schedule(for bookmark: Bookmark) {
        let config = CiderConfig.load()
        guard config.enableAutoTagging || config.enableEmbeddings
           || config.enableOCRIndexing || config.enableColorExtraction
           || config.enablePageSummaries
        else { return }

        activeTasks[bookmark.id]?.cancel()
        activeTasks[bookmark.id] = Task { [weak self] in
            await self?.run(for: bookmark, config: config)
            await MainActor.run { [weak self] in
                self?.activeTasks.removeValue(forKey: bookmark.id)
            }
        }
    }

    func cancel(for id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    // MARK: - Enrichment Pipeline

    private func run(for bookmark: Bookmark, config: CiderConfig) async {
        guard !Task.isCancelled else { return }

        // ── 1. Auto-tagging (NaturalLanguage, any Mac) ──────────────────────
        var suggestedTags: [String] = []
        if config.enableAutoTagging {
            let text = "\(bookmark.title) \(bookmark.hostDisplay) \(bookmark.notes)"
            suggestedTags = await Task.detached(priority: .utility) {
                NLPipeline.suggestTags(
                    title: bookmark.title,
                    host: bookmark.hostDisplay,
                    notes: bookmark.notes
                )
            }.value
        }

        guard !Task.isCancelled else { return }

        // ── 2. Embedding vector (NaturalLanguage, any Mac) ──────────────────
        if config.enableEmbeddings {
            let text = [bookmark.title, bookmark.hostDisplay, bookmark.notes]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            EmbeddingStore.shared.computeAndStore(
                id: bookmark.id,
                text: text,
                modifiedAt: bookmark.updatedAt
            )
        }

        // ── 3. OCR (Vision, any Mac) — thumbnail must exist ─────────────────
        var ocrText: String? = bookmark.ocrText
        if config.enableOCRIndexing,
           bookmark.ocrText == nil,
           let thumbnailURL = bookmark.thumbnailFileURL
        {
            ocrText = await OCRService.extractText(from: thumbnailURL)
        }

        guard !Task.isCancelled else { return }

        // ── 4. Color extraction (CoreGraphics, any Mac) ──────────────────────
        var dominantColors: [String]? = bookmark.dominantColors
        if config.enableColorExtraction,
           bookmark.dominantColors == nil,
           let thumbnailURL = bookmark.thumbnailFileURL
        {
            let colors = await ColorExtractionService.extractDominantColors(
                from: thumbnailURL,
                count: 3
            )
            dominantColors = colors.isEmpty ? nil : colors
        }

        guard !Task.isCancelled else { return }

        // ── 5. Page summary (Foundation Models, Apple Intelligence) ──────────
        // Summary is triggered separately when Reader mode content is available.
        // Here we only run it if we already have a stored summary or it was
        // explicitly requested — we don't fetch the page ourselves.
        // (See SummaryService + BookmarkReaderView integration)

        // ── Apply results back to storage ───────────────────────────────────
        let newTags = mergedTags(
            existing: bookmark.tags,
            suggested: suggestedTags
        )
        let changed = newTags != bookmark.tags
                   || ocrText != bookmark.ocrText
                   || dominantColors != bookmark.dominantColors

        if changed {
            BookmarksStorage.shared.applyAIResults(
                for: bookmark.id,
                tags: newTags,
                ocrText: ocrText,
                dominantColors: dominantColors
            )
        }
    }

    // MARK: - Helpers

    /// Merge AI-suggested tags with user tags. User tags always win;
    /// suggested tags are added only if the user doesn't already have them.
    private func mergedTags(existing: [String], suggested: [String]) -> [String] {
        let existingSet = Set(existing.map { $0.lowercased() })
        let newSuggested = suggested.filter { !existingSet.contains($0.lowercased()) }
        return existing + newSuggested
    }
}
