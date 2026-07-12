import Foundation

enum CodexUsageSchemaVersion: String, Sendable, Equatable {
    case v1 = "cider.codex-usage-monitor.v1"
}

enum CodexUsageBucketKind: String, Sendable, Equatable {
    case codex
    case spark
    case unknownRequiresReview
}

enum CodexUsageWindowDuration: Sendable, Equatable, Hashable {
    case fiveHours
    case weekly
    case unknown(minutes: Int)

    var minutes: Int {
        switch self {
        case .fiveHours: 300
        case .weekly: 10_080
        case .unknown(let minutes): minutes
        }
    }
}

enum CodexUsageSeverity: String, Sendable, Equatable {
    case normal, watch, warning, high, critical, separate, unknown
}

enum CodexUsagePolicyAction: String, Sendable, Equatable {
    case `continue`
    case pauseNonessentialSolCoding = "pause_nonessential_sol_coding"
    case reserveSolForBlockersReviewLanding = "reserve_sol_for_blockers_review_landing"
    case trackSeparatelyNotSolAuthorization = "track_separately_not_sol_authorization"
    case reviewUnknownWindow = "review_unknown_window"
    case reviewUnknownBucket = "review_unknown_bucket"
}

enum CodexUsageReviewState: Sendable, Equatable {
    case recognized
    case unknownWindow
    case unknownBucket
}

struct CodexUsageWindow: Sendable, Equatable {
    let duration: CodexUsageWindowDuration
    let usedPercent: Int
    let remainingPercent: Int
    let resetsAt: Date
    let severity: CodexUsageSeverity
    let policyAction: CodexUsagePolicyAction
    let reachedReason: String?
    let reviewState: CodexUsageReviewState
}

struct CodexUsageBucket: Sendable, Equatable {
    let publicLimitID: String
    let publicDisplayName: String?
    let kind: CodexUsageBucketKind
    let windows: [CodexUsageWindow]
}

struct CodexUsageSnapshot: Sendable, Equatable {
    let schemaVersion: CodexUsageSchemaVersion
    let accountType: String
    let planType: String?
    let retrievedAt: Date
    let buckets: [CodexUsageBucket]
}

/// The only model intended for a future Settings surface. It deliberately has no
/// process, path, byte-buffer, diagnostic, identity, token, or credit fields.
struct CodexUsagePresentation: Sendable, Equatable {
    struct Bucket: Sendable, Equatable {
        let limitID: String
        let displayName: String?
        let kind: CodexUsageBucketKind
        let windows: [CodexUsageWindow]
    }

    let accountType: String
    let planType: String?
    let retrievedAt: Date
    let buckets: [Bucket]

    init(snapshot: CodexUsageSnapshot) {
        accountType = snapshot.accountType
        planType = snapshot.planType
        retrievedAt = snapshot.retrievedAt
        buckets = snapshot.buckets.map {
            Bucket(limitID: $0.publicLimitID, displayName: $0.publicDisplayName, kind: $0.kind, windows: $0.windows)
        }
    }
}

enum CodexUsageFailure: Error, Sendable, Equatable, LocalizedError, CustomStringConvertible {
    case unavailable
    case timeout
    case processFailure
    case malformedResponse
    case unsupportedResponse
    case cancelled

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .unavailable: "Usage information is unavailable."
        case .timeout: "The usage check timed out."
        case .processFailure: "The usage check could not be completed."
        case .malformedResponse: "The usage response was invalid."
        case .unsupportedResponse: "This usage response version is not supported."
        case .cancelled: "The usage check was cancelled."
        }
    }
}

struct CodexUsageResponseDecoder: Sendable {
    private struct Report: Decodable {
        let schemaVersion: String
        let accountType: String
        let planType: String?
        let retrievedAt: String
        let buckets: [Bucket]
    }

    private struct Bucket: Decodable {
        let limitId: String
        let displayName: String?
        let unknownReason: String?
        let windows: [Window]
    }

    private struct Window: Decodable {
        let windowDurationMins: Int
        let usedPercent: Int
        let remainingPercent: Int
        let resetsAt: Int64
        let resetsAtLocal: String
        let reachedReason: String?
        let severity: String
        let policyAction: String
        let unknownReason: String?
    }

