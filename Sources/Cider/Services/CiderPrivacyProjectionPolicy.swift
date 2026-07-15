import Foundation

enum CiderPrivacyProjectionContext: String, CaseIterable, Sendable {
    case systemLog = "system_log"
    case userFacingDiagnostic = "user_facing_diagnostic"
}

struct CiderPrivateValue: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case browserURL = "browser_url"
        case localPath = "local_path"
        case sourceText = "source_text"
        case senderIdentity = "sender_identity"
        case processStandardError = "process_stderr"
        case diagnosticDetail = "diagnostic_detail"
    }

    let kind: Kind
    let rawValue: String
}

enum CiderPrivacySafeEvent: String, Sendable {
    case browserCaptureSucceeded = "browser_capture_succeeded"
}

/// Projects private runtime values at outward boundaries without changing the
/// canonical value held by the owning feature or persistence layer.
enum CiderPrivacyProjectionPolicy {
    static func project(
        _ value: CiderPrivateValue,
        for context: CiderPrivacyProjectionContext
    ) -> String {
        switch context {
        case .systemLog:
            return "<private:\(value.kind.rawValue)>"
        case .userFacingDiagnostic:
            return "[\(value.kind.rawValue) omitted]"
        }
    }

    static func systemLogMessage(for event: CiderPrivacySafeEvent) -> String {
        event.rawValue
    }
}
