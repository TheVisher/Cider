import Foundation

enum JournalVoiceCapturePermissionState: Equatable, Sendable {
    case ready
    case notDetermined
    case denied
    case restricted
    case unavailable
    case offline
}

@MainActor
protocol JournalVoiceCaptureAuthorizing: AnyObject {
    func state(for provider: CiderStoredAudioTranscriptionProviderRequest) -> JournalVoiceCapturePermissionState
    func requestAuthorization(
        for provider: CiderStoredAudioTranscriptionProviderRequest
    ) async -> JournalVoiceCapturePermissionState
}

/// Combines the selected stored-audio provider's own authorization with the
/// microphone permission needed to create its input. It never substitutes a provider.
@MainActor
final class JournalVoiceCaptureAuthorizationService: JournalVoiceCaptureAuthorizing {
    typealias ProviderResolver = @MainActor (
        CiderStoredAudioTranscriptionProviderRequest
    ) -> Result<CiderResolvedTranscriptionProvider, TranscriptionFailure>

    private let microphone: any CiderMicrophoneAuthorizationServicing
    private let providerResolver: ProviderResolver

    init(
        microphone: any CiderMicrophoneAuthorizationServicing = SystemCiderMicrophoneAuthorizationService(),
        providerResolver: @escaping ProviderResolver = CiderTranscriptionProviderSelection.resolveStoredAudio
    ) {
        self.microphone = microphone
        self.providerResolver = providerResolver
    }

    func state(for provider: CiderStoredAudioTranscriptionProviderRequest) -> JournalVoiceCapturePermissionState {
        guard let resolved = resolve(provider) else { return .unavailable }
        return state(resolved: resolved)
    }

    private func state(resolved: CiderResolvedTranscriptionProvider) -> JournalVoiceCapturePermissionState {
        let microphoneState = microphone.authorization()
        guard microphoneState == .authorized else { return Self.permissionState(microphoneState) }
        let providerState = resolved.service.authorization(for: .storedAudioFile)
        guard providerState == .authorized else { return Self.permissionState(providerState) }
        switch resolved.service.readiness(for: .storedAudioFile) {
        case .ready: return .ready
        case .unavailable: return .unavailable
        case .offline: return .offline
        }
    }

    func requestAuthorization(
        for provider: CiderStoredAudioTranscriptionProviderRequest
    ) async -> JournalVoiceCapturePermissionState {
        guard let resolved = resolve(provider) else { return .unavailable }
        if microphone.authorization() == .notDetermined {
            _ = await microphone.requestAuthorization()
        }
        guard microphone.authorization() == .authorized else {
            return Self.permissionState(microphone.authorization())
        }
        if resolved.service.authorization(for: .storedAudioFile) == .notDetermined {
            _ = await resolved.service.requestAuthorization(for: .storedAudioFile)
        }
        return state(resolved: resolved)
    }

    private func resolve(
        _ provider: CiderStoredAudioTranscriptionProviderRequest
    ) -> CiderResolvedTranscriptionProvider? {
        guard case .success(let resolved) = providerResolver(provider),
              resolved.requestedProviderID == provider.providerID,
              resolved.service.provider.supportedInputs.contains(.storedAudioFile),
              resolved.service.provider.execution != .network,
              !resolved.service.provider.allowsNetworkFallback else {
            return nil
        }
        return resolved
    }

    private static func permissionState(_ state: TranscriptionAuthorization) -> JournalVoiceCapturePermissionState {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .ready
        }
    }
}

struct JournalVoiceCapturePublicReceipt: Equatable, Sendable {
    let receiptID: String
    let journalDate: String
    let time: String
    let providerID: String
    let wasReused: Bool

    init(_ receipt: JournalStoredVoiceCaptureReceipt) {
        receiptID = receipt.atomicReceipt.receiptID
        journalDate = receipt.atomicReceipt.journalDate
        time = receipt.atomicReceipt.time
        providerID = receipt.transcription.providerID
        wasReused = receipt.wasReused
    }
}

enum JournalVoiceCaptureSessionFailure: String, Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case providerUnavailable
    case recorderUnavailable
    case recordingLimitExceeded
    case captureFailed

    var title: String {
        switch self {
        case .permissionDenied: "Voice capture access denied"
        case .permissionRestricted: "Voice capture restricted"
        case .providerUnavailable: "Transcription unavailable"
        case .recorderUnavailable: "Recording unavailable"
        case .recordingLimitExceeded: "Recording limit reached"
        case .captureFailed: "Voice note not saved"
        }
    }

    var detail: String {
        switch self {
        case .permissionDenied:
            "Allow microphone and any selected-provider speech access in System Settings, then choose Record again."
        case .permissionRestricted:
            "This Mac does not currently allow Journal voice capture."
        case .providerUnavailable:
            "The selected provider is unavailable. Cider did not choose a fallback."
        case .recorderUnavailable:
            "Cider could not create a private temporary recording. Nothing was saved."
        case .recordingLimitExceeded:
            "The bounded temporary recording was removed. Nothing was saved."
        case .captureFailed:
            "Transcription or atomic Journal capture failed. Nothing new is claimed."
        }
    }
}

