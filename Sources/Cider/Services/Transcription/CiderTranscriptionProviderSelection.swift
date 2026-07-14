import Foundation

/// One production composition point for Cider transcription providers.
/// A different default requires an explicit shared policy change rather than a surface-only swap.
@MainActor
enum CiderTranscriptionProviderSelection {
    static let defaultProviderID = "apple-speech-on-device"

    static func makeDefault(locale: Locale = .current) -> any CiderTranscriptionServicing {
        AppleSpeechTranscriptionService(locale: locale)
    }
}
