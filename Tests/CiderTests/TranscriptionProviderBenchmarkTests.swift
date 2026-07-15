import Foundation
import Testing
@testable import Cider

@Suite("Transcription Provider Benchmark Tests")
@MainActor
struct TranscriptionProviderBenchmarkTests {
    @Test("benchmark facts are deterministic machine-readable and content-free")
    func deterministicBenchmarkFacts() async throws {
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark-fixture.aiff")
        let service = BenchmarkFixtureTranscriptionService()
        let dates = BenchmarkDateProvider(values: [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 1.125),
        ])

        let comparison = await TranscriptionBenchmarkHarness.compare(
            fixtureID: "deterministic-v1",
            knownScript: "alpha beta gamma",
            audioURL: fixtureURL,
            providers: [service],
            timeout: 1,
            now: dates.next
        )
        let facts = try #require(comparison.providers.first)

        #expect(comparison.knownScriptWordCount == 3)
        #expect(comparison.selectedDefaultProviderID == "apple-speech-on-device")
        #expect(comparison.defaultChanged == false)
        #expect(facts.outcome == "success")
        #expect(facts.wallLatencyMilliseconds == 125)
        #expect(facts.hypothesisWordCount == 2)
        #expect(facts.wordEditDistance == 1)
        #expect(facts.wordErrorRate == 1.0 / 3.0)
        #expect(facts.normalizedExactMatch == false)
        #expect(facts.segmentCount == 2)
        #expect(facts.segmentTimestampsObserved == true)
        #expect(facts.sourceIdentityPreserved == true)
        #expect(facts.originalRetentionPreserved == true)
        #expect(facts.liveInputFailureCode == TranscriptionFailureCode.unsupportedInput.rawValue)
        #expect(facts.missingFileFailureCode == TranscriptionFailureCode.sourceNotFound.rawValue)

        let json = try JSONEncoder().encode(comparison)
        let encoded = String(decoding: json, as: UTF8.self)
        #expect(!encoded.contains("alpha"))
        #expect(!encoded.contains("gamma"))
        #expect(encoded.contains("wordErrorRate"))
        #expect(encoded.contains("supportsLivePartialResults"))
        #expect(encoded.contains("liveInputFailureCode"))
        #expect(encoded.contains("missingFileFailureCode"))
    }

    @Test("generated disposable audio compares configured local and Apple adapters without prompting")
    func generatedAudioEmpiricalComparison() async throws {
        guard ProcessInfo.processInfo.environment["CIDER_RUN_TRANSCRIPTION_BENCHMARK"] == "1" else {
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let pythonPath = try #require(environment["CIDER_FASTER_WHISPER_PYTHON"])
        let modelPath = try #require(environment["CIDER_FASTER_WHISPER_MODEL_PATH"])
        let modelIdentity = environment["CIDER_FASTER_WHISPER_MODEL_ID"] ?? "Systran/faster-whisper-base"
        let script = "Cider voice benchmark checks local privacy timestamps and shared provider selection."
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid767-benchmark-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let generator = BoundedLocalTranscriptionProcessRunner()
        let generation = try await generator.run(.init(
            executableURL: URL(fileURLWithPath: "/usr/bin/say"),
            arguments: ["-v", "Samantha", "-r", "165", "-o", fixtureURL.path, script],
            environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()],
            timeout: 15,
            maximumOutputBytes: 4_096
        ))
        #expect(generation.terminationStatus == 0)
        #expect(FileManager.default.isReadableFile(atPath: fixtureURL.path))

        let local = LocalFasterWhisperTranscriptionService(configuration: .init(
            executableURL: URL(fileURLWithPath: pythonPath),
            modelDirectoryURL: URL(fileURLWithPath: modelPath, isDirectory: true),
            modelIdentity: modelIdentity,
            language: nil,
            timeout: 120,
            maximumOutputBytes: 1_000_000
        ))
        #expect(local.readiness(for: .storedAudioFile) == .ready)
        let apple = AppleSpeechTranscriptionService(locale: Locale(identifier: "en_US"))
        let comparison = await TranscriptionBenchmarkHarness.compare(
            fixtureID: "cid767-say-samantha-165-v1",
            knownScript: script,
            audioURL: fixtureURL,
            providers: [apple, local],
            timeout: 120
        )
        let localFacts = try #require(comparison.providers.first { $0.providerID == "local-faster-whisper" })
        #expect(localFacts.outcome == "success")
        #expect(localFacts.supportsLivePartialResults == false)
        #expect(localFacts.supportsStoredAudioFiles == true)
        #expect(localFacts.requiresOfflinePrivateExecution == true)
        #expect(comparison.selectedDefaultProviderID == "apple-speech-on-device")
        #expect(comparison.defaultChanged == false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        print("CID767_BENCHMARK_JSON=\(String(decoding: try encoder.encode(comparison), as: UTF8.self))")
    }
}

@MainActor
private final class BenchmarkFixtureTranscriptionService: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(
        id: "benchmark-fixture-provider",
        adapterVersion: "test-1",
        modelIdentity: "fixture-model",
        execution: .localProcess,
        supportedInputs: [.storedAudioFile],
        supportsLivePartialResults: false,
        supportsSegmentTimestamps: true,
        allowsNetworkFallback: false
    )

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }
    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws {
        throw TranscriptionFailure(code: .unsupportedInput, message: "Stored only.")
    }
    func stopLive() {}
    func cancelLive() {}
    func cancelStoredAudio() {}

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        if request.fileURL.lastPathComponent.hasPrefix("cider-benchmark-missing-") {
            return .failure(.init(code: .sourceNotFound, message: "Missing benchmark fixture."))
        }
        return .success(.init(
            text: "alpha gamma",
            isFinal: true,
            provenance: .init(
                provider: provider,
                source: request.source,
                locale: .init(identifier: "en"),
                timing: .init(
                    startedAt: Date(timeIntervalSince1970: 1),
                    completedAt: Date(timeIntervalSince1970: 1.1),
                    audioDuration: 1
                )
            ),
            segments: [
                .init(text: "alpha", timestamp: 0, duration: 0.4),
                .init(text: "gamma", timestamp: 0.5, duration: 0.5),
            ]
        ))
    }
}

private final class BenchmarkDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    func next() -> Date {
        lock.withLock { values.isEmpty ? Date(timeIntervalSince1970: 1.125) : values.removeFirst() }
    }
}
