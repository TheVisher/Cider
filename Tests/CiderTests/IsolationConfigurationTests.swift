import Darwin
import Foundation
import Testing
@testable import Cider

@Suite("CID-782 isolation configuration", .serialized)
struct IsolationConfigurationTests {
    @Test("production configuration and explicit production clients remain unchanged")
    func productionEquivalence() {
        let production = IsolationConfiguration.production
        #expect(production.mode == .production)
        #expect(production.root == nil)
        #expect(production.integrationPlan == .production)

        let endpoint = URL(string: "http://127.0.0.1:8642")!
        let session = URLSession(configuration: .default)
        let client = HermesAPIClient(baseURL: endpoint, apiKey: "production-key", session: session)
        #expect(client.baseURL == endpoint)
        #expect(client.apiKey == "production-key")
        #expect(client.session === session)

        var config = CiderConfig()
        config.vaultDirectory = "/private/tmp/production-vault"
        #expect(StoragePaths.vaultDirectoryURL(
            config: config,
            isolationConfiguration: .production
        ).path == "/private/tmp/production-vault")
    }

    @Test("complete dogfood fixture derives every child beneath one canonical root")
    func validDogfoodAndDerivedPaths() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let configuration = try fixture.install()

        #expect(configuration.isDogfood)
        #expect(configuration.integrationPlan == .dogfood)
        let root = try #require(configuration.root)
        for path in fixture.derivedPaths(configuration) {
            #expect(path.path.hasPrefix(root.path + "/"))
        }
        #expect(StoragePaths.vaultDirectoryURL(
            config: fixture.productionConfig,
            isolationConfiguration: configuration
        ) == configuration.vaultRoot)

        let client = HermesAPIClient(isolationConfiguration: configuration)
        #expect(client.baseURL == configuration.hermesEndpoint)
        #expect(client.apiKey == fixture.apiKey)
    }

    @Test("activation rejects every independently missing factor")
    func missingFactors() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }

        for index in fixture.arguments.indices.dropFirst() {
            var arguments = fixture.arguments
            arguments.remove(at: index)
            #expect(throws: IsolationBootstrapError.self) {
                try fixture.install(arguments: arguments)
            }
        }
        for key in [IsolationBootstrap.nonceEnvironmentKey, IsolationBootstrap.sandboxDigestEnvironmentKey] {
            var environment = fixture.environment
            environment.removeValue(forKey: key)
            #expect(throws: IsolationBootstrapError.self) {
                try fixture.install(environment: environment)
            }
        }

        // A lone environment variable is ordinary production mode, never activation.
        let store = IsolationConfigurationStore()
        let result = try IsolationBootstrap(
            store: store,
            sentinel: IsolationAccessSentinel(),
            dependencies: fixture.dependencies
        ).install(arguments: ["Cider"], environment: [IsolationBootstrap.nonceEnvironmentKey: fixture.nonce])
        #expect(result.mode == "production")
    }

    @Test("marker mismatches fail independently")
    func markerMismatches() throws {
        let mutations: [[String: Any]] = [
            ["runID": UUID().uuidString.lowercased()],
            ["nonce": "wrong-nonce"],
            ["expectedBuildCommit": "wrong-build"],
            ["expectedBundleID": "wrong.bundle"],
            ["expectedUID": UInt32(getuid()) &+ 1],
            ["sandboxPolicyDigest": String(repeating: "b", count: 64)],
            ["hermesExecutableDigest": String(repeating: "c", count: 64)]
        ]
        for mutation in mutations {
            let fixture = try IsolationFixture()
            defer { fixture.remove() }
            try fixture.writeMarker(overrides: mutation)
            #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        }
    }

    @Test("partial, unknown, and mixed-root marker input fails closed")
    func partialAndMixedConfiguration() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }

        try fixture.writeMarker(removing: "expectedUID")
        #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        try fixture.writeMarker(overrides: ["vaultRoot": fixture.productionRoot.path])
        #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        try fixture.writeMarker(overrides: ["hermesExecutable": "/usr/local/bin/hermes"])
        #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
    }

    @Test("relative tilde dot dot-dot canonical case and Unicode root variants fail")
    func invalidRootSpellings() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let decomposed = fixture.root.path.decomposedStringWithCanonicalMapping
        let candidates = [
            "relative/root", "~/root", fixture.root.path + "/.",
            fixture.root.path + "/child/..", fixture.root.path.uppercased(), decomposed
        ]
        for candidate in candidates where candidate != fixture.root.path {
            var arguments = fixture.arguments
            arguments[3] = IsolationBootstrap.rootArgumentPrefix + candidate
            #expect(throws: IsolationBootstrapError.self) { try fixture.install(arguments: arguments) }
        }
    }

    @Test("production equality parent child and same resource are rejected")
    func productionOverlap() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        for production in [fixture.root, fixture.root.deletingLastPathComponent(), fixture.root.appendingPathComponent("cider")] {
            var dependencies = fixture.dependencies
            dependencies.productionRoots = { [production] }
            #expect(throws: IsolationBootstrapError.self) {
                try fixture.install(dependencies: dependencies)
            }
        }
    }

    @Test("symlink at known root descendants is rejected")
    func symlinkRejection() throws {
        for relative in ["extra-link", "cider/link", "hermes/profile/link"] {
            let fixture = try IsolationFixture()
            defer { fixture.remove() }
            let link = fixture.root.appendingPathComponent(relative)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.productionRoot)
            #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        }
    }

    @Test("symlink marker key and executable leaves are rejected")
    func sensitiveLeafSymlinks() throws {
        for leaf in ["isolation-marker.json", "hermes/secrets/hermes-api-key", "hermes/runtime/bin/hermes"] {
            let fixture = try IsolationFixture()
            defer { fixture.remove() }
            let leafURL = fixture.root.appendingPathComponent(leaf)
            let target = fixture.productionRoot.appendingPathComponent(UUID().uuidString)
            try Data("production-resource".utf8).write(to: target)
            chmod(target.path, 0o700)
            try FileManager.default.removeItem(at: leafURL)
            try FileManager.default.createSymbolicLink(at: leafURL, withDestinationURL: target)
            #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        }
    }

    @Test("insecure root marker key and executable metadata is rejected")
    func insecureMetadata() throws {
        let cases: [(IsolationFixture) throws -> Void] = [
            { chmod($0.root.path, 0o755) },
            { chmod($0.markerURL.path, 0o644) },
            { chmod($0.keyURL.path, 0o644) },
            { chmod($0.executableURL.path, 0o722) }
        ]
        for mutate in cases {
            let fixture = try IsolationFixture()
            defer { fixture.remove() }
            try mutate(fixture)
            #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        }
    }

    @Test("port 8642 non-loopback occupied malformed and redirect-like endpoints fail")
    func unsafeEndpoints() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        for endpoint in [
            "http://127.0.0.1:8642", "http://0.0.0.0:18642", "http://localhost:18642",
            "https://127.0.0.1:18642", "http://127.0.0.1:18642/redirect?to=prod"
        ] {
            try fixture.writeMarker(overrides: ["hermesEndpoint": endpoint])
            #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
        }
        try fixture.writeMarker()
        var occupied = fixture.dependencies
        occupied.endpointIsOccupied = { _ in true }
        #expect(throws: IsolationBootstrapError.self) { try fixture.install(dependencies: occupied) }
    }

    @Test("weak and missing API keys fail closed")
    func weakKeys() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        try Data("short".utf8).write(to: fixture.keyURL)
        chmod(fixture.keyURL.path, 0o600)
        #expect(throws: IsolationBootstrapError.self) { try fixture.install() }

        try FileManager.default.removeItem(at: fixture.keyURL)
        #expect(throws: IsolationBootstrapError.self) { try fixture.install() }
    }

    @Test("Hermes environment is an exact allowlist with no ambient secret or production path")
    func sanitizedHermesEnvironment() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let configuration = try fixture.install()
        let environment = configuration.hermesChildEnvironment(apiKey: fixture.apiKey)
        #expect(Set(environment.keys) == [
            "API_SERVER_ENABLED", "API_SERVER_HOST", "API_SERVER_KEY", "API_SERVER_PORT",
            "HERMES_GATEWAY_LOCK_DIR", "HERMES_HOME", "HOME", "LANG", "LC_ALL", "PATH",
            "TERMINAL_HOME_MODE", "TMPDIR", "XDG_CACHE_HOME", "XDG_STATE_HOME"
        ])
        for forbidden in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "SSH_AUTH_SOCK",
                          "AWS_ACCESS_KEY_ID", "OPENAI_API_KEY", "PYTHONPATH", "NODE_PATH"] {
            #expect(environment[forbidden] == nil)
        }
        #expect(!environment.values.contains { $0.contains(fixture.productionRoot.path) })
    }

    @Test("Cider process environment derives only non-secret paths from the root")
    func ciderProcessEnvironment() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        var dependencies = fixture.dependencies
        dependencies.installProcessEnvironment = { environment in
            #expect(Set(environment.keys) == ["CFFIXED_USER_HOME", "CIDER_PERF_LOG_PATH", "HOME", "TMPDIR"])
            #expect(environment.values.allSatisfy { $0.hasPrefix(fixture.root.path + "/") })
            #expect(!environment.values.contains(fixture.apiKey))
            #expect(!environment.values.contains(fixture.nonce))
        }
        _ = try fixture.install(dependencies: dependencies)
    }

    @Test("dogfood process runner cannot execute CLI fallback")
    func cliFallbackImpossible() async throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let configuration = try fixture.install()
        let runner = HermesProcessRunner(isolationConfiguration: configuration)
        #expect(runner.cliExecutionAllowed == false)
        await #expect(throws: HermesSessionClientError.self) {
            try await runner.runHermes(arguments: ["sessions", "list"])
        }

        let productionRunner = HermesProcessRunner(
            executablePath: "/usr/bin/true",
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp"),
            isolationConfiguration: .production
        )
        #expect(productionRunner.cliExecutionAllowed)
    }

    @Test("attestation is deterministic credential-free and states both limitations")
    func sanitizedAttestation() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let configuration = try fixture.install()
        let attestation = IsolationStartupAttestation(configuration: configuration)
        let first = try attestation.encoded()
        let second = try attestation.encoded()
        let text = String(decoding: first, as: UTF8.self)
        #expect(first == second)
        #expect(attestation.processLocalOnly)
        #expect(attestation.osConfinementRequired)
        #expect(!text.contains(fixture.apiKey))
        #expect(!text.contains(fixture.nonce))
        #expect(!text.contains("message content"))
        #expect(!text.contains("ambient-secret"))

        try IsolationAttestationSink.writeInsideIsolationRoot(attestation)
        let writtenURL = fixture.root.appendingPathComponent("startup-attestation.json")
        #expect(FileManager.default.fileExists(atPath: writtenURL.path))
        #expect(try Data(contentsOf: writtenURL) == first)
    }
}

