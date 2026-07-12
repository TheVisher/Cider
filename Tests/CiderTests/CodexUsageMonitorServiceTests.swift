import Darwin
import Foundation
import XCTest
@testable import Cider

final class CodexUsageMonitorDecodingTests: XCTestCase {
    private let decoder = CodexUsageResponseDecoder()

    func testLiveStyleProliteCodexAndNamedSparkDecode() throws {
        let snapshot = try decoder.decode(Self.report())

        XCTAssertEqual(snapshot.schemaVersion, .v1)
        XCTAssertEqual(snapshot.accountType, "chatgpt")
        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertEqual(snapshot.buckets.map(\.kind), [.codex, .spark])
        XCTAssertEqual(snapshot.buckets[0].windows.map(\.duration), [.fiveHours, .weekly])
        XCTAssertEqual(snapshot.buckets[1].publicLimitID, "codex_bengalfox")
        XCTAssertTrue(snapshot.buckets[1].windows.allSatisfy { $0.policyAction == .trackSeparatelyNotSolAuthorization })
    }

    func testUnknownFuturePlanRemainsDisplayable() throws {
        let snapshot = try decoder.decode(Self.report(plan: "future ultra-plan 2"))
        XCTAssertEqual(snapshot.planType, "future ultra-plan 2")
    }

    func testUnknownBucketAndWindowRemainReviewable() throws {
        let data = Self.report(buckets: [[
            "limitId": "future-bucket",
            "unknownReason": "unrecognized_limit_id",
            "windows": [Self.window(duration: 720, used: 20, severity: "unknown", action: "review_unknown_bucket", unknownReason: "unrecognized_window_duration")]
        ]])
        let snapshot = try decoder.decode(data)
        XCTAssertEqual(snapshot.buckets[0].kind, .unknownRequiresReview)
        XCTAssertEqual(snapshot.buckets[0].windows[0].duration, .unknown(minutes: 720))
        XCTAssertEqual(snapshot.buckets[0].windows[0].reviewState, .unknownBucket)
    }

    func testRejectsUnsupportedSchemaAndMalformedRequiredFields() {
        assertRejected(Self.report(schema: "cider.codex-usage-monitor.v2"), as: .unsupportedResponse)
        assertRejected(Self.json(["schemaVersion": "cider.codex-usage-monitor.v1"]), as: .malformedResponse)
    }

    func testRejectsImpossibleOrNoncomplementaryPercents() {
        assertMutationRejected { $0["usedPercent"] = 101 }
        assertMutationRejected { $0["remainingPercent"] = 76 }
        assertMutationRejected { $0["usedPercent"] = -1 }
    }

    func testRejectsDuplicateBucketAndWindow() {
        let codex = Self.codexBucket()
        assertRejected(Self.report(buckets: [codex, codex]), as: .malformedResponse)
        var duplicateWindowBucket = codex
        duplicateWindowBucket["windows"] = [Self.codexWindow(), Self.codexWindow()]
        assertRejected(Self.report(buckets: [duplicateWindowBucket]), as: .malformedResponse)
    }

    func testRejectsMissingInvalidOrMismatchedResetTimestamps() {
        assertMutationRejected { $0.removeValue(forKey: "resetsAt") }
        assertMutationRejected { $0["resetsAt"] = 0 }
        assertMutationRejected { $0["resetsAtLocal"] = "not-a-date" }
        assertMutationRejected { $0["resetsAtLocal"] = "2033-05-18T05:33:21+00:00" }
    }

    func testRejectsInvalidSeverityActionAndCategoryCombinations() {
        assertMutationRejected { $0["severity"] = "separate" }
        assertMutationRejected { $0["policyAction"] = "track_separately_not_sol_authorization" }
        assertMutationRejected { $0["severity"] = "critical" }

        var fakeSpark = Self.sparkBucket()
        fakeSpark["unknownReason"] = "unrecognized_limit_id"
        assertRejected(Self.report(buckets: [fakeSpark]), as: .malformedResponse)
    }

    func testRejectsOversizedControlAndPrivateUseStrings() {
        assertRejected(Self.report(plan: String(repeating: "x", count: 81)), as: .malformedResponse)
        assertRejected(Self.report(plan: "bad\nplan"), as: .malformedResponse)
        assertRejected(Self.report(plan: "private\u{E000}plan"), as: .malformedResponse)
        var bucket = Self.codexBucket()
        bucket["displayName"] = "bad\u{0001}name"
        assertRejected(Self.report(buckets: [bucket]), as: .malformedResponse)
    }

