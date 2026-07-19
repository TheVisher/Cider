import Darwin
import Foundation
import SQLite3
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("CID-868 offline database maintenance restore", .serialized)
@MainActor
struct DatabaseOfflineMaintenanceRestoreTests {
    @Test("production restore sources contain no test-only behavior seams")
    func productionRestoreSourcesContainNoTestingSeams() throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sources = repository.appendingPathComponent("Sources", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let swiftFiles = enumerator.compactMap { element -> URL? in
            guard let url = element as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
        #expect(!swiftFiles.isEmpty)
        let relativePaths = Set(swiftFiles.map {
            $0.path.replacingOccurrences(of: sources.path + "/", with: "")
        })
        #expect(relativePaths.contains("Cider/Database/CiderDatabase.swift"))
        #expect(relativePaths.contains("Cider/Database/OfflineDatabaseRestore.swift"))
        #expect(relativePaths.contains("Cider/Database/DatabaseStartupPreflight.swift"))
        #expect(relativePaths.contains("CiderDatabaseMaintenance/main.swift"))
        #expect(relativePaths.contains("CiderCLI/CiderCLI.swift"))

        let forbidden = [
            "initializationObserverForTesting",
            "OfflineDatabaseRestoreHooks",
            "OfflineDatabaseRestoreBoundary",
            "OfflineDatabaseRestoreFault",
            "interruptedClassificationForTesting",
            "Injected terminal",
            "Injected sqlite3",
            "Injected verified source",
            "Injected existing destination",
            "CID868_INTERPOSE",
            "restoreCheckpoint",
            "restoreFault",
        ]
        let productionText = try swiftFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for token in forbidden {
            #expect(!productionText.contains(token), "shipping Sources/Cider contains forbidden test seam: \(token)")
        }
        print("CID868_SOURCE_SHAPE swiftFiles=\(swiftFiles.count) knownOwners=5 forbidden=\(forbidden.count)")
    }

    @Test("ordinary database ownership blocks exclusive maintenance until close")
    func ordinaryDatabaseLifetimeOwnsSharedMaintenanceLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)

