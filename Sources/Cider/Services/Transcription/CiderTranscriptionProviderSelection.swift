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

struct CiderStoredAudioTranscriptionProviderRequest: Equatable, Sendable {
    let providerID: String
    let localeIdentifier: String?
    let localFasterWhisperConfiguration: LocalFasterWhisperConfiguration?

    init(
        providerID: String,
        localeIdentifier: String? = nil,
        localFasterWhisperConfiguration: LocalFasterWhisperConfiguration? = nil
    ) {
        self.providerID = String(providerID.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        self.localeIdentifier = localeIdentifier.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        }
        self.localFasterWhisperConfiguration = localFasterWhisperConfiguration
    }
}

@MainActor
struct CiderResolvedTranscriptionProvider {
    let requestedProviderID: String
    let service: any CiderTranscriptionServicing
    let usedSharedDefault: Bool

    var selectedProviderID: String { service.provider.id }
    var usedFallback: Bool { false }
}

/// One production composition point for Cider transcription providers.
/// A different default requires an explicit shared policy change rather than a surface-only swap.
@MainActor
enum CiderTranscriptionProviderSelection {
    static let defaultProviderID = "apple-speech-on-device"
    static let sharedDefaultRequestID = "shared-default"
    static let localFasterWhisperProviderID = "local-faster-whisper"
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

    /// Resolves one explicit stored-audio provider request. Failure is terminal:
    /// this selector never substitutes Apple, local faster-whisper, or a network
    /// provider when the requested adapter is unavailable or misconfigured.
    static func resolveStoredAudio(
        _ request: CiderStoredAudioTranscriptionProviderRequest
    ) -> Result<CiderResolvedTranscriptionProvider, TranscriptionFailure> {
        let locale = request.localeIdentifier.flatMap { $0.isEmpty ? nil : Locale(identifier: $0) } ?? .current
        switch request.providerID {
        case sharedDefaultRequestID:
            return .success(.init(
                requestedProviderID: request.providerID,
                service: makeDefault(locale: locale),
                usedSharedDefault: true
            ))
        case defaultProviderID:
            return .success(.init(
                requestedProviderID: request.providerID,
                service: AppleSpeechTranscriptionService(locale: locale),
                usedSharedDefault: false
            ))
        case localFasterWhisperProviderID:
            guard let configuration = request.localFasterWhisperConfiguration else {
                return .failure(.init(
                    code: .unavailable,
                    message: "The explicitly selected local transcription provider is not configured."
                ))
            }
            return .success(.init(
                requestedProviderID: request.providerID,
                service: LocalFasterWhisperTranscriptionService(configuration: configuration),
                usedSharedDefault: false
            ))
        default:
            return .failure(.init(
                code: .unsupportedInput,
                message: "The explicitly selected stored-audio transcription provider is unsupported."
            ))
        }
    }
}
