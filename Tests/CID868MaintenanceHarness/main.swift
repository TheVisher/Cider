@testable import Cider
import Darwin
import Foundation

@main
@MainActor
struct CID868MaintenanceHarness {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let mode = arguments.first,
              let databasePath = flag("--database", in: arguments) else {
            Darwin.exit(64)
        }
        let databaseURL = URL(fileURLWithPath: databasePath)
        switch mode {
        case "hold-open":
            guard let readyPath = flag("--ready", in: arguments) else { Darwin.exit(64) }
            let database = CiderDatabase()
            try database.open(at: databaseURL)
            try Data("ready".utf8).write(to: URL(fileURLWithPath: readyPath))
            while true { pause() }

        case "hold-open-statement":
            guard let readyPath = flag("--ready", in: arguments) else { Darwin.exit(64) }
            let database = CiderDatabase()
            try database.open(at: databaseURL)
            let statement = try database.prepare("SELECT 1;")
            database.close()
            withExtendedLifetime(statement) {
                try? Data("ready".utf8).write(to: URL(fileURLWithPath: readyPath))
                while true { pause() }
            }

        case "hold-exclusive":
            guard let readyPath = flag("--ready", in: arguments) else { Darwin.exit(64) }
            let ownership = try DatabaseStartupLock.acquireMaintenanceExclusive(
                for: databaseURL,
                timeout: 1
            )
            try Data("ready".utf8).write(to: URL(fileURLWithPath: readyPath))
            withExtendedLifetime(ownership) {
                while true { pause() }
            }

        case "open-once":
            let database = CiderDatabase()
            try database.open(at: databaseURL)
            database.close()

        case "wal-crash":
            let database = CiderDatabase()
            try database.open(at: databaseURL)
            try database.runSQL("PRAGMA wal_autocheckpoint=0;")
            try database.runSQL("UPDATE projects SET title = 'OLD-WAL' WHERE id = 'cid868-state';")
            kill(getpid(), SIGKILL)
            Darwin.exit(70)

        default:
            Darwin.exit(64)
        }
    }

    private static func flag(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
