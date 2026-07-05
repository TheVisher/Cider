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

    func testVerifyWaitsForAccessibleCiderWindow() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("wait_for_accessible_window()"))
        XCTAssertTrue(script.contains("count of windows"))
        XCTAssertTrue(script.contains("did not expose an accessible window after launch"))
    }

    func testVerifyReportsLockedMacOSSessionBeforeWindowPolling() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("screen_is_locked()"))
        XCTAssertTrue(script.contains("CGSessionCopyCurrentDictionary"))
        XCTAssertTrue(script.contains("session.get(\"CGSSessionScreenIsLocked\")"))
        XCTAssertTrue(script.contains("Cannot verify a Cider window while the macOS screen is locked"))
    }

    func testVerifyLaunchUsesNormalChromeWithVerificationPlacement() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("--env \"CIDER_VERIFY_VISIBLE_WINDOW=1\""))
        XCTAssertTrue(script.contains("--env \"CIDER_VERIFY_WINDOW_STATUS_PATH=$VERIFY_WINDOW_STATUS_PATH\""))

        let standardVerificationLaunch = try XCTUnwrap(
            script.range(of: "elif [[ \"$VERIFY\" -eq 1 ]]; then")
        )
        let normalLaunch = try XCTUnwrap(
            script.range(of: "else", range: standardVerificationLaunch.upperBound..<script.endIndex)
        )
        let standardVerificationBlock = script[standardVerificationLaunch.upperBound..<normalLaunch.lowerBound]

        XCTAssertFalse(standardVerificationBlock.contains("CIDER_QA_VISIBLE_WINDOW"))
    }
}
