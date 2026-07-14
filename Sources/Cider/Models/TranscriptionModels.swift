import Foundation

enum TranscriptionAuthorization: String, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum TranscriptionReadiness: Equatable, Sendable {
    case ready
    case unavailable(reason: String)
    case offline(reason: String)
}

enum TranscriptionInputKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case liveMicrophone
    case storedAudioFile
}

enum TranscriptionProviderExecution: String, Equatable, Sendable {
    case onDevice
    case localProcess
    case network
}

struct TranscriptionProviderMetadata: Equatable, Sendable {
    let id: String
    let adapterVersion: String
    let execution: TranscriptionProviderExecution
    let supportedInputs: Set<TranscriptionInputKind>
    let allowsNetworkFallback: Bool

    init(
        id: String,
        adapterVersion: String,
        execution: TranscriptionProviderExecution,
        supportedInputs: Set<TranscriptionInputKind>,
        allowsNetworkFallback: Bool
    ) {
        self.id = String(id.prefix(64))
        self.adapterVersion = String(adapterVersion.prefix(32))
        self.execution = execution
        self.supportedInputs = supportedInputs
        self.allowsNetworkFallback = allowsNetworkFallback
    }
}

enum TranscriptionSourceRetention: String, Equatable, Sendable {
    /// Live audio is process-local input and is not retained by the transcription capability.
    case doNotRetain
    /// The caller owns an immutable original file; transcription may only read it.
    case preserveOriginal
}

struct TranscriptionSourceIdentity: Equatable, Sendable {
    let kind: TranscriptionInputKind
    let sourceID: String
    let displayName: String?
    let retention: TranscriptionSourceRetention

    static func liveMicrophone(sourceID: String) -> TranscriptionSourceIdentity {
        .init(
            kind: .liveMicrophone,
            sourceID: sourceID,
            displayName: nil,
            retention: .doNotRetain
        )
    }

    static func storedAudio(sourceID: String, displayName: String?) -> TranscriptionSourceIdentity {
        .init(
            kind: .storedAudioFile,
            sourceID: sourceID,
            displayName: displayName,
            retention: .preserveOriginal
        )
    }

    init(
        kind: TranscriptionInputKind,
        sourceID: String,
        displayName: String?,
        retention: TranscriptionSourceRetention
    ) {
        self.kind = kind
        self.sourceID = String(sourceID.prefix(256))
        self.displayName = displayName.map { String($0.prefix(160)) }
        self.retention = retention
    }
}

struct TranscriptionLocaleMetadata: Equatable, Sendable {
    let identifier: String

    init(identifier: String) {
        self.identifier = String(identifier.prefix(64))
    }
}

struct TranscriptionTimingMetadata: Equatable, Sendable {
    let startedAt: Date
    let completedAt: Date?
    let audioDuration: TimeInterval?

    init(startedAt: Date, completedAt: Date?, audioDuration: TimeInterval?) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.audioDuration = audioDuration.map { max(0, $0) }
    }
}

struct TranscriptionProvenance: Equatable, Sendable {
    let provider: TranscriptionProviderMetadata
    let source: TranscriptionSourceIdentity
    let locale: TranscriptionLocaleMetadata
    let timing: TranscriptionTimingMetadata
    let networkFallbackProviderID: String?

    init(
        provider: TranscriptionProviderMetadata,
        source: TranscriptionSourceIdentity,
        locale: TranscriptionLocaleMetadata,
        timing: TranscriptionTimingMetadata,
        networkFallbackProviderID: String? = nil
    ) {
        self.provider = provider
        self.source = source
        self.locale = locale
        self.timing = timing
        self.networkFallbackProviderID = networkFallbackProviderID.map { String($0.prefix(64)) }
    }

    var usedNetworkFallback: Bool { networkFallbackProviderID != nil }
}

struct TranscriptionTranscript: Equatable, Sendable {
    let text: String
    let isFinal: Bool
    let provenance: TranscriptionProvenance

    init(text: String, isFinal: Bool, provenance: TranscriptionProvenance) {
        self.text = Self.normalize(text)
        self.isFinal = isFinal
        self.provenance = provenance
    }

    static func normalize(_ text: String) -> String {
        let safeScalars = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar), scalar != "\n", scalar != "\t" {
                return " "
            }
            return String(scalar)
        }.joined()
        // The shared result must not inherit Chat's composer limit: stored-audio
        // consumers need the complete derived transcript. Each presentation or
        // persistence surface applies its own explicit bound when appropriate.
        return safeScalars.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriptionFailureCode: String, Equatable, Sendable {
    case authorizationDenied
    case authorizationRestricted
    case authorizationRequired
    case unavailable
    case offline
    case busy
    case unsupportedInput
    case invalidSource
    case sourceNotFound
    case sourceUnreadable
    case recognitionFailed
    case cancelled
}

struct TranscriptionFailure: Error, Equatable, LocalizedError, Sendable {
    let code: TranscriptionFailureCode
    let message: String
    let provenance: TranscriptionProvenance?

    init(code: TranscriptionFailureCode, message: String, provenance: TranscriptionProvenance? = nil) {
        self.code = code
        self.message = String(
            message
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .prefix(240)
        )
        self.provenance = provenance
    }

    var errorDescription: String? { message }
}

enum TranscriptionEvent: Equatable, Sendable {
    case level(Double)
    case partial(TranscriptionTranscript)
    case final(TranscriptionTranscript)
    case failure(TranscriptionFailure)
}

struct LiveTranscriptionRequest: Equatable, Sendable {
    let source: TranscriptionSourceIdentity

    init(sourceID: String) {
        source = .liveMicrophone(sourceID: sourceID)
    }
}

struct StoredAudioTranscriptionRequest: Equatable, Sendable {
    /// The URL is an input handle only. Results retain the stable source identity, not the path.
    let fileURL: URL
    let source: TranscriptionSourceIdentity

    init(fileURL: URL, sourceID: String, displayName: String? = nil) {
        self.fileURL = fileURL
        self.source = .storedAudio(sourceID: sourceID, displayName: displayName)
    }
}

typealias TranscriptionResult = Result<TranscriptionTranscript, TranscriptionFailure>

/// Shared Cider speech-to-text boundary. Surface code owns capture retention and editable
/// state; providers only consume explicitly supplied live or stored-audio input.
@MainActor
protocol CiderTranscriptionServicing: AnyObject {
    var provider: TranscriptionProviderMetadata { get }

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization

    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws
    func stopLive()
    func cancelLive()

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult
    func cancelStoredAudio()
}
