import AVFoundation
import Foundation

/// Surface-neutral microphone permission boundary. Speech providers and recording
/// surfaces share this adapter so permission prompts remain explicit and testable.
@MainActor
protocol CiderMicrophoneAuthorizationServicing: AnyObject {
    func authorization() -> TranscriptionAuthorization
    func requestAuthorization() async -> TranscriptionAuthorization
}

@MainActor
final class SystemCiderMicrophoneAuthorizationService: CiderMicrophoneAuthorizationServicing {
    func authorization() -> TranscriptionAuthorization {
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestAuthorization() async -> TranscriptionAuthorization {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        return authorization()
    }

    private static func map(_ status: AVAuthorizationStatus) -> TranscriptionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}
