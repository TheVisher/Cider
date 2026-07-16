import AVFoundation
import Foundation

struct JournalVoiceRecordedAudio: Equatable, Sendable {
    let fileURL: URL
    let duration: TimeInterval
    let byteSize: Int64
}

enum JournalVoiceAudioRecorderError: Error, Equatable, Sendable {
    case alreadyRecording
    case unavailable
    case emptyRecording
}

@MainActor
protocol JournalVoiceAudioRecording: AnyObject {
    var elapsedTime: TimeInterval { get }
    var byteSize: Int64 { get }

    func start(
        at fileURL: URL,
        maximumDuration: TimeInterval,
        onAutomaticFinish: @escaping @MainActor @Sendable (Bool) -> Void
    ) throws
    func stop() throws -> JournalVoiceRecordedAudio
    func cancel()
}

/// Bounded native audio capture. It records the original once to a caller-owned
/// working URL and never performs transcription or canonical persistence.
@MainActor
final class SystemJournalVoiceAudioRecorder: NSObject, JournalVoiceAudioRecording, @preconcurrency AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var onAutomaticFinish: (@MainActor @Sendable (Bool) -> Void)?

    var elapsedTime: TimeInterval {
        max(0, recorder?.currentTime ?? 0)
    }

    var byteSize: Int64 {
        guard let recordingURL,
              let values = try? recordingURL.resourceValues(forKeys: [.fileSizeKey])
        else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    func start(
        at fileURL: URL,
        maximumDuration: TimeInterval,
        onAutomaticFinish: @escaping @MainActor @Sendable (Bool) -> Void
    ) throws {
        guard recorder == nil else { throw JournalVoiceAudioRecorderError.alreadyRecording }
        guard fileURL.isFileURL, maximumDuration > 0 else {
            throw JournalVoiceAudioRecorderError.unavailable
        }
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(
                url: fileURL,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            )
        } catch {
            throw JournalVoiceAudioRecorderError.unavailable
        }
        recorder.delegate = self
        recorder.isMeteringEnabled = false
        guard recorder.prepareToRecord(), recorder.record(forDuration: maximumDuration) else {
            recorder.delegate = nil
            throw JournalVoiceAudioRecorderError.unavailable
        }
        self.recorder = recorder
        recordingURL = fileURL
        self.onAutomaticFinish = onAutomaticFinish
    }

    func stop() throws -> JournalVoiceRecordedAudio {
        guard let recorder, let recordingURL else {
            throw JournalVoiceAudioRecorderError.unavailable
        }
        let duration = max(0, recorder.currentTime)
        if recorder.isRecording { recorder.stop() }
        let bytes = byteSize
        finishRecorder()
        guard duration > 0, bytes > 0 else {
            throw JournalVoiceAudioRecorderError.emptyRecording
        }
        return .init(fileURL: recordingURL, duration: duration, byteSize: bytes)
    }

    func cancel() {
        if recorder?.isRecording == true { recorder?.stop() }
        finishRecorder()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === self.recorder else { return }
        onAutomaticFinish?(flag)
    }

    private func finishRecorder() {
        recorder?.delegate = nil
        recorder = nil
        recordingURL = nil
        onAutomaticFinish = nil
    }
}

@MainActor
final class JournalVoiceTemporaryFileStore {
    private let fileManager: FileManager
    let root: URL

    init(
        root: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.root = (root ?? fileManager.temporaryDirectory
            .appendingPathComponent("cider-journal-voice-recording", isDirectory: true))
            .standardizedFileURL
    }

    func makeWorkingURL(recordingID: UUID) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw JournalVoiceAudioRecorderError.unavailable
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        return root.appendingPathComponent("voice-\(recordingID.uuidString.lowercased()).m4a")
    }

    func remove(_ url: URL?) {
        guard let url, contains(url) else { return }
        try? fileManager.removeItem(at: url)
        removeRootIfEmpty()
    }

    func contains(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.hasPrefix(rootPath)
    }

    private func removeRootIfEmpty() {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: root.path),
              contents.isEmpty else { return }
        try? fileManager.removeItem(at: root)
    }
}
