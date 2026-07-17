import CryptoKit
import Darwin
import Foundation
import SQLite3
import Testing
@testable import Cider

@Suite("Cider database startup preflight", .serialized)
@MainActor
struct CiderDatabaseStartupPreflightTests {
    @Test("Healthy current schema opens without a migration safety artifact")
    func currentSchemaDoesNotCreateMigrationArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }

        let created = CiderDatabase()
        try created.open(at: fixture.databaseURL)
        created.close()

        let beforeManifest = try fixture.directoryManifest()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }

        #expect(reopened.lastMigrationSafetyArtifactURL == nil)
        #expect(try fixture.directoryManifest() == beforeManifest)
    }

    @Test("Fresh database creation remains supported without a source artifact")
    func freshDatabaseDoesNotRequireMigrationArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        #expect(database.lastMigrationSafetyArtifactURL == nil)
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion)
        #expect(try database.integrityCheck().isHealthy)
        database.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.migrationSafetyDirectory.path))
    }

    @Test("A source created after fresh classification cannot bypass existing-source preflight")
    func sourceCreatedAtFreshOpenBoundaryReceivesRequiredArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        let prepared = try StartupDatabaseFixture()
        defer {
            fixture.cleanup()
            prepared.cleanup()
        }
        try prepared.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        try prepared.execute("""
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('late-open-source', 'Late Open Source', '', 'active', '{}', 1, 2);
            """)

        let lateInstaller = try LateSourceInstallingSQLiteVFS(
            sourceURL: prepared.databaseURL,
            destinationURL: fixture.databaseURL
        )
        defer { lateInstaller.stop() }

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        #expect(
            lateInstaller.didInstallSource,
            "Expected \(lateInstaller.destinationPath); observed SQLite opens: \(lateInstaller.observedOpenNames); link errno: \(lateInstaller.installErrno)"
        )
        #expect(database.lastMigrationSafetyArtifactURL != nil)
        #expect(try fixture.scalarText(
            at: fixture.databaseURL,
            sql: "SELECT title FROM projects WHERE id = 'late-open-source';"
        ) == "Late Open Source")
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion)
        database.close()

        let artifacts = try retainedMigrationArtifacts(in: fixture.migrationSafetyDirectory)
        #expect(artifacts.count == 1)
        if let artifactURL = artifacts.first {
            #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
            #expect(try fixture.integrityMessages(at: artifactURL) == ["ok"])
            #expect(try fixture.scalarText(
                at: artifactURL,
                sql: "SELECT title FROM projects WHERE id = 'late-open-source';"
            ) == "Late Open Source")
        }

        let physicallyReopened = CiderDatabase()
        try physicallyReopened.open(at: fixture.databaseURL)
        defer { physicallyReopened.close() }
        #expect(try physicallyReopened.integrityCheck().isHealthy)
    }

    @Test("A current source created at the fresh-open boundary is preserved and physically reopened")
    func currentSourceCreatedAtFreshOpenBoundaryIsReclassified() throws {
        let fixture = try StartupDatabaseFixture()
        let prepared = try StartupDatabaseFixture()
        defer {
            fixture.cleanup()
            prepared.cleanup()
        }
        try prepared.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion)
        try prepared.execute("""
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('late-current-source', 'Late Current Source', '', 'active', '{}', 1, 2);
            """)

        let lateInstaller = try LateSourceInstallingSQLiteVFS(
            sourceURL: prepared.databaseURL,
            destinationURL: fixture.databaseURL
        )
        defer { lateInstaller.stop() }

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        #expect(lateInstaller.didInstallSource)
        #expect(database.lastMigrationSafetyArtifactURL == nil)
        #expect(try fixture.scalarText(
            at: fixture.databaseURL,
            sql: "SELECT title FROM projects WHERE id = 'late-current-source';"
        ) == "Late Current Source")
        #expect(try database.integrityCheck().isHealthy)
        database.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.migrationSafetyDirectory.path))

        let physicallyReopened = CiderDatabase()
        try physicallyReopened.open(at: fixture.databaseURL)
        defer { physicallyReopened.close() }
        #expect(try physicallyReopened.integrityCheck().isHealthy)
        #expect(try fixture.scalarText(
            at: fixture.databaseURL,
            sql: "SELECT title FROM projects WHERE id = 'late-current-source';"
        ) == "Late Current Source")
    }

    @Test("A corrupt source created at the fresh-open boundary fails without mutation")
    func corruptSourceCreatedAtFreshOpenBoundaryFailsNonmutating() throws {
        let fixture = try StartupDatabaseFixture()
        let prepared = try StartupDatabaseFixture()
        defer {
            fixture.cleanup()
            prepared.cleanup()
        }
        try Data(repeating: 0xA5, count: 8_192).write(to: prepared.databaseURL)
        let expectedHashes = try prepared.sourceArtifactHashes()
        let expectedManifest = try prepared.topLevelManifest()

        let lateInstaller = try LateSourceInstallingSQLiteVFS(
            sourceURL: prepared.databaseURL,
            destinationURL: fixture.databaseURL
        )
        defer { lateInstaller.stop() }

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected late corrupt source preflight to fail")
        } catch let error as CiderDatabaseError {
            guard case .startupPreflightFailed = error else {
                Issue.record("Expected startupPreflightFailed, got \(error)")
                return
            }
        }

        #expect(lateInstaller.didInstallSource)
        #expect(!database.isOpen)
        #expect(try fixture.sourceArtifactHashes() == expectedHashes)
        let actualManifest = try fixture.topLevelManifest()
        #expect(
            actualManifest == expectedManifest,
            "Expected manifest \(expectedManifest); actual \(actualManifest)"
        )
        #expect(!FileManager.default.fileExists(atPath: fixture.migrationSafetyDirectory.path))
        #expect(try fixture.canPhysicallyOpenReadOnly())
    }

    @Test("Freshness is recomputed after waiting for startup serialization")
    func databaseCreatedWhileWaitingReceivesRequiredArtifact() throws {
        let fixture = try StartupDatabaseFixture(databaseRelativePath: ".cider/cider.db")
        let prepared = try StartupDatabaseFixture()
        defer {
            fixture.cleanup()
            prepared.cleanup()
        }
        try prepared.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        try prepared.execute("""
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('installed-while-waiting', 'Installed While Waiting', '', 'active', '{}', 1, 2);
            """)

        let serializationLock = try TestDirectoryLock.acquire(
            fixture.databaseURL.deletingLastPathComponent()
        )
        let invocation = configuredCLIProcess(
            executable: try cliExecutableURL(),
            vaultURL: fixture.rootURL,
            arguments: ["db", "integrity", "--json"]
        )
        try invocation.process.run()
        defer {
            if invocation.process.isRunning {
                invocation.process.terminate()
                invocation.process.waitUntilExit()
            }
        }
        try waitForProcess(
            invocation.process,
            toOpen: fixture.databaseURL.deletingLastPathComponent()
        )
        try FileManager.default.copyItem(at: prepared.databaseURL, to: fixture.databaseURL)
        serializationLock.release()

        invocation.process.waitUntilExit()
        let output = String(decoding: invocation.output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(invocation.process.terminationStatus == 0, "CLI failed: \(output)")
        let artifacts = try retainedMigrationArtifacts(in: fixture.migrationSafetyDirectory)
        #expect(artifacts.count == 1)
        let artifactURL = try #require(artifacts.first)
        #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.scalarText(
            at: artifactURL,
            sql: "SELECT title FROM projects WHERE id = 'installed-while-waiting';"
        ) == "Installed While Waiting")
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion)
    }

    @Test("Corrupt existing database fails typed preflight without mutating source artifacts or manifest")
    func corruptHeaderFailsClosedWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try Data(repeating: 0xA5, count: 8_192).write(to: fixture.databaseURL)
        try Data("unchanged-wal".utf8).write(to: fixture.walURL)
        try Data("unchanged-shm".utf8).write(to: fixture.shmURL)
        let before = try fixture.fingerprint()

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected corrupt database preflight to fail")
        } catch let error as CiderDatabaseError {
            guard case .startupPreflightFailed = error else {
                Issue.record("Expected startupPreflightFailed, got \(error)")
                return
            }
        }

        #expect(!database.isOpen)
        let after = try fixture.fingerprint()
        #expect(after == before, "Before: \(before); after: \(after)")
    }

    @Test("Orphan WAL and SHM states fail closed without source creation")
    func orphanSidecarsFailClosedWithoutMutation() throws {
        for sidecars in [["-wal"], ["-shm"], ["-wal", "-shm"]] {
            let fixture = try StartupDatabaseFixture()
            defer { fixture.cleanup() }
            for suffix in sidecars {
                try Data("orphan-\(suffix)".utf8).write(
                    to: URL(fileURLWithPath: fixture.databaseURL.path + suffix)
                )
            }
            let before = try fixture.fingerprint()

            try expectPreflightFailure(opening: fixture.databaseURL)

            #expect(!FileManager.default.fileExists(atPath: fixture.databaseURL.path))
            #expect(try fixture.fingerprint() == before)
        }
    }

    @Test("Older healthy database creates and verifies a mandatory artifact before migration")
    func olderSchemaCreatesVerifiedArtifactBeforeMigration() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        let artifactURL = try #require(database.lastMigrationSafetyArtifactURL)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion)
        #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.integrityMessages(at: artifactURL) == ["ok"])
        database.close()

        let physicallyReopened = CiderDatabase()
        try physicallyReopened.open(at: fixture.databaseURL)
        defer { physicallyReopened.close() }
        #expect(try physicallyReopened.integrityCheck().isHealthy)
    }

    @Test("Future schema rejection remains nonmutating")
    func futureSchemaFailsWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion + 1)
        let before = try fixture.fingerprint()

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected future schema to fail")
        } catch let error as CiderDatabaseError {
            guard case .schemaTooNew = error else {
                Issue.record("Expected schemaTooNew, got \(error)")
                return
            }
        }

        #expect(try fixture.fingerprint() == before)
    }

    @Test("Malformed database pages fail preflight without source mutation")
    func malformedPagesFailClosedWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion)
        try fixture.execute("CREATE TABLE large_payload (value BLOB); INSERT INTO large_payload VALUES (zeroblob(32768));")
        let rootPage = try fixture.scalarInt(
            at: fixture.databaseURL,
            sql: "SELECT rootpage FROM sqlite_schema WHERE name = 'large_payload';"
        )
        var bytes = try Data(contentsOf: fixture.databaseURL)
        let encodedPageSize = Int(bytes[16]) << 8 | Int(bytes[17])
        let pageSize = encodedPageSize == 1 ? 65_536 : encodedPageSize
        let pageOffset = (rootPage - 1) * pageSize
        #expect(pageOffset < bytes.count)
        bytes[pageOffset] = 0xFF
        try bytes.write(to: fixture.databaseURL)
        let before = try fixture.fingerprint()

        try expectPreflightFailure(opening: fixture.databaseURL)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("Failed SQLite integrity is typed and nonmutating")
    func failedIntegrityFailsClosedWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion)
        var bytes = try Data(contentsOf: fixture.databaseURL)
        #expect(bytes.count >= 100)
        // SQLite header offsets 32 and 36 are the first freelist trunk page
        // and total freelist page count. Claiming an impossible trunk page is
        // a non-header-format integrity failure detected by integrity_check.
        bytes.replaceSubrange(32..<36, with: [0x7F, 0xFF, 0xFF, 0xFF])
        bytes.replaceSubrange(36..<40, with: [0x00, 0x00, 0x00, 0x01])
        try bytes.write(to: fixture.databaseURL)
        let before = try fixture.fingerprint()

        try expectPreflightFailure(opening: fixture.databaseURL)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("Unreadable source fails typed preflight without recreation")
    func unreadableSourceFailsClosedWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion)
        let before = try fixture.fingerprint()
        #expect(chmod(fixture.databaseURL.path, 0) == 0)

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected unreadable source to fail")
        } catch let error as CiderDatabaseError {
            guard case .startupPreflightFailed(kind: .unreadable, _) = error else {
                Issue.record("Expected typed unreadable preflight failure, got \(error)")
                _ = chmod(fixture.databaseURL.path, S_IRUSR | S_IWUSR)
                return
            }
        }
        #expect(chmod(fixture.databaseURL.path, S_IRUSR | S_IWUSR) == 0)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("Unhealthy WAL fails before source DB WAL or SHM mutation")
    func unhealthyWALFailsClosedWithoutMutation() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        let writer = try fixture.openWALWriter(version: DatabaseMigrations.latestVersion)
        defer { sqlite3_close_v2(writer) }
        var wal = try Data(contentsOf: fixture.walURL)
        #expect(wal.count > 32)
        wal[0] ^= 0xFF
        try wal.write(to: fixture.walURL)
        let before = try fixture.fingerprint()

        try expectPreflightFailure(opening: fixture.databaseURL)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("WAL frame checksum corruption fails before source mutation")
    func unhealthyWALFrameChecksumFailsClosed() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        let writer = try fixture.openWALWriter(version: DatabaseMigrations.latestVersion)
        defer { sqlite3_close_v2(writer) }
        var wal = try Data(contentsOf: fixture.walURL)
        #expect(wal.count > 64)
        wal[wal.count - 1] ^= 0x01
        try wal.write(to: fixture.walURL)
        let before = try fixture.fingerprint()

        try expectPreflightFailure(opening: fixture.databaseURL)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("Healthy current WAL source opens without a migration artifact")
    func currentWALDatabaseOpensWithoutArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        let writer = try fixture.openWALWriter(
            version: DatabaseMigrations.latestVersion,
            extraSQL: """
                INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
                VALUES ('current-wal-project', 'Current WAL Project', '', 'active', '{}', 1, 2);
                """
        )
        defer { sqlite3_close_v2(writer) }
        #expect((try Data(contentsOf: fixture.walURL)).count > 32)

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        #expect(database.lastMigrationSafetyArtifactURL == nil)
        #expect(try fixture.scalarText(
            at: fixture.databaseURL,
            sql: "SELECT title FROM projects WHERE id = 'current-wal-project';"
        ) == "Current WAL Project")
        #expect(try database.integrityCheck().isHealthy)
        database.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.migrationSafetyDirectory.path))
    }

    @Test("Older healthy WAL database migrates from a verified parity artifact")
    func olderWALDatabaseMigratesWithParityArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        let writer = try fixture.openWALWriter(
            version: DatabaseMigrations.latestVersion - 1,
            extraSQL: """
                INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
                VALUES ('wal-project', 'WAL Project', 'before migration', 'active', '{}', 1, 2);
                """
        )
        defer { sqlite3_close_v2(writer) }
        #expect((try Data(contentsOf: fixture.walURL)).count > 32)

        let database = CiderDatabase()
        try database.open(at: fixture.databaseURL)
        let artifactURL = try #require(database.lastMigrationSafetyArtifactURL)
        #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.scalarText(at: artifactURL, sql: "SELECT title FROM projects WHERE id = 'wal-project';") == "WAL Project")
        #expect(try fixture.scalarText(at: fixture.databaseURL, sql: "SELECT title FROM projects WHERE id = 'wal-project';") == "WAL Project")
        database.close()

        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        #expect(try reopened.integrityCheck().isHealthy)
        #expect(try fixture.scalarText(at: fixture.databaseURL, sql: "SELECT subtitle FROM projects WHERE id = 'wal-project';") == "before migration")
        reopened.close()
    }

    @Test("External SQLite commit after artifact verification is refused before migration")
    func externalWriterCommitAfterArtifactVerificationIsRefused() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        try fixture.execute("""
            PRAGMA journal_mode=DELETE;
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('external-commit', 'Before', '', 'active', '{}', 1, 2);
            """)
        let sourceIdentity = try fixture.fileIdentity(at: fixture.databaseURL)
        let sourceSize = try fixture.fileSize(at: fixture.databaseURL)

        let writer = try configuredArtifactGatedSQLiteWriter(
            databaseURL: fixture.databaseURL,
            migrationSafetyDirectory: fixture.migrationSafetyDirectory,
            sqlAfterArtifactOrTimeout: "UPDATE projects SET title = 'After!' WHERE id = 'external-commit';"
        )
        try writer.process.run()
        defer {
            if writer.process.isRunning {
                writer.process.terminate()
                writer.process.waitUntilExit()
            }
        }
        let ready = try readProcessOutput(
            writer.process,
            from: writer.output.fileHandleForReading,
            through: "writer-ready"
        )
        #expect(ready.contains("writer-ready"), "External writer did not acquire its SQLite transaction: \(ready)")

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected changed source to be refused before migration")
        } catch let error as CiderDatabaseError {
            guard case .startupPreflightFailed(kind: .changedDuringRead, _) = error else {
                Issue.record("Expected changedDuringRead preflight failure, got \(error)")
                return
            }
        }
        let artifactURL = try #require(database.lastMigrationSafetyArtifactURL)
        writer.process.waitUntilExit()
        let writerRemainder = String(
            decoding: writer.output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(writer.process.terminationStatus == 0, "External writer failed: \(ready)\(writerRemainder)")

        #expect(try fixture.fileIdentity(at: fixture.databaseURL) == sourceIdentity)
        let finalSourceSize = try fixture.fileSize(at: fixture.databaseURL)
        #expect(
            finalSourceSize == sourceSize,
            "Expected same-size external commit; before \(sourceSize), after \(finalSourceSize)"
        )
        #expect(try fixture.scalarText(
            at: fixture.databaseURL,
            sql: "SELECT title FROM projects WHERE id = 'external-commit';"
        ) == "After!")
        #expect(try fixture.scalarText(
            at: artifactURL,
            sql: "SELECT title FROM projects WHERE id = 'external-commit';"
        ) == "Before")
        #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.integrityMessages(at: artifactURL) == ["ok"])
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.integrityMessages(at: fixture.databaseURL) == ["ok"])
    }

    @Test("Migration refuses when mandatory artifact capture cannot start")
    func artifactCaptureFailureLeavesSourceUnchanged() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        let migrationRoot = fixture.migrationSafetyDirectory
        try FileManager.default.createDirectory(
            at: migrationRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("collision".utf8).write(to: migrationRoot)
        let before = try fixture.fingerprint()

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected artifact capture failure")
        } catch let error as CiderDatabaseError {
            guard case .migrationSafetyArtifactCaptureFailed = error else {
                Issue.record("Expected migrationSafetyArtifactCaptureFailed, got \(error)")
                return
            }
        }
        let after = try fixture.fingerprint()
        #expect(after == before, "Before: \(before); after: \(after)")
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion - 1)
    }

    @Test("Migration refuses when captured artifact cannot pass physical verification")
    func artifactVerificationFailureLeavesSourceUnchanged() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        try fixture.execute("CREATE TABLE verification_payload (value BLOB); INSERT INTO verification_payload VALUES (zeroblob(67108864));")
        let beforeHashes = try fixture.sourceArtifactHashes()
        let replacementFinished = DispatchSemaphore(value: 0)
        let migrationRoot = fixture.migrationSafetyDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let urls = try? FileManager.default.contentsOfDirectory(
                    at: migrationRoot,
                    includingPropertiesForKeys: nil
                ), let staging = urls.first(where: { $0.lastPathComponent.hasSuffix(".tmp.db") }) {
                    try? FileManager.default.removeItem(at: staging)
                    try? Data("not a sqlite database".utf8).write(to: staging)
                    replacementFinished.signal()
                    return
                }
                Thread.sleep(forTimeInterval: 0.0001)
            }
            replacementFinished.signal()
        }

        let database = CiderDatabase()
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected artifact verification failure")
        } catch let error as CiderDatabaseError {
            guard case .migrationSafetyArtifactVerificationFailed = error else {
                Issue.record("Expected migrationSafetyArtifactVerificationFailed, got \(error)")
                return
            }
        }
        #expect(replacementFinished.wait(timeout: .now() + 1) == .success)
        let afterHashes = try fixture.sourceArtifactHashes()
        #expect(afterHashes == beforeHashes, "Before: \(beforeHashes); after: \(afterHashes)")
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion - 1)
    }

    @Test("Migration failure rolls back source and retains verified artifact")
    func migrationFailureRollsBackAndRetainsArtifact() throws {
        let fixture = try StartupDatabaseFixture()
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        try fixture.execute("""
            INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
            VALUES ('rollback-project', 'Before Failure', '', 'active', '{}', 1, 2);
            CREATE TRIGGER force_migration_failure
            BEFORE DELETE ON schema_version
            BEGIN
                SELECT RAISE(ABORT, 'forced migration failure');
            END;
            """)

        let database = CiderDatabase()
        let artifactURL: URL
        do {
            try database.open(at: fixture.databaseURL)
            Issue.record("Expected migration failure")
            return
        } catch let error as CiderDatabaseError {
            guard case .migrationFailed(let retainedURL, _) = error else {
                Issue.record("Expected migrationFailed, got \(error)")
                return
            }
            artifactURL = retainedURL
        }

        #expect(FileManager.default.fileExists(atPath: artifactURL.path))
        #expect(try fixture.integrityMessages(at: artifactURL) == ["ok"])
        #expect(try fixture.schemaVersion(at: artifactURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion - 1)
        #expect(try fixture.scalarText(at: fixture.databaseURL, sql: "SELECT title FROM projects WHERE id = 'rollback-project';") == "Before Failure")
        #expect(try fixture.integrityMessages(at: fixture.databaseURL) == ["ok"])
    }

    @Test("Production startup composition preserves the fail-closed state machine")
    func productionCompositionOrderingGuard() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRoot = root.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!sourceFiles.isEmpty)

        let owners = [
            "Sources/Cider/Database/CiderDatabase.swift",
            "Sources/Cider/Database/DatabaseStartupPreflight.swift",
            "Sources/Cider/Database/DatabaseMigrations.swift",
            "Sources/Cider/App/AppDelegate.swift",
            "Sources/CiderCLI/CiderCLI.swift",
        ]
        for owner in owners {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(owner).path), "Missing production owner \(owner)")
        }

        let databaseSource = try String(contentsOf: root.appendingPathComponent(owners[0]), encoding: .utf8)
        let health = try #require(databaseSource.range(of: "establishExistingDatabaseHealth"))
        let artifact = try #require(databaseSource.range(of: "createRequiredMigrationSafetyArtifact"))
        let migration = try #require(databaseSource.range(of: "DatabaseMigrations.runMigrations"))
        let postOpen = try #require(databaseSource.range(of: "validatePostOpenDatabase"))
        #expect(health.lowerBound < artifact.lowerBound)
        #expect(artifact.lowerBound < migration.lowerBound)
        #expect(migration.lowerBound < postOpen.lowerBound)

        let appSource = try String(contentsOf: root.appendingPathComponent(owners[3]), encoding: .utf8)
        let appOpen = try #require(appSource.range(of: "guard openSQLiteForStartupOrTerminate()"))
        let appDerivedWrite = try #require(appSource.range(of: "StoragePaths.ensureVaultStructure()"))
        #expect(appOpen.lowerBound < appDerivedWrite.lowerBound)
        #expect(!appSource.contains("capturePreOpenSnapshotIfNeeded(databaseURL: dbPath)"))

        let cliSource = try String(contentsOf: root.appendingPathComponent(owners[4]), encoding: .utf8)
        let cliOpen = try #require(cliSource.range(of: "try openCanonicalDatabaseWithRetry(at: dbPath)"))
        let cliDerivedWrite = try #require(cliSource.range(of: "let vaultStructureReport = StoragePaths.ensureVaultStructure()"))
        let cliUsageWrite = try #require(cliSource.range(of: "CiderUsageAuditService.shared.recordCLI"))
        #expect(cliOpen.lowerBound < cliDerivedWrite.lowerBound)
        #expect(cliOpen.lowerBound < cliUsageWrite.lowerBound)
        #expect(!cliSource.contains("capturePreOpenSnapshotIfNeeded(databaseURL: dbPath)"))
    }

    @Test("Two real CLI processes serialize migration startup and publish one artifact")
    func concurrentCLIStartupIsBoundedAndTruthful() throws {
        let fixture = try StartupDatabaseFixture(databaseRelativePath: ".cider/cider.db")
        defer { fixture.cleanup() }
        try fixture.createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion - 1)
        let executable = try cliExecutableURL()

        let first = configuredCLIProcess(
            executable: executable,
            vaultURL: fixture.rootURL,
            arguments: ["db", "integrity", "--json"]
        )
        let second = configuredCLIProcess(
            executable: executable,
            vaultURL: fixture.rootURL,
            arguments: ["db", "integrity", "--json"]
        )
        try first.process.run()
        try second.process.run()
        first.process.waitUntilExit()
        second.process.waitUntilExit()
        let firstOutput = String(decoding: first.output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let secondOutput = String(decoding: second.output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(first.process.terminationStatus == 0, "First CLI failed: \(firstOutput)")
        #expect(second.process.terminationStatus == 0, "Second CLI failed: \(secondOutput)")
        #expect(firstOutput.contains("\"healthy\" : true") || firstOutput.contains("\"healthy\":true"))
        #expect(secondOutput.contains("\"healthy\" : true") || secondOutput.contains("\"healthy\":true"))
        let artifacts = try FileManager.default.contentsOfDirectory(
            at: fixture.migrationSafetyDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "db" && !$0.lastPathComponent.hasPrefix(".") }
        #expect(artifacts.count == 1)
        #expect(try fixture.schemaVersion(at: fixture.databaseURL) == DatabaseMigrations.latestVersion)
        #expect(try fixture.integrityMessages(at: fixture.databaseURL) == ["ok"])
    }

    @Test("CLI startup failure exits nonzero without derived-store or manifest writes")
    func cliPropagatesPreflightFailureWithoutFallback() throws {
        let fixture = try StartupDatabaseFixture(databaseRelativePath: ".cider/cider.db")
        defer { fixture.cleanup() }
        try Data(repeating: 0xCC, count: 8_192).write(to: fixture.databaseURL)
        try Data("bad-wal".utf8).write(to: fixture.walURL)
        try Data("stable-shm".utf8).write(to: fixture.shmURL)
        let before = try fixture.fingerprint()
        let invocation = configuredCLIProcess(
            executable: try cliExecutableURL(),
            vaultURL: fixture.rootURL,
            arguments: ["item", "graph-health", "--json"]
        )

        try invocation.process.run()
        invocation.process.waitUntilExit()
        let output = String(decoding: invocation.output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(invocation.process.terminationStatus != 0)
        #expect(output.contains("startup safety gate"))
        #expect(output.contains("\"ok\" : false") || output.contains("\"ok\":false"))
        #expect(try fixture.fingerprint() == before)
    }

    private func expectPreflightFailure(opening url: URL) throws {
        let database = CiderDatabase()
        do {
            try database.open(at: url)
            Issue.record("Expected startup preflight failure")
        } catch let error as CiderDatabaseError {
            guard case .startupPreflightFailed = error else {
                Issue.record("Expected startupPreflightFailed, got \(error)")
                return
            }
        }
        #expect(!database.isOpen)
    }

    private func cliExecutableURL() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func configuredCLIProcess(
        executable: URL,
        vaultURL: URL,
        arguments: [String]
    ) -> (process: Process, output: Pipe) {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--vault", vaultURL.path] + arguments
        process.standardOutput = output
        process.standardError = output
        return (process, output)
    }

    private func retainedMigrationArtifacts(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "db" && !$0.lastPathComponent.hasPrefix(".") }
    }

    private func waitForProcess(_ process: Process, toOpen url: URL) throws {
        let expectedPaths = [url.path, url.resolvingSymlinksInPath().path]
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            let probe = Process()
            let output = Pipe()
            probe.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            probe.arguments = ["-a", "-p", String(process.processIdentifier), "-Fn"]
            probe.standardOutput = output
            probe.standardError = FileHandle.nullDevice
            try probe.run()
            probe.waitUntilExit()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if expectedPaths.contains(where: text.contains) { return }
            usleep(10_000)
        }
        throw SQLiteFixtureError.message("Timed out waiting for the CLI to block on the startup directory lock")
    }

    private func configuredArtifactGatedSQLiteWriter(
        databaseURL: URL,
        migrationSafetyDirectory: URL,
        sqlAfterArtifactOrTimeout: String
    ) throws -> (process: Process, output: Pipe) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        let quotedArtifactDirectory = shellQuote(migrationSafetyDirectory.path)
        let script = """
            .bail on
            PRAGMA busy_timeout=5000;
            BEGIN IMMEDIATE;
            .print writer-ready
            .shell i=0; while [ \"$i\" -lt 30 ]; do if find \(quotedArtifactDirectory) -type f -name 'migration-*.db' ! -name '.*' -print -quit 2>/dev/null | grep -q .; then break; fi; i=$((i + 1)); sleep 0.01; done
            \(sqlAfterArtifactOrTimeout)
            COMMIT;
            """
        try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try input.fileHandleForWriting.close()
        return (process, output)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func readProcessOutput(
        _ process: Process,
        from handle: FileHandle,
        through marker: String
    ) throws -> String {
        var data = Data()
        while process.isRunning {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            let text = String(decoding: data, as: UTF8.self)
            if text.contains(marker) { return text }
        }
        throw SQLiteFixtureError.message(
            "Process exited before emitting \(marker): \(String(decoding: data, as: UTF8.self))"
        )
    }
}

