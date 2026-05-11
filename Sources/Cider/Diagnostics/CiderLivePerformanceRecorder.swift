import CoreGraphics
import Foundation
import os

@MainActor
final class CiderLivePerformanceRecorder {
    static let shared = CiderLivePerformanceRecorder.fromEnvironment()

    private(set) var currentSummary: CiderLivePerformanceSummary
    private let isEnabled: Bool
    private let jankThresholdSeconds: TimeInterval
    private let logSink: CiderLivePerformanceLogSink
    private let hangMonitor: CiderMainThreadHangMonitor?
    private var lastTimestamp: TimeInterval?
    private var sessionStarted = false

    init(
        isEnabled: Bool,
        jankThresholdSeconds: TimeInterval = 1.0 / 30.0,
        logSink: CiderLivePerformanceLogSink = .default,
        hangMonitor: CiderMainThreadHangMonitor? = nil
    ) {
        self.isEnabled = isEnabled
        self.jankThresholdSeconds = jankThresholdSeconds
        self.logSink = logSink
        self.hangMonitor = hangMonitor
        self.currentSummary = CiderLivePerformanceSummary(context: .unknown)
    }

    func startSession(surface: String) {
        guard isEnabled, !sessionStarted else { return }
        sessionStarted = true
        logSink.write("CIDER_PERF session_start surface=\"\(Self.escape(surface))\" \(currentSummary.context.logFields)")
        hangMonitor?.start(initialContext: currentSummary.context)
    }

    func updateContext(_ context: CiderLivePerformanceContext) {
        guard isEnabled else { return }
        currentSummary.context = context
        hangMonitor?.updateContext(context)
        logSink.write("CIDER_PERF context \(context.logFields)")
    }

    func recordNavigation(
        action: String,
        from previous: CiderLivePerformanceNavigationSnapshot,
        to next: CiderLivePerformanceNavigationSnapshot
    ) {
        guard isEnabled else { return }
        logSink.write(
            "CIDER_NAV action=\"\(Self.escape(action))\" " +
            "\(previous.logFields(prefix: "from")) " +
            "\(next.logFields(prefix: "to")) " +
            currentSummary.context.logFields
        )
    }

    func recordFrame(
        event: CiderLivePerformanceEvent,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
        windowSize: CGSize
    ) {
        guard isEnabled else { return }

        let interval = lastTimestamp.map { timestamp - $0 }
        lastTimestamp = timestamp
        currentSummary.record(
            event: event,
            interval: interval,
            threshold: jankThresholdSeconds,
            windowSize: windowSize
        )

        logSink.write(
            "CIDER_PERF sample event=\(event.rawValue) " +
            "sample=\(currentSummary.sampleCount) " +
            "dt_ms=\(Self.formatMilliseconds(interval)) " +
            "jank=\(interval.map { $0 > jankThresholdSeconds } ?? false) " +
            "width=\(Self.format(windowSize.width)) " +
            "height=\(Self.format(windowSize.height)) " +
            currentSummary.context.logFields
        )
    }

    func flushSession(reason: String) {
        guard isEnabled else { return }
        logSink.write(currentSummary.summaryLine(reason: reason))
        hangMonitor?.stop()
    }

    private static func fromEnvironment() -> CiderLivePerformanceRecorder {
        let environment = ProcessInfo.processInfo.environment
        let enabledValues = ["1", "true", "yes", "on"]
        let isEnabled = environment["CIDER_PERF_MONITOR"]
            .map { enabledValues.contains($0.lowercased()) } ?? false
        let logURL = environment["CIDER_PERF_LOG_PATH"].map(URL.init(fileURLWithPath:))
        return CiderLivePerformanceRecorder(
            isEnabled: isEnabled,
            logSink: CiderLivePerformanceLogSink(
                logURL: logURL ?? CiderLivePerformanceLogSink.defaultLogURL,
                mirrorsToConsole: true
            ),
            hangMonitor: isEnabled ? CiderMainThreadHangMonitor(
                logSink: CiderLivePerformanceLogSink(
                    logURL: logURL ?? CiderLivePerformanceLogSink.defaultLogURL,
                    mirrorsToConsole: true
                )
            ) : nil
        )
    }

