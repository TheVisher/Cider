import Darwin
import Foundation

struct LocalTranscriptionProcessRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval
    let maximumOutputBytes: Int
}

struct LocalTranscriptionProcessOutput: Equatable, Sendable {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
}

enum LocalTranscriptionProcessError: Error, Equatable, Sendable {
    case busy
    case launchFailed
    case timedOut
    case outputLimitExceeded
    case cancelled
}

@MainActor
protocol LocalTranscriptionProcessRunning: AnyObject {
    func run(_ request: LocalTranscriptionProcessRequest) async throws -> LocalTranscriptionProcessOutput
    func cancel()
}

/// Executes an argument-vector process directly. It never invokes a shell, inherits no
/// ambient credential environment, drains both pipes, and terminates work that exceeds
/// either the wall-clock or output bound.
@MainActor
final class BoundedLocalTranscriptionProcessRunner: LocalTranscriptionProcessRunning {
    private var activeProcess: Process?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false
    private var timeoutTriggered = false

    func run(_ request: LocalTranscriptionProcessRequest) async throws -> LocalTranscriptionProcessOutput {
        guard activeProcess == nil else { throw LocalTranscriptionProcessError.busy }
        guard request.executableURL.isFileURL,
              request.timeout > 0,
              request.maximumOutputBytes > 0
        else { throw LocalTranscriptionProcessError.launchFailed }

        cancellationRequested = false
        timeoutTriggered = false
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let collected = BoundedProcessOutput(maximumBytes: request.maximumOutputBytes)

        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        activeProcess = process

        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if !collected.appendStandardOutput(data) { process.terminate() }
        }
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if !collected.appendStandardError(data) { process.terminate() }
        }

        return try await withTaskCancellationHandler {
            let terminationStatus: Int32
            do {
                terminationStatus = try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { completed in
                        continuation.resume(returning: completed.terminationStatus)
                    }
                    do {
                        try process.run()
                        armTimeout(for: process, seconds: request.timeout)
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: LocalTranscriptionProcessError.launchFailed)
                    }
                }
            } catch {
                cleanup(process: process, stdout: standardOutputPipe, stderr: standardErrorPipe)
                throw error
            }

            timeoutTask?.cancel()
            standardOutputPipe.fileHandleForReading.readabilityHandler = nil
            standardErrorPipe.fileHandleForReading.readabilityHandler = nil
            collected.appendStandardOutput(standardOutputPipe.fileHandleForReading.readDataToEndOfFile())
            collected.appendStandardError(standardErrorPipe.fileHandleForReading.readDataToEndOfFile())
            let output = collected.snapshot(terminationStatus: terminationStatus)
            let wasCancelled = cancellationRequested
            let didTimeOut = timeoutTriggered
            cleanup(process: process, stdout: standardOutputPipe, stderr: standardErrorPipe)

            if wasCancelled { throw LocalTranscriptionProcessError.cancelled }
            if didTimeOut { throw LocalTranscriptionProcessError.timedOut }
            if collected.exceededLimit { throw LocalTranscriptionProcessError.outputLimitExceeded }
            return output
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        guard let activeProcess else { return }
        cancellationRequested = true
        terminate(activeProcess)
    }

    private func armTimeout(for process: Process, seconds: TimeInterval) {
        timeoutTask = Task { @MainActor [weak self, weak process] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let self, let process, self.activeProcess === process else { return }
            self.timeoutTriggered = true
            self.terminate(process)
        }
    }

    private func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        Task { @MainActor [weak self, weak process] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, let process, self.activeProcess === process, process.isRunning else { return }
            _ = Darwin.kill(pid, SIGKILL)
        }
    }

    private func cleanup(process: Process, stdout: Pipe, stderr: Pipe) {
        timeoutTask?.cancel()
        timeoutTask = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if activeProcess === process { activeProcess = nil }
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var standardOutput = Data()
    private var standardError = Data()
    private var exceededLimitStorage = false

    var exceededLimit: Bool { lock.withLock { exceededLimitStorage } }

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    @discardableResult
    func appendStandardOutput(_ data: Data) -> Bool {
        lock.withLock { append(data, isStandardOutput: true) }
    }

    @discardableResult
    func appendStandardError(_ data: Data) -> Bool {
        lock.withLock { append(data, isStandardOutput: false) }
    }

    func snapshot(terminationStatus: Int32) -> LocalTranscriptionProcessOutput {
        lock.withLock {
            .init(
                standardOutput: standardOutput,
                standardError: standardError,
                terminationStatus: terminationStatus
            )
        }
    }

    private func append(_ data: Data, isStandardOutput: Bool) -> Bool {
        guard !data.isEmpty else { return !exceededLimitStorage }
        let remaining = maximumBytes - standardOutput.count - standardError.count
        guard remaining > 0 else {
            exceededLimitStorage = true
            return false
        }
        if isStandardOutput {
            standardOutput.append(data.prefix(remaining))
        } else {
            standardError.append(data.prefix(remaining))
        }
        if data.count > remaining { exceededLimitStorage = true }
        return !exceededLimitStorage
    }
}