enum JournalVoiceCaptureSessionState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording(elapsed: TimeInterval)
    case processing
    case succeeded(JournalVoiceCapturePublicReceipt)
    case cancelled
    case failed(JournalVoiceCaptureSessionFailure)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .recording, .processing: true
        case .idle, .succeeded, .cancelled, .failed: false
        }
    }
}

/// Surface-neutral push-to-talk lifecycle for retained Journal voice. The
/// controller owns only temporary recording state and delegates the sole durable
/// mutation to JournalStoredVoiceCapturing.
@MainActor
final class JournalVoiceCaptureSessionController: ObservableObject {
    static let maximumDuration: TimeInterval = 15 * 60
    static let maximumWorkingBytes: Int64 = 64 * 1024 * 1024

    @Published private(set) var state: JournalVoiceCaptureSessionState = .idle
    private(set) var lastReceipt: JournalStoredVoiceCaptureReceipt?

    private struct ActiveRecording {
        let token: UUID
        let journalDate: String
        let capturedAt: Date
        let sourceID: String
        let idempotencyKey: String
        let fileURL: URL
    }

    private let authorizer: any JournalVoiceCaptureAuthorizing
    private let recorder: any JournalVoiceAudioRecording
    private let temporaryFiles: JournalVoiceTemporaryFileStore
    private let coordinator: any JournalStoredVoiceCapturing
    private let provider: CiderStoredAudioTranscriptionProviderRequest
    private let now: @MainActor () -> Date
    private var active: ActiveRecording?
    private var captureTask: Task<JournalStoredVoiceCaptureReceipt, Error>?
    private var elapsedTimer: Timer?

    init(
        authorizer: any JournalVoiceCaptureAuthorizing,
        recorder: any JournalVoiceAudioRecording,
        temporaryFiles: JournalVoiceTemporaryFileStore,
        coordinator: any JournalStoredVoiceCapturing,
        provider: CiderStoredAudioTranscriptionProviderRequest = .init(
            providerID: CiderTranscriptionProviderSelection.sharedDefaultRequestID
        ),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.authorizer = authorizer
        self.recorder = recorder
        self.temporaryFiles = temporaryFiles
        self.coordinator = coordinator
        self.provider = provider
        self.now = now
    }

    static func production(
        database: CiderDatabase = .shared,
        notesStorage: NotesStorage = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL
    ) -> JournalVoiceCaptureSessionController {
        JournalVoiceCaptureSessionController(
            authorizer: JournalVoiceCaptureAuthorizationService(),
            recorder: SystemJournalVoiceAudioRecorder(),
            temporaryFiles: JournalVoiceTemporaryFileStore(),
            coordinator: JournalStoredVoiceCaptureCoordinator(
                database: database,
                notesStorage: notesStorage,
                vaultRoot: vaultRoot
            )
        )
    }

    func startRecording(journalDate: String) async {
        guard !state.isActive, JournalTitle.isValidISODate(journalDate) else { return }
        cleanupActiveFile()
        lastReceipt = nil
        let token = UUID()
        state = .requestingPermission

        var permission = authorizer.state(for: provider)
        if permission == .notDetermined {
            permission = await authorizer.requestAuthorization(for: provider)
        }
        guard state == .requestingPermission else { return }
        guard permission == .ready else {
            state = .failed(Self.failure(for: permission))
            return
        }

        let capturedAt = now()
        let fileURL: URL
        do {
            fileURL = try temporaryFiles.makeWorkingURL(recordingID: token)
        } catch {
            state = .failed(.recorderUnavailable)
            return
        }
        let context = ActiveRecording(
            token: token,
            journalDate: journalDate,
            capturedAt: capturedAt,
            sourceID: "cider-journal-voice:\(token.uuidString.lowercased())",
            idempotencyKey: "cider-journal-voice-capture:\(UUID().uuidString.lowercased())",
            fileURL: fileURL
        )
        active = context
        do {
            try recorder.start(at: fileURL, maximumDuration: Self.maximumDuration) { [weak self] succeeded in
                guard let self else { return }
                if succeeded {
                    Task { await self.stopRecording() }
                } else {
                    self.failActiveRecording(token: token)
                }
            }
            guard active?.token == token else {
                recorder.cancel()
                temporaryFiles.remove(fileURL)
                return
            }
            state = .recording(elapsed: 0)
            startElapsedTimer()
        } catch {
            active = nil
            temporaryFiles.remove(fileURL)
            state = .failed(.recorderUnavailable)
        }
    }

