import Combine
import Darwin
import Foundation

protocol CodexUsageRunning: Sendable {
    func fetch() async throws -> CodexUsageSnapshot
}

protocol CodexUsageMonitorLocating: Sendable {
    func locateMonitor() throws -> URL
}

struct ProductionCodexUsageMonitorLocator: CodexUsageMonitorLocating {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func locateMonitor() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            bundle.url(forResource: "codex_usage_monitor", withExtension: "py"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("scripts/codex_usage_monitor.py")
        ].compactMap { $0 }
        guard let result = candidates.first(where: {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && fileManager.isReadableFile(atPath: $0.path)
        }) else {
            throw CodexUsageFailure.unavailable
        }
        return result
    }
}

enum ProcessExecutionError: Error, Sendable, Equatable {
    case unavailable
    case timeout
    case cancelled
    case nonzeroExit
    case stdoutLimitExceeded
}

protocol CodexUsageProcessExecuting: Sendable {
    func execute(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data
}

struct CodexUsageProcessRunner: CodexUsageRunning {
    private let locator: any CodexUsageMonitorLocating
    private let executor: any CodexUsageProcessExecuting
    private let timeout: TimeInterval
    private let decoder: CodexUsageResponseDecoder

    init(
        locator: any CodexUsageMonitorLocating = ProductionCodexUsageMonitorLocator(),
        executor: any CodexUsageProcessExecuting = FoundationCodexUsageProcessExecutor(),
        timeout: TimeInterval = 10,
        decoder: CodexUsageResponseDecoder = CodexUsageResponseDecoder()
    ) {
        self.locator = locator
        self.executor = executor
        self.timeout = min(max(timeout.isFinite ? timeout : 10, 1), 30)
        self.decoder = decoder
    }

    func fetch() async throws -> CodexUsageSnapshot {
        let monitor: URL
        do {
            monitor = try locator.locateMonitor()
        } catch {
            throw CodexUsageFailure.unavailable
        }
        let formattedTimeout = timeout.rounded() == timeout ? String(Int(timeout)) : String(format: "%.3f", timeout)
        let data: Data
        do {
            data = try await executor.execute(
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [monitor.path, "--json", "--timeout", formattedTimeout],
                timeout: timeout + 1
            )
        } catch let error as ProcessExecutionError {
            switch error {
            case .unavailable: throw CodexUsageFailure.unavailable
            case .timeout: throw CodexUsageFailure.timeout
            case .cancelled: throw CodexUsageFailure.cancelled
            case .nonzeroExit, .stdoutLimitExceeded: throw CodexUsageFailure.processFailure
            }
        } catch is CancellationError {
            throw CodexUsageFailure.cancelled
        } catch {
            throw CodexUsageFailure.processFailure
        }
        do {
            return try decoder.decode(data)
        } catch let failure as CodexUsageFailure {
            throw failure
        } catch {
            throw CodexUsageFailure.malformedResponse
        }
    }
}

struct FoundationCodexUsageProcessExecutor: CodexUsageProcessExecuting {
    let stdoutLimit: Int
    let terminationGrace: TimeInterval

    init(stdoutLimit: Int = 256 * 1_024, terminationGrace: TimeInterval = 0.25) {
        self.stdoutLimit = max(1, min(stdoutLimit, 1_024 * 1_024))
        self.terminationGrace = max(0.01, min(terminationGrace, 1))
    }

    func execute(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data {
        guard timeout.isFinite, timeout > 0 else { throw ProcessExecutionError.timeout }
        let control = ProcessExecutionControl(stdoutLimit: stdoutLimit, terminationGrace: terminationGrace)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                control.start(executable: executable, arguments: arguments, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            control.requestStop(.cancelled)
        }
    }
}

private final class ProcessExecutionControl: @unchecked Sendable {
    private let lock = NSLock()
    private let stdoutLimit: Int
    private let terminationGrace: TimeInterval
    private var process: Process?
    private var stdout = Data()
    private var stopError: ProcessExecutionError?
    private var continuation: CheckedContinuation<Data, Error>?
    private var finished = false
    private var timeoutWork: DispatchWorkItem?