final class IsolationFixture: @unchecked Sendable {
    let root: URL
    let productionRoot: URL
    let markerURL: URL
    let keyURL: URL
    let executableURL: URL
    let runID = UUID()
    let nonce = "fixture-nonce-that-is-not-attested"
    let sandboxDigest = String(repeating: "a", count: 64)
    let apiKey = "fixture-api-key-0123456789-abcdefghijklmno"
    let bundleID = "com.cider.tests"
    let buildCommit = "ce58a53cbd08ff2f20141fd5a8d433d3e1aa1a56"
    var dependencies: IsolationBootstrapDependencies

    var arguments: [String] {
        [
            "Cider",
            IsolationBootstrap.activationArgument,
            IsolationBootstrap.acknowledgementArgument,
            IsolationBootstrap.rootArgumentPrefix + root.path,
            IsolationBootstrap.runIDArgumentPrefix + runID.uuidString.lowercased()
        ]
    }
    var environment: [String: String] {
        [
            IsolationBootstrap.nonceEnvironmentKey: nonce,
            IsolationBootstrap.sandboxDigestEnvironmentKey: sandboxDigest,
            "HTTP_PROXY": "http://production-proxy.invalid",
            "SSH_AUTH_SOCK": "/production/agent.sock",
            "OPENAI_API_KEY": "ambient-secret"
        ]
    }

