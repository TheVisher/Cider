import AVFoundation
import Foundation
import Speech

/// Native adapter for Cider's shared transcription capability. Both live microphone
/// and stored-file recognition are forced on-device and never fall back to a network provider.
@MainActor
final class AppleSpeechTranscriptionService: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(
        id: "apple-speech-on-device",
        adapterVersion: "2",
        modelIdentity: "apple-speech-system-on-device",
        execution: .onDevice,
        supportedInputs: [.liveMicrophone, .storedAudioFile],
        supportsLivePartialResults: true,
        supportsSegmentTimestamps: true,
        allowsNetworkFallback: false
    )

    private let recognizer: SFSpeechRecognizer?
    private let locale: TranscriptionLocaleMetadata
    private let audioEngine = AVAudioEngine()
    private let microphoneAuthorization: any CiderMicrophoneAuthorizationServicing
    private let now: @MainActor () -> Date

    private var liveRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveEventHandler: (@MainActor @Sendable (TranscriptionEvent) -> Void)?
    private var liveSource: TranscriptionSourceIdentity?
    private var liveStartedAt: Date?
    private var tapInstalled = false

    private var storedAudioContinuation: CheckedContinuation<TranscriptionResult, Never>?
    private var storedAudioProvenance: TranscriptionProvenance?

    init(
        locale: Locale = .current,
        microphoneAuthorization: any CiderMicrophoneAuthorizationServicing = SystemCiderMicrophoneAuthorizationService(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        recognizer = SFSpeechRecognizer(locale: locale)
        self.locale = TranscriptionLocaleMetadata(identifier: locale.identifier)
        self.microphoneAuthorization = microphoneAuthorization
        self.now = now
    }

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization {
        let speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        guard input == .liveMicrophone else { return speech }

        let microphone = microphoneAuthorization.authorization()
        if speech == .denied || microphone == .denied { return .denied }
        if speech == .restricted || microphone == .restricted { return .restricted }
        if speech == .notDetermined || microphone == .notDetermined { return .notDetermined }
        return .authorized
    }

    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness {
        guard provider.supportedInputs.contains(input) else {
            return .unavailable(reason: "This transcription input is not supported by the selected provider.")
        }
        guard let recognizer else {
            return .unavailable(reason: "Speech recognition is unavailable for the current language.")
        }
        guard recognizer.isAvailable else {
            return .offline(reason: "Speech recognition is offline or temporarily unavailable.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable(reason: "On-device transcription is unavailable for the current language.")
        }
        return .ready
    }

    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        guard Self.map(SFSpeechRecognizer.authorizationStatus()) == .authorized,
              input == .liveMicrophone
        else {
            return authorization(for: input)
        }
        if microphoneAuthorization.authorization() == .notDetermined {
            _ = await microphoneAuthorization.requestAuthorization()
        }
        return authorization(for: input)
    }

    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws {
        guard request.source.kind == .liveMicrophone,
              request.source.retention == .doNotRetain,
              !request.source.sourceID.isEmpty
        else {
            throw TranscriptionFailure(code: .invalidSource, message: "Live transcription requires a valid ephemeral source identity.")
        }
        try requireAvailable(input: .liveMicrophone, source: request.source)
        guard recognitionTask == nil, liveRequest == nil, storedAudioContinuation == nil else {
            throw TranscriptionFailure(code: .busy, message: "The transcription provider is already processing audio.")
        }
        guard let recognizer else {
            throw TranscriptionFailure(code: .unavailable, message: "On-device transcription is unavailable.")
        }

        liveSource = request.source
        liveStartedAt = now()
        liveEventHandler = onEvent

        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        speechRequest.requiresOnDeviceRecognition = true
        liveRequest = speechRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            let failure = liveFailure(code: .unavailable, message: "The microphone is unavailable.")
            finishLiveSession(cancelRecognitionTask: true)
            throw failure
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            speechRequest.append(buffer)
            let level = Self.normalizedLevel(buffer)
            Task { @MainActor [weak self] in
                self?.liveEventHandler?(.level(level))
            }
        }
        tapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let transcript = self.liveTranscript(from: result)
                    self.liveEventHandler?(result.isFinal ? .final(transcript) : .partial(transcript))
                    if result.isFinal {
                        self.finishLiveSession(cancelRecognitionTask: false)
                        return
                    }
                }
                if error != nil {
                    self.liveEventHandler?(.failure(self.liveFailure(
                        code: .recognitionFailed,
                        message: "Transcription stopped before Cider received a final result."
                    )))
                    self.finishLiveSession(cancelRecognitionTask: true)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            let failure = liveFailure(code: .unavailable, message: "Cider could not start the microphone.")
            finishLiveSession(cancelRecognitionTask: true)
            throw failure
        }
    }

    func stopLive() {
        guard liveRequest != nil else { return }
        liveRequest?.endAudio()
        stopAudioInput()
    }

    func cancelLive() {
        guard liveRequest != nil || liveSource != nil else { return }
        finishLiveSession(cancelRecognitionTask: true)
    }

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        let startedAt = now()
        let initialProvenance = provenance(
            source: request.source,
            startedAt: startedAt,
            completedAt: nil,
            audioDuration: nil
        )

        guard request.source.kind == .storedAudioFile,
              request.source.retention == .preserveOriginal,
              !request.source.sourceID.isEmpty,
              request.fileURL.isFileURL
        else {
            return .failure(.init(
                code: .invalidSource,
                message: "Stored-audio transcription requires a file URL and stable original-source identity.",
                provenance: initialProvenance
            ))
        }
        do {
            try requireAvailable(input: .storedAudioFile, source: request.source)
        } catch let failure as TranscriptionFailure {
            return .failure(failure)
        } catch {
            return .failure(.init(code: .unavailable, message: "Stored-audio transcription is unavailable.", provenance: initialProvenance))
        }
        guard recognitionTask == nil, liveRequest == nil, storedAudioContinuation == nil else {
            return .failure(.init(
                code: .busy,
                message: "The transcription provider is already processing audio.",
                provenance: initialProvenance
            ))
        }

        do {
            let values = try request.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                return .failure(.init(
                    code: .invalidSource,
                    message: "Stored-audio transcription requires a regular, non-symbolic-link source file.",
                    provenance: initialProvenance
                ))
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .failure(.init(code: .sourceNotFound, message: "The original audio source file was not found.", provenance: initialProvenance))
        } catch {
            return .failure(.init(code: .sourceUnreadable, message: "The original audio source file is not readable.", provenance: initialProvenance))
        }
        guard FileManager.default.isReadableFile(atPath: request.fileURL.path) else {
            return .failure(.init(code: .sourceUnreadable, message: "The original audio source file is not readable.", provenance: initialProvenance))
        }
        guard let recognizer else {
            return .failure(.init(code: .unavailable, message: "On-device transcription is unavailable.", provenance: initialProvenance))
        }

        let speechRequest = SFSpeechURLRecognitionRequest(url: request.fileURL)
        speechRequest.shouldReportPartialResults = false
        speechRequest.requiresOnDeviceRecognition = true
        storedAudioProvenance = initialProvenance

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                storedAudioContinuation = continuation
                recognitionTask = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let result, result.isFinal {
                            self.completeStoredAudio(.success(self.storedTranscript(
                                from: result,
                                source: request.source,
                                startedAt: startedAt
                            )))
                        } else if error != nil {
                            self.completeStoredAudio(.failure(.init(
                                code: .recognitionFailed,
                                message: "Cider could not transcribe the original audio file on device.",
                                provenance: self.completedStoredProvenance()
                            )))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelStoredAudio()
            }
        }
    }

    func cancelStoredAudio() {
        guard storedAudioContinuation != nil else { return }
        recognitionTask?.cancel()
        completeStoredAudio(.failure(.init(
            code: .cancelled,
            message: "Stored-audio transcription was cancelled.",
            provenance: completedStoredProvenance()
        )), cancelRecognitionTask: false)
    }

    private func requireAvailable(input: TranscriptionInputKind, source: TranscriptionSourceIdentity) throws {
        let startedAt = now()
        let context = provenance(source: source, startedAt: startedAt, completedAt: startedAt, audioDuration: nil)
        switch authorization(for: input) {
        case .authorized:
            break
        case .notDetermined:
            throw TranscriptionFailure(code: .authorizationRequired, message: "Speech transcription authorization is required.", provenance: context)
        case .denied:
            throw TranscriptionFailure(code: .authorizationDenied, message: "Speech transcription authorization was denied.", provenance: context)
        case .restricted:
            throw TranscriptionFailure(code: .authorizationRestricted, message: "Speech transcription is restricted on this Mac.", provenance: context)
        }
        switch readiness(for: input) {
        case .ready:
            return
        case .unavailable(let reason):
            throw TranscriptionFailure(code: .unavailable, message: reason, provenance: context)
        case .offline(let reason):
            throw TranscriptionFailure(code: .offline, message: reason, provenance: context)
        }
    }

    private func liveTranscript(from result: SFSpeechRecognitionResult) -> TranscriptionTranscript {
        let startedAt = liveStartedAt ?? now()
        return .init(
            text: result.bestTranscription.formattedString,
            isFinal: result.isFinal,
            provenance: provenance(
                source: liveSource ?? .liveMicrophone(sourceID: "unknown-live-source"),
                startedAt: startedAt,
                completedAt: result.isFinal ? now() : nil,
                audioDuration: Self.audioDuration(result.bestTranscription)
            ),
            segments: Self.segments(result.bestTranscription)
        )
    }

    private func storedTranscript(
        from result: SFSpeechRecognitionResult,
        source: TranscriptionSourceIdentity,
        startedAt: Date
    ) -> TranscriptionTranscript {
        .init(
            text: result.bestTranscription.formattedString,
            isFinal: true,
            provenance: provenance(
                source: source,
                startedAt: startedAt,
                completedAt: now(),
                audioDuration: Self.audioDuration(result.bestTranscription)
            ),
            segments: Self.segments(result.bestTranscription)
        )
    }

    private func liveFailure(code: TranscriptionFailureCode, message: String) -> TranscriptionFailure {
        let startedAt = liveStartedAt ?? now()
        return .init(
            code: code,
            message: message,
            provenance: provenance(
                source: liveSource ?? .liveMicrophone(sourceID: "unknown-live-source"),
                startedAt: startedAt,
                completedAt: now(),
                audioDuration: nil
            )
        )
    }

    private func completedStoredProvenance() -> TranscriptionProvenance? {
        guard let storedAudioProvenance else { return nil }
        return provenance(
            source: storedAudioProvenance.source,
            startedAt: storedAudioProvenance.timing.startedAt,
            completedAt: now(),
            audioDuration: storedAudioProvenance.timing.audioDuration
        )
    }

    private func provenance(
        source: TranscriptionSourceIdentity,
        startedAt: Date,
        completedAt: Date?,
        audioDuration: TimeInterval?
    ) -> TranscriptionProvenance {
        .init(
            provider: provider,
            source: source,
            locale: locale,
            timing: .init(startedAt: startedAt, completedAt: completedAt, audioDuration: audioDuration)
        )
    }

    private func finishLiveSession(cancelRecognitionTask: Bool) {
        if cancelRecognitionTask { recognitionTask?.cancel() }
        recognitionTask = nil
        liveRequest?.endAudio()
        liveRequest = nil
        stopAudioInput()
        liveEventHandler = nil
        liveSource = nil
        liveStartedAt = nil
    }

    private func completeStoredAudio(_ result: TranscriptionResult, cancelRecognitionTask: Bool = true) {
        if cancelRecognitionTask { recognitionTask?.cancel() }
        recognitionTask = nil
        storedAudioProvenance = nil
        let continuation = storedAudioContinuation
        storedAudioContinuation = nil
        continuation?.resume(returning: result)
    }

    private func stopAudioInput() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private static func audioDuration(_ transcription: SFTranscription) -> TimeInterval? {
        transcription.segments.map { $0.timestamp + $0.duration }.max()
    }

    private static func segments(_ transcription: SFTranscription) -> [TranscriptionSegment] {
        transcription.segments.map {
            .init(text: $0.substring, timestamp: $0.timestamp, duration: $0.duration)
        }
    }

    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, Double((decibels + 55) / 55)))
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> TranscriptionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }

}