private struct StartupDatabaseFixture {
    struct Fingerprint: Equatable {
        let artifacts: [String: String]
        let manifest: [String]
    }

    let rootURL: URL
    let databaseURL: URL

    var walURL: URL { URL(fileURLWithPath: databaseURL.path + "-wal") }
    var shmURL: URL { URL(fileURLWithPath: databaseURL.path + "-shm") }
    var migrationSafetyDirectory: URL {
        DatabaseStartupPreflight.migrationSafetyDirectory(for: databaseURL)
    }

    init(databaseRelativePath: String = "cider.db") throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-startup-preflight-\(UUID().uuidString)", isDirectory: true)
        databaseURL = rootURL.appendingPathComponent(databaseRelativePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func createCurrentDatabaseThenDowngrade(to version: Int) throws {
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        if version == DatabaseMigrations.latestVersion - 1 {
            try database.runSQL("""
                DROP TABLE conversation_messages;
                DROP TABLE conversation_turns;
                DROP TABLE conversation_runtime_bindings;
                DROP TABLE conversation_rooms;
                """)
        }
        try database.runSQL("DELETE FROM schema_version;")
        try database.runSQL("INSERT INTO schema_version (version) VALUES (\(version));")
        database.close()
    }

    func fingerprint() throws -> Fingerprint {
        Fingerprint(artifacts: try sourceArtifactHashes(), manifest: try directoryManifest())
    }

    func sourceArtifactHashes() throws -> [String: String] {
        var artifacts: [String: String] = [:]
        for url in [databaseURL, walURL, shmURL] where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            artifacts[url.lastPathComponent] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return artifacts
    }

    func directoryManifest() throws -> [String] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        )
        var entries: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let relative = String(url.path.dropFirst(rootURL.path.count + 1))
            entries.append("\(relative)|\(values.isDirectory == true ? "d" : "f")|\(values.fileSize ?? 0)")
        }
        return entries.sorted()
    }

    func topLevelManifest() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        ).map { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return "\(url.lastPathComponent)|\(values.isDirectory == true ? "d" : "f")|\(values.fileSize ?? 0)"
        }.sorted()
    }

    func schemaVersion(at url: URL) throws -> Int {
        let handle = try openReadOnly(url)
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT MAX(version) FROM schema_version;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteFixtureError.message(String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func integrityMessages(at url: URL) throws -> [String] {
        let handle = try openReadOnly(url)
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteFixtureError.message(String(cString: sqlite3_errmsg(handle)))
        }
        var messages: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                messages.append(String(cString: text))
            }
        }
        return messages
    }

    func scalarText(at url: URL, sql: String) throws -> String? {
        let handle = try openReadOnly(url)
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteFixtureError.message(String(cString: sqlite3_errmsg(handle)))
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    func scalarInt(at url: URL, sql: String) throws -> Int {
        let handle = try openReadOnly(url)
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteFixtureError.message(String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            throw SQLiteFixtureError.message("unable to open writable fixture")
        }
        defer { sqlite3_close_v2(handle) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            throw SQLiteFixtureError.message(errorMessage.map { String(cString: $0) } ?? "fixture SQL failed")
        }
    }

    func fileIdentity(at url: URL) throws -> UInt64 {
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            throw SQLiteFixtureError.message("unable to stat \(url.path)")
        }
        return UInt64(information.st_ino)
    }

    func fileSize(at url: URL) throws -> Int64 {
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            throw SQLiteFixtureError.message("unable to stat \(url.path)")
        }
        return information.st_size
    }

    func canPhysicallyOpenReadOnly() throws -> Bool {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        sqlite3_close_v2(handle)
        return result == SQLITE_OK && handle != nil
    }

    @MainActor
    func openWALWriter(version: Int, extraSQL: String = "") throws -> OpaquePointer {
        try createCurrentDatabaseThenDowngrade(to: DatabaseMigrations.latestVersion)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            throw SQLiteFixtureError.message("unable to open WAL fixture")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let sql = """
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            \(version == DatabaseMigrations.latestVersion - 1 ? "DROP TABLE conversation_messages; DROP TABLE conversation_turns; DROP TABLE conversation_runtime_bindings; DROP TABLE conversation_rooms;" : "")
            DELETE FROM schema_version;
            INSERT INTO schema_version (version) VALUES (\(version));
            INSERT OR REPLACE INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('wal-marker', 'WAL Marker', '#000000', 'custom', 0, 0);
            \(extraSQL)
            """
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "WAL fixture SQL failed"
            sqlite3_free(errorMessage)
            sqlite3_close_v2(handle)
            throw SQLiteFixtureError.message(message)
        }
        sqlite3_free(errorMessage)
        return handle
    }

    private func openReadOnly(_ url: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let isPortableArtifact = url.path.contains("/migration-safety/")
        let path = isPortableArtifact ? "file:\(url.path)?mode=ro&immutable=1" : url.path
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | (isPortableArtifact ? SQLITE_OPEN_URI : 0)
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            throw SQLiteFixtureError.message(message)
        }
        return handle
    }
}