    func testRawPrivacyFieldsNeverEnterTypedOrPresentationDescriptions() throws {
        let sentinel = "PRIVATE_SENTINEL_TOKEN_email@example.com_accountID_reset-credit_/Users/private/stderr"
        var root = Self.reportObject()
        root["accessToken"] = sentinel
        root["email"] = sentinel
        root["accountID"] = sentinel
        root["rateLimitResetCredits"] = ["description": sentinel]
        let snapshot = try decoder.decode(Self.json(root))
        let presentation = CodexUsagePresentation(snapshot: snapshot)
        let visible = String(describing: snapshot) + String(describing: presentation)
        XCTAssertFalse(visible.contains(sentinel))
        for forbidden in ["accessToken", "email@example.com", "accountID", "reset-credit", "/Users/private", "stderr"] {
            XCTAssertFalse(visible.contains(forbidden))
        }
    }

    private func assertMutationRejected(_ mutate: (inout [String: Any]) -> Void) {
        var bucket = Self.codexBucket()
        var windows = bucket["windows"] as! [[String: Any]]
        mutate(&windows[0])
        bucket["windows"] = windows
        assertRejected(Self.report(buckets: [bucket]), as: .malformedResponse)
    }

    private func assertRejected(_ data: Data, as expected: CodexUsageFailure, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decoder.decode(data), file: file, line: line) { error in
            XCTAssertEqual(error as? CodexUsageFailure, expected, file: file, line: line)
            XCTAssertFalse(String(describing: error).contains("PRIVATE_SENTINEL"), file: file, line: line)
        }
    }

    static func report(schema: String = "cider.codex-usage-monitor.v1", plan: String = "prolite", buckets: [[String: Any]]? = nil) -> Data {
        json(reportObject(schema: schema, plan: plan, buckets: buckets))
    }

    static func reportObject(schema: String = "cider.codex-usage-monitor.v1", plan: String = "prolite", buckets: [[String: Any]]? = nil) -> [String: Any] {
        [
            "schemaVersion": schema,
            "accountType": "chatgpt",
            "planType": plan,
            "retrievedAt": "2033-05-18T03:33:20+00:00",
            "buckets": buckets ?? [codexBucket(), sparkBucket()]
        ]
    }

    static func codexBucket() -> [String: Any] {
        ["limitId": "codex", "displayName": "Codex", "windows": [
            codexWindow(),
            window(duration: 10_080, used: 40, severity: "normal", action: "continue", reset: 2_000_604_800, local: "2033-05-25T03:33:20+00:00")
        ]]
    }

    static func sparkBucket() -> [String: Any] {
        ["limitId": "codex_bengalfox", "displayName": "GPT-5.3-Codex-Spark", "windows": [
            window(duration: 300, used: 0, severity: "separate", action: "track_separately_not_sol_authorization"),
            window(duration: 10_080, used: 0, severity: "separate", action: "track_separately_not_sol_authorization", reset: 2_000_604_800, local: "2033-05-25T03:33:20+00:00")
        ]]
    }

    static func codexWindow() -> [String: Any] {
        window(duration: 300, used: 25, severity: "normal", action: "continue")
    }

    static func window(duration: Int, used: Int, severity: String, action: String, reset: Int = 2_000_018_000, local: String = "2033-05-18T08:33:20+00:00", unknownReason: String? = nil) -> [String: Any] {
        var result: [String: Any] = [
            "windowDurationMins": duration, "usedPercent": used, "remainingPercent": 100 - used,
            "resetsAt": reset, "resetsAtLocal": local, "severity": severity, "policyAction": action,
            "reachedReason": NSNull()
        ]
        if let unknownReason { result["unknownReason"] = unknownReason }
        return result
    }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

