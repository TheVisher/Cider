import Foundation
import os

/// Orchestrates AI enrichment for VaultFiles — OCR, color extraction,
/// and smart title suggestion. Runs in the background after file scanning.
@MainActor
final class VaultFileEnrichment {
    static let shared = VaultFileEnrichment()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultFileEnrichment"
    )

    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Public API

    /// Schedule enrichment for a vault file. Only images are enriched.
    func schedule(for file: VaultFile) {
        guard file.fileType == .image else { return }
        // Skip if already enriched (has OCR text or dominant colors)
        guard file.ocrText == nil && file.dominantColors == nil else { return }

        activeTasks[file.id]?.cancel()
        activeTasks[file.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.enrich(file)
            self.activeTasks.removeValue(forKey: file.id)
        }
    }

    /// Schedule enrichment for all un-enriched image files.
    func scheduleAll() {
        let imageFiles = VaultFileService.shared.files.filter {
            $0.fileType == .image && $0.ocrText == nil && $0.dominantColors == nil
        }
        for file in imageFiles {
            schedule(for: file)
        }
    }

    func cancel(for id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    // MARK: - Enrichment Pipeline

    private func enrich(_ file: VaultFile) async {
        let url = file.absoluteURL
        guard !Task.isCancelled else { return }

        // ── 1. OCR ──────────────────────────────────────────────────────
        let ocrText = await OCRService.extractText(from: url)

        guard !Task.isCancelled else { return }

        // ── 2. Color extraction ─────────────────────────────────────────
        let colors = await ColorExtractionService.extractDominantColors(from: url, count: 3)
        let dominantColors = colors.isEmpty ? nil : colors

        guard !Task.isCancelled else { return }

        // ── 3. Smart title from OCR ─────────────────────────────────────
        var suggestedTitle: String?
        if let text = ocrText, !text.isEmpty, isGenericFilename(file.filename) {
            if let aiTitle = await SummaryService.shared.suggestTitle(
                currentTitle: file.filename,
                articleText: text
            ) {
                suggestedTitle = aiTitle
            } else {
                suggestedTitle = extractTitleFromOCR(text)
            }
        }

        // ── 4. Apply results ────────────────────────────────────────────
        let hasChanges = ocrText != nil || dominantColors != nil || suggestedTitle != nil
        guard hasChanges else { return }

        // Verify file still exists — it may have been deleted or moved during async work
        guard VaultFileService.shared.file(for: file.id) != nil else { return }

        await MainActor.run {
            VaultFileStorage.shared.applyEnrichment(
                fileID: file.id,
                ocrText: ocrText,
                dominantColors: dominantColors,
                title: suggestedTitle
            )
        }

        logger.info("Enriched vault file \(file.filename): OCR=\(ocrText != nil), colors=\(dominantColors != nil), title=\(suggestedTitle ?? "nil")")
    }

    // MARK: - Helpers

    /// Returns true if the filename looks auto-generated (IMG_1234, Screenshot, etc.)
    private func isGenericFilename(_ filename: String) -> Bool {
        let name = (filename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        if name.isEmpty { return true }
        // Common auto-generated patterns
        if name.hasPrefix("img_") || name.hasPrefix("img ") { return true }
        if name.hasPrefix("image") && name.count < 12 { return true }
        if name.hasPrefix("screenshot") { return true }
        if name.hasPrefix("photo") && name.count < 12 { return true }
        if name.hasPrefix("dsc") || name.hasPrefix("dcim") { return true }
        // Purely numeric or timestamp-like
        if name.allSatisfy({ $0.isNumber || $0 == "_" || $0 == "-" || $0 == " " }) { return true }
        // UUID-like filenames
        if name.count >= 32 && name.filter({ $0.isHexDigit || $0 == "-" }).count == name.count { return true }

        return false
    }

    /// Extract a meaningful title from the first non-trivial line of OCR text.
    private func extractTitleFromOCR(_ text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && !$0.allSatisfy { $0.isNumber || $0.isPunctuation || $0 == " " } }
        guard let firstLine = lines.first else { return nil }
        let truncated = String(firstLine.prefix(60))
        return truncated
    }
}
