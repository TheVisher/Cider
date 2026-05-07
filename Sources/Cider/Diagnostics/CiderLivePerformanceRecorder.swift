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
    private var lastTimestamp: TimeInterval?

    init(
        isEnabled: Bool,
        jankThresholdSeconds: TimeInterval = 1.0 / 30.0,
        logSink: CiderLivePerformanceLogSink = .default
    ) {
        self.isEnabled = isEnabled
        self.jankThresholdSeconds = jankThresholdSeconds
        self.logSink = logSink
        self.currentSummary = CiderLivePerformanceSummary(context: .unknown)
    }

    func updateContext(_ context: CiderLivePerformanceContext) {
        guard isEnabled else { return }
        currentSummary.context = context
        logSink.write("CIDER_PERF context \(context.logFields)")
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
            )
        )
    }

    private static func formatMilliseconds(_ interval: TimeInterval?) -> String {
        guard let interval else { return "n/a" }
        return String(format: "%.3f", interval * 1_000)
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
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
