import Foundation

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
        }
    }
}