    var productionConfig: CiderConfig {
        var config = CiderConfig()
        config.vaultDirectory = productionRoot.path
        config.directoryOverrides = [StorageType.notes.rawValue: productionRoot.appendingPathComponent("notes").path]
        return config
    }

    init() throws {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(temporaryPath, &resolved) != nil else {
            throw IsolationBootstrapError.pathInvalid("test temporary root")
        }
        let canonicalTemporaryPath = String(
            decoding: resolved.prefix { $0 != 0 }.map(UInt8.init),
            as: UTF8.self
        )
        let temporary = URL(fileURLWithPath: canonicalTemporaryPath, isDirectory: true)
        root = temporary.appendingPathComponent("cider-isolation-\(UUID().uuidString)", isDirectory: true)
        productionRoot = temporary.appendingPathComponent("cider-production-\(UUID().uuidString)", isDirectory: true)
        markerURL = root.appendingPathComponent("isolation-marker.json")
        keyURL = root.appendingPathComponent("hermes/secrets/hermes-api-key")
        executableURL = root.appendingPathComponent("hermes/runtime/bin/hermes")
        dependencies = IsolationBootstrapDependencies(
            uid: { getuid() },
            bundleID: { "com.cider.tests" },
            buildCommit: { "ce58a53cbd08ff2f20141fd5a8d433d3e1aa1a56" },
            productionRoots: { [] },
            endpointIsOccupied: { _ in false },
            installProcessEnvironment: { _ in }
        )
        try secureDirectory(root)
        try secureDirectory(productionRoot)
        for relative in [
            "cider", "cider/home", "cider/vault", "cider/cache", "cider/logs", "tmp", "tmp/cider",
            "hermes", "hermes/profile", "hermes/profile/sessions", "hermes/profile/gateway-locks",
            "hermes/runtime", "hermes/runtime/bin", "hermes/secrets"
        ] {
            try secureDirectory(root.appendingPathComponent(relative, isDirectory: true))
        }
        try Data("fixture-hermes-executable".utf8).write(to: executableURL)
        chmod(executableURL.path, 0o700)
        try Data(apiKey.utf8).write(to: keyURL)
        chmod(keyURL.path, 0o600)
        try writeMarker()
        let capturedProductionRoot = productionRoot
        dependencies.productionRoots = { [capturedProductionRoot] }
    }

