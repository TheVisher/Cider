import Foundation

/// Errors thrown by CiderDatabase operations.
enum CiderDatabaseError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)
    case runExec(String)

    var errorDescription: String? {
        switch self {
        case .open(let msg): "Failed to open database: \(msg)"
        case .prepare(let msg): "Failed to prepare statement: \(msg)"
        case .step(let msg): "Failed to step statement: \(msg)"
        case .runExec(let msg): "Failed to run SQL: \(msg)"
        }
    }
}
