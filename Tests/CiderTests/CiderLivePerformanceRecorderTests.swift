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
