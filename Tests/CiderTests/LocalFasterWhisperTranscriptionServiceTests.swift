import Foundation
import Testing
@testable import Cider

@Suite("Local Faster Whisper Transcription Service Tests")
@MainActor
struct LocalFasterWhisperTranscriptionServiceTests {
    @Test("provider truth is stored-file only and the shared default remains universal Apple")
    func capabilityAndDefaultDecisionAreExplicit() throws {
        let runner = FakeLocalTranscriptionProcessRunner()
        let service = LocalFasterWhisperTranscriptionService(
            configuration: configuration(),
            processRunner: runner,
            prerequisiteReadiness: { .ready }
        )

        #expect(service.provider.id == "local-faster-whisper")
        #expect(service.provider.modelIdentity == "Systran/faster-whisper-base")
        #expect(service.provider.execution == .localProcess)
        #expect(service.provider.supportedInputs == [.storedAudioFile])
        #expect(service.provider.supportsLivePartialResults == false)
        #expect(service.provider.supportsSegmentTimestamps == true)
        #expect(service.provider.allowsNetworkFallback == false)
        #expect(service.readiness(for: .storedAudioFile) == .ready)

        guard case .unavailable = service.readiness(for: .liveMicrophone) else {
            Issue.record("faster-whisper must state that live microphone input is unsupported")
            return
        }
        do {
            try service.startLive(.init(sourceID: "chat-live")) { _ in }
            Issue.record("stored-file-only faster-whisper unexpectedly accepted live input")
        } catch let failure as TranscriptionFailure {
            #expect(failure.code == .unsupportedInput)
        }

        let decision = CiderTranscriptionProviderSelection.sharedDefaultDecision
        #expect(decision.defaultProviderID == "apple-speech-on-device")
        #expect(decision.evaluatedProviderIDs == ["apple-speech-on-device", "local-faster-whisper"])
        #expect(decision.changedDefault == false)
        #expect(decision.hasSingleUniversalAlternative == false)
        #expect(decision.reason == .localFasterWhisperLacksLivePartialInput)
        #expect(CiderTranscriptionProviderSelection.makeDefault().provider.id == decision.defaultProviderID)
    }

    @Test("stored result preserves source identity normalization segments and read-only input")
    func storedResultUsesSharedContractWithoutMutatingSource() async throws {
        let fixture = try AudioFixture()
        defer { fixture.cleanup() }
        let originalData = try Data(contentsOf: fixture.audioURL)
        let runner = FakeLocalTranscriptionProcessRunner()
        runner.nextOutput = .init(
            standardOutput: Data(#"{"text":"  Alpha\u0007 beta  ","language":"en","duration":2.5,"segments":[{"text":" Alpha ","start":0.0,"end":1.0},{"text":" beta ","start":1.1,"end":2.5}]}"#.utf8),
            standardError: Data(),
            terminationStatus: 0
        )
        let service = LocalFasterWhisperTranscriptionService(
            configuration: configuration(),
            processRunner: runner,
            prerequisiteReadiness: { .ready },
            now: SequenceDateProvider().next
        )

        let result = await service.transcribeStoredAudio(.init(
            fileURL: fixture.audioURL,
            sourceID: "journal-audio:fixture",
            displayName: "Fixture.aiff"
        ))
        let transcript = try #require(result.success)

        #expect(transcript.text == "Alpha  beta")
        #expect(transcript.isFinal)
        #expect(transcript.segments == [
            .init(text: "Alpha", timestamp: 0, duration: 1),
            .init(text: "beta", timestamp: 1.1, duration: 1.4),
        ])
        #expect(transcript.provenance.provider == service.provider)
        #expect(transcript.provenance.source.sourceID == "journal-audio:fixture")
        #expect(transcript.provenance.source.retention == .preserveOriginal)
        #expect(transcript.provenance.locale.identifier == "en")
        #expect(transcript.provenance.timing.audioDuration == 2.5)
        #expect(transcript.provenance.usedNetworkFallback == false)
        #expect(try Data(contentsOf: fixture.audioURL) == originalData)
        #expect(runner.requests.count == 1)

