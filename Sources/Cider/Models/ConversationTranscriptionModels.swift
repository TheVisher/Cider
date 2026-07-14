import Foundation

// Compatibility names for existing Conversation call sites while the production
// capability now lives in the neutral shared transcription model.
typealias ConversationTranscriptionAuthorization = TranscriptionAuthorization
typealias ConversationTranscriptionReadiness = TranscriptionReadiness
typealias ConversationTranscriptionEvent = TranscriptionEvent
typealias ConversationTranscriptionServicing = CiderTranscriptionServicing

enum AgentRoomsSpeechInputState: String, Equatable, Sendable {
    case notDetermined
    case requestingPermission
    case ready
    case denied
    case restricted
    case unavailable
    case offline
    case listening
    case transcribing
    case completed
    case cancelled
    case failed

    var isActive: Bool {
        self == .requestingPermission || self == .listening || self == .transcribing
    }
}

struct AgentRoomsSpeechInputPresentation: Equatable, Sendable {
    let state: AgentRoomsSpeechInputState
    let title: String
    let detail: String?
    let level: Double

    static func initial(
        authorization: ConversationTranscriptionAuthorization,
        readiness: ConversationTranscriptionReadiness
    ) -> AgentRoomsSpeechInputPresentation {
        switch authorization {
        case .notDetermined:
            return .init(
                state: .notDetermined,
                title: "Microphone permission required",
                detail: "Cider asks only after you start microphone transcription.",
                level: 0
            )
        case .denied:
            return .init(
                state: .denied,
                title: "Microphone transcription denied",
                detail: "Allow microphone and speech recognition access in System Settings to dictate.",
                level: 0
            )
        case .restricted:
            return .init(
                state: .restricted,
                title: "Microphone transcription restricted",
                detail: "This Mac does not currently allow microphone transcription.",
                level: 0
            )
        case .authorized:
            return readinessPresentation(readiness)
        }
    }

    static func readinessPresentation(
        _ readiness: ConversationTranscriptionReadiness
    ) -> AgentRoomsSpeechInputPresentation {
        switch readiness {
        case .ready:
            return .init(
                state: .ready,
                title: "Microphone transcription ready",
                detail: "Dictation stays in the editable room draft until you explicitly send it.",
                level: 0
            )
        case .unavailable(let reason):
            return .init(state: .unavailable, title: "Transcription unavailable", detail: bounded(reason), level: 0)
        case .offline(let reason):
            return .init(state: .offline, title: "Transcription offline", detail: bounded(reason), level: 0)
        }
    }

    static func bounded(_ text: String, maximumLength: Int = 180) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return String(flattened.prefix(maximumLength))
    }
}

/// Process-local Cider provenance for the current editable speech-derived draft.
/// It is intentionally not a Conversation Core row and never retains raw audio.
struct AgentRoomsSpeechDraft: Equatable, Sendable {
    static let maximumTranscriptLength = 4_000

    let roomID: String
    let providerID: String
    let transcript: String
    let isFinal: Bool
    let retainsRawAudio: Bool

    init(roomID: String, providerID: String, transcript: String, isFinal: Bool) {
        self.roomID = roomID
        self.providerID = String(providerID.prefix(64))
        self.transcript = Self.boundedTranscript(transcript)
        self.isFinal = isFinal
        self.retainsRawAudio = false
    }

    static func boundedTranscript(_ text: String) -> String {
        String(TranscriptionTranscript.normalize(text).prefix(maximumTranscriptLength))
    }

    static func merge(originalDraft: String, transcript: String) -> String {
        let transcript = boundedTranscript(transcript)
        guard !transcript.isEmpty else { return originalDraft }
        guard !originalDraft.isEmpty else { return transcript }
        if originalDraft.last?.isWhitespace == true { return originalDraft + transcript }
        return originalDraft + " " + transcript
    }
}
