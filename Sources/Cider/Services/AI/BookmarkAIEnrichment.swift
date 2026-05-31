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
                _ = self?.activeTasks.removeValue(forKey: bookmark.id)
            }
        }
    }

    func cancel(for id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    /// Re-run AI enrichment on all bookmarks with the latest algorithm.
    /// Throttled to avoid saturating the main thread.
    func retagAll() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        Task { @MainActor in
            for bookmark in bookmarks {
                guard !Task.isCancelled else { break }
                schedule(for: bookmark)
                // Yield between scheduling to keep UI responsive
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: - Enrichment Pipeline

    private func run(for bookmark: Bookmark, config: CiderConfig) async {
        guard !Task.isCancelled else { return }

        // ── 0. oEmbed enrichment (TikTok, YouTube, Instagram, X) ────────────
        if OEmbedService.supports(bookmark.urlString),
           !bookmark.notesManuallySet, bookmark.notes.isEmpty
        {
            if let result = await OEmbedService.fetch(for: bookmark.urlString) {
                let suggestedTitle = OEmbedService.suggestTitle(
                    from: result,
                    currentTitle: bookmark.title,
                    urlString: bookmark.urlString
                )
                let notes = OEmbedService.buildNotes(from: result)
                await MainActor.run {
                    VaultBookmarkService.shared.applyOEmbedResults(
                        for: bookmark.id,
                        title: suggestedTitle,
                        notes: notes
                    )
                }
            }
        }

        guard !Task.isCancelled else { return }

        // ── 1. Auto-tagging (NaturalLanguage, any Mac) ──────────────────────
        var suggestedTags: [String] = []
        if config.enableAutoTagging {
            suggestedTags = await Task.detached(priority: .utility) {
                NLPipeline.suggestTags(
                    title: bookmark.title,
                    host: bookmark.hostDisplay,
                    notes: bookmark.notes,
                    urlString: bookmark.urlString
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

        // ── 5a. Smart title from OCR (image bookmarks with generic titles) ──────
        // Skip if the user or an external agent explicitly set the title.
        var suggestedTitle: String?
        if let text = ocrText, !text.isEmpty,
           Self.canUseOCRTitle(
               currentTitle: bookmark.title,
               urlString: bookmark.urlString,
               titleManuallySet: bookmark.titleManuallySet
           ) {
            // Prefer Apple Intelligence if available, fall back to first OCR line
            if let aiTitle = await SummaryService.shared.suggestTitle(
                currentTitle: bookmark.title,
                articleText: text
            ) {
                suggestedTitle = aiTitle
            } else {
                suggestedTitle = Self.suggestedTitleFromOCR(
                    text,
                    currentTitle: bookmark.title,
                    urlString: bookmark.urlString,
                    titleManuallySet: bookmark.titleManuallySet
                )
            }
        }

        // ── Apply results back to storage ───────────────────────────────────
        // Re-read the live bookmark — it may have been modified during async AI work
        // (user edited tags, Claude renamed title, etc.). Use live state for diff comparison.
        let live = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == bookmark.id }) ?? bookmark
        let newTags = mergedTags(
            existing: live.tags,
            suggested: suggestedTags
        )
        let changed = newTags != live.tags
                   || ocrText != live.ocrText
                   || dominantColors != live.dominantColors
                   || (suggestedTitle != nil && !live.titleManuallySet)

        if changed {
            VaultBookmarkService.shared.applyAIResults(
                for: bookmark.id,
                tags: newTags,
                ocrText: ocrText,
                dominantColors: dominantColors,
                title: suggestedTitle
            )
        }

        // ── Create CardLabel objects from AI tags and assign to bookmark ──
        // Re-fetch bookmark from storage — it may have been modified during async AI work.
        // Skip any label the user previously dismissed.
        if !suggestedTags.isEmpty {
            await MainActor.run {
                let current = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == bookmark.id })
                for tagName in suggestedTags {
                    let label = CardLabelStorage.shared.findOrCreate(name: tagName, colorHex: nil)
                    if let current, current.dismissedLabelIDs.contains(label.id) { continue }
                    _ = VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: label.id)
                }
            }
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

    static func suggestedTitleFromOCR(
        _ text: String,
        currentTitle: String,
        urlString: String,
        titleManuallySet: Bool
    ) -> String? {
        guard canUseOCRTitle(
            currentTitle: currentTitle,
            urlString: urlString,
            titleManuallySet: titleManuallySet
        ) else { return nil }
        return extractTitleFromOCR(text, urlString: urlString)
    }

    private static func canUseOCRTitle(
        currentTitle: String,
        urlString: String,
        titleManuallySet: Bool
    ) -> Bool {
        if titleManuallySet { return false }
        if isGenericImageTitle(currentTitle) { return true }
        guard let url = URL(string: urlString) else { return false }
        return isHostDerivedTitle(currentTitle, sourceURL: url)
            || isProviderGenericTitle(currentTitle, sourceURL: url)
    }

    /// Returns true if the title looks like a generic placeholder that can be replaced.
    private static func isGenericImageTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        if t.lowercased() == "saved image" { return true }
        // Single word shorter than 5 chars (e.g. "IMG", "pic")
        if !t.contains(" ") && t.count < 5 { return true }
        // Purely numeric (e.g. "20241215_123456")
        if t.allSatisfy({ $0.isNumber || $0 == "_" || $0 == "-" }) { return true }
        return false
    }

    /// Extract a meaningful title from the first non-trivial line of OCR text.
    private static func extractTitleFromOCR(_ text: String, urlString: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && !$0.allSatisfy { $0.isNumber || $0.isPunctuation || $0 == " " } }
        guard let firstLine = lines.first else { return nil }
        let cleaned = cleanOCRTitleLine(firstLine, urlString: urlString)
        guard !cleaned.isEmpty else { return nil }
        let truncated = String(cleaned.prefix(60))
        return titleCased(truncated)
    }

    private static func cleanOCRTitleLine(_ line: String, urlString: String) -> String {
        var cleaned = line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: urlString),
           (url.host?.lowercased() ?? "").contains("tiktok.com"),
           let dateRange = cleaned.range(
               of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,
               options: .regularExpression
           ) {
            cleaned = String(cleaned[...dateRange.upperBound])
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleCased(_ title: String) -> String {
        title
            .split(separator: " ")
            .map { word in
                if word.count <= 3, word.allSatisfy(\.isUppercase) {
                    return String(word)
                }
                return word.capitalized
            }
            .joined(separator: " ")
    }

    private static func isHostDerivedTitle(_ title: String, sourceURL: URL) -> Bool {
        let current = duplicateSuffixStrippedTitle(title)
        guard !current.isEmpty else { return true }
        let hostTitle = resolvedTitle(for: sourceURL)
        return current.caseInsensitiveCompare(hostTitle) == .orderedSame
    }

    private static func isProviderGenericTitle(_ title: String, sourceURL: URL) -> Bool {
        let normalized = duplicateSuffixStrippedTitle(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }

        let host = sourceURL.host?.lowercased() ?? ""
        let genericTitles: [String]
        if host.contains("tiktok.com") {
            genericTitles = ["tiktok - make your day"]
        } else if host.contains("instagram.com") {
            genericTitles = ["instagram"]
        } else if host.contains("reddit.com") {
            genericTitles = [
                "reddit - dive into anything",
                "reddit - the heart of the internet",
            ]
        } else if host.contains("x.com") || host.contains("twitter.com") {
            genericTitles = ["x.com", "x", "twitter", "twitter.com"]
        } else {
            genericTitles = []
        }
        return genericTitles.contains(normalized)
    }

    private static func resolvedTitle(for url: URL) -> String {
        if let host = url.host {
            let hostWithoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return hostWithoutWWW.capitalized
        }
        return url.absoluteString
    }

    private static func duplicateSuffixStrippedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
