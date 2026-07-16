import Foundation

@MainActor
protocol JournalStoredVoiceCapturing: AnyObject {
    func capture(_ request: JournalStoredVoiceCaptureRequest) async throws -> JournalStoredVoiceCaptureReceipt
}

/// Neutral stored-voice intake for Journal. The coordinator validates and
/// transcribes a caller-accessible local audio file without canonical mutation,
/// then delegates the only write to JournalAtomicCaptureWriter. A failed
/// transcription therefore cannot create a source card, day entry, event,
/// candidate source, or receipt that claims success.
@MainActor
final class JournalStoredVoiceCaptureCoordinator: JournalStoredVoiceCapturing {
    typealias ProviderResolver = @MainActor (
        CiderStoredAudioTranscriptionProviderRequest
    ) -> Result<CiderResolvedTranscriptionProvider, TranscriptionFailure>

    private enum MetadataKey {
        static let retryDigest = "journal_voice_retry_digest"
        static let sourceID = "journal_voice_source_id"
        static let sourceSHA256 = "journal_voice_source_sha256"
        static let requestedProviderID = "journal_voice_requested_provider_id"
        static let selectedProviderID = "journal_voice_selected_provider_id"
        static let status = "journal_voice_status"
        static let transactionPolicy = "journal_voice_transaction_policy"
    }

    private let database: CiderDatabase
    private let notesStorage: NotesStorage
    private let vaultRoot: URL
    private let mediaIntake: JournalMediaIntakeService
    private let atomicWriter: JournalAtomicCaptureWriter
    private let providerResolver: ProviderResolver

    init(
        database: CiderDatabase,
        notesStorage: NotesStorage,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        mediaIntake: JournalMediaIntakeService? = nil,
        atomicWriter: JournalAtomicCaptureWriter? = nil,
        providerResolver: @escaping ProviderResolver = CiderTranscriptionProviderSelection.resolveStoredAudio
    ) {
        self.database = database
        self.notesStorage = notesStorage
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.mediaIntake = mediaIntake ?? JournalMediaIntakeService(database: database, vaultRoot: vaultRoot)
        self.atomicWriter = atomicWriter ?? JournalAtomicCaptureWriter(
            database: database,
            notesStorage: notesStorage,
            vaultRoot: vaultRoot,
            mediaIntake: mediaIntake
        )
        self.providerResolver = providerResolver
    }

