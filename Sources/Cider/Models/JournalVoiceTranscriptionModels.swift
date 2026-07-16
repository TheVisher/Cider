import Foundation

struct JournalVoiceTranscriptionSegment: Codable, Equatable, Hashable, Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
}

struct JournalVoiceTranscription: Equatable, Hashable, Sendable {
    enum Status: String, Equatable, Hashable, Sendable {
        case completed
    }

    let status: Status
    let text: String
    let providerID: String
    let adapterVersion: String
    let modelIdentity: String?
    let execution: TranscriptionProviderExecution
    let localeIdentifier: String
    let startedAt: Date
    let completedAt: Date?
    let audioDuration: TimeInterval?
    let segments: [JournalVoiceTranscriptionSegment]
    let sourceAudioID: String
    let sourceAudioSHA256: String
    let retention: TranscriptionSourceRetention
    let usedNetworkFallback: Bool

    init(transcript: TranscriptionTranscript, sourceAudioSHA256: String) {
        status = .completed
        text = transcript.text
        providerID = transcript.provenance.provider.id
        adapterVersion = transcript.provenance.provider.adapterVersion
        modelIdentity = transcript.provenance.provider.modelIdentity
        execution = transcript.provenance.provider.execution
        localeIdentifier = transcript.provenance.locale.identifier
        startedAt = transcript.provenance.timing.startedAt
        completedAt = transcript.provenance.timing.completedAt
        audioDuration = transcript.provenance.timing.audioDuration
        segments = transcript.segments.map {
            .init(text: $0.text, timestamp: $0.timestamp, duration: $0.duration)
        }
        sourceAudioID = transcript.provenance.source.sourceID
        self.sourceAudioSHA256 = sourceAudioSHA256
        retention = transcript.provenance.source.retention
        usedNetworkFallback = transcript.provenance.usedNetworkFallback
    }

    fileprivate init?(_ metadata: [String: String]) {
        guard let status = Status(rawValue: metadata[StorageKey.status] ?? ""),
              let text = metadata[StorageKey.text],
              let providerID = metadata[StorageKey.providerID],
              let adapterVersion = metadata[StorageKey.adapterVersion],
              let execution = TranscriptionProviderExecution(rawValue: metadata[StorageKey.execution] ?? ""),
              let localeIdentifier = metadata[StorageKey.locale],
              let startedAt = Self.date(metadata[StorageKey.startedAt]),
              let sourceAudioID = metadata[StorageKey.sourceAudioID],
              let sourceAudioSHA256 = metadata[StorageKey.sourceAudioSHA256],
              let retention = TranscriptionSourceRetention(rawValue: metadata[StorageKey.retention] ?? ""),
              let usedNetworkFallback = Self.boolean(metadata[StorageKey.usedNetworkFallback]),
              let segmentsJSON = metadata[StorageKey.segments],
              let segmentsData = segmentsJSON.data(using: .utf8),
              let segments = try? JSONDecoder().decode([JournalVoiceTranscriptionSegment].self, from: segmentsData)
        else {
            return nil
        }
        self.status = status
        self.text = text
        self.providerID = providerID
        self.adapterVersion = adapterVersion
        modelIdentity = metadata[StorageKey.modelIdentity]
        self.execution = execution
        self.localeIdentifier = localeIdentifier
        self.startedAt = startedAt
        completedAt = Self.date(metadata[StorageKey.completedAt])
        audioDuration = metadata[StorageKey.audioDuration].flatMap(TimeInterval.init)
        self.segments = segments
        self.sourceAudioID = sourceAudioID
        self.sourceAudioSHA256 = sourceAudioSHA256
        self.retention = retention
        self.usedNetworkFallback = usedNetworkFallback
    }