    init(stdoutLimit: Int, terminationGrace: TimeInterval) {
        self.stdoutLimit = stdoutLimit
        self.terminationGrace = terminationGrace
    }

    private static func sanitizedEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var result: [String: String] = [
            "PATH": source["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        for key in ["HOME", "TMPDIR"] {
            if let value = source[key], !value.isEmpty { result[key] = value }
        }
        return result
    }

    func start(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        continuation: CheckedContinuation<Data, Error>
    ) {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = Self.sanitizedEnvironment()

        lock.lock()
        self.continuation = continuation
        self.process = process
        let cancellationWasRequested = stopError != nil
        lock.unlock()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }
        process.terminationHandler = { [weak self] terminated in
            output.fileHandleForReading.readabilityHandler = nil
            self?.append(output.fileHandleForReading.readDataToEndOfFile())
            self?.complete(terminationStatus: terminated.terminationStatus)
        }

        if cancellationWasRequested {
            requestStop(.cancelled)
        }
        do {
            try process.run()
        } catch {
            finish(.failure(.unavailable))
            return
        }

        let timeoutWork = DispatchWorkItem { [weak self] in self?.requestStop(.timeout) }
        lock.lock()
        self.timeoutWork = timeoutWork
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        if cancellationWasRequested { requestStop(.cancelled) }
    }

    func requestStop(_ error: ProcessExecutionError) {
        lock.lock()
        if stopError == nil { stopError = error }
        let process = self.process
        let shouldStop = !finished && process?.isRunning == true
        lock.unlock()
        guard shouldStop, let process else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGrace) {
            if process.isRunning { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else { return }
        var exceeded = false
        lock.lock()
        if stdout.count + data.count > stdoutLimit {
            exceeded = true
            if stopError == nil { stopError = .stdoutLimitExceeded }
        } else {
            stdout.append(data)
        }
        lock.unlock()
        if exceeded { requestStop(.stdoutLimitExceeded) }
    }

    private func complete(terminationStatus: Int32) {
        lock.lock()
        let error = stopError
        let data = stdout
        lock.unlock()
        if let error {
            finish(.failure(error))
        } else if terminationStatus == 0 {
            finish(.success(data))
        } else {
            finish(.failure(.nonzeroExit))
        }
    }

    private func finish(_ result: Result<Data, ProcessExecutionError>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        timeoutWork?.cancel()
        let continuation = self.continuation
        self.continuation = nil
        process = nil
        stdout.removeAll(keepingCapacity: false)
        lock.unlock()
        continuation?.resume(with: result.mapError { $0 as Error })
    }
}

@MainActor
final class CodexUsageObservableState: ObservableObject {
    enum State: Sendable, Equatable {
        case idle
        case loading
        case loaded(CodexUsagePresentation)
        case failed(CodexUsageFailure)
    }

    @Published private(set) var state: State = .idle
    var presentation: CodexUsagePresentation? {
        guard case .loaded(let presentation) = state else { return nil }
        return presentation
    }

    private let runner: any CodexUsageRunning
    private var refreshTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(runner: any CodexUsageRunning = CodexUsageProcessRunner()) {
        self.runner = runner
    }

    func refresh() {
        generation &+= 1
        let requestedGeneration = generation
        refreshTask?.cancel()
        state = .loading
        let runner = self.runner
        refreshTask = Task { [weak self] in
            do {
                let snapshot = try await runner.fetch()
                guard let self, self.generation == requestedGeneration, !Task.isCancelled else { return }
                self.refreshTask = nil
                self.state = .loaded(CodexUsagePresentation(snapshot: snapshot))
            } catch {
                guard let self, self.generation == requestedGeneration, !Task.isCancelled else { return }
                self.refreshTask = nil
                self.state = .failed(Self.sanitize(error))
            }
        }
    }

    func cancel(silently: Bool = false) {
        let wasLoading = state == .loading
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        if silently {
            if wasLoading { state = .idle }
        } else {
            state = .failed(.cancelled)
        }
    }

    private static func sanitize(_ error: Error) -> CodexUsageFailure {
        if let failure = error as? CodexUsageFailure { return failure }
        if error is CancellationError { return .cancelled }
        return .processFailure
    }
}