        let processRequest = try #require(runner.requests.first)
        #expect(processRequest.executableURL == configuration().executableURL)
        #expect(processRequest.arguments.contains(fixture.audioURL.path))
        #expect(processRequest.arguments.contains(configuration().modelDirectoryURL.path))
        #expect(processRequest.environment["HF_HUB_OFFLINE"] == "1")
        #expect(processRequest.environment["TRANSFORMERS_OFFLINE"] == "1")
        #expect(processRequest.environment.keys.allSatisfy { !$0.localizedCaseInsensitiveContains("token") })
    }

    @Test("missing malformed and symbolic-link sources fail before a process starts")
    func invalidSourcesFailClosed() async throws {
        let runner = FakeLocalTranscriptionProcessRunner()
        let service = LocalFasterWhisperTranscriptionService(
            configuration: configuration(),
            processRunner: runner,
            prerequisiteReadiness: { .ready }
        )
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-audio-\(UUID().uuidString).aiff")
        let missingResult = await service.transcribeStoredAudio(.init(
            fileURL: missing,
            sourceID: "missing-source"
        ))
        #expect(missingResult.failure?.code == .sourceNotFound)

        let fixture = try AudioFixture()
        defer { fixture.cleanup() }
        let link = fixture.root.appendingPathComponent("linked.aiff")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.audioURL)
        let linkedResult = await service.transcribeStoredAudio(.init(
            fileURL: link,
            sourceID: "linked-source"
        ))
        #expect(linkedResult.failure?.code == .invalidSource)

        runner.nextOutput = .init(
            standardOutput: Data("not-json".utf8),
            standardError: Data(),
            terminationStatus: 0
        )
        let malformedResult = await service.transcribeStoredAudio(.init(
            fileURL: fixture.audioURL,
            sourceID: "malformed-output"
        ))
        #expect(malformedResult.failure?.code == .recognitionFailed)
        #expect(runner.requests.count == 1)
    }

    @Test("timeout output overflow process failure and cancellation use shared typed failures")
    func processFailuresAreTypedAndCancellable() async throws {
        let fixture = try AudioFixture()
        defer { fixture.cleanup() }
        let runner = FakeLocalTranscriptionProcessRunner()
        let service = LocalFasterWhisperTranscriptionService(
            configuration: configuration(),
            processRunner: runner,
            prerequisiteReadiness: { .ready }
        )

        for (error, expected) in [
            (LocalTranscriptionProcessError.timedOut, TranscriptionFailureCode.timedOut),
            (LocalTranscriptionProcessError.outputLimitExceeded, .recognitionFailed),
            (LocalTranscriptionProcessError.launchFailed, .unavailable),
        ] {
            runner.nextError = error
            let result = await service.transcribeStoredAudio(.init(
                fileURL: fixture.audioURL,
                sourceID: "failure-\(expected.rawValue)"
            ))
            #expect(result.failure?.code == expected)
        }

        runner.blocksUntilCancelled = true
        let task = Task { @MainActor in
            await service.transcribeStoredAudio(.init(
                fileURL: fixture.audioURL,
                sourceID: "cancelled-source"
            ))
        }
        await Task.yield()
        service.cancelStoredAudio()
        let cancelled = await task.value
        #expect(cancelled.failure?.code == .cancelled)
        #expect(runner.cancelCount == 1)
    }

    private func configuration() -> LocalFasterWhisperConfiguration {
        .init(
            executableURL: URL(fileURLWithPath: "/local/hermes/venv/bin/python"),
            modelDirectoryURL: URL(fileURLWithPath: "/local/models/faster-whisper-base", isDirectory: true),
            modelIdentity: "Systran/faster-whisper-base",
            language: nil,
            timeout: 30,
            maximumOutputBytes: 32_768
        )
    }
}

@Suite("Bounded Local Transcription Process Tests")
@MainActor
struct BoundedLocalTranscriptionProcessTests {
    @Test("arguments are executed directly without shell interpolation")
    func argumentsAreNotShellInterpreted() async throws {
        let sentinel = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-transcription-injection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sentinel) }
        let literal = "$(touch \(sentinel.path))"
        let runner = BoundedLocalTranscriptionProcessRunner()

        let output = try await runner.run(.init(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", literal],
            environment: ["PATH": "/usr/bin:/bin"],
            timeout: 2,
            maximumOutputBytes: 1_024
        ))

        #expect(String(decoding: output.standardOutput, as: UTF8.self) == literal)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("wall timeout and output limits terminate the subprocess")
    func timeoutAndOutputAreBounded() async throws {
        let timeoutRunner = BoundedLocalTranscriptionProcessRunner()
        await #expect(throws: LocalTranscriptionProcessError.timedOut) {
            try await timeoutRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                environment: ["PATH": "/usr/bin:/bin"],
                timeout: 0.05,
                maximumOutputBytes: 1_024
            ))
        }

        let outputRunner = BoundedLocalTranscriptionProcessRunner()
        await #expect(throws: LocalTranscriptionProcessError.outputLimitExceeded) {
            try await outputRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                arguments: ["bounded"],
                environment: ["PATH": "/usr/bin:/bin"],
                timeout: 2,
                maximumOutputBytes: 256
            ))
        }
    }
}

@MainActor
private final class FakeLocalTranscriptionProcessRunner: LocalTranscriptionProcessRunning {
    var nextOutput = LocalTranscriptionProcessOutput(
        standardOutput: Data(),
        standardError: Data(),
        terminationStatus: 0
    )
    var nextError: LocalTranscriptionProcessError?
    var blocksUntilCancelled = false
    private(set) var requests: [LocalTranscriptionProcessRequest] = []
    private(set) var cancelCount = 0
    private var continuation: CheckedContinuation<LocalTranscriptionProcessOutput, Error>?

    func run(_ request: LocalTranscriptionProcessRequest) async throws -> LocalTranscriptionProcessOutput {
        requests.append(request)
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        if blocksUntilCancelled {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return nextOutput
    }

    func cancel() {
        cancelCount += 1
        continuation?.resume(throwing: LocalTranscriptionProcessError.cancelled)
        continuation = nil
    }
}

private final class SequenceDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [
        Date(timeIntervalSince1970: 10),
        Date(timeIntervalSince1970: 12),
    ]

    func next() -> Date {
        lock.withLock { values.isEmpty ? Date(timeIntervalSince1970: 12) : values.removeFirst() }
    }
}

private struct AudioFixture {
    let root: URL
    let audioURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-local-stt-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        audioURL = root.appendingPathComponent("fixture.aiff")
        try Data("disposable fake audio bytes".utf8).write(to: audioURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension TranscriptionResult {
    var success: TranscriptionTranscript? {
        guard case .success(let transcript) = self else { return nil }
        return transcript
    }

    var failure: TranscriptionFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}