final class CodexUsageProcessRunnerTests: XCTestCase {
    func testBuildsExactDirectPythonInvocationWithoutShellOrForbiddenStrings() async throws {
        let executor = InvocationRecordingExecutor(result: .success(CodexUsageMonitorDecodingTests.report()))
        let runner = CodexUsageProcessRunner(
            locator: FixedMonitorLocator(url: URL(fileURLWithPath: "/safe/CodexUsageMonitor.py")),
            executor: executor,
            timeout: 7
        )
        _ = try await runner.fetch()
        let invocation = await executor.invocations.first
        XCTAssertEqual(invocation?.executable.path, "/usr/bin/python3")
        XCTAssertEqual(invocation?.arguments, ["/safe/CodexUsageMonitor.py", "--json", "--timeout", "7"])
        let flattened = ([invocation?.executable.path] + (invocation?.arguments ?? [])).compactMap { $0 }.joined(separator: " ")
        for forbidden in ["/bin/sh", "-c", "CiderVault", "Hermes", "token", "accountID", "reset-credit"] {
            XCTAssertFalse(flattened.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testMissingScriptAndProcessFailuresAreSanitized() async {
        let missing = CodexUsageProcessRunner(locator: MissingMonitorLocator(), executor: InvocationRecordingExecutor(result: .success(Data())))
        await assertFailure(.unavailable) { _ = try await missing.fetch() }

        let failed = CodexUsageProcessRunner(
            locator: FixedMonitorLocator(url: URL(fileURLWithPath: "/safe/monitor.py")),
            executor: InvocationRecordingExecutor(result: .failure(.nonzeroExit))
        )
        await assertFailure(.processFailure) { _ = try await failed.fetch() }

        let rawFailure = CodexUsageProcessRunner(
            locator: FixedMonitorLocator(url: URL(fileURLWithPath: "/safe/monitor.py")),
            executor: PrivateFailingExecutor()
        )
        await assertFailure(.processFailure) { _ = try await rawFailure.fetch() }
    }

    func testTimeoutCancellationAndStdoutCapMapToFiniteFailures() async {
        for (error, expected) in [(ProcessExecutionError.timeout, CodexUsageFailure.timeout), (.cancelled, .cancelled), (.stdoutLimitExceeded, .processFailure)] {
            let runner = CodexUsageProcessRunner(
                locator: FixedMonitorLocator(url: URL(fileURLWithPath: "/safe/monitor.py")),
                executor: InvocationRecordingExecutor(result: .failure(error))
            )
            await assertFailure(expected) { _ = try await runner.fetch() }
        }
    }

    func testProductionEnvironmentIsStrictlyAllowlisted() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Services/CodexUsageMonitorService.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("for key in [\"HOME\", \"TMPDIR\"]"))
        XCTAssertTrue(source.contains("\"PATH\":"))
        for forbidden in ["OPENAI_API_KEY", "CODEX_HOME", "AWS_", "TOKEN", "SECRET", "API_KEY"] {
            XCTAssertFalse(source.contains(forbidden))
        }
    }

    func testFoundationExecutorCapsStdoutTimesOutCancelsAndCleansChild() async throws {
        let fixture = try PythonFixture.make()
        defer { fixture.remove() }
        let executor = FoundationCodexUsageProcessExecutor(stdoutLimit: 1_024, terminationGrace: 0.05)

        await assertExecutionError(.stdoutLimitExceeded) {
            try await executor.execute(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.url.path, "flood"], timeout: 2)
        }
        await assertExecutionError(.timeout) {
            try await executor.execute(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.url.path, "sleep"], timeout: 0.05)
        }
        await assertExecutionError(.timeout) {
            try await executor.execute(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.url.path, "stubborn"], timeout: 0.05)
        }

        let task = Task {
            try await executor.execute(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.url.path, "sleep"], timeout: 5)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await assertExecutionError(.cancelled) { try await task.value }
        try await Task.sleep(for: .milliseconds(100))
        for pid in fixture.recordedPIDs() { XCTAssertEqual(kill(pid, 0), -1, "child \(pid) must be reaped") }
    }

    private func assertFailure(_ expected: CodexUsageFailure, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? CodexUsageFailure, expected); XCTAssertFalse(String(describing: error).contains("PRIVATE_SENTINEL")) }
    }

    private func assertExecutionError(_ expected: ProcessExecutionError, operation: () async throws -> Data) async {
        do { _ = try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? ProcessExecutionError, expected) }
    }
}

@MainActor
final class CodexUsageObservableStateTests: XCTestCase {
    func testDormantUntilExplicitRefreshThenLoadsExactlyOnce() async throws {
        let runner = ControlledUsageRunner()
        let model = CodexUsageObservableState(runner: runner)
        XCTAssertEqual(model.state, .idle)
        let initialCount = await runner.count()
        XCTAssertEqual(initialCount, 0)

        model.refresh()
        await runner.waitForInvocationCount(1)
        XCTAssertEqual(model.state, .loading)
        try await runner.succeed(CodexUsageMonitorDecodingTests.report())
        await waitUntil { if case .loaded = model.state { true } else { false } }
        let finalCount = await runner.count()
        XCTAssertEqual(finalCount, 1)
    }