    private static func formatMilliseconds(_ interval: TimeInterval?) -> String {
        guard let interval else { return "n/a" }
        return String(format: "%.3f", interval * 1_000)
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum CiderLivePerformanceEvent: String, Codable, Sendable {
    case move
    case resize
    case layoutWidth
}

struct CiderLivePerformanceContext: Codable, Equatable, Sendable {
    static let unknown = CiderLivePerformanceContext(view: "unknown", visibleItemCount: nil)

    let view: String
    let visibleItemCount: Int?

    init(view: String, visibleItemCount: Int? = nil) {
        self.view = view
        self.visibleItemCount = visibleItemCount
    }

    var logFields: String {
        var fields = "view=\"\(Self.escape(view))\""
        if let visibleItemCount {
            fields += " visible_items=\(visibleItemCount)"
        } else {
            fields += " visible_items=unknown"
        }
        return fields
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct CiderLivePerformanceNavigationSnapshot: Codable, Equatable, Sendable {
    let domain: String?
    let route: String?
    let tab: String?
    let hasFolder: Bool
    let tagCount: Int

    init(
        domain: String?,
        route: String?,
        tab: String?,
        hasFolder: Bool = false,
        tagCount: Int = 0
    ) {
        self.domain = domain
        self.route = route
        self.tab = tab
        self.hasFolder = hasFolder
        self.tagCount = tagCount
    }

    var logFields: String {
        logFields(prefix: nil)
    }

    func logFields(prefix: String?) -> String {
        let fieldPrefix = prefix.map { "\($0)_" } ?? ""
        return "\(fieldPrefix)domain=\"\(Self.escape(domain ?? "none"))\" " +
            "\(fieldPrefix)route=\"\(Self.escape(route ?? "none"))\" " +
            "\(fieldPrefix)tab=\"\(Self.escape(tab ?? "none"))\" " +
            "\(fieldPrefix)folder=\(hasFolder) " +
            "\(fieldPrefix)tag_count=\(tagCount)"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct CiderLivePerformanceSummary: Codable, Equatable, Sendable {
    var context: CiderLivePerformanceContext
    private(set) var sampleCount = 0
    private(set) var moveSampleCount = 0
    private(set) var resizeSampleCount = 0
    private(set) var layoutWidthSampleCount = 0
    private(set) var jankSampleCount = 0
    private(set) var maxFrameIntervalSeconds: TimeInterval = 0
    private(set) var lastWindowSize: CGSize = .zero

    mutating func record(
        event: CiderLivePerformanceEvent,
        interval: TimeInterval?,
        threshold: TimeInterval,
        windowSize: CGSize
    ) {
        sampleCount += 1
        lastWindowSize = windowSize
        switch event {
        case .move: moveSampleCount += 1
        case .resize: resizeSampleCount += 1
        case .layoutWidth: layoutWidthSampleCount += 1
        }

        if let interval {
            maxFrameIntervalSeconds = max(maxFrameIntervalSeconds, interval)
            if interval > threshold {
                jankSampleCount += 1
            }
        }
    }

    func summaryLine(reason: String) -> String {
        "CIDER_PERF summary reason=\"\(reason)\" " +
        "samples=\(sampleCount) " +
        "move_samples=\(moveSampleCount) " +
        "resize_samples=\(resizeSampleCount) " +
        "layout_width_samples=\(layoutWidthSampleCount) " +
        "jank_samples=\(jankSampleCount) " +
        "max_dt_ms=\(String(format: "%.3f", maxFrameIntervalSeconds * 1_000)) " +
        "width=\(String(format: "%.1f", Double(lastWindowSize.width))) " +
        "height=\(String(format: "%.1f", Double(lastWindowSize.height))) " +
        context.logFields
    }
}

struct CiderLivePerformanceLogSink: Sendable {
    static let defaultLogURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Cider/performance.log")
    static let `default` = CiderLivePerformanceLogSink(logURL: defaultLogURL, mirrorsToConsole: true)

    let logURL: URL
    let mirrorsToConsole: Bool
    private let logger = Logger(subsystem: "com.cider.app", category: "Performance")

    func write(_ line: String) {
        if mirrorsToConsole {
            print(line)
            logger.debug("\(line, privacy: .public)")
        }

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let output = "\(Self.timestamp()) \(line)\n"
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(output.utf8))
            } else {
                try output.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            if mirrorsToConsole {
                logger.error("Failed to write performance log: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