    func install(
        arguments: [String]? = nil,
        environment: [String: String]? = nil,
        dependencies: IsolationBootstrapDependencies? = nil
    ) throws -> IsolationConfiguration {
        let store = IsolationConfigurationStore()
        let bootstrap = IsolationBootstrap(
            store: store,
            sentinel: IsolationAccessSentinel(),
            dependencies: dependencies ?? self.dependencies
        )
        _ = try bootstrap.install(
            arguments: arguments ?? self.arguments,
            environment: environment ?? self.environment
        )
        return try #require(store.configuration)
    }

    func writeMarker(overrides: [String: Any] = [:], removing: String? = nil) throws {
        var marker: [String: Any] = [
            "schemaVersion": 1,
            "runID": runID.uuidString.lowercased(),
            "nonce": nonce,
            "expectedBuildCommit": buildCommit,
            "expectedBundleID": bundleID,
            "expectedUID": UInt32(getuid()),
            "sandboxPolicyDigest": sandboxDigest,
            "hermesExecutableDigest": try IsolationDigest.sha256(fileURL: executableURL),
            "hermesEndpoint": "http://127.0.0.1:18642"
        ]
        overrides.forEach { marker[$0.key] = $0.value }
        if let removing { marker.removeValue(forKey: removing) }
        let data = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
        try data.write(to: markerURL, options: .atomic)
        chmod(markerURL.path, 0o600)
    }

    func derivedPaths(_ configuration: IsolationConfiguration) -> [URL] {
        [
            configuration.ciderHome, configuration.vaultRoot, configuration.databaseURL,
            configuration.diagnosticsRoot, configuration.cachesRoot, configuration.temporaryRoot,
            configuration.logsRoot, configuration.hermesHome, configuration.hermesStateDatabaseURL,
            configuration.hermesSessionsRoot, configuration.hermesExecutable,
            configuration.hermesWorkingDirectory, configuration.hermesAPIKeyFile,
            configuration.hermesGatewayLockRoot
        ].compactMap { $0 }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: productionRoot)
    }

    private func secureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }
}
