import Foundation

enum CodexUsageSettingsContent: Sendable, Equatable {
    case idle(message: String, actionTitle: String)
    case loading(message: String, actionTitle: String)
    case loaded(CodexUsageSettingsDisplay)
    case failed(message: String, actionTitle: String)

    var actionTitle: String {
        switch self {
        case .idle(_, let actionTitle), .loading(_, let actionTitle), .failed(_, let actionTitle):
            actionTitle
        case .loaded:
            "Refresh"
        }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    var accessibilityValue: String {
        switch self {
        case .idle:
            "Not checked"
        case .loading:
            "Checking usage"
        case .loaded(let display):
            "Loaded. Last checked \(display.lastChecked)"
        case .failed(let message, _):
            "Check failed. \(message)"
        }
    }
}

struct CodexUsageSettingsDisplay: Sendable, Equatable {
    struct Section: Sendable, Equatable {
        let title: String
        let rows: [Row]
    }

    struct Row: Sendable, Equatable {
        let label: String
        let usedPercent: Int?
        let remainingPercent: Int?
        let reset: String?
        let severity: String
        let guidance: String

        static func usage(
            label: String,
            usedPercent: Int,
            remainingPercent: Int,
            reset: String,
            severity: String,
            guidance: String
        ) -> Self {
            .init(
                label: label,
                usedPercent: usedPercent,
                remainingPercent: remainingPercent,
                reset: reset,
                severity: severity,
                guidance: guidance
            )
        }

        static func needsReview(
            label: String,
            usedPercent: Int? = nil,
            remainingPercent: Int? = nil,
            reset: String? = nil,
            guidance: String
        ) -> Self {
            .init(
                label: label,
                usedPercent: usedPercent,
                remainingPercent: remainingPercent,
                reset: reset,
                severity: "Needs review",
                guidance: guidance
            )
        }
    }

    let planLabel: String
    let lastChecked: String
    let codexRows: [Row]
    let sparkNotice: String
    let sparkSections: [Section]
    let additionalSections: [Section]
}

struct CodexUsageSettingsFormatter: Sendable {
    private let locale: Locale
    private let timeZone: TimeZone

    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.locale = locale
        self.timeZone = timeZone
    }

    func content(for state: CodexUsageObservableState.State) -> CodexUsageSettingsContent {
        switch state {
        case .idle:
            .idle(
                message: "Checking usage is read-only and does not start a model turn.",
                actionTitle: "Refresh Usage"
            )
        case .loading:
            .loading(message: "Checking Codex usage…", actionTitle: "Refreshing…")
        case .failed(let failure):
            .failed(message: failure.description, actionTitle: "Retry")
        case .loaded(let presentation):
            .loaded(display(presentation))
        }
    }

    private func display(_ presentation: CodexUsagePresentation) -> CodexUsageSettingsDisplay {
        let codexBuckets = presentation.buckets.filter { $0.kind == .codex }
        let codexWindows = codexBuckets.flatMap(\.windows)
        var codexRows = [
            expectedRow(.fiveHours, label: "5-hour limit", windows: codexWindows),
            expectedRow(.weekly, label: "Weekly limit", windows: codexWindows),
        ]
        codexRows.append(contentsOf: codexWindows.compactMap { window in
            guard case .unknown = window.duration else { return nil }
            return reviewRow(window, label: "Needs review", guidance: reviewGuidance(for: window))
        })

        let sparkSections = presentation.buckets
            .filter { $0.kind == .spark }
            .map { bucket in
                CodexUsageSettingsDisplay.Section(
                    title: safeDisplayName(bucket.displayName, fallback: "Spark allowance"),
                    rows: bucket.windows.map { window in
                        window.reviewState == .recognized
                            ? usageRow(window, label: windowLabel(window.duration))
                            : reviewRow(window, label: "Needs review", guidance: reviewGuidance(for: window))
                    }
                )
            }

        let additionalSections = presentation.buckets
            .filter { $0.kind == .unknownRequiresReview }
            .map { bucket in
                CodexUsageSettingsDisplay.Section(
                    title: safeDisplayName(bucket.displayName, fallback: "Additional allowance"),
                    rows: bucket.windows.map {
                        reviewRow($0, label: "Needs review", guidance: reviewGuidance(for: $0))
                    }
                )
            }

        return CodexUsageSettingsDisplay(
            planLabel: planLabel(presentation.planType),
            lastChecked: dateText(presentation.retrievedAt),
            codexRows: codexRows,
            sparkNotice: "Spark allowance is separate and does not authorize Sol coding.",
            sparkSections: sparkSections,
            additionalSections: additionalSections
        )
    }

