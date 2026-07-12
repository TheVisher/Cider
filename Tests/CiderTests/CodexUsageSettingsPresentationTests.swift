import Foundation
import Testing
@testable import Cider

@Suite("Codex Usage Settings presentation")
struct CodexUsageSettingsPresentationTests {
    private let timeZone = TimeZone(secondsFromGMT: -7 * 60 * 60)!
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test("Idle, loading, and sanitized failures have explicit manual actions")
    func stateCopy() {
        let formatter = makeFormatter()

        #expect(formatter.content(for: .idle) == .idle(
            message: "Checking usage is read-only and does not start a model turn.",
            actionTitle: "Refresh Usage"
        ))
        #expect(formatter.content(for: .loading) == .loading(
            message: "Checking Codex usage…",
            actionTitle: "Refreshing…"
        ))

        for failure in CodexUsageFailure.allSettingsFailures {
            #expect(formatter.content(for: .failed(failure)) == .failed(
                message: failure.description,
                actionTitle: "Retry"
            ))
        }
    }

    @Test("Loaded Pro Lite usage preserves exact values and local reset formatting")
    func loadedProLite() throws {
        let display = try #require(loadedDisplay(presentation(plan: "prolite")))

        #expect(display.planLabel == "Pro Lite")
        #expect(display.lastChecked == "May 17, 2033 at 8:33 PM")
        #expect(display.codexRows.count == 2)
        #expect(display.codexRows[0] == .usage(
            label: "5-hour limit",
            usedPercent: 25,
            remainingPercent: 75,
            reset: "May 18, 2033 at 1:33 AM",
            severity: "Normal",
            guidance: "Usage is in a comfortable range. Continue normally."
        ))
        #expect(display.codexRows[1] == .usage(
            label: "Weekly limit",
            usedPercent: 40,
            remainingPercent: 60,
            reset: "May 24, 2033 at 8:33 PM",
            severity: "Normal",
            guidance: "Usage is in a comfortable range. Continue normally."
        ))
    }

    @Test("Future plan labels remain visible and policy wording follows typed action")
    func futurePlanAndPolicy() throws {
        let weekly = window(
            duration: .weekly,
            used: 88,
            reset: date(2_000_604_800),
            severity: .high,
            action: .pauseNonessentialSolCoding
        )
        let display = try #require(loadedDisplay(presentation(plan: "future ultra-plan 2", codexWindows: [
            window(duration: .fiveHours, used: 72, severity: .warning),
            weekly,
        ])))

        #expect(display.planLabel == "future ultra-plan 2")
        #expect(display.codexRows[0].severity == "Warning")
        #expect(display.codexRows[0].guidance == "Usage is elevated. Keep nonessential Sol work brief.")
        #expect(display.codexRows[1].severity == "High")
        #expect(display.codexRows[1].guidance == "Pause nonessential Sol coding until this allowance resets.")
    }

    @Test("Spark is a separate named subsection and never authorizes Sol")
    func sparkSeparation() throws {
        let display = try #require(loadedDisplay(presentation(plan: "prolite")))

        #expect(display.sparkSections.map(\.title) == ["GPT-5.3-Codex-Spark"])
        #expect(display.sparkNotice == "Spark allowance is separate and does not authorize Sol coding.")
        #expect(display.sparkSections[0].rows[0].severity == "Separate")
        #expect(display.sparkSections[0].rows[0].guidance == "Track this allowance separately. It does not authorize Sol coding.")
    }

    @Test("Unknown buckets and windows need review without hiding known data or leaking IDs")
    func unknownAllowances() throws {
        let privateSentinel = "PRIVATE_SENTINEL_token_account_reset-credit_/Users/private_stderr"
        let unknownWindow = window(
            duration: .unknown(minutes: 720),
            used: 20,
            severity: .unknown,
            action: .reviewUnknownWindow,
            reviewState: .unknownWindow
        )
        let unknownBucket = CodexUsageBucket(
            publicLimitID: privateSentinel,
            publicDisplayName: nil,
            kind: .unknownRequiresReview,
            windows: [window(
                duration: .unknown(minutes: 90),
                used: 10,
                severity: .unknown,
                action: .reviewUnknownBucket,
                reviewState: .unknownBucket
            )]
        )
        let namedUnknownBucket = CodexUsageBucket(
            publicLimitID: "future-internal-id",
            publicDisplayName: "Research Preview",
            kind: .unknownRequiresReview,
            windows: [window(
                duration: .fiveHours,
                used: 15,
                severity: .unknown,
                action: .reviewUnknownBucket,
                reviewState: .unknownBucket
            )]
        )
        let value = presentation(plan: "prolite", codexWindows: [
            window(duration: .fiveHours, used: 25),
            window(duration: .weekly, used: 40, reset: date(2_000_604_800)),
            unknownWindow,
        ], additionalBuckets: [unknownBucket, namedUnknownBucket])
        let display = try #require(loadedDisplay(value))
        let visible = String(describing: display)

        #expect(display.codexRows.count == 3)
        #expect(display.codexRows.last?.label == "Needs review")
        #expect(display.additionalSections.map(\.title) == ["Additional allowance", "Research Preview"])
        #expect(display.additionalSections.allSatisfy { $0.rows.allSatisfy { $0.severity == "Needs review" } })
        #expect(!visible.contains(privateSentinel))
        #expect(!visible.contains("future-internal-id"))
        for forbidden in ["token", "account", "reset-credit", "/Users/private", "stderr"] {
            #expect(!visible.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test("Missing expected Codex windows remain visible as review rows")
    func missingExpectedWindow() throws {
        let display = try #require(loadedDisplay(presentation(
            plan: nil,
            codexWindows: [window(duration: .fiveHours, used: 25)]
        )))

        #expect(display.planLabel == "Plan not reported")
        #expect(display.codexRows.count == 2)
        #expect(display.codexRows[1] == .needsReview(
            label: "Weekly limit",
            guidance: "This expected Codex window was not reported. Review usage before relying on it."
        ))
    }

    private func makeFormatter() -> CodexUsageSettingsFormatter {
        CodexUsageSettingsFormatter(locale: locale, timeZone: timeZone)
    }

    private func loadedDisplay(_ presentation: CodexUsagePresentation) -> CodexUsageSettingsDisplay? {
        guard case .loaded(let display) = makeFormatter().content(for: .loaded(presentation)) else { return nil }
        return display
    }

    private func presentation(
        plan: String?,
        codexWindows: [CodexUsageWindow]? = nil,
        additionalBuckets: [CodexUsageBucket] = []
    ) -> CodexUsagePresentation {
        let codex = CodexUsageBucket(
            publicLimitID: "codex",
            publicDisplayName: "Codex",
            kind: .codex,
            windows: codexWindows ?? [
                window(duration: .fiveHours, used: 25),
                window(duration: .weekly, used: 40, reset: date(2_000_604_800)),
            ]
        )
        let spark = CodexUsageBucket(
            publicLimitID: "codex_bengalfox",
            publicDisplayName: "GPT-5.3-Codex-Spark",
            kind: .spark,
            windows: [
                window(duration: .fiveHours, used: 0, severity: .separate, action: .trackSeparatelyNotSolAuthorization),
                window(duration: .weekly, used: 0, reset: date(2_000_604_800), severity: .separate, action: .trackSeparatelyNotSolAuthorization),
            ]
        )
        return CodexUsagePresentation(snapshot: CodexUsageSnapshot(
            schemaVersion: .v1,
            accountType: "PRIVATE_SENTINEL_account",
            planType: plan,
            retrievedAt: date(2_000_000_000),
            buckets: [codex, spark] + additionalBuckets
        ))
    }

    private func window(
        duration: CodexUsageWindowDuration,
        used: Int,
        reset: Date? = nil,
        severity: CodexUsageSeverity = .normal,
        action: CodexUsagePolicyAction = .continue,
        reviewState: CodexUsageReviewState = .recognized
    ) -> CodexUsageWindow {
        CodexUsageWindow(
            duration: duration,
            usedPercent: used,
            remainingPercent: 100 - used,
            resetsAt: reset ?? date(2_000_018_000),
            severity: severity,
            policyAction: action,
            reachedReason: nil,
            reviewState: reviewState
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

private extension CodexUsageFailure {
    static var allSettingsFailures: [Self] {
        [.unavailable, .timeout, .processFailure, .malformedResponse, .unsupportedResponse, .cancelled]
    }
}
