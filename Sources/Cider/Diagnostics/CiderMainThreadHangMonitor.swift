import Foundation

final class CiderMainThreadHangMonitor: @unchecked Sendable {
    private let thresholdSeconds: TimeInterval
    private let heartbeatIntervalSeconds: TimeInterval
    private let checkIntervalSeconds: TimeInterval
    private let uptime: @Sendable () -> TimeInterval
    private let logSink: CiderLivePerformanceLogSink
    private let lock = NSLock()

    private var lastMainHeartbeat: TimeInterval
    private var lastReportedStallWindow: Int = -1
    private var context: CiderLivePerformanceContext = .unknown
    private var heartbeatTimer: Timer?
    private var watchdogTimer: DispatchSourceTimer?

    init(
        thresholdSeconds: TimeInterval = 2.0,
        heartbeatIntervalSeconds: TimeInterval = 0.5,
        checkIntervalSeconds: TimeInterval = 1.0,
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        logSink: CiderLivePerformanceLogSink = .default
    ) {
        self.thresholdSeconds = thresholdSeconds
        self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
        self.checkIntervalSeconds = checkIntervalSeconds
        self.uptime = uptime
        self.logSink = logSink
        self.lastMainHeartbeat = uptime()
    }

    @MainActor
    func start(initialContext: CiderLivePerformanceContext) {
        guard heartbeatTimer == nil, watchdogTimer == nil else { return }
        updateContext(initialContext)
        markMainHeartbeat(at: uptime())

        let heartbeatTimer = Timer(timeInterval: heartbeatIntervalSeconds, repeats: true) { [weak self] _ in
            self?.markMainHeartbeat()
        }
        RunLoop.main.add(heartbeatTimer, forMode: .common)
        self.heartbeatTimer = heartbeatTimer

        watchdogTimer = makeWatchdogTimer()
        logSink.write(
            "CIDER_HANG_MONITOR started threshold_ms=\(Self.formatMilliseconds(thresholdSeconds)) " +
            initialContext.logFields
        )
    }

    @MainActor
    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        watchdogTimer?.cancel()
        watchdogTimer = nil
        logSink.write("CIDER_HANG_MONITOR stopped")
    }

    func updateContext(_ context: CiderLivePerformanceContext) {
        lock.lock()
        self.context = context
        lock.unlock()
    }

    func markMainHeartbeat(at timestamp: TimeInterval? = nil) {
        lock.lock()
        lastMainHeartbeat = timestamp ?? uptime()
        lock.unlock()
    }

    private func makeWatchdogTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + checkIntervalSeconds, repeating: checkIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.checkHeartbeat()
        }
        timer.resume()
        return timer
    }

    @discardableResult
    func checkHeartbeat(now timestamp: TimeInterval? = nil) -> String? {
        let now = timestamp ?? uptime()
        lock.lock()
        let lag = now - lastMainHeartbeat
        let context = context
        let stallWindow = Int(lag / max(thresholdSeconds, 0.001))
        let shouldReport = lag >= thresholdSeconds && stallWindow > lastReportedStallWindow
        if shouldReport {
            lastReportedStallWindow = stallWindow
        }
        lock.unlock()

        guard shouldReport else { return nil }
        let line = "CIDER_HANG suspected_main_thread_stall " +
            "lag_ms=\(Self.formatMilliseconds(lag)) " +
            "threshold_ms=\(Self.formatMilliseconds(thresholdSeconds)) " +
            context.logFields
        logSink.write(line)
        return line
    }

    private static func formatMilliseconds(_ value: TimeInterval) -> String {
        String(format: "%.3f", value * 1_000)
    }
}
