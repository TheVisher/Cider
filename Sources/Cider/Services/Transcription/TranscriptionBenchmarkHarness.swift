import Foundation

struct TranscriptionBenchmarkFacts: Codable, Equatable, Sendable {
    let providerID: String
    let adapterVersion: String
    let modelIdentity: String?
    let execution: String
    let supportedInputs: [String]
    let supportsLivePartialResults: Bool
    let supportsStoredAudioFiles: Bool
    let supportsSegmentTimestamps: Bool
    let allowsNetworkFallback: Bool
    /// Provider contract requirement, not proof that a blocked benchmark actually executed.
    let requiresOfflinePrivateExecution: Bool
    let outcome: String
    let failureCode: String?
    let wallLatencyMilliseconds: Int
    let referenceWordCount: Int
    let hypothesisWordCount: Int?
    let wordEditDistance: Int?
    let wordErrorRate: Double?
    let normalizedExactMatch: Bool?
    let segmentCount: Int?
    let segmentTimestampsObserved: Bool?
    let sourceIdentityPreserved: Bool?
    let originalRetentionPreserved: Bool?
    let liveInputFailureCode: String?
    let missingFileFailureCode: String?
}

struct TranscriptionBenchmarkComparison: Codable, Equatable, Sendable {
    let fixtureID: String
    let knownScriptWordCount: Int
    let providers: [TranscriptionBenchmarkFacts]
    let selectedDefaultProviderID: String
    let defaultChanged: Bool
    let universalAlternativeAvailable: Bool
    let decisionReason: String
}

/// Deterministic, content-free benchmark projection. The reference and provider transcript
/// are used only in memory to calculate accuracy; neither appears in the report.
@MainActor
enum TranscriptionBenchmarkHarness {
    static func compare(
        fixtureID: String,
        knownScript: String,
        audioURL: URL,
        providers: [any CiderTranscriptionServicing],
        timeout: TimeInterval = 120,
        now: @escaping @MainActor () -> Date = Date.init
    ) async -> TranscriptionBenchmarkComparison {
        var facts: [TranscriptionBenchmarkFacts] = []
        for provider in providers {
            facts.append(await benchmark(
                provider: provider,
                knownScript: knownScript,
                audioURL: audioURL,
                fixtureID: fixtureID,
                timeout: timeout,
                now: now
            ))
        }
        let decision = CiderTranscriptionProviderSelection.sharedDefaultDecision
        return .init(
            fixtureID: String(fixtureID.prefix(80)),
            knownScriptWordCount: words(in: knownScript).count,
            providers: facts,
            selectedDefaultProviderID: decision.defaultProviderID,
            defaultChanged: decision.changedDefault,
            universalAlternativeAvailable: decision.hasSingleUniversalAlternative,
            decisionReason: decision.reason.rawValue
        )
    }

