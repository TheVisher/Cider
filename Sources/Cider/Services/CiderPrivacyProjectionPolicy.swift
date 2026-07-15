import Foundation

enum CiderPrivacyProjectionContext: String, CaseIterable, Sendable {
    case systemLog = "system_log"
    case userFacingDiagnostic = "user_facing_diagnostic"
    case cliDefault = "cli_default"
    case portableExport = "portable_export"
    case trustedLocal = "trusted_local"
}

struct CiderCaptureProvenanceProjectionDecision: Equatable, Sendable {
    let projection: String
    let containsPrivateData: Bool
    let includesRawPrivateValues: Bool
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
        case .cliDefault, .portableExport:
            return "[\(value.kind.rawValue) omitted]"
        case .trustedLocal:
            return value.rawValue
        }
    }

    /// Capture provenance fails closed everywhere except an explicit trusted-local
    /// projection selected by the direct CLI command handling the request.
    static func captureProvenanceDecision(
        for context: CiderPrivacyProjectionContext
    ) -> CiderCaptureProvenanceProjectionDecision {
        switch context {
        case .trustedLocal:
            return CiderCaptureProvenanceProjectionDecision(
                projection: CiderPrivacyProjectionContext.trustedLocal.rawValue,
                containsPrivateData: true,
                includesRawPrivateValues: true
            )
        case .portableExport:
            return CiderCaptureProvenanceProjectionDecision(
                projection: CiderPrivacyProjectionContext.portableExport.rawValue,
                containsPrivateData: false,
                includesRawPrivateValues: false
            )
        case .cliDefault, .systemLog, .userFacingDiagnostic:
            return CiderCaptureProvenanceProjectionDecision(
                projection: CiderPrivacyProjectionContext.cliDefault.rawValue,
                containsPrivateData: false,
                includesRawPrivateValues: false
            )
        }
    }

    static func safeProvenanceCategory(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = normalizedProjectionToken(rawValue)
        let knownCategories: Set<String> = [
            "active_browser", "ai_assistant", "capture_add", "chat", "cider", "cider_cli", "cli", "discord",
            "drop_zone", "imessage", "local", "macos_services", "mlx_tool", "note",
            "pasteboard", "screen_capture", "system", "telegram", "url_drop", "user",
        ]
        guard knownCategories.contains(normalized) else { return "other" }
        return normalized
    }

    static func safeProvenanceMetadataKeys<S: Sequence>(_ rawKeys: S) -> [String]
    where S.Element == String {
        let knownKeys: Set<String> = [
            "attachment_kind", "capture_method", "content_type", "format", "origin",
            "provider", "route", "source", "source_kind", "surface", "transport",
        ]
        return Array(Set(rawKeys.map { rawKey in
            let normalized = normalizedProjectionToken(rawKey)
            return knownKeys.contains(normalized) ? normalized : "other"
        })).sorted()
    }

    private static func normalizedProjectionToken(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber || character == "_" ? character : "_"
            }
            .reduce(into: "") { result, character in
                if character != "_" || result.last != "_" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func systemLogMessage(for event: CiderPrivacySafeEvent) -> String {
        event.rawValue
    }
}