    func stopRecording() async {
        guard case .recording = state, let context = active else { return }
        stopElapsedTimer()
        state = .processing
        let recorded: JournalVoiceRecordedAudio
        do {
            recorded = try recorder.stop()
        } catch {
            active = nil
            temporaryFiles.remove(context.fileURL)
            state = .failed(.recorderUnavailable)
            return
        }
        guard recorded.fileURL.standardizedFileURL == context.fileURL.standardizedFileURL,
              temporaryFiles.contains(recorded.fileURL),
              recorded.byteSize > 0,
              recorded.byteSize <= Self.maximumWorkingBytes,
              recorded.duration > 0,
              recorded.duration <= Self.maximumDuration + 1 else {
            active = nil
            temporaryFiles.remove(context.fileURL)
            state = .failed(.recordingLimitExceeded)
            return
        }

        let request = Self.captureRequest(context: context, provider: provider)
        let task = Task { try await coordinator.capture(request) }
        captureTask = task
        do {
            let receipt = try await task.value
            guard active?.token == context.token, state == .processing else { return }
            captureTask = nil
            active = nil
            temporaryFiles.remove(context.fileURL)
            lastReceipt = receipt
            state = .succeeded(.init(receipt))
        } catch {
            guard active?.token == context.token, state == .processing else { return }
            captureTask = nil
            active = nil
            temporaryFiles.remove(context.fileURL)
            state = .failed(.captureFailed)
        }
    }

    func cancel() {
        guard state.isActive else { return }
        let fileURL = active?.fileURL
        captureTask?.cancel()
        captureTask = nil
        recorder.cancel()
        stopElapsedTimer()
        active = nil
        temporaryFiles.remove(fileURL)
        lastReceipt = nil
        state = .cancelled
    }

    func reset() {
        guard !state.isActive else { return }
        cleanupActiveFile()
        lastReceipt = nil
        state = .idle
    }

    /// Exposed for deterministic timer and acceptance tests; production calls it
    /// from the bounded elapsed timer.
    func refreshRecordingBounds() {
        guard case .recording = state, let context = active else { return }
        let elapsed = min(Self.maximumDuration, max(0, recorder.elapsedTime))
        state = .recording(elapsed: elapsed)
        guard recorder.byteSize <= Self.maximumWorkingBytes else {
            recorder.cancel()
            stopElapsedTimer()
            active = nil
            temporaryFiles.remove(context.fileURL)
            state = .failed(.recordingLimitExceeded)
            return
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshRecordingBounds() }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func cleanupActiveFile() {
        captureTask?.cancel()
        captureTask = nil
        recorder.cancel()
        stopElapsedTimer()
        temporaryFiles.remove(active?.fileURL)
        active = nil
    }

    private func failActiveRecording(token: UUID) {
        guard active?.token == token, case .recording = state else { return }
        let fileURL = active?.fileURL
        recorder.cancel()
        stopElapsedTimer()
        active = nil
        temporaryFiles.remove(fileURL)
        state = .failed(.recorderUnavailable)
    }

    private static func captureRequest(
        context: ActiveRecording,
        provider: CiderStoredAudioTranscriptionProviderRequest
    ) -> JournalStoredVoiceCaptureRequest {
        .init(
            journalDate: context.journalDate,
            time: journalTime(context.capturedAt),
            audioURL: context.fileURL,
            sourceID: context.sourceID,
            displayTitle: "Voice note at \(journalTime(context.capturedAt))",
            mimeType: "audio/mp4",
            source: "cider-journal-voice",
            capturedAt: context.capturedAt,
            idempotencyKey: context.idempotencyKey,
            sourceContext: CaptureSourceContext(
                surface: "macos-journal",
                channel: "journal-day",
                messageID: context.token.uuidString.lowercased(),
                originalText: nil
            ),
            provider: provider
        )
    }

    private static func journalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func failure(
        for permission: JournalVoiceCapturePermissionState
    ) -> JournalVoiceCaptureSessionFailure {
        switch permission {
        case .denied: .permissionDenied
        case .restricted: .permissionRestricted
        case .ready, .notDetermined, .unavailable, .offline: .providerUnavailable
        }
    }
}
