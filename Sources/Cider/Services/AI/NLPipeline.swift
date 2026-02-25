import Foundation
import NaturalLanguage

/// On-device NLP using the NaturalLanguage framework.
/// Works on any Mac — no Apple Intelligence required.
struct NLPipeline {

    // MARK: - Public API

    /// Suggest tags for a bookmark based on its title, host, notes, and existing tags.
    /// Returns up to 8 deduplicated lowercase tag strings.
    static func suggestTags(title: String, host: String, notes: String) -> [String] {
        let text = [title, host, notes]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let entities = extractEntities(from: text)
        let keywords = extractKeywords(from: text)
        // Combine, deduplicate, filter short tokens, cap at 8
        let combined = (entities + keywords)
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
        return Array(Set(combined)).sorted().prefix(8).map { $0 }
    }

    // MARK: - Internals

    /// Named entity recognition: people, organizations, places.
    static func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var results: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .joinNames]
        ) { tag, tokenRange in
            if let tag, [.personalName, .organizationName, .placeName].contains(tag) {
                let token = String(text[tokenRange])
                if token.count > 2 { results.append(token) }
            }
            return true
        }
        return Array(Set(results))
    }

    /// Keyword extraction using lexical class tagging — picks the most frequent nouns.
    static func extractKeywords(from text: String, maxCount: Int = 6) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var nouns: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            if tag == .noun {
                let word = String(text[tokenRange])
                if word.count > 3 { nouns.append(word) }
            }
            return true
        }
        let freq = Dictionary(nouns.map { ($0.lowercased(), 1) }, uniquingKeysWith: +)
        return freq.sorted { $0.value > $1.value }.prefix(maxCount).map(\.key)
    }

    /// Compute a sentence-level embedding vector for the given text.
    /// Returns nil if no embedding model is available.
    static func embedding(for text: String) -> [Double]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Prefer sentence-level, fall back to word-level
        let model = NLEmbedding.sentenceEmbedding(for: .english)
               ?? NLEmbedding.wordEmbedding(for: .english)
        guard let model else { return nil }
        return model.vector(for: text)
    }

    /// Detect the dominant language of a text snippet.
    static func detectLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
}
