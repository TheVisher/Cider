import Foundation

struct LocalFasterWhisperConfiguration: Equatable, Sendable {
    let executableURL: URL
    let modelDirectoryURL: URL
    let modelIdentity: String
    let language: String?
    let timeout: TimeInterval
    let maximumOutputBytes: Int

    init(
        executableURL: URL,
        modelDirectoryURL: URL,
        modelIdentity: String,
        language: String?,
        timeout: TimeInterval = 120,
        maximumOutputBytes: Int = 2_000_000
    ) {
        self.executableURL = executableURL
        self.modelDirectoryURL = modelDirectoryURL
        self.modelIdentity = String(modelIdentity.prefix(160))
        let normalizedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = normalizedLanguage.flatMap { $0.isEmpty ? nil : String($0.prefix(32)) }
        self.timeout = max(1, min(timeout, 600))
        self.maximumOutputBytes = max(1_024, min(maximumOutputBytes, 8_000_000))
    }

    func readiness(fileManager: FileManager = .default) -> TranscriptionReadiness {
        guard executableURL.isFileURL,
              fileManager.isExecutableFile(atPath: executableURL.path)
        else {
            return .unavailable(reason: "The configured local faster-whisper executable is unavailable.")
        }
        var isDirectory: ObjCBool = false
        guard modelDirectoryURL.isFileURL,
              fileManager.fileExists(atPath: modelDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .unavailable(reason: "The configured local faster-whisper model cache is unavailable.")
        }
        for filename in ["config.json", "model.bin", "tokenizer.json", "vocabulary.txt"] {
            let file = modelDirectoryURL.appendingPathComponent(filename)
            guard fileManager.isReadableFile(atPath: file.path) else {
                return .unavailable(reason: "The configured local faster-whisper model cache is incomplete.")
            }
        }
        return .ready
    }
}

/// Stored-file adapter for the existing local faster-whisper runtime. It is deliberately
/// not a live microphone adapter: faster-whisper's batch file API cannot truthfully provide
/// Chat's current partial-result contract.
@MainActor
final class LocalFasterWhisperTranscriptionService: CiderTranscriptionServicing {
    let provider: TranscriptionProviderMetadata

    private let configuration: LocalFasterWhisperConfiguration
    private let processRunner: any LocalTranscriptionProcessRunning
    private let prerequisiteReadiness: @MainActor () -> TranscriptionReadiness
    private let now: @MainActor () -> Date
    private var isTranscribingStoredAudio = false

    init(
        configuration: LocalFasterWhisperConfiguration,
        processRunner: any LocalTranscriptionProcessRunning = BoundedLocalTranscriptionProcessRunner(),
        prerequisiteReadiness: (@MainActor () -> TranscriptionReadiness)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.processRunner = processRunner
        self.prerequisiteReadiness = prerequisiteReadiness ?? { configuration.readiness() }
        self.now = now
        provider = .init(
            id: "local-faster-whisper",
            adapterVersion: "1",
            modelIdentity: configuration.modelIdentity,
            execution: .localProcess,
            supportedInputs: [.storedAudioFile],
            supportsLivePartialResults: false,
            supportsSegmentTimestamps: true,
            allowsNetworkFallback: false
        )
    }

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization {
        .authorized
    }

    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness {
        guard provider.supportedInputs.contains(input) else {
            return .unavailable(reason: "Local faster-whisper supports stored audio only; live partial transcription is unavailable.")
        }
        return prerequisiteReadiness()
    }

    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization {
        .authorized
    }

    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws {
        throw TranscriptionFailure(
            code: .unsupportedInput,
            message: "Local faster-whisper does not support live partial transcription.",
            provenance: provenance(source: request.source, startedAt: now(), completedAt: now(), duration: nil, locale: configuration.language)
        )
    }

    func stopLive() {}
    func cancelLive() {}

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        let startedAt = now()
        let initialProvenance = provenance(
            source: request.source,
            startedAt: startedAt,
            completedAt: nil,
            duration: nil,
            locale: configuration.language
        )
        guard request.source.kind == .storedAudioFile,
              request.source.retention == .preserveOriginal,
              !request.source.sourceID.isEmpty,
              request.fileURL.isFileURL
        else {
            return failure(
                .invalidSource,
                "Stored-audio transcription requires a file URL and stable original-source identity.",
                provenance: initialProvenance
            )
        }
        guard readiness(for: .storedAudioFile) == .ready else {
            return failure(.unavailable, "Local faster-whisper prerequisites are unavailable.", provenance: initialProvenance)
        }
        guard !isTranscribingStoredAudio else {
            return failure(.busy, "The transcription provider is already processing audio.", provenance: initialProvenance)
        }
        switch validateSourceFile(request.fileURL) {
        case .success:
            break
        case .failure(let sourceFailure):
            return failure(sourceFailure, sourceFailureMessage(sourceFailure), provenance: initialProvenance)
        }