    static func benchmark(
        provider service: any CiderTranscriptionServicing,
        knownScript: String,
        audioURL: URL,
        fixtureID: String,
        timeout: TimeInterval = 120,
        now: @escaping @MainActor () -> Date = Date.init
    ) async -> TranscriptionBenchmarkFacts {
        let metadata = service.provider
        let referenceWords = words(in: knownScript)
        let sourceID = "benchmark:\(String(fixtureID.prefix(80))):\(metadata.id)"

        guard metadata.supportedInputs.contains(.storedAudioFile) else {
            return baseFacts(
                metadata: metadata,
                outcome: "unsupported",
                failureCode: TranscriptionFailureCode.unsupportedInput.rawValue,
                latency: 0,
                referenceWordCount: referenceWords.count
            )
        }
        let authorization = service.authorization(for: .storedAudioFile)
        guard authorization == .authorized else {
            return baseFacts(
                metadata: metadata,
                outcome: "blocked",
                failureCode: authorizationFailureCode(authorization).rawValue,
                latency: 0,
                referenceWordCount: referenceWords.count
            )
        }
        guard service.readiness(for: .storedAudioFile) == .ready else {
            return baseFacts(
                metadata: metadata,
                outcome: "blocked",
                failureCode: TranscriptionFailureCode.unavailable.rawValue,
                latency: 0,
                referenceWordCount: referenceWords.count
            )
        }

        let startedAt = now()
        let result = await transcribe(
            service: service,
            request: .init(fileURL: audioURL, sourceID: sourceID, displayName: audioURL.lastPathComponent),
            timeout: timeout
        )
        let latency = max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-benchmark-missing-\(UUID().uuidString).aiff")
        let missingResult = await service.transcribeStoredAudio(.init(
            fileURL: missingURL,
            sourceID: "\(sourceID):missing",
            displayName: "missing.aiff"
        ))
        let missingFailure = missingResult.failure?.code.rawValue

        switch result {
        case .failure(let failure):
            return baseFacts(
                metadata: metadata,
                outcome: "failure",
                failureCode: failure.code.rawValue,
                latency: latency,
                referenceWordCount: referenceWords.count,
                missingFileFailureCode: missingFailure
            )
        case .success(let transcript):
            let hypothesisWords = words(in: transcript.text)
            let distance = editDistance(referenceWords, hypothesisWords)
            let wordErrorRate = referenceWords.isEmpty
                ? (hypothesisWords.isEmpty ? 0 : 1)
                : Double(distance) / Double(referenceWords.count)
            return .init(
                providerID: metadata.id,
                adapterVersion: metadata.adapterVersion,
                modelIdentity: metadata.modelIdentity,
                execution: metadata.execution.rawValue,
                supportedInputs: metadata.supportedInputs.map(\.rawValue).sorted(),
                supportsLivePartialResults: metadata.supportsLivePartialResults,
                supportsStoredAudioFiles: metadata.supportedInputs.contains(.storedAudioFile),
                supportsSegmentTimestamps: metadata.supportsSegmentTimestamps,
                allowsNetworkFallback: metadata.allowsNetworkFallback,
                requiresOfflinePrivateExecution: metadata.execution != .network && !metadata.allowsNetworkFallback,
                outcome: "success",
                failureCode: nil,
                wallLatencyMilliseconds: latency,
                referenceWordCount: referenceWords.count,
                hypothesisWordCount: hypothesisWords.count,
                wordEditDistance: distance,
                wordErrorRate: wordErrorRate,
                normalizedExactMatch: referenceWords == hypothesisWords,
                segmentCount: transcript.segments.count,
                segmentTimestampsObserved: !transcript.segments.isEmpty && transcript.segments.allSatisfy {
                    $0.timestamp >= 0 && $0.duration >= 0
                },
                sourceIdentityPreserved: transcript.provenance.source.sourceID == sourceID,
                originalRetentionPreserved: transcript.provenance.source.retention == .preserveOriginal,
                liveInputFailureCode: metadata.supportedInputs.contains(.liveMicrophone)
                    ? nil
                    : TranscriptionFailureCode.unsupportedInput.rawValue,
                missingFileFailureCode: missingFailure
            )
        }
    }

    private static func transcribe(
        service: any CiderTranscriptionServicing,
        request: StoredAudioTranscriptionRequest,
        timeout: TimeInterval
    ) async -> TranscriptionResult {
        let task = Task { @MainActor in await service.transcribeStoredAudio(request) }
        let timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(max(1, timeout)))
            } catch {
                return
            }
            service.cancelStoredAudio()
        }
        let result = await task.value
        timeoutTask.cancel()
        return result
    }

    private static func baseFacts(
        metadata: TranscriptionProviderMetadata,
        outcome: String,
        failureCode: String,
        latency: Int,
        referenceWordCount: Int,
        missingFileFailureCode: String? = nil
    ) -> TranscriptionBenchmarkFacts {
        .init(
            providerID: metadata.id,
            adapterVersion: metadata.adapterVersion,
            modelIdentity: metadata.modelIdentity,
            execution: metadata.execution.rawValue,
            supportedInputs: metadata.supportedInputs.map(\.rawValue).sorted(),
            supportsLivePartialResults: metadata.supportsLivePartialResults,
            supportsStoredAudioFiles: metadata.supportedInputs.contains(.storedAudioFile),
            supportsSegmentTimestamps: metadata.supportsSegmentTimestamps,
            allowsNetworkFallback: metadata.allowsNetworkFallback,
            requiresOfflinePrivateExecution: metadata.execution != .network && !metadata.allowsNetworkFallback,
            outcome: outcome,
            failureCode: failureCode,
            wallLatencyMilliseconds: latency,
            referenceWordCount: referenceWordCount,
            hypothesisWordCount: nil,
            wordEditDistance: nil,
            wordErrorRate: nil,
            normalizedExactMatch: nil,
            segmentCount: nil,
            segmentTimestampsObserved: nil,
            sourceIdentityPreserved: nil,
            originalRetentionPreserved: nil,
            liveInputFailureCode: metadata.supportedInputs.contains(.liveMicrophone)
                ? nil
                : TranscriptionFailureCode.unsupportedInput.rawValue,
            missingFileFailureCode: missingFileFailureCode
        )
    }

    private static func authorizationFailureCode(_ authorization: TranscriptionAuthorization) -> TranscriptionFailureCode {
        switch authorization {
        case .notDetermined: .authorizationRequired
        case .denied: .authorizationDenied
        case .restricted: .authorizationRestricted
        case .authorized: .recognitionFailed
        }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
    }

    private static func editDistance(_ left: [String], _ right: [String]) -> Int {
        var previous = Array(0...right.count)
        for (leftIndex, leftWord) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightWord) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftWord == rightWord ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? 0
    }
}

private extension TranscriptionResult {
    var failure: TranscriptionFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}