        #expect(throws: (any Error).self) {
            _ = try DatabaseStartupLock.acquireMaintenanceExclusive(
                for: fixture.databaseURL,
                timeout: 0.1
            )
        }

        database.close()
        let maintenance = try DatabaseStartupLock.acquireMaintenanceExclusive(
            for: fixture.databaseURL,
            timeout: 0.1
        )
        maintenance.release()

        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        #expect(try reopened.integrityCheck().isHealthy)
        reopened.close()
    }

    @Test("prepared statements retain ordinary ownership through sqlite3_close_v2")
    func outstandingStatementRetainsSharedMaintenanceLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        var statement: SQLStatement? = try database.prepare("SELECT 1;")
        #expect(statement != nil)
        database.close()

        #expect(throws: (any Error).self) {
            _ = try DatabaseStartupLock.acquireMaintenanceExclusive(
                for: fixture.databaseURL,
                timeout: 0.1
            )
        }
        statement = nil
        let maintenance = try DatabaseStartupLock.acquireMaintenanceExclusive(
            for: fixture.databaseURL,
            timeout: 0.1
        )
        maintenance.release()
    }

    @Test("multiple ordinary handles coexist under shared maintenance ownership")
    func multipleOrdinaryHandlesCanOpenTogether() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = CiderDatabase()
        let second = CiderDatabase()
        try first.open(at: fixture.databaseURL)
        try second.open(at: fixture.databaseURL)
        #expect(try first.integrityCheck().isHealthy)
        #expect(try second.integrityCheck().isHealthy)
        first.close()
        #expect(throws: (any Error).self) {
            _ = try DatabaseStartupLock.acquireMaintenanceExclusive(
                for: fixture.databaseURL,
                timeout: 0.1
            )
        }
        second.close()
    }

    @Test("offline restore does not initialize a normal CiderDatabase")
    func offlineRestoreDoesNotInitializeNormalDatabase() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()

        let helperSource = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/CiderDatabaseMaintenance/main.swift"),
            encoding: .utf8
        )
        #expect(!helperSource.contains("CiderDatabase.shared"))
        #expect(!helperSource.contains("CiderDatabase()"))
        let result = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
        #expect(result.status == 0)
        let receipt = try JSONDecoder().decode(
            OfflineDatabaseRestoreReceipt.self,
            from: Data(result.output.utf8)
        )
        #expect(receipt.changed)
        #expect(receipt.classification == .new)
        #expect(receipt.integrity.isHealthy)
        try fixture.expectNewAndWritable()
        try fixture.expectRollbackIsExactOld(at: URL(fileURLWithPath: receipt.rollbackPath))
    }

    @Test("pre-restore rollback includes committed content left in an active WAL")
    func rollbackCapturesActiveWALContent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()
        let process = Process()
        process.executableURL = try executable(named: "CID868MaintenanceHarness")
        process.arguments = ["wal-crash", "--database", fixture.databaseURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
        let walURL = URL(fileURLWithPath: fixture.databaseURL.path + "-wal")
        let walSize = (try FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(walSize > 0)

        let receipt = try OfflineDatabaseRestoreRunner.restore(
            backupURL: backupURL,
            databaseURL: fixture.databaseURL,
            lockTimeout: 0.5
        )
        try fixture.expectRollbackIsExactOld(
            at: URL(fileURLWithPath: receipt.rollbackPath),
            expectedTitle: "OLD-WAL"
        )
        try fixture.expectNewAndWritable()
    }

    @Test("moved, replaced, and non-v2 sources are rejected before destination mutation")
    func ineligibleSourcesFailBeforeDestinationMutation() throws {
        let movedFixture = try Fixture()
        defer { movedFixture.remove() }
        let originalURL = try movedFixture.prepareRestore()
        let movedURL = movedFixture.rootURL.appendingPathComponent("moved.ciderbackup")
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        #expect(throws: (any Error).self) {
            _ = try OfflineDatabaseRestoreRunner.restore(
                backupURL: originalURL,
                databaseURL: movedFixture.databaseURL,
                lockTimeout: 0.2
            )
        }
        #expect(try movedFixture.stateTitle() == "OLD")

        let rawFixture = try Fixture()
        defer { rawFixture.remove() }
        let packageURL = try rawFixture.prepareRestore()
        let rawURL = packageURL.appendingPathComponent("database.sqlite")
        #expect(throws: (any Error).self) {
            _ = try OfflineDatabaseRestoreRunner.restore(
                backupURL: rawURL,
                databaseURL: rawFixture.databaseURL,
                lockTimeout: 0.2
            )
        }
        #expect(try rawFixture.stateTitle() == "OLD")
        let rawHelper = Process()
        let rawOutput = Pipe()
        rawHelper.executableURL = try executable(named: "cider-db-maintenance")
        rawHelper.arguments = [
            "restore", "--backup", rawURL.path,
            "--database", rawFixture.databaseURL.path,
            "--lock-timeout", "0.2", "--json",
        ]
        rawHelper.standardOutput = rawOutput
        rawHelper.standardError = rawOutput
        try rawHelper.run()
        rawHelper.waitUntilExit()
        let rawText = String(
            decoding: rawOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(rawHelper.terminationStatus != 0)
        let rawFailure = try decodeFailure(rawText)
        #expect(!rawFailure.ok)
        #expect(rawFailure.changed == false)
        #expect(rawFailure.classification == .old)
        #expect(try rawFixture.stateTitle() == "OLD")

        let replacedFixture = try Fixture()
        defer { replacedFixture.remove() }
        let replaceURL = try replacedFixture.prepareRestore()
        let heldURL = replacedFixture.rootURL.appendingPathComponent("held-source.ciderbackup")
        let paused = try startInterposedHelper(
            backupURL: replaceURL,
            fixture: replacedFixture,
            boundary: "beforeIntentPublication",
            action: "pause"
        )
        try waitForFile(paused.markerURL)
        try FileManager.default.moveItem(at: replaceURL, to: heldURL)
        kill(paused.process.processIdentifier, SIGCONT)
        let replaced = try finish(paused)
        #expect(replaced.status != 0)
        let failure = try decodeFailure(replaced.output)
        #expect(failure.changed == false)
        #expect(failure.classification == .old)
        #expect(try replacedFixture.stateTitle() == "OLD")
    }

    @Test("a separate ordinary Cider process blocks the production maintenance helper")
    func separateProcessSharedOwnerBlocksMaintenance() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()
        let readyURL = fixture.rootURL.appendingPathComponent("holder.ready")
        let holder = Process()
        holder.executableURL = try executable(named: "CID868MaintenanceHarness")
        holder.arguments = [
            "hold-open", "--database", fixture.databaseURL.path, "--ready", readyURL.path,
        ]
        holder.standardOutput = FileHandle.nullDevice
        holder.standardError = FileHandle.nullDevice
        try holder.run()
        defer {
            if holder.isRunning { holder.terminate() }
            holder.waitUntilExit()
        }
        try waitForFile(readyURL)

        let helper = Process()
        let output = Pipe()
        helper.executableURL = try executable(named: "cider-db-maintenance")
        helper.arguments = [
            "restore", "--backup", backupURL.path,
            "--database", fixture.databaseURL.path,
            "--lock-timeout", "0.1", "--json",
        ]
        helper.standardOutput = output
        helper.standardError = output
        try helper.run()
        helper.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(helper.terminationStatus != 0)
        let blockedFailure = try decodeFailure(text)
        #expect(blockedFailure.changed == false)
        #expect(blockedFailure.classification == .unknown)
        #expect(try fixture.stateTitle() == "OLD")
        #expect(!FileManager.default.fileExists(
            atPath: fixture.rootURL.appendingPathComponent("backups/sqlite/maintenance").path
        ))

        holder.terminate()
        holder.waitUntilExit()
        let receipt = try OfflineDatabaseRestoreRunner.restore(
            backupURL: backupURL,
            databaseURL: fixture.databaseURL,
            lockTimeout: 0.5
        )
        #expect(receipt.ok)
        try fixture.expectNewAndWritable()
    }

    @Test("first-use evidence ancestry survives a crash and is rediscovered on restart")
    func firstUseEvidenceDirectoriesAreDurableAndDiscoverable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore(extraRows: 32)
        let maintenanceURL = fixture.rootURL.appendingPathComponent(
            "backups/sqlite/maintenance",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: maintenanceURL.path))
        let crashed = try runInterposedHelper(
            backupURL: backupURL,
            fixture: fixture,
            boundary: "beforeFirstBackupStep",
            action: "crash"
        )
        print("CID868_FIRST_USE_CRASH status=\(crashed.status) reason=\(crashed.reason.rawValue) output=\(crashed.output)")
        #expect(crashed.reason == .uncaughtSignal && crashed.status == SIGKILL)
        #expect(FileManager.default.fileExists(
            atPath: maintenanceURL.appendingPathComponent("active-restore-v1.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: maintenanceURL.appendingPathComponent("receipts", isDirectory: true).path
        ))
        #expect(try fixture.stateTitle() == "OLD")

        let resumed = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
        #expect(resumed.status == 0, "First-use resume failed: \(resumed.output)")
        let receipt = try JSONDecoder().decode(
            OfflineDatabaseRestoreReceipt.self,
            from: Data(resumed.output.utf8)
        )
        #expect(receipt.resumedInterruptedRestore)
        try fixture.expectNewAndWritable()
    }

    @Test("two-process shared and exclusive ownership remains symmetric and durable")
    func twoProcessOwnershipMatrix() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.prepareRestore()

        let first = try startHolder(mode: "hold-open", fixture: fixture, label: "first")
        defer { stop(first.process) }
        try waitForFile(first.readyURL)
        let lockName = try #require(
            FileManager.default.contentsOfDirectory(atPath: fixture.lockRegistryURL.path)
                .first(where: { $0.hasSuffix(".lock") })
        )
        let lockURL = fixture.lockRegistryURL.appendingPathComponent(lockName)
        let initialLockIdentity = try fileIdentity(lockURL)
        let second = try startHolder(mode: "hold-open", fixture: fixture, label: "second")
        defer { stop(second.process) }
        try waitForFile(second.readyURL)
        #expect(first.process.isRunning && second.process.isRunning)

        stop(first.process)
        stop(second.process)
        let exclusive = try startHolder(mode: "hold-exclusive", fixture: fixture, label: "exclusive")
        defer { stop(exclusive.process) }
        try waitForFile(exclusive.readyURL)
        let probe = Process()
        probe.executableURL = try executable(named: "CID868MaintenanceHarness")
        probe.arguments = ["open-once", "--database", fixture.databaseURL.path]
        probe.environment = ProcessInfo.processInfo.environment
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        try probe.run()
        probe.waitUntilExit()
        #expect(probe.terminationStatus != 0)

        stop(exclusive.process)
        let resumed = Process()
        resumed.executableURL = try executable(named: "CID868MaintenanceHarness")
        resumed.arguments = ["open-once", "--database", fixture.databaseURL.path]
        resumed.environment = ProcessInfo.processInfo.environment
        resumed.standardOutput = FileHandle.nullDevice
        resumed.standardError = FileHandle.nullDevice
        try resumed.run()
        resumed.waitUntilExit()
        #expect(resumed.terminationStatus == 0)
        #expect(try fileIdentity(lockURL) == initialLockIdentity)
    }

    @Test("separate-process outstanding statement and database leaf replacement cannot split ownership")
    func separateStatementAndLeafReplacementKeepSameLockAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()
        let holder = try startHolder(
            mode: "hold-open-statement",
            fixture: fixture,
            label: "statement"
        )
        defer { stop(holder.process) }
        try waitForFile(holder.readyURL)

        let heldDatabase = fixture.rootURL.appendingPathComponent("held-cider.db")
        try FileManager.default.moveItem(at: fixture.databaseURL, to: heldDatabase)
        try FileManager.default.createSymbolicLink(
            at: fixture.databaseURL,
            withDestinationURL: heldDatabase
        )
        let blocked = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
        #expect(blocked.status != 0)
        let failure = try decodeFailure(blocked.output)
        #expect(failure.changed == false)
        #expect(failure.classification == .unknown)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.rootURL.appendingPathComponent("backups/sqlite/maintenance").path
        ))
    }

    @Test("SwiftPM CLI and maintenance products are siblings and confirmed CLI restore uses the sibling")
    func swiftPMHelperSiblingLayoutAndConfirmedCLIFlow() throws {
        let cliURL = try executable(named: "cider-cli")
        let helperURL = try executable(named: "cider-db-maintenance")
        #expect(cliURL.deletingLastPathComponent() == helperURL.deletingLastPathComponent())

        let fixture = try Fixture(databaseRelativePath: "vault/.cider/cider.db")
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = cliURL
        process.arguments = [
            "--vault", fixture.rootURL.appendingPathComponent("vault").path,
            "db", "restore", backupURL.lastPathComponent, "--yes", "--json",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CIDER_DATABASE_MAINTENANCE_EXECUTABLE")
        environment["CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"] = fixture.lockRegistryURL.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        print(
            "CID868_CLI_SIBLING status=\(process.terminationStatus) "
                + "cli=\(cliURL.lastPathComponent) helper=\(helperURL.lastPathComponent)"
        )
        #expect(process.terminationStatus == 0, "CLI sibling restore failed: \(text) \(errorText)")
        #expect(text.contains("\"ok\" : true") || text.contains("\"ok\":true"))
        try fixture.expectNewAndWritable()
    }

    @Test("missing maintenance helper fails closed before restore")
    func missingHelperFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore()
        let prior = ProcessInfo.processInfo.environment[
            "CIDER_DATABASE_MAINTENANCE_EXECUTABLE"
        ]
        setenv(
            "CIDER_DATABASE_MAINTENANCE_EXECUTABLE",
            fixture.rootURL.appendingPathComponent("missing-helper").path,
            1
        )
        defer {
            if let prior {
                setenv("CIDER_DATABASE_MAINTENANCE_EXECUTABLE", prior, 1)
            } else {
                unsetenv("CIDER_DATABASE_MAINTENANCE_EXECUTABLE")
            }
        }
        #expect(throws: (any Error).self) {
            _ = try CiderCLI.runOfflineDatabaseMaintenanceRestore(
                backupURL: backupURL,
                databaseURL: fixture.databaseURL
            )
        }
        #expect(try fixture.stateTitle() == "OLD")
    }

    @Test("CLI propagates the helper's exact NEW-but-failed JSON and exit status")
    func cliPropagatesExactHelperFailureTruth() throws {
        let fixture = try Fixture(databaseRelativePath: "vault/.cider/cider.db")
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore(extraRows: 32)
        let cliURL = try executable(named: "cider-cli")
        let dylibURL = cliURL.deletingLastPathComponent()
            .appendingPathComponent("libCID850Interpose.dylib")
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = cliURL
        process.arguments = [
            "--vault", fixture.rootURL.appendingPathComponent("vault").path,
            "db", "restore", backupURL.lastPathComponent, "--yes", "--json",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CIDER_DATABASE_MAINTENANCE_EXECUTABLE")
        environment["CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"] = fixture.lockRegistryURL.path
        environment["DYLD_INSERT_LIBRARIES"] = dylibURL.path
        environment["CID868_INTERPOSE_BOUNDARY"] = "reopen"
        environment["CID868_INTERPOSE_ACTION"] = "fail"
        environment["CID868_INTERPOSE_DATABASE"] = fixture.databaseURL.path
        environment["CID868_INTERPOSE_MARKER"] = fixture.rootURL
            .appendingPathComponent("cli-new-failure.marker").path
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus != 0)
        let failure = try decodeFailure(text)
        #expect(!failure.ok)
        #expect(failure.changed == true)
        #expect(failure.classification == .new)
        #expect(failure.evidencePreserved)
        #expect(try fixture.stateTitle() == "NEW")
        let ordinary = CiderDatabase()
        #expect(throws: (any Error).self) { try ordinary.open(at: fixture.databaseURL) }

        let resumed = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
        #expect(resumed.status == 0)
        try fixture.expectNewAndWritable()
    }

    @Test("finite SIGKILL boundaries restart as exact OLD or NEW and converge to verified NEW")
    func finiteCrashBoundaryMatrix() throws {
        let cases: [(String, Int)] = [
            ("beforeIntentPublication", 1),
            ("beforeFirstBackupStep", 1),
            ("duringBackupSteps", 2),
            ("atSQLiteDone", 1),
            ("afterDestinationClose", 1),
            ("beforeTerminalVerification", 1),
            ("beforeReceiptPublication", 1),
            ("afterReceiptPublication", 1),
        ]
        var oldCount = 0
        var newCount = 0

        for (boundary, occurrence) in cases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let backupURL = try fixture.prepareRestore(extraRows: 700)
            let result = try runInterposedHelper(
                backupURL: backupURL,
                fixture: fixture,
                boundary: boundary,
                action: "crash",
                occurrence: occurrence
            )
            #expect(
                result.reason == .uncaughtSignal && result.status == SIGKILL,
                "Boundary \(boundary) was not reached: \(result.output)"
            )

            switch try fixture.stateTitle() {
            case "OLD":
                oldCount += 1
            case "NEW":
                newCount += 1
            default:
                Issue.record("Crash boundary \(boundary) was neither exact OLD nor exact NEW")
            }

            let ordinary = CiderDatabase()
            if boundary == "beforeIntentPublication" || boundary == "afterReceiptPublication" {
                try ordinary.open(at: fixture.databaseURL)
                ordinary.close()
            } else {
                #expect(throws: (any Error).self) {
                    try ordinary.open(at: fixture.databaseURL)
                }
            }

            let resumed = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
            #expect(resumed.status == 0, "Resume failed for \(boundary): \(resumed.output)")
            try fixture.expectNewAndWritable()
        }
        #expect(oldCount + newCount == cases.count)
        #expect(oldCount > 0)
        #expect(newCount > 0)
        print("CID868_CRASH_MATRIX cases=\(cases.count) old=\(oldCount) new=\(newCount) ambiguous=0")
    }

    @Test("all finite restore failure seams throw and restart without false success")
    func finiteFailureMatrixNeverReturnsSuccess() throws {
        let cases = [
            "sourceOpen", "destinationOpen", "backupInit", "backupStep",
            "backupFinish", "reopen", "integrity", "beforeReceiptPublication",
            "intentUnlink", "intentParentFsync",
        ]
        var oldCount = 0
        var newCount = 0
        for boundary in cases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let backupURL = try fixture.prepareRestore(extraRows: 700)
            let result = try runInterposedHelper(
                backupURL: backupURL,
                fixture: fixture,
                boundary: boundary,
                action: "fail"
            )
            #expect(result.status != 0, "Failure boundary \(boundary) returned success")
            let failure = try decodeFailure(result.output)
            #expect(!failure.ok)
            switch try fixture.stateTitle() {
            case "OLD":
                oldCount += 1
                #expect(failure.changed == false)
                #expect(failure.classification == .old)
            case "NEW":
                newCount += 1
                #expect(failure.changed == true)
                #expect(failure.classification == .new)
            default:
                Issue.record("Failure boundary \(boundary) was neither exact OLD nor exact NEW")
            }
            if boundary != "intentParentFsync" {
                #expect(failure.evidencePreserved)
            }
            let ordinary = CiderDatabase()
            if boundary == "intentUnlink" || boundary == "intentParentFsync" {
                try ordinary.open(at: fixture.databaseURL)
                ordinary.close()
            } else {
                #expect(throws: (any Error).self) {
                    try ordinary.open(at: fixture.databaseURL)
                }
            }
            let resumed = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
            #expect(resumed.status == 0, "Failure resume failed for \(boundary): \(resumed.output)")
            try fixture.expectNewAndWritable()
        }
        #expect(oldCount + newCount == cases.count)
        #expect(oldCount > 0 && newCount > 0)
        print("CID868_FAILURE_MATRIX cases=\(cases.count) old=\(oldCount) new=\(newCount) falseSuccess=0")
    }

    @Test("ambiguous logical state blocks restart and preserves rollback evidence")
    func ambiguousStateFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = try fixture.prepareRestore(extraRows: 8)
        let paused = try startInterposedHelper(
            backupURL: backupURL,
            fixture: fixture,
            boundary: "beforeTerminalVerification",
            action: "pause"
        )
        try waitForFile(paused.markerURL)
        try fixture.execute("UPDATE projects SET title='AMBIGUOUS' WHERE id='cid868-state';")
        kill(paused.process.processIdentifier, SIGCONT)
        let result = try finish(paused)
        #expect(result.status != 0)
        let failure = try decodeFailure(result.output)
        #expect(failure.changed == nil)
        #expect(failure.classification == .ambiguous)
        #expect(failure.evidencePreserved)
        let observedRollbackURL = try fixture.activeIntentRollbackURL()
        let rollbackURL = try #require(observedRollbackURL)
        #expect(FileManager.default.fileExists(atPath: rollbackURL.path))
        let ordinary = CiderDatabase()
        #expect(throws: (any Error).self) { try ordinary.open(at: fixture.databaseURL) }
        let retry = try runMaintenanceHelper(backupURL: backupURL, fixture: fixture)
        #expect(retry.status != 0)
        #expect(FileManager.default.fileExists(atPath: rollbackURL.path))
        #expect(try fixture.stateTitle() == "AMBIGUOUS")
    }
}

