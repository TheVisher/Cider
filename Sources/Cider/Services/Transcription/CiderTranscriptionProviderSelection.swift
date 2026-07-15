import Foundation

enum CiderTranscriptionDefaultDecisionReason: String, Equatable, Sendable {
    case localFasterWhisperLacksLivePartialInput
}

struct CiderTranscriptionDefaultDecision: Equatable, Sendable {
    let defaultProviderID: String
    let evaluatedProviderIDs: [String]
    let changedDefault: Bool
    let hasSingleUniversalAlternative: Bool
    let reason: CiderTranscriptionDefaultDecisionReason
}

/// One production composition point for Cider transcription providers.
/// A different default requires an explicit shared policy change rather than a surface-only swap.
@MainActor
enum CiderTranscriptionProviderSelection {
    static let defaultProviderID = "apple-speech-on-device"
    static let sharedDefaultDecision = CiderTranscriptionDefaultDecision(
        defaultProviderID: defaultProviderID,
        evaluatedProviderIDs: [defaultProviderID, "local-faster-whisper"],
        changedDefault: false,
        hasSingleUniversalAlternative: false,
        reason: .localFasterWhisperLacksLivePartialInput
    )

    static func makeDefault(locale: Locale = .current) -> any CiderTranscriptionServicing {
        AppleSpeechTranscriptionService(locale: locale)
    }
}
