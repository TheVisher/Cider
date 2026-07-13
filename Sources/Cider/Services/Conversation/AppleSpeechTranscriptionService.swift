import AVFoundation
import Foundation
import Speech

enum AppleSpeechTranscriptionError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        }
    }
}

/// Native Apple implementation of Cider's provider-neutral transcription edge.
/// It is local/on-device only and never persists audio or falls back to a network provider.
@MainActor
final class AppleSpeechTranscriptionService: ConversationTranscriptionServicing {
    let providerID = "apple-speech-on-device"

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onEvent: (@MainActor @Sendable (ConversationTranscriptionEvent) -> Void)?
    private var tapInstalled = false

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    var authorization: ConversationTranscriptionAuthorization {
        let speech = Self.map(SFSpeechRecognizer.authorizationStatus())
        let microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        if speech == .denied || microphone == .denied { return .denied }
        if speech == .restricted || microphone == .restricted { return .restricted }
        if speech == .notDetermined || microphone == .notDetermined { return .notDetermined }
        return .authorized
    }

    var readiness: ConversationTranscriptionReadiness {
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

    func requestAuthorization() async -> ConversationTranscriptionAuthorization {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        guard Self.map(SFSpeechRecognizer.authorizationStatus()) == .authorized else {
            return authorization
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        return authorization
    }

    func start(
        onEvent: @escaping @MainActor @Sendable (ConversationTranscriptionEvent) -> Void
    ) throws {
        guard authorization == .authorized else {
            throw AppleSpeechTranscriptionError.unavailable("Microphone transcription is not authorized.")
        }
        guard readiness == .ready, let recognizer else {
            throw AppleSpeechTranscriptionError.unavailable("On-device transcription is unavailable.")
        }
        cancelSession(clearHandler: true)
        self.onEvent = onEvent

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cancelSession(clearHandler: true)
            throw AppleSpeechTranscriptionError.unavailable("The microphone is unavailable.")
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.normalizedLevel(buffer)
            Task { @MainActor [weak self] in
                self?.onEvent?(.level(level))
            }
        }
        tapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text {
                    self.onEvent?(isFinal ? .final(text) : .partial(text))
                }
                if isFinal {
                    self.cancelSession(clearHandler: true, cancelRecognitionTask: false)
                } else if failed {
                    self.onEvent?(.failure("Transcription stopped before Cider received a final result."))
                    self.cancelSession(clearHandler: true)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cancelSession(clearHandler: true)
            throw AppleSpeechTranscriptionError.unavailable("Cider could not start the microphone.")
        }
    }

    func stop() {
        guard request != nil else { return }
        request?.endAudio()
        stopAudioInput()
    }

    func cancel() {
        cancelSession(clearHandler: true)
    }

    private func cancelSession(clearHandler: Bool, cancelRecognitionTask: Bool = true) {
        if cancelRecognitionTask { recognitionTask?.cancel() }
        recognitionTask = nil
        request?.endAudio()
        request = nil
        stopAudioInput()
        if clearHandler { onEvent = nil }
    }

    private func stopAudioInput() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
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

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> ConversationTranscriptionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> ConversationTranscriptionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}