private final class TestDirectoryLock {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(_ url: URL) throws -> TestDirectoryLock {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw SQLiteFixtureError.message("unable to acquire test startup lock at \(url.path)")
        }
        return TestDirectoryLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

private enum SQLiteFixtureError: Error {
    case message(String)
}

private final class LateSourceInstallingSQLiteVFS {
    private struct Installation {
        let originalVFS: UnsafeMutablePointer<sqlite3_vfs>
        let sourcePath: String
        let destinationPath: String
        var didInstall = false
        var observedOpenNames: [String] = []
        var installErrno: Int32?
    }

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var installation: Installation?

    private let originalVFS: UnsafeMutablePointer<sqlite3_vfs>
    private let wrapperVFS: UnsafeMutablePointer<sqlite3_vfs>
    private let wrapperName: UnsafeMutablePointer<CChar>
    private var isStopped = false

    var didInstallSource: Bool {
        Self.stateLock.withLock { Self.installation?.didInstall == true }
    }

    var observedOpenNames: [String] {
        Self.stateLock.withLock { Self.installation?.observedOpenNames ?? [] }
    }

    var installErrno: Int32? {
        Self.stateLock.withLock { Self.installation?.installErrno }
    }

    var destinationPath: String {
        Self.stateLock.withLock { Self.installation?.destinationPath ?? "<stopped>" }
    }