@MainActor
private struct Fixture {
    let rootURL: URL
    let databaseURL: URL
    let lockRegistryURL: URL
    let priorLockRegistry: String?

    init(databaseRelativePath: String = "cider.db") throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cid868-offline-maintenance-\(UUID().uuidString)",
            isDirectory: true
        )
        databaseURL = rootURL.appendingPathComponent(databaseRelativePath)
        lockRegistryURL = rootURL.appendingPathComponent("maintenance-locks", isDirectory: true)
        priorLockRegistry = ProcessInfo.processInfo.environment[
            "CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"
        ]
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: lockRegistryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        setenv("CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY", lockRegistryURL.path, 1)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
        if let priorLockRegistry {
            setenv("CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY", priorLockRegistry, 1)
        } else {
            unsetenv("CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY")
        }
    }

    func prepareRestore(extraRows: Int = 0) throws -> URL {
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        try database.runSQL("""
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('cid868-state', 'NEW', '', 'active', '{}', 1, 1);
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('cid868-new-only', 'NEW ONLY', '', 'active', '{}', 1, 1);
            """)
        for index in 0..<extraRows {
            let payload = String(repeating: "n", count: 1_024)
            try database.runSQL("""
                INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
                VALUES ('cid868-padding-\(index)', 'Padding \(index)', '', 'active', '{"payload":"\(payload)"}', 1, 1);
                """)
        }
        let artifact = try DatabaseSafetyService().createRollingBackup(
            reason: "cid868-offline-test",
            database: database,
            updateState: false
        )
        let backupURL = artifact.policyURL.appendingPathComponent(
            artifact.packageName,
            isDirectory: true
        )
        try database.runSQL("""
            UPDATE projects SET title = 'OLD' WHERE id = 'cid868-state';
            DELETE FROM projects WHERE id = 'cid868-new-only';
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('cid868-old-only', 'OLD ONLY', '', 'active', '{}', 1, 1);
            """)
        database.close()
        return backupURL
    }

    func stateTitle() throws -> String {
        try scalarText(
            at: databaseURL,
            sql: "SELECT title FROM projects WHERE id='cid868-state';",
            immutable: false
        )
    }

    func expectNewAndWritable() throws {
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        defer { database.close() }
        #expect(try database.integrityCheck().isHealthy)
        let mode = try database.prepare("PRAGMA journal_mode;")
        #expect(try mode.step())
        #expect(mode.string(at: 0).lowercased() == "wal")
        let state = try database.prepare("SELECT title FROM projects WHERE id='cid868-state';")
        #expect(try state.step())
        #expect(state.string(at: 0) == "NEW")
        let newOnly = try database.prepare("SELECT count(*) FROM projects WHERE id='cid868-new-only';")
        #expect(try newOnly.step())
        #expect(newOnly.int(at: 0) == 1)
        let oldOnly = try database.prepare("SELECT count(*) FROM projects WHERE id='cid868-old-only';")
        #expect(try oldOnly.step())
        #expect(oldOnly.int(at: 0) == 0)
        try database.runSQL("""
            INSERT OR REPLACE INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('cid868-post-write', 'POST WRITE', '', 'active', '{}', 2, 2);
            """)
    }

    func expectRollbackIsExactOld(at rollbackURL: URL, expectedTitle: String = "OLD") throws {
        let materialized = rootURL.appendingPathComponent("rollback-check.db")
        try DatabaseSafetyService().materializeVerifiedBackupDatabase(
            from: rollbackURL,
            at: materialized
        )
        #expect(try scalarText(at: materialized, sql: "SELECT title FROM projects WHERE id='cid868-state';") == expectedTitle)
        #expect(try scalarInt(at: materialized, sql: "SELECT count(*) FROM projects WHERE id='cid868-old-only';") == 1)
        #expect(try scalarInt(at: materialized, sql: "SELECT count(*) FROM projects WHERE id='cid868-new-only';") == 0)
        #expect(try scalarText(at: materialized, sql: "PRAGMA integrity_check;").lowercased() == "ok")
    }

    func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            throw FixtureError.sqlite("open for injected mutation")
        }
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func activeIntentRollbackURL() throws -> URL? {
        let intentURL = rootURL.appendingPathComponent(
            "backups/sqlite/maintenance/active-restore-v1.json"
        )
        guard FileManager.default.fileExists(atPath: intentURL.path) else { return nil }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: intentURL))
        guard let dictionary = object as? [String: Any],
              let path = dictionary["rollbackPath"] as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func scalarText(at url: URL, sql: String, immutable: Bool = true) throws -> String {
        var handle: OpaquePointer?
        let source = immutable ? "file:\(url.path)?mode=ro&immutable=1" : url.path
        guard sqlite3_open_v2(
            source,
            &handle,
            SQLITE_OPEN_READONLY | (immutable ? SQLITE_OPEN_URI : 0) | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            throw FixtureError.sqlite("open")
        }
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw FixtureError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
    }

    private func scalarInt(at url: URL, sql: String) throws -> Int {
        Int(try scalarText(at: url, sql: sql)) ?? -1
    }
}