    private func expectedRow(
        _ duration: CodexUsageWindowDuration,
        label: String,
        windows: [CodexUsageWindow]
    ) -> CodexUsageSettingsDisplay.Row {
        guard let window = windows.first(where: { $0.duration == duration }) else {
            return .needsReview(
                label: label,
                guidance: "This expected Codex window was not reported. Review usage before relying on it."
            )
        }
        return usageRow(window, label: label)
    }

    private func usageRow(_ window: CodexUsageWindow, label: String) -> CodexUsageSettingsDisplay.Row {
        .usage(
            label: label,
            usedPercent: window.usedPercent,
            remainingPercent: window.remainingPercent,
            reset: dateText(window.resetsAt),
            severity: severityLabel(window.severity),
            guidance: guidance(window)
        )
    }

    private func reviewRow(
        _ window: CodexUsageWindow,
        label: String,
        guidance: String
    ) -> CodexUsageSettingsDisplay.Row {
        .needsReview(
            label: label,
            usedPercent: window.usedPercent,
            remainingPercent: window.remainingPercent,
            reset: dateText(window.resetsAt),
            guidance: guidance
        )
    }

    private func planLabel(_ plan: String?) -> String {
        guard let plan, !plan.isEmpty else { return "Plan not reported" }
        let normalized = plan.lowercased().filter(\.isLetter)
        if normalized == "prolite" { return "Pro Lite" }
        return plan
    }

    private func safeDisplayName(_ displayName: String?, fallback: String) -> String {
        guard let displayName, !displayName.isEmpty else { return fallback }
        return displayName
    }

    private func windowLabel(_ duration: CodexUsageWindowDuration) -> String {
        switch duration {
        case .fiveHours: "5-hour limit"
        case .weekly: "Weekly limit"
        case .unknown: "Needs review"
        }
    }

    private func severityLabel(_ severity: CodexUsageSeverity) -> String {
        switch severity {
        case .normal: "Normal"
        case .watch: "Watch"
        case .warning: "Warning"
        case .high: "High"
        case .critical: "Critical"
        case .separate: "Separate"
        case .unknown: "Needs review"
        }
    }

    private func guidance(_ window: CodexUsageWindow) -> String {
        switch window.policyAction {
        case .pauseNonessentialSolCoding:
            "Pause nonessential Sol coding until this allowance resets."
        case .reserveSolForBlockersReviewLanding:
            "Reserve Sol for blockers, review, and landing work until this allowance resets."
        case .trackSeparatelyNotSolAuthorization:
            "Track this allowance separately. It does not authorize Sol coding."
        case .reviewUnknownWindow, .reviewUnknownBucket:
            reviewGuidance(for: window)
        case .continue:
            switch window.severity {
            case .normal:
                "Usage is in a comfortable range. Continue normally."
            case .watch:
                "Weekly usage is building. Keep an eye on remaining allowance."
            case .warning:
                "Usage is elevated. Keep nonessential Sol work brief."
            case .high:
                "Usage is high. Limit Sol work to what matters most."
            case .critical:
                "Usage is near the limit. Reserve Sol for essential work."
            case .separate:
                "Track this allowance separately. It does not authorize Sol coding."
            case .unknown:
                reviewGuidance(for: window)
            }
        }
    }

    private func reviewGuidance(for window: CodexUsageWindow) -> String {
        switch window.reviewState {
        case .unknownBucket:
            "This allowance is not recognized yet. Review it before relying on it."
        case .unknownWindow:
            "This time window is not recognized yet. Review it before relying on it."
        case .recognized:
            "Review this allowance before relying on it."
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
}