        isTranscribingStoredAudio = true
        defer { isTranscribingStoredAudio = false }
        do {
            let output = try await processRunner.run(processRequest(for: request.fileURL))
            guard output.terminationStatus == 0 else {
                return failure(
                    .recognitionFailed,
                    "Local faster-whisper could not transcribe the original audio file.",
                    provenance: completed(initialProvenance)
                )
            }
            let response = try JSONDecoder().decode(FasterWhisperResponse.self, from: output.standardOutput)
            guard !TranscriptionTranscript.normalize(response.text).isEmpty,
                  response.duration.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  response.segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start })
            else {
                return failure(
                    .recognitionFailed,
                    "Local faster-whisper returned an invalid transcription result.",
                    provenance: completed(initialProvenance)
                )
            }
            let segments = response.segments.map {
                TranscriptionSegment(text: $0.text, timestamp: $0.start, duration: $0.end - $0.start)
            }
            let finishedAt = now()
            return .success(.init(
                text: response.text,
                isFinal: true,
                provenance: provenance(
                    source: request.source,
                    startedAt: startedAt,
                    completedAt: finishedAt,
                    duration: response.duration ?? segments.map { $0.timestamp + $0.duration }.max(),
                    locale: response.language ?? configuration.language
                ),
                segments: segments
            ))
        } catch let processError as LocalTranscriptionProcessError {
            let completedProvenance = completed(initialProvenance)
            switch processError {
            case .cancelled:
                return failure(.cancelled, "Stored-audio transcription was cancelled.", provenance: completedProvenance)
            case .timedOut:
                return failure(.timedOut, "Local faster-whisper exceeded the transcription time limit.", provenance: completedProvenance)
            case .launchFailed:
                return failure(.unavailable, "Local faster-whisper could not be started.", provenance: completedProvenance)
            case .busy:
                return failure(.busy, "The transcription provider is already processing audio.", provenance: completedProvenance)
            case .outputLimitExceeded:
                return failure(.recognitionFailed, "Local faster-whisper exceeded the bounded result size.", provenance: completedProvenance)
            }
        } catch {
            return failure(
                .recognitionFailed,
                "Local faster-whisper returned an unreadable transcription result.",
                provenance: completed(initialProvenance)
            )
        }
    }

    func cancelStoredAudio() {
        guard isTranscribingStoredAudio else { return }
        processRunner.cancel()
    }

    private func validateSourceFile(_ url: URL) -> Result<Void, TranscriptionFailureCode> {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                return .failure(.invalidSource)
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .failure(.sourceNotFound)
        } catch {
            return .failure(.sourceUnreadable)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure(.sourceUnreadable)
        }
        return .success(())
    }

    private func sourceFailureMessage(_ code: TranscriptionFailureCode) -> String {
        switch code {
        case .sourceNotFound:
            "The original audio source file was not found."
        case .sourceUnreadable:
            "The original audio source file is not readable."
        default:
            "Stored-audio transcription requires a regular, non-symbolic-link source file."
        }
    }

    private func processRequest(for audioURL: URL) -> LocalTranscriptionProcessRequest {
        var arguments = [
            "-I",
            "-c",
            Self.pythonAdapterProgram,
            "--model", configuration.modelDirectoryURL.path,
            "--audio", audioURL.path,
        ]
        if let language = configuration.language {
            arguments.append(contentsOf: ["--language", language])
        }
        return .init(
            executableURL: configuration.executableURL,
            arguments: arguments,
            environment: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin",
                "TMPDIR": FileManager.default.temporaryDirectory.path,
                "PYTHONNOUSERSITE": "1",
                "HF_HUB_OFFLINE": "1",
                "TRANSFORMERS_OFFLINE": "1",
                "HF_HUB_DISABLE_TELEMETRY": "1",
            ],
            timeout: configuration.timeout,
            maximumOutputBytes: configuration.maximumOutputBytes
        )
    }

    private func completed(_ provenance: TranscriptionProvenance) -> TranscriptionProvenance {
        self.provenance(
            source: provenance.source,
            startedAt: provenance.timing.startedAt,
            completedAt: now(),
            duration: provenance.timing.audioDuration,
            locale: provenance.locale.identifier
        )
    }

    private func provenance(
        source: TranscriptionSourceIdentity,
        startedAt: Date,
        completedAt: Date?,
        duration: TimeInterval?,
        locale: String?
    ) -> TranscriptionProvenance {
        .init(
            provider: provider,
            source: source,
            locale: .init(identifier: locale ?? "auto"),
            timing: .init(startedAt: startedAt, completedAt: completedAt, audioDuration: duration)
        )
    }

    private func failure(
        _ code: TranscriptionFailureCode,
        _ message: String,
        provenance: TranscriptionProvenance
    ) -> TranscriptionResult {
        .failure(.init(code: code, message: message, provenance: provenance))
    }

    private struct FasterWhisperResponse: Decodable {
        let text: String
        let language: String?
        let duration: TimeInterval?
        let segments: [FasterWhisperSegment]
    }

    private struct FasterWhisperSegment: Decodable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    private static let pythonAdapterProgram = #"""
import argparse
import json

from faster_whisper import WhisperModel

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--model", required=True)
parser.add_argument("--audio", required=True)
parser.add_argument("--language")
args = parser.parse_args()

model = WhisperModel(args.model, device="cpu", compute_type="int8")
segments, info = model.transcribe(
    args.audio,
    language=args.language,
    beam_size=5,
    vad_filter=False,
    word_timestamps=False,
)
items = []
text = []
for segment in segments:
    items.append({"text": segment.text, "start": segment.start, "end": segment.end})
    text.append(segment.text)
json.dump(
    {
        "text": "".join(text),
        "language": info.language,
        "duration": info.duration,
        "segments": items,
    },
    fp=__import__("sys").stdout,
    ensure_ascii=False,
    separators=(",", ":"),
)
"""#
}