    init(sourceURL: URL, destinationURL: URL) throws {
        guard let originalVFS = sqlite3_vfs_find(nil),
              let wrapperName = strdup("cider-late-source-\(UUID().uuidString)") else {
            throw SQLiteFixtureError.message("unable to prepare the late-source SQLite VFS")
        }
        let wrapperVFS = UnsafeMutablePointer<sqlite3_vfs>.allocate(capacity: 1)
        wrapperVFS.initialize(to: originalVFS.pointee)
        wrapperVFS.pointee.zName = UnsafePointer(wrapperName)
        wrapperVFS.pointee.xOpen = Self.interceptingOpen

        Self.stateLock.withLock {
            Self.installation = Installation(
                originalVFS: originalVFS,
                sourcePath: sourceURL.resolvingSymlinksInPath().path,
                destinationPath: destinationURL.deletingLastPathComponent()
                    .resolvingSymlinksInPath()
                    .appendingPathComponent(destinationURL.lastPathComponent)
                    .path
            )
        }
        guard sqlite3_vfs_register(wrapperVFS, 1) == SQLITE_OK else {
            Self.stateLock.withLock { Self.installation = nil }
            wrapperVFS.deinitialize(count: 1)
            wrapperVFS.deallocate()
            free(wrapperName)
            throw SQLiteFixtureError.message("unable to register the late-source SQLite VFS")
        }

        self.originalVFS = originalVFS
        self.wrapperVFS = wrapperVFS
        self.wrapperName = wrapperName
    }