    func capture(_ request: JournalStoredVoiceCaptureRequest) async throws -> JournalStoredVoiceCaptureReceipt {
        try Task.checkCancellation()
        try validate(request)
        let mediaRequest = JournalMediaIntakeRequest(
            sourceURL: request.audioURL,
            sourceID: request.sourceID,
            kind: .audio,
            capturedAt: request.capturedAt,
            displayName: request.displayTitle
        )
        let validated: JournalValidatedMediaBatch
        do {
            validated = try mediaIntake.validateBatch([mediaRequest])
        } catch {
            throw JournalStoredVoiceCaptureError(.validationFailed)
        }
        guard let sourceSHA256 = validated.contentHashes.first else {
            throw JournalStoredVoiceCaptureError(.validationFailed)
        }

        let retryMetadata = Self.retryMetadata(
            request: request,
            normalizedSourceID: mediaRequest.sourceID,
            sourceSHA256: sourceSHA256
        )
        do {
            if let existing = try atomicWriter.existingReceipt(
                idempotencyKey: request.idempotencyKey,
                matchingEventMetadata: retryMetadata
            ) {
                return try durableReceipt(for: existing, expectedMetadata: retryMetadata)
            }
        } catch let error as JournalAtomicCaptureError {
            switch error.code {
            case .idempotencyConflict:
                throw JournalStoredVoiceCaptureError(.idempotencyConflict)
            case .validationFailed, .notCommitted:
                throw JournalStoredVoiceCaptureError(.persistenceFailed)
            case .indeterminate:
                throw JournalStoredVoiceCaptureError(.indeterminate)
            }
        }

        try Task.checkCancellation()

        let resolution: CiderResolvedTranscriptionProvider
        switch providerResolver(request.provider) {
        case .success(let resolved):
            resolution = resolved
        case .failure(let failure):
            throw JournalStoredVoiceCaptureError(
                .providerUnavailable,
                transcriptionFailureCode: failure.code
            )
        }
        let service = resolution.service
        guard resolution.requestedProviderID == request.provider.providerID,
              service.provider.supportedInputs.contains(.storedAudioFile),
              service.provider.execution != .network,
              !service.provider.allowsNetworkFallback else {
            throw JournalStoredVoiceCaptureError(
                .providerUnavailable,
                transcriptionFailureCode: .unsupportedInput
            )
        }
        let authorization = service.authorization(for: .storedAudioFile)
        guard authorization == .authorized else {
            throw JournalStoredVoiceCaptureError(
                .providerUnavailable,
                transcriptionFailureCode: Self.authorizationFailure(authorization)
            )
        }
        switch service.readiness(for: .storedAudioFile) {
        case .ready:
            break
        case .unavailable:
            throw JournalStoredVoiceCaptureError(
                .providerUnavailable,
                transcriptionFailureCode: .unavailable
            )
        case .offline:
            throw JournalStoredVoiceCaptureError(
                .providerUnavailable,
                transcriptionFailureCode: .offline
            )
        }

        let result = await mediaIntake.transcribeValidatedAudio(validated, using: service)
        try Task.checkCancellation()
        let transcript: TranscriptionTranscript
        switch result {
        case .success(let value):
            transcript = value
        case .failure(let failure):
            throw JournalStoredVoiceCaptureError(
                .transcriptionFailed,
                transcriptionFailureCode: failure.code
            )
        }
        guard transcript.isFinal,
              !transcript.text.isEmpty,
              transcript.provenance.provider == service.provider,
              transcript.provenance.source.kind == .storedAudioFile,
              transcript.provenance.source.sourceID == mediaRequest.sourceID,
              transcript.provenance.source.retention == .preserveOriginal,
              !transcript.provenance.usedNetworkFallback,
              transcript.provenance.provider.execution != .network,
              !transcript.provenance.provider.allowsNetworkFallback else {
            throw JournalStoredVoiceCaptureError(
                .transcriptionFailed,
                transcriptionFailureCode: .recognitionFailed
            )
        }

        let voiceTranscription = JournalVoiceTranscription(
            transcript: transcript,
            sourceAudioSHA256: sourceSHA256
        )
        var captureMetadata = retryMetadata
        captureMetadata[MetadataKey.selectedProviderID] = resolution.selectedProviderID
        captureMetadata[MetadataKey.status] = JournalVoiceTranscription.Status.completed.rawValue
        captureMetadata[MetadataKey.transactionPolicy] = "atomic_after_successful_transcription"
        let atomicRequest = JournalAtomicCaptureRequest(
            journalDate: request.journalDate,
            time: request.time,
            text: transcript.text,
            source: request.source,
            capturedAt: request.capturedAt,
            idempotencyKey: request.idempotencyKey,
            sourceContext: request.sourceContext,
            media: [
                .init(
                    sourceURL: request.audioURL,
                    sourceID: mediaRequest.sourceID,
                    kind: .audio,
                    displayTitle: request.displayTitle,
                    mimeType: request.mimeType,
                    expectedContentSHA256: sourceSHA256,
                    transcription: voiceTranscription
                ),
            ],
            captureMetadata: captureMetadata
        )

        // The atomic writer is synchronous on the main actor. Cancellation is
        // honored up to this boundary; once the transaction begins it produces
        // one durable receipt or rolls back as a unit.
        try Task.checkCancellation()

        let atomicReceipt: JournalAtomicCaptureReceipt
        do {
            atomicReceipt = try atomicWriter.capture(atomicRequest)
        } catch let error as JournalAtomicCaptureError {
            switch error.code {
            case .idempotencyConflict:
                throw JournalStoredVoiceCaptureError(.idempotencyConflict)
            case .validationFailed, .notCommitted:
                throw JournalStoredVoiceCaptureError(.persistenceFailed)
            case .indeterminate:
                throw JournalStoredVoiceCaptureError(.indeterminate)
            }
        } catch {
            throw JournalStoredVoiceCaptureError(.persistenceFailed)
        }
        return try durableReceipt(for: atomicReceipt, expectedMetadata: retryMetadata)
    }

