import CryptoKit
import Darwin
import Foundation

struct IsolationConfiguration: Sendable, Equatable {
    enum Mode: String, Sendable {
        case production
        #if DEBUG
        case dogfood
        #endif
    }

    struct IntegrationPlan: Sendable, Equatable {
        let accessibilityPrompt: Bool
        let sparkle: Bool
        let spotlight: Bool
        let sync: Bool
        let telegram: Bool
        let clipboardMonitoring: Bool
        let globalEventMonitoring: Bool
        let notificationScheduling: Bool
        let servicesRegistration: Bool
        let fileWatching: Bool
        let agentTools: Bool

        static let production = IntegrationPlan(
            accessibilityPrompt: true,
            sparkle: true,
            spotlight: true,
            sync: true,
            telegram: true,
            clipboardMonitoring: true,
            globalEventMonitoring: true,
            notificationScheduling: true,
            servicesRegistration: true,
            fileWatching: true,
            agentTools: true
        )

        #if DEBUG
        static let dogfood = IntegrationPlan(
            accessibilityPrompt: false,
            sparkle: false,
            spotlight: false,
            sync: false,
            telegram: false,
            clipboardMonitoring: false,
            globalEventMonitoring: false,
            notificationScheduling: false,
            servicesRegistration: false,
            fileWatching: false,
            agentTools: false
        )
        #endif
    }

    let mode: Mode
    let schemaVersion: Int
    let runID: UUID?
    let root: URL?
    let markerDigest: String?
    let expectedUID: uid_t?
    let expectedBundleID: String?
    let expectedBuildCommit: String?
    let sandboxPolicyDigest: String?
    let nonceDigest: String?

    let ciderHome: URL?
    let vaultRoot: URL?
    let databaseURL: URL?
    let diagnosticsRoot: URL?
    let defaultsSuiteName: String?
    let cachesRoot: URL?
    let temporaryRoot: URL?
    let logsRoot: URL?

    let hermesHome: URL?
    let hermesStateDatabaseURL: URL?
    let hermesSessionsRoot: URL?
    let hermesExecutable: URL?
    let hermesExecutableDigest: String?
    let hermesWorkingDirectory: URL?
    let hermesEndpoint: URL?
    let hermesAPIKeyFile: URL?
    let hermesAPIKey: String?
    let hermesGatewayLockRoot: URL?
    let integrationPlan: IntegrationPlan

    static let production = IsolationConfiguration(
        mode: .production,
        schemaVersion: 1,
        runID: nil,
        root: nil,
        markerDigest: nil,
        expectedUID: nil,
        expectedBundleID: nil,
        expectedBuildCommit: nil,
        sandboxPolicyDigest: nil,
        nonceDigest: nil,
        ciderHome: nil,
        vaultRoot: nil,
        databaseURL: nil,
        diagnosticsRoot: nil,
        defaultsSuiteName: nil,
        cachesRoot: nil,
        temporaryRoot: nil,
        logsRoot: nil,
        hermesHome: nil,
        hermesStateDatabaseURL: nil,
        hermesSessionsRoot: nil,
        hermesExecutable: nil,
        hermesExecutableDigest: nil,
        hermesWorkingDirectory: nil,
        hermesEndpoint: nil,
        hermesAPIKeyFile: nil,
        hermesAPIKey: nil,
        hermesGatewayLockRoot: nil,
        integrationPlan: .production
    )

    var isDogfood: Bool {
        #if DEBUG
        mode == .dogfood
        #else
        false
        #endif
    }

    func hermesChildEnvironment(apiKey: String) -> [String: String] {
        guard isDogfood,
              let hermesHome,
              let endpointPort = hermesEndpoint?.port,
              let hermesGatewayLockRoot
        else { return [:] }

        return [
            "API_SERVER_ENABLED": "1",
            "API_SERVER_HOST": "127.0.0.1",
            "API_SERVER_KEY": apiKey,
            "API_SERVER_PORT": String(endpointPort),
            "HERMES_GATEWAY_LOCK_DIR": hermesGatewayLockRoot.path,
            "HERMES_HOME": hermesHome.path,
            "HOME": hermesHome.appendingPathComponent("home", isDirectory: true).path,
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERMINAL_HOME_MODE": "profile",
            "TMPDIR": hermesHome.appendingPathComponent("tmp", isDirectory: true).path,
            "XDG_CACHE_HOME": hermesHome.appendingPathComponent("xdg/cache", isDirectory: true).path,
            "XDG_STATE_HOME": hermesHome.appendingPathComponent("xdg/state", isDirectory: true).path
        ]
    }

