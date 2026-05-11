import CoreGraphics
import Foundation
import Testing
@testable import Cider

@MainActor
struct CiderLivePerformanceRecorderTests {
    @Test("live performance recorder aggregates frame intervals and writes machine readable logs")
    func recordsResizeAndFrameStats() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-live-performance-recorder-test-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let sink = CiderLivePerformanceLogSink(logURL: logURL, mirrorsToConsole: false)
        let recorder = CiderLivePerformanceRecorder(
            isEnabled: true,
            jankThresholdSeconds: 1.0 / 30.0,
            logSink: sink
        )

        recorder.updateContext(
            CiderLivePerformanceContext(view: "Populated Kanban", visibleItemCount: 180)
        )
        recorder.recordFrame(
            event: .resize,
            timestamp: 0.000,
            windowSize: CGSize(width: 1000, height: 760)
        )
        recorder.recordFrame(
            event: .resize,
            timestamp: 0.016,
            windowSize: CGSize(width: 1001, height: 760)
        )
        recorder.recordFrame(
            event: .resize,
            timestamp: 0.080,
            windowSize: CGSize(width: 1002, height: 760)
        )
        recorder.flushSession(reason: "test")

        let summary = recorder.currentSummary
        #expect(summary.sampleCount == 3)
        #expect(summary.resizeSampleCount == 3)
        #expect(summary.jankSampleCount == 1)
        #expect(summary.maxFrameIntervalSeconds == 0.064)
        #expect(summary.context.view == "Populated Kanban")
        #expect(summary.context.visibleItemCount == 180)

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("CIDER_PERF sample"))
        #expect(log.contains("event=resize"))
        #expect(log.contains("view=\"Populated Kanban\""))
        #expect(log.contains("visible_items=180"))
        #expect(log.contains("CIDER_PERF summary"))
        #expect(log.contains("jank_samples=1"))
    }

    @Test("live performance recorder writes navigation transitions")
    func recordsNavigationTransitions() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-live-performance-navigation-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let sink = CiderLivePerformanceLogSink(logURL: logURL, mirrorsToConsole: false)
        let recorder = CiderLivePerformanceRecorder(isEnabled: true, logSink: sink)

        recorder.updateContext(CiderLivePerformanceContext(view: "Home"))
        recorder.recordNavigation(
            action: "open_space:Media",
            from: CiderLivePerformanceNavigationSnapshot(
                domain: "Home",
                route: "Overview",
                tab: "Welcome"
            ),
            to: CiderLivePerformanceNavigationSnapshot(
                domain: nil,
                route: "Overview",
                tab: "Media"
            )
        )

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("CIDER_NAV"))
        #expect(log.contains("action=\"open_space:Media\""))
        #expect(log.contains("from_domain=\"Home\""))
        #expect(log.contains("to_tab=\"Media\""))
        #expect(log.contains("view=\"Home\""))
    }

    @Test("main thread hang monitor reports stale heartbeats once per stall window")
    func hangMonitorReportsStaleHeartbeat() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-main-thread-hang-monitor-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let sink = CiderLivePerformanceLogSink(logURL: logURL, mirrorsToConsole: false)
        let monitor = CiderMainThreadHangMonitor(
            thresholdSeconds: 2.0,
            uptime: { 0 },
            logSink: sink
        )

        monitor.updateContext(CiderLivePerformanceContext(view: "Media", visibleItemCount: nil))
        monitor.markMainHeartbeat(at: 10)

        #expect(monitor.checkHeartbeat(now: 11.9) == nil)
        let firstStall = monitor.checkHeartbeat(now: 12.1)
        #expect(firstStall?.contains("CIDER_HANG suspected_main_thread_stall") == true)
        #expect(firstStall?.contains("lag_ms=2100.000") == true)
        #expect(firstStall?.contains("view=\"Media\"") == true)
        #expect(monitor.checkHeartbeat(now: 12.5) == nil)

        let nextWindow = monitor.checkHeartbeat(now: 14.1)
        #expect(nextWindow?.contains("lag_ms=4100.000") == true)

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("CIDER_HANG suspected_main_thread_stall"))
    }

    @Test("main thread hang monitor watchdog can run from its background queue")
    func hangMonitorWatchdogDoesNotInheritMainActorIsolation() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-main-thread-hang-monitor-watchdog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let sink = CiderLivePerformanceLogSink(logURL: logURL, mirrorsToConsole: false)
        let monitor = CiderMainThreadHangMonitor(
            thresholdSeconds: 60.0,
            heartbeatIntervalSeconds: 0.05,
            checkIntervalSeconds: 0.05,
            logSink: sink
        )

        monitor.start(initialContext: CiderLivePerformanceContext(view: "QA", visibleItemCount: 1))
        try await Task.sleep(nanoseconds: 200_000_000)
        monitor.stop()

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("CIDER_HANG_MONITOR started"))
        #expect(log.contains("CIDER_HANG_MONITOR stopped"))
    }

    @Test("disabled live performance recorder stays silent")
    func disabledRecorderDoesNotWriteLogs() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-live-performance-recorder-disabled-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let sink = CiderLivePerformanceLogSink(logURL: logURL, mirrorsToConsole: false)
        let recorder = CiderLivePerformanceRecorder(isEnabled: false, logSink: sink)

        recorder.recordFrame(
            event: .move,
            timestamp: 0.000,
            windowSize: CGSize(width: 1000, height: 760)
        )
        recorder.flushSession(reason: "disabled")

        #expect(recorder.currentSummary.sampleCount == 0)
        #expect(FileManager.default.fileExists(atPath: logURL.path) == false)
    }
}
