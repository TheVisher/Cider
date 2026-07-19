import Cider
import Darwin
import Foundation

@main
@MainActor
struct CiderDatabaseMaintenanceMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let json = arguments.contains("--json")
        guard arguments.first == "restore",
              let backupPath = flag("--backup", in: arguments),
              let databasePath = flag("--database", in: arguments) else {
            fail(
                "Usage: cider-db-maintenance restore --backup <current-v2.ciderbackup> --database <existing.db> [--json]",
                json: json
            )
        }
        let timeout = flag("--lock-timeout", in: arguments).flatMap(TimeInterval.init) ?? 5
        do {
            let receipt = try OfflineDatabaseRestoreRunner.restore(
                backupURL: URL(fileURLWithPath: backupPath),
                databaseURL: URL(fileURLWithPath: databasePath),
                lockTimeout: timeout
            )
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(receipt))
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print("Restored SQLite database from \(URL(fileURLWithPath: receipt.backupPath).lastPathComponent).")
                print("Pre-restore rollback: \(receipt.rollbackPath)")
                print("Integrity, exact logical NEW, WAL mode, and a rollback-capable write all passed.")
                print("Receipt: \(receipt.receiptPath)")
            }
        } catch let failure as OfflineDatabaseRestoreFailure {
            fail(failure.receipt, json: json)
        } catch {
            fail(error.localizedDescription, json: json)
        }
    }

    private static func flag(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func fail(_ message: String, json: Bool) -> Never {
        if json {
            let payload: [String: Any] = [
                "ok": false,
                "changed": false,
                "classification": "unknown",
                "command": "db.restore",
                "error": message,
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        }
        Darwin.exit(1)
    }

    private static func fail(
        _ receipt: OfflineDatabaseRestoreFailureReceipt,
        json: Bool
    ) -> Never {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(receipt) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            let changed = receipt.changed.map(String.init) ?? "unknown"
            FileHandle.standardError.write(
                Data(
                    "Error: \(receipt.error)\nState: \(receipt.classification.rawValue); changed: \(changed)\n".utf8
                )
            )
        }
        Darwin.exit(1)
    }
}
