import Foundation

enum CiderDatabasePreflightFailureKind: String, Equatable {
    case unreadable
    case malformed
    case unhealthy
    case changedDuringRead
    case concurrentStartup
}

/// Errors thrown by CiderDatabase operations.
enum CiderDatabaseError: Error, LocalizedError {
    case open(String)
    case alreadyOpen(String)
    case prepare(String)
    case step(String)
    case runExec(String)
    case busy(String)
    case immediateTransactionRequiresImmediateRoot
    case transactionState(String)
    case schemaTooNew(current: Int, supported: Int)
    case startupPreflightFailed(kind: CiderDatabasePreflightFailureKind, detail: String)
    case migrationSafetyArtifactCaptureFailed(detail: String)
    case migrationSafetyArtifactVerificationFailed(detail: String)
    case migrationFailed(artifactURL: URL, detail: String)
    case postOpenValidationFailed(messages: [String])

    var isBusyConflict: Bool {
        if case .busy = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .open(let msg): "Failed to open database: \(msg)"
        case .alreadyOpen(let msg): "Database already open: \(msg)"
        case .prepare(let msg): "Failed to prepare statement: \(msg)"
        case .step(let msg): "Failed to step statement: \(msg)"
        case .runExec(let msg): "Failed to run SQL: \(msg)"
        case .busy(let msg): "Database is busy: \(msg)"
        case .immediateTransactionRequiresImmediateRoot:
            "An immediate transaction cannot be nested inside a deferred transaction because SQLite cannot upgrade the root transaction's writer reservation."
        case .transactionState(let msg): "Invalid database transaction state: \(msg)"
        case .schemaTooNew(let current, let supported):
            "Database schema version \(current) is newer than this build supports (max \(supported)). Upgrade the app or restore a compatible backup."
        case .startupPreflightFailed(let kind, let detail):
            "Database startup preflight failed (\(kind.rawValue)): \(detail) No startup writes were attempted."
        case .migrationSafetyArtifactCaptureFailed(let detail):
            "Database migration was refused because its mandatory safety artifact could not be captured: \(detail)"
        case .migrationSafetyArtifactVerificationFailed(let detail):
            "Database migration was refused because its mandatory safety artifact could not be verified: \(detail)"
        case .migrationFailed(_, let detail):
            "Database migration failed and was rolled back. The verified pre-migration artifact was retained in private migration-safety storage. \(detail)"
        case .postOpenValidationFailed(let messages):
            "Database post-open validation failed: \(messages.joined(separator: " | "))"
        }
    }
}