    func testSanitizedFailureRetryAndStaleGenerationCannotOverwrite() async throws {
        let runner = ControlledUsageRunner()
        let model = CodexUsageObservableState(runner: runner)
        model.refresh()
        await runner.waitForInvocationCount(1)
        await runner.fail(.processFailure)
        await waitUntil { model.state == .failed(.processFailure) }

        model.refresh()
        await runner.waitForInvocationCount(2)
        model.refresh()
        await runner.waitForInvocationCount(3)
        try await runner.succeed(CodexUsageMonitorDecodingTests.report(plan: "newest"), invocation: 2)
        await waitUntil { model.presentation?.planType == "newest" }
        try await runner.succeed(CodexUsageMonitorDecodingTests.report(plan: "stale"), invocation: 1)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.presentation?.planType, "newest")
    }

    func testCancellationDoesNotAllowCompletionOverwrite() async throws {
        let runner = ControlledUsageRunner()
        let model = CodexUsageObservableState(runner: runner)
        model.refresh()
        await runner.waitForInvocationCount(1)
        model.cancel()
        XCTAssertEqual(model.state, .failed(.cancelled))
        try await runner.succeed(CodexUsageMonitorDecodingTests.report())
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.state, .failed(.cancelled))
    }

    func testInjectableAsyncRunnerKeepsMainActorResponsive() async {
        let runner = ControlledUsageRunner()
        let model = CodexUsageObservableState(runner: runner)
        model.refresh()
        await runner.waitForInvocationCount(1)
        var marker = false
        await Task.yield()
        marker = true
        XCTAssertTrue(marker)
        XCTAssertEqual(model.state, .loading)
        model.cancel()
    }

    func testSilentCancellationReturnsLoadingStateToIdleWithoutPersistentFailure() async {
        let runner = ControlledUsageRunner()
        let model = CodexUsageObservableState(runner: runner)
        model.refresh()
        await runner.waitForInvocationCount(1)

        model.cancel(silently: true)

        XCTAssertEqual(model.state, .idle)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 where !predicate() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }
}

private actor InvocationRecordingExecutor: CodexUsageProcessExecuting {
    struct Invocation: Sendable { let executable: URL; let arguments: [String]; let timeout: TimeInterval }
    var invocations: [Invocation] = []
    let result: Result<Data, ProcessExecutionError>
    init(result: Result<Data, ProcessExecutionError>) { self.result = result }
    func execute(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data {
        invocations.append(.init(executable: executable, arguments: arguments, timeout: timeout))
        return try result.get()
    }
}

private struct PrivateFailingExecutor: CodexUsageProcessExecuting {
    private struct PrivateError: Error, CustomStringConvertible {
        var description: String { "PRIVATE_SENTINEL stderr /Users/private token@example.com accountID reset-credit" }
    }
    func execute(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data {
        throw PrivateError()
    }
}

private struct FixedMonitorLocator: CodexUsageMonitorLocating {
    let url: URL
    func locateMonitor() throws -> URL { url }
}

private struct MissingMonitorLocator: CodexUsageMonitorLocating {
    func locateMonitor() throws -> URL { throw CodexUsageFailure.unavailable }
}

private actor ControlledUsageRunner: CodexUsageRunning {
    private var continuations: [CheckedContinuation<CodexUsageSnapshot, Error>] = []
    private(set) var invocationCount = 0
    func fetch() async throws -> CodexUsageSnapshot {
        invocationCount += 1
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func waitForInvocationCount(_ count: Int) async {
        while invocationCount < count { await Task.yield() }
    }
    func count() -> Int { invocationCount }
    func succeed(_ data: Data, invocation: Int? = nil) throws {
        let index = invocation ?? (continuations.count - 1)
        continuations[index].resume(returning: try CodexUsageResponseDecoder().decode(data))
    }
    func fail(_ failure: CodexUsageFailure) { continuations.last?.resume(throwing: failure) }
}

private struct PythonFixture {
    let directory: URL
    let url: URL
    let pidFile: URL
    static func make() throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fixture.py")
        let pid = directory.appendingPathComponent("pids")
        let source = """
        import os, sys, time
        with open(\(String(reflecting: pid.path)), 'a') as f: f.write(str(os.getpid()) + '\\n')
        if sys.argv[1] == 'flood':
            sys.stdout.write('x' * 200000); sys.stdout.flush(); time.sleep(10)
        elif sys.argv[1] == 'sleep': time.sleep(10)
        elif sys.argv[1] == 'stubborn':
            import signal
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            time.sleep(10)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        return Self(directory: directory, url: script, pidFile: pid)
    }
    func recordedPIDs() -> [pid_t] {
        ((try? String(contentsOf: pidFile, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { pid_t($0) }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