private enum FixtureError: Error {
    case sqlite(String)
    case timeout(String)
}

private struct MaintenanceProcessResult {
    let status: Int32
    let reason: Process.TerminationReason
    let output: String
}

private struct RunningMaintenanceProcess {
    let process: Process
    let pipe: Pipe
    let markerURL: URL
}

private struct RunningHolder {
    let process: Process
    let readyURL: URL
}

private func startHolder(
    mode: String,
    fixture: Fixture,
    label: String
) throws -> RunningHolder {
    let readyURL = fixture.rootURL.appendingPathComponent("\(label).ready")
    let process = Process()
    process.executableURL = try executable(named: "CID868MaintenanceHarness")
    process.arguments = [
        mode, "--database", fixture.databaseURL.path, "--ready", readyURL.path,
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"] = fixture.lockRegistryURL.path
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return RunningHolder(process: process, readyURL: readyURL)
}

private func stop(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    process.waitUntilExit()
}

private func fileIdentity(_ url: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    return "\(device):\(inode)"
}

private func decodeFailure(_ output: String) throws -> OfflineDatabaseRestoreFailureReceipt {
    try JSONDecoder().decode(
        OfflineDatabaseRestoreFailureReceipt.self,
        from: Data(output.utf8)
    )
}

private func runMaintenanceHelper(
    backupURL: URL,
    fixture: Fixture
) throws -> MaintenanceProcessResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = try executable(named: "cider-db-maintenance")
    process.arguments = [
        "restore", "--backup", backupURL.path,
        "--database", fixture.databaseURL.path,
        "--lock-timeout", "0.5", "--json",
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"] = fixture.lockRegistryURL.path
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    return MaintenanceProcessResult(
        status: process.terminationStatus,
        reason: process.terminationReason,
        output: String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    )
}

private func runInterposedHelper(
    backupURL: URL,
    fixture: Fixture,
    boundary: String,
    action: String,
    occurrence: Int = 1
) throws -> MaintenanceProcessResult {
    try finish(startInterposedHelper(
        backupURL: backupURL,
        fixture: fixture,
        boundary: boundary,
        action: action,
        occurrence: occurrence
    ))
}

private func startInterposedHelper(
    backupURL: URL,
    fixture: Fixture,
    boundary: String,
    action: String,
    occurrence: Int = 1
) throws -> RunningMaintenanceProcess {
    let helperURL = try executable(named: "cider-db-maintenance")
    let dylibURL = helperURL.deletingLastPathComponent()
        .appendingPathComponent("libCID850Interpose.dylib")
    guard FileManager.default.isExecutableFile(atPath: dylibURL.path) else {
        throw FixtureError.timeout("Missing test interposition dylib at \(dylibURL.path)")
    }
    let markerURL = fixture.rootURL.appendingPathComponent(
        "interpose-\(boundary)-\(UUID().uuidString).marker"
    )
    let process = Process()
    let pipe = Pipe()
    process.executableURL = helperURL
    process.arguments = [
        "restore", "--backup", backupURL.path,
        "--database", fixture.databaseURL.path,
        "--lock-timeout", "0.5", "--json",
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["CIDER_DATABASE_MAINTENANCE_LOCK_DIRECTORY"] = fixture.lockRegistryURL.path
    environment["DYLD_INSERT_LIBRARIES"] = dylibURL.path
    environment["CID868_INTERPOSE_BOUNDARY"] = boundary
    environment["CID868_INTERPOSE_ACTION"] = action
    environment["CID868_INTERPOSE_DATABASE"] = fixture.databaseURL.path
    environment["CID868_INTERPOSE_MARKER"] = markerURL.path
    environment["CID868_INTERPOSE_OCCURRENCE"] = String(occurrence)
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    return RunningMaintenanceProcess(process: process, pipe: pipe, markerURL: markerURL)
}

private func finish(_ running: RunningMaintenanceProcess) throws -> MaintenanceProcessResult {
    running.process.waitUntilExit()
    return MaintenanceProcessResult(
        status: running.process.terminationStatus,
        reason: running.process.terminationReason,
        output: String(
            decoding: running.pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    )
}

private func executable(named name: String) throws -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidates = [
        root.appendingPathComponent(".build/arm64-apple-macosx/debug/\(name)"),
        root.appendingPathComponent(".build/debug/\(name)"),
    ]
    guard let executable = candidates.first(where: {
        FileManager.default.isExecutableFile(atPath: $0.path)
    }) else {
        throw FixtureError.timeout("Missing executable \(name)")
    }
    return executable
}

private func waitForFile(_ url: URL) throws {
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) { return }
        usleep(10_000)
    }
    throw FixtureError.timeout(url.path)
}