    func storageMetadata() -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let segmentsJSON = (try? encoder.encode(segments)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        var metadata: [String: String] = [
            StorageKey.status: status.rawValue,
            StorageKey.text: text,
            StorageKey.providerID: providerID,
            StorageKey.adapterVersion: adapterVersion,
            StorageKey.execution: execution.rawValue,
            StorageKey.locale: localeIdentifier,
            StorageKey.startedAt: Self.dateString(startedAt),
            StorageKey.segments: segmentsJSON,
            StorageKey.sourceAudioID: sourceAudioID,
            StorageKey.sourceAudioSHA256: sourceAudioSHA256,
            StorageKey.retention: retention.rawValue,
            StorageKey.usedNetworkFallback: usedNetworkFallback ? "true" : "false",
        ]
        if let modelIdentity { metadata[StorageKey.modelIdentity] = modelIdentity }
        if let completedAt { metadata[StorageKey.completedAt] = Self.dateString(completedAt) }
        if let audioDuration { metadata[StorageKey.audioDuration] = String(audioDuration) }
        return metadata
    }

    static func read(from metadata: [String: String]) -> JournalVoiceTranscription? {
        JournalVoiceTranscription(metadata)
    }

    private enum StorageKey {
        static let status = "transcription_status"
        static let text = "transcript_text"
        static let providerID = "transcription_provider_id"
        static let adapterVersion = "transcription_adapter_version"
        static let modelIdentity = "transcription_model_identity"
        static let execution = "transcription_execution"
        static let locale = "transcription_locale"
        static let startedAt = "transcription_started_at"
        static let completedAt = "transcription_completed_at"
        static let audioDuration = "transcription_audio_duration"
        static let segments = "transcription_segments"
        static let sourceAudioID = "transcription_source_audio_id"
        static let sourceAudioSHA256 = "transcription_source_audio_sha256"
        static let retention = "transcription_retention"
        static let usedNetworkFallback = "transcription_used_network_fallback"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fractional.date(from: raw) { return value }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func boolean(_ raw: String?) -> Bool? {
        switch raw {
        case "true": true
        case "false": false
        default: nil
        }
    }
}

struct JournalStoredVoiceCaptureRequest: Equatable {
    let journalDate: String
    let time: String
    let audioURL: URL
    let sourceID: String
    let displayTitle: String?
    let mimeType: String?
    let source: String
    let capturedAt: Date
    let idempotencyKey: String
    let sourceContext: CaptureSourceContext?
    let provider: CiderStoredAudioTranscriptionProviderRequest
}

struct JournalStoredVoiceCaptureReceipt: Equatable, Sendable {
    let atomicReceipt: JournalAtomicCaptureReceipt
    let transcription: JournalVoiceTranscription

    var wasReused: Bool { atomicReceipt.wasReused }

    var descriptionForPublicOutput: String {
        "Journal voice capture \(wasReused ? "reused" : "completed") with \(transcription.providerID)."
    }
}

struct JournalStoredVoiceCaptureError: Error, Equatable, LocalizedError, Sendable {
    enum Code: String, Equatable, Sendable {
        case validationFailed
        case idempotencyConflict
        case providerUnavailable
        case transcriptionFailed
        case persistenceFailed
        case indeterminate
    }

    let code: Code
    let transcriptionFailureCode: TranscriptionFailureCode?

    init(_ code: Code, transcriptionFailureCode: TranscriptionFailureCode? = nil) {
        self.code = code
        self.transcriptionFailureCode = transcriptionFailureCode
    }

    var errorDescription: String? {
        switch code {
        case .validationFailed:
            "Cider could not safely validate the selected Journal audio; nothing was committed."
        case .idempotencyConflict:
            "That Journal voice retry identity belongs to different source audio; nothing was changed."
        case .providerUnavailable:
            "The explicitly selected transcription provider cannot process this stored audio; nothing was committed."
        case .transcriptionFailed:
            "The selected provider did not produce a trustworthy final transcript; nothing was committed."
        case .persistenceFailed:
            "Journal voice capture could not be committed; no success is claimed."
        case .indeterminate:
            "Journal voice capture state could not be verified; no new mutation was attempted."
        }
    }
}
