import XCTest

final class BuildRunScriptPolicyTests: XCTestCase {
    func testTelemetryLaunchDoesNotForceQAVisibleWindowChrome() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)
        let telemetryLaunch = try XCTUnwrap(
            script.range(of: "if [[ \"$TELEMETRY\" -eq 1 ]]; then")
        )
        let normalLaunch = try XCTUnwrap(
            script.range(of: "else", range: telemetryLaunch.upperBound..<script.endIndex)
        )
        let telemetryBlock = script[telemetryLaunch.upperBound..<normalLaunch.lowerBound]

        XCTAssertTrue(telemetryBlock.contains("CIDER_PERF_MONITOR=1"))
        XCTAssertTrue(telemetryBlock.contains("if [[ \"$QA_VISIBLE\" -eq 1 ]]; then"))
        XCTAssertFalse(telemetryBlock.contains("--env \"CIDER_QA_VISIBLE_WINDOW=1\" \\\n    \"$APP_PATH\""))
    }
}
