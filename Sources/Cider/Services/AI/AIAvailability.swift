import Foundation
import FoundationModels
import NaturalLanguage

/// Detects which AI capabilities are available on the current device.
struct AIAvailability {

    /// Whether Foundation Models (on-device LLM) is available.
    /// Requires macOS 26+ AND Apple Intelligence enabled by the user.
    static var isFoundationModelsAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }

    /// Whether NaturalLanguage word embeddings are available (always true on macOS 14+).
    static var isEmbeddingAvailable: Bool {
        NLEmbedding.wordEmbedding(for: .english) != nil
    }
}