    func stop() {
        guard !isStopped else { return }
        _ = sqlite3_vfs_unregister(wrapperVFS)
        _ = sqlite3_vfs_register(originalVFS, 1)
        Self.stateLock.withLock { Self.installation = nil }
        wrapperVFS.deinitialize(count: 1)
        wrapperVFS.deallocate()
        free(wrapperName)
        isStopped = true
    }

    deinit {
        stop()
    }

    private static let interceptingOpen: @convention(c) (
        UnsafeMutablePointer<sqlite3_vfs>?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<sqlite3_file>?,
        Int32,
        UnsafeMutablePointer<Int32>?
    ) -> Int32 = { _, name, file, flags, outputFlags in
        let originalVFS: UnsafeMutablePointer<sqlite3_vfs>? = stateLock.withLock {
            guard var current = installation else { return nil }
            defer { installation = current }
            if let name {
                let openedPath = String(cString: name)
                current.observedOpenNames.append(openedPath)
                let isDestination = openedPath == current.destinationPath
                    || openedPath == "/private" + current.destinationPath
                if isDestination, !current.didInstall {
                    current.didInstall = Darwin.link(current.sourcePath, openedPath) == 0
                    if !current.didInstall {
                        current.installErrno = errno
                    }
                }
            }
            return current.originalVFS
        }
        guard let originalVFS, let originalOpen = originalVFS.pointee.xOpen else {
            return SQLITE_CANTOPEN
        }
        return originalOpen(originalVFS, name, file, flags, outputFlags)
    }
}