    func decode(_ data: Data) throws -> CodexUsageSnapshot {
        let report: Report
        do {
            report = try JSONDecoder().decode(Report.self, from: data)
        } catch {
            throw CodexUsageFailure.malformedResponse
        }

        guard report.schemaVersion == CodexUsageSchemaVersion.v1.rawValue else {
            throw CodexUsageFailure.unsupportedResponse
        }
        guard Self.isSafeLabel(report.accountType), report.planType.map(Self.isSafeLabel) ?? true,
              let retrievedAt = Self.date(report.retrievedAt), !report.buckets.isEmpty else {
            throw CodexUsageFailure.malformedResponse
        }

        var seenBucketIDs = Set<String>()
        var buckets: [CodexUsageBucket] = []
        for rawBucket in report.buckets {
            guard Self.isSafeIdentifier(rawBucket.limitId),
                  rawBucket.displayName.map(Self.isSafeDisplayName) ?? true,
                  !rawBucket.windows.isEmpty,
                  seenBucketIDs.insert(rawBucket.limitId.lowercased()).inserted else {
                throw CodexUsageFailure.malformedResponse
            }

            let kind = try Self.bucketKind(rawBucket)
            var seenDurations = Set<Int>()
            var windows: [CodexUsageWindow] = []
            for rawWindow in rawBucket.windows {
                guard rawWindow.windowDurationMins > 0,
                      seenDurations.insert(rawWindow.windowDurationMins).inserted,
                      (0...100).contains(rawWindow.usedPercent),
                      (0...100).contains(rawWindow.remainingPercent),
                      rawWindow.usedPercent + rawWindow.remainingPercent == 100,
                      rawWindow.resetsAt > 0,
                      let localReset = Self.date(rawWindow.resetsAtLocal),
                      abs(localReset.timeIntervalSince1970 - Double(rawWindow.resetsAt)) < 1,
                      rawWindow.reachedReason.map(Self.isSafeIdentifier) ?? true,
                      let severity = CodexUsageSeverity(rawValue: rawWindow.severity),
                      let action = CodexUsagePolicyAction(rawValue: rawWindow.policyAction) else {
                    throw CodexUsageFailure.malformedResponse
                }

                let duration: CodexUsageWindowDuration = switch rawWindow.windowDurationMins {
                case 300: .fiveHours
                case 10_080: .weekly
                default: .unknown(minutes: rawWindow.windowDurationMins)
                }
                let reviewState = try Self.validateSemantics(
                    kind: kind,
                    duration: duration,
                    used: rawWindow.usedPercent,
                    reset: localReset,
                    retrievedAt: retrievedAt,
                    severity: severity,
                    action: action,
                    unknownReason: rawWindow.unknownReason
                )
                windows.append(CodexUsageWindow(
                    duration: duration,
                    usedPercent: rawWindow.usedPercent,
                    remainingPercent: rawWindow.remainingPercent,
                    resetsAt: localReset,
                    severity: severity,
                    policyAction: action,
                    reachedReason: rawWindow.reachedReason,
                    reviewState: reviewState
                ))
            }
            buckets.append(CodexUsageBucket(
                publicLimitID: rawBucket.limitId,
                publicDisplayName: rawBucket.displayName,
                kind: kind,
                windows: windows
            ))
        }

        return CodexUsageSnapshot(
            schemaVersion: .v1,
            accountType: report.accountType,
            planType: report.planType,
            retrievedAt: retrievedAt,
            buckets: buckets
        )
    }

    private static func bucketKind(_ bucket: Bucket) throws -> CodexUsageBucketKind {
        if let reason = bucket.unknownReason {
            guard reason == "unrecognized_limit_id" else { throw CodexUsageFailure.malformedResponse }
            return .unknownRequiresReview
        }
        let pairs = bucket.windows.map { ($0.severity, $0.policyAction) }
        if pairs.allSatisfy({ $0 == ("separate", "track_separately_not_sol_authorization") }) {
            return .spark
        }
        if pairs.contains(where: { $0 == ("separate", "track_separately_not_sol_authorization") }) {
            throw CodexUsageFailure.malformedResponse
        }
        return .codex
    }

    private static func validateSemantics(
        kind: CodexUsageBucketKind,
        duration: CodexUsageWindowDuration,
        used: Int,
        reset: Date,
        retrievedAt: Date,
        severity: CodexUsageSeverity,
        action: CodexUsagePolicyAction,
        unknownReason: String?
    ) throws -> CodexUsageReviewState {
        switch kind {
        case .unknownRequiresReview:
            guard severity == .unknown, action == .reviewUnknownBucket else { throw CodexUsageFailure.malformedResponse }
            if case .unknown = duration {
                guard unknownReason == "unrecognized_window_duration" else { throw CodexUsageFailure.malformedResponse }
            } else if unknownReason != nil {
                throw CodexUsageFailure.malformedResponse
            }
            return .unknownBucket
        case .spark:
            guard severity == .separate, action == .trackSeparatelyNotSolAuthorization else { throw CodexUsageFailure.malformedResponse }
            if case .unknown = duration {
                guard unknownReason == "unrecognized_window_duration" else { throw CodexUsageFailure.malformedResponse }
                return .unknownWindow
            }
            guard unknownReason == nil else { throw CodexUsageFailure.malformedResponse }
            return .recognized
        case .codex:
            if case .unknown = duration {
                guard unknownReason == "unrecognized_window_duration", severity == .unknown, action == .reviewUnknownWindow else {
                    throw CodexUsageFailure.malformedResponse
                }
                return .unknownWindow
            }
            guard unknownReason == nil else { throw CodexUsageFailure.malformedResponse }
            let expectedSeverity: CodexUsageSeverity
            let expectedAction: CodexUsagePolicyAction
            switch duration {
            case .fiveHours:
                expectedSeverity = used >= 95 ? .critical : used >= 85 ? .high : used >= 70 ? .warning : .normal
                expectedAction = .continue
            case .weekly:
                expectedSeverity = used >= 92 ? .critical : used >= 85 ? .high : used >= 75 ? .warning : used >= 60 ? .watch : .normal
                let remaining = 100 - used
                expectedAction = remaining < 8
                    ? .reserveSolForBlockersReviewLanding
                    : remaining < 15 && reset.timeIntervalSince(retrievedAt) > 86_400
                        ? .pauseNonessentialSolCoding
                        : .continue
            case .unknown:
                throw CodexUsageFailure.malformedResponse
            }
            guard severity == expectedSeverity, action == expectedAction else { throw CodexUsageFailure.malformedResponse }
            return .recognized
        }
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func isSafeLabel(_ value: String) -> Bool {
        isBoundedASCII(value, pattern: #"[A-Za-z0-9][A-Za-z0-9 ._+()/:-]{0,79}"#)
    }

    private static func isSafeDisplayName(_ value: String) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines) && isSafeLabel(value)
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        isBoundedASCII(value, pattern: #"[A-Za-z0-9][A-Za-z0-9._:/+() -]{0,79}"#)
    }

    private static func isBoundedASCII(_ value: String, pattern: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 80, value.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        return value.range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
    }
}