    #if DEBUG
    static func dogfood(
        schemaVersion: Int,
        runID: UUID,
        root: URL,
        markerDigest: String,
        expectedUID: uid_t,
        expectedBundleID: String,
        expectedBuildCommit: String,
        sandboxPolicyDigest: String,
        nonceDigest: String,
        hermesExecutableDigest: String,
        hermesEndpoint: URL,
        hermesAPIKey: String
    ) -> IsolationConfiguration {
        let cider = root.appendingPathComponent("cider", isDirectory: true)
        let vault = cider.appendingPathComponent("vault", isDirectory: true)
        let hermes = root.appendingPathComponent("hermes", isDirectory: true)
        let profile = hermes.appendingPathComponent("profile", isDirectory: true)
        return IsolationConfiguration(
            mode: .dogfood,
            schemaVersion: schemaVersion,
            runID: runID,
            root: root,
            markerDigest: markerDigest,
            expectedUID: expectedUID,
            expectedBundleID: expectedBundleID,
            expectedBuildCommit: expectedBuildCommit,
            sandboxPolicyDigest: sandboxPolicyDigest,
            nonceDigest: nonceDigest,
            ciderHome: cider.appendingPathComponent("home", isDirectory: true),
            vaultRoot: vault,
            databaseURL: vault.appendingPathComponent(".cider/cider.db"),
            diagnosticsRoot: vault.appendingPathComponent(".cider/diagnostics", isDirectory: true),
            defaultsSuiteName: "com.cider.app.dogfood.\(runID.uuidString.lowercased())",
            cachesRoot: cider.appendingPathComponent("cache", isDirectory: true),
            temporaryRoot: root.appendingPathComponent("tmp/cider", isDirectory: true),
            logsRoot: cider.appendingPathComponent("logs", isDirectory: true),
            hermesHome: profile,
            hermesStateDatabaseURL: profile.appendingPathComponent("state.db"),
            hermesSessionsRoot: profile.appendingPathComponent("sessions", isDirectory: true),
            hermesExecutable: hermes.appendingPathComponent("runtime/bin/hermes"),
            hermesExecutableDigest: hermesExecutableDigest,
            hermesWorkingDirectory: profile,
            hermesEndpoint: hermesEndpoint,
            hermesAPIKeyFile: hermes.appendingPathComponent("secrets/hermes-api-key"),
            hermesAPIKey: hermesAPIKey,
            hermesGatewayLockRoot: profile.appendingPathComponent("gateway-locks", isDirectory: true),
            integrationPlan: .dogfood
        )
    }
    #endif
}

struct IsolationStartupAttestation: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let mode: String
    let processLocalOnly: Bool
    let osConfinementRequired: Bool
    let limitations: [String]
    let runID: String?
    let root: String?
    let effectivePaths: [String: String]
    let endpoint: String?
    let buildCommit: String?
    let bundleID: String?
    let uid: UInt32?
    let markerDigest: String?
    let executableDigest: String?
    let sandboxPolicyDigest: String?
    let nonceDigest: String?

    init(configuration: IsolationConfiguration) {
        schemaVersion = configuration.schemaVersion
        mode = configuration.mode.rawValue
        processLocalOnly = true
        osConfinementRequired = true
        limitations = [
            "No OS filesystem or arbitrary-tool confinement is provided.",
            "Preflight validation does not eliminate same-user TOCTOU path replacement.",
            "A separate restricted account, OS sandbox, or VM is required before dogfood."
        ]
        runID = configuration.runID?.uuidString.lowercased()
        root = configuration.root?.path
        effectivePaths = [
            "ciderCaches": configuration.cachesRoot?.path,
            "ciderDatabase": configuration.databaseURL?.path,
            "ciderDiagnostics": configuration.diagnosticsRoot?.path,
            "ciderHome": configuration.ciderHome?.path,
            "ciderLogs": configuration.logsRoot?.path,
            "ciderTemporary": configuration.temporaryRoot?.path,
            "ciderVault": configuration.vaultRoot?.path,
            "hermesExecutable": configuration.hermesExecutable?.path,
            "hermesGatewayLocks": configuration.hermesGatewayLockRoot?.path,
            "hermesHome": configuration.hermesHome?.path,
            "hermesSessions": configuration.hermesSessionsRoot?.path,
            "hermesStateDatabase": configuration.hermesStateDatabaseURL?.path,
            "hermesWorkingDirectory": configuration.hermesWorkingDirectory?.path
        ].compactMapValues { $0 }
        endpoint = configuration.hermesEndpoint?.absoluteString
        buildCommit = configuration.expectedBuildCommit
        bundleID = configuration.expectedBundleID
        uid = configuration.expectedUID.map { UInt32($0) }
        markerDigest = configuration.markerDigest
        executableDigest = configuration.hermesExecutableDigest
        sandboxPolicyDigest = configuration.sandboxPolicyDigest
        nonceDigest = configuration.nonceDigest
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum IsolationAttestationSink {
    static func writeInsideIsolationRoot(_ attestation: IsolationStartupAttestation) throws {
        guard attestation.mode != IsolationConfiguration.Mode.production.rawValue,
              let root = attestation.root
        else { return }
        let destination = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("startup-attestation.json")
        let descriptor = open(
            destination.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else {
            throw IsolationBootstrapError.insecureMetadata(destination.path)
        }
        defer { close(descriptor) }
        let data = try attestation.encoded()
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    throw IsolationBootstrapError.insecureMetadata(destination.path)
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else {
            throw IsolationBootstrapError.insecureMetadata(destination.path)
        }
    }
}

enum IsolationDigest {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(fileURL: URL) throws -> String {
        sha256(try Data(contentsOf: fileURL, options: .mappedIfSafe))
    }
}
