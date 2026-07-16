import Dispatch
import Foundation
import Speech
import Synchronization
import Testing
@testable import Cider

@Suite("Apple Speech Transcription Service Tests")
@MainActor
struct AppleSpeechTranscriptionServiceTests {
    @Test("speech authorization completion crosses from a background queue exactly once")
    func speechAuthorizationCompletionHopsToMainActorExactlyOnce() async {
        let callbackWasMainThread = Mutex<Bool?>(nil)
        let status = Mutex(SFSpeechRecognizerAuthorizationStatus.notDetermined)
        let service = AppleSpeechTranscriptionService(
            locale: Locale(identifier: "en_US"),
            speechAuthorization: AppleSpeechAuthorizationClient(
                currentStatus: {
                    status.withLock { $0 }
                },
                requestAuthorization: { completion in
                    DispatchQueue.global().async {
                        callbackWasMainThread.withLock { $0 = Thread.isMainThread }
                        status.withLock { $0 = .denied }
                        completion(.denied)
                        completion(.authorized)
                    }
                }
            )
        )

        let authorization = await service.requestAuthorization(for: .storedAudioFile)

        MainActor.preconditionIsolated()
        #expect(authorization == .denied)
        #expect(callbackWasMainThread.withLock { $0 } == false)
    }

    @Test("cancellation completes before a late speech authorization callback")
    func cancellationCompletesBeforeLateSpeechAuthorizationCallback() async throws {
        let storedCompletion = Mutex<AppleSpeechAuthorizationClient.Completion?>(nil)
        let service = AppleSpeechTranscriptionService(
            locale: Locale(identifier: "en_US"),
            speechAuthorization: AppleSpeechAuthorizationClient(
                currentStatus: { .notDetermined },
                requestAuthorization: { completion in
                    storedCompletion.withLock { $0 = completion }
                }
            )
        )
        let request = Task { @MainActor in
            await service.requestAuthorization(for: .storedAudioFile)
        }

        for _ in 0..<1_000 {
            if storedCompletion.withLock({ $0 != nil }) { break }
            await Task.yield()
        }
        let lateCompletion = try #require(storedCompletion.withLock { $0 })

        request.cancel()
        #expect(await request.value == .notDetermined)

        await withCheckedContinuation { callbackReturned in
            DispatchQueue.global().async {
                lateCompletion(.authorized)
                callbackReturned.resume()
            }
        }
        await Task.yield()
        MainActor.preconditionIsolated()
    }
}