    private func durableReceipt(
        for atomicReceipt: JournalAtomicCaptureReceipt,
        expectedMetadata: [String: String]
    ) throws -> JournalStoredVoiceCaptureReceipt {
        guard let noteID = UUID(uuidString: atomicReceipt.item.id) else {
            throw JournalStoredVoiceCaptureError(.indeterminate)
        }
        let sourceCards: [JournalMediaSourceCard]
        do {
            sourceCards = try JournalMediaSourceCardReadService(
                database: database,
                vaultRoot: vaultRoot
            ).sourceCards(noteIDs: [noteID])
        } catch {
            throw JournalStoredVoiceCaptureError(.indeterminate)
        }
        guard let sourceRef = atomicReceipt.mediaSources.first,
              atomicReceipt.mediaSources.count == 1,
              let card = sourceCards.first(where: { $0.id == sourceRef.id }),
              let transcription = card.transcription,
              transcription.status == .completed,
              transcription.sourceAudioID == expectedMetadata[MetadataKey.sourceID],
              transcription.sourceAudioSHA256 == expectedMetadata[MetadataKey.sourceSHA256],
              transcription.retention == .preserveOriginal,
              !transcription.usedNetworkFallback else {
            throw JournalStoredVoiceCaptureError(.indeterminate)
        }
        return .init(atomicReceipt: atomicReceipt, transcription: transcription)
    }

    private func validate(_ request: JournalStoredVoiceCaptureRequest) throws {
        let clock = request.time.split(separator: ":")
        guard JournalTitle.isValidISODate(request.journalDate),
              clock.count == 2,
              clock[0].count == 2,
              clock[1].count == 2,
              clock[0].allSatisfy(\.isNumber),
              clock[1].allSatisfy(\.isNumber),
              (Int(clock[0]) ?? -1) >= 0,
              (Int(clock[0]) ?? 24) <= 23,
              (Int(clock[1]) ?? -1) >= 0,
              (Int(clock[1]) ?? 60) <= 59,
              request.audioURL.isFileURL,
              !request.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.provider.providerID.isEmpty else {
            throw JournalStoredVoiceCaptureError(.validationFailed)
        }
    }

    private static func retryMetadata(
        request: JournalStoredVoiceCaptureRequest,
        normalizedSourceID: String,
        sourceSHA256: String
    ) -> [String: String] {
        let context = request.sourceContext.map {
            [
                $0.surface ?? "",
                $0.channel ?? "",
                $0.channelID ?? "",
                $0.threadID ?? "",
                $0.messageID ?? "",
                $0.senderID ?? "",
            ].joined(separator: "|")
        } ?? ""
        let seed = [
            request.journalDate,
            request.time,
            request.source,
            normalizedSourceID,
            request.displayTitle ?? "",
            request.mimeType ?? "",
            context,
            request.provider.providerID,
            request.provider.localeIdentifier ?? "",
            request.provider.localFasterWhisperConfiguration?.modelIdentity ?? "",
            sourceSHA256,
        ].joined(separator: "\u{1e}")
        return [
            MetadataKey.retryDigest: LocalFileIntakeValidator.sha256(Data(seed.utf8)),
            MetadataKey.sourceID: normalizedSourceID,
            MetadataKey.sourceSHA256: sourceSHA256,
            MetadataKey.requestedProviderID: request.provider.providerID,
        ]
    }

    private static func authorizationFailure(
        _ authorization: TranscriptionAuthorization
    ) -> TranscriptionFailureCode {
        switch authorization {
        case .notDetermined: .authorizationRequired
        case .denied: .authorizationDenied
        case .restricted: .authorizationRestricted
        case .authorized: .recognitionFailed
        }
    }
}
