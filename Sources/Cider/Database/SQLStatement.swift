import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy the bound string immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Lightweight wrapper around a SQLite3 prepared statement.
/// Provides type-safe bind and column accessors. Finalizes on deinit.
final class SQLStatement {
    private let stmt: OpaquePointer

    init(_ stmt: OpaquePointer) {
        self.stmt = stmt
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    // MARK: - Bind

    /// Bind a String value (or NULL if nil) at the given 1-based index.
    @discardableResult
    func bind(_ value: String?, at index: Int32) -> Self {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
        return self
    }

    /// Bind an Int64 value at the given 1-based index.
    @discardableResult
    func bind(_ value: Int64, at index: Int32) -> Self {
        sqlite3_bind_int64(stmt, index, value)
        return self
    }

    /// Bind a Double value at the given 1-based index.
    @discardableResult
    func bind(_ value: Double, at index: Int32) -> Self {
        sqlite3_bind_double(stmt, index, value)
        return self
    }

    /// Bind an Int value at the given 1-based index.
    @discardableResult
    func bind(_ value: Int, at index: Int32) -> Self {
        sqlite3_bind_int64(stmt, index, Int64(value))
        return self
    }

    /// Bind a Double? value (or NULL if nil) at the given 1-based index.
    @discardableResult
    func bind(_ value: Double?, at index: Int32) -> Self {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
        return self
    }

    /// Bind an Int64? value (or NULL if nil) at the given 1-based index.
    @discardableResult
    func bind(_ value: Int64?, at index: Int32) -> Self {
        if let value {
            sqlite3_bind_int64(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
        return self
    }

    // MARK: - Step

    /// Execute one step. Returns `true` if there is a row (SQLITE_ROW),
    /// `false` if done (SQLITE_DONE). Throws on error.
    @discardableResult
    func step() throws -> Bool {
        let result = sqlite3_step(stmt)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            let db = sqlite3_db_handle(stmt)
            let message = String(cString: sqlite3_errmsg(db))
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                throw CiderDatabaseError.busy(message)
            }
            throw CiderDatabaseError.step(message)
        }
    }

    /// Reset the statement so it can be re-executed with new bindings.
    func reset() {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    // MARK: - Column Accessors (non-nil)

    /// Read a non-nil String from the given 0-based column index.
    func string(at index: Int32) -> String {
        if let cStr = sqlite3_column_text(stmt, index) {
            return String(cString: cStr)
        }
        return ""
    }

    /// Read a Double from the given 0-based column index.
    func double(at index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    /// Read an Int from the given 0-based column index.
    func int(at index: Int32) -> Int {
        Int(sqlite3_column_int(stmt, index))
    }

    /// Read an Int64 from the given 0-based column index.
    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    /// Read a Bool from the given 0-based column index (0 = false, else true).
    func bool(at index: Int32) -> Bool {
        sqlite3_column_int(stmt, index) != 0
    }

    // MARK: - Column Accessors (nullable)

    /// Read an optional String from the given 0-based column index.
    func optionalString(at index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return string(at: index)
    }

    /// Read an optional Double from the given 0-based column index.
    func optionalDouble(at index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return double(at: index)
    }

    /// Read an optional Int from the given 0-based column index.
    func optionalInt(at index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return int(at: index)
    }

    /// Read an optional Int64 from the given 0-based column index.
    func optionalInt64(at index: Int32) -> Int64? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return int64(at: index)
    }

    /// Read an optional Bool from the given 0-based column index.
    func optionalBool(at index: Int32) -> Bool? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return bool(at: index)
    }
}
