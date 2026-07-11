import Darwin
import Foundation
import os

enum IsolationBootstrapError: Error, LocalizedError, Equatable {
    case invalidArguments
    case unavailableInThisBuild
    case missingFactor(String)
    case markerInvalid(String)
    case pathInvalid(String)
    case insecureMetadata(String)
    case productionOverlap(String)
    case endpointInvalid(String)
    case digestMismatch(String)
    case weakAPIKey
    case accessBeforeInstall(String)
    case alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "Isolation activation arguments are incomplete or ambiguous"
        case .unavailableInThisBuild: "Isolation dogfood mode is unavailable in this build"
        case .missingFactor(let factor): "Isolation activation is missing required factor: \(factor)"
        case .markerInvalid(let detail): "Isolation marker is invalid: \(detail)"
        case .pathInvalid(let detail): "Isolation path is invalid: \(detail)"
        case .insecureMetadata(let detail): "Isolation filesystem metadata is insecure: \(detail)"
        case .productionOverlap(let detail): "Isolation overlaps a production resource: \(detail)"
        case .endpointInvalid(let detail): "Isolation Hermes endpoint is invalid: \(detail)"
        case .digestMismatch(let detail): "Isolation digest mismatch: \(detail)"
        case .weakAPIKey: "Isolation Hermes API key is missing or weak"
        case .accessBeforeInstall(let accessor): "Isolation dependency was accessed before bootstrap: \(accessor)"
        case .alreadyInstalled: "Isolation configuration is already installed"
        }
    }
}

struct IsolationBootstrapDependencies: Sendable {
    var uid: @Sendable () -> uid_t
    var bundleID: @Sendable () -> String?
    var buildCommit: @Sendable () -> String?
    var productionRoots: @Sendable () -> [URL]
    var endpointIsOccupied: @Sendable (URL) -> Bool
    var installProcessEnvironment: @Sendable ([String: String]) throws -> Void

    static let live = IsolationBootstrapDependencies(
        uid: { getuid() },
        bundleID: { Bundle.main.bundleIdentifier },
        buildCommit: {
            Bundle.main.object(forInfoDictionaryKey: "CiderBuildCommit") as? String
                ?? ProcessInfo.processInfo.environment["CIDER_BUILD_COMMIT"]
        },
        productionRoots: {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return [
                home.appendingPathComponent("CiderVault", isDirectory: true),
                home.appendingPathComponent(".hermes", isDirectory: true),
                home.appendingPathComponent("Library/Caches/Cider", isDirectory: true),
                home.appendingPathComponent("Library/Logs/Cider", isDirectory: true)
            ]
        },
        endpointIsOccupied: { endpoint in
            guard let port = endpoint.port else { return true }
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return true }
            defer { close(descriptor) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        },
        installProcessEnvironment: { environment in
            for (key, value) in environment {
                guard setenv(key, value, 1) == 0 else {
                    throw IsolationBootstrapError.insecureMetadata("cannot install \(key)")
                }
            }
        }
    )
}

final class IsolationAccessSentinel: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var firstAccess: String?

    func record(_ accessor: String) {
        lock.lock()
        if firstAccess == nil { firstAccess = accessor }
        lock.unlock()
    }

    func assertUntouched() throws {
        lock.lock()
        let access = firstAccess
        lock.unlock()
        if let access {
            throw IsolationBootstrapError.accessBeforeInstall(access)
        }
    }
}

final class IsolationConfigurationStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var installed: IsolationConfiguration?

    func install(_ configuration: IsolationConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }
        guard installed == nil else { throw IsolationBootstrapError.alreadyInstalled }
        installed = configuration
    }

    var configuration: IsolationConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }
}

struct IsolationBootstrap: Sendable {
    static let activationArgument = "--cider-isolation-dogfood"
    static let acknowledgementArgument = "--cider-isolation-acknowledge-process-local-only"
    static let rootArgumentPrefix = "--cider-isolation-root="
    static let runIDArgumentPrefix = "--cider-isolation-run-id="
    static let nonceEnvironmentKey = "CIDER_ISOLATION_NONCE"
    static let sandboxDigestEnvironmentKey = "CIDER_ISOLATION_SANDBOX_POLICY_DIGEST"

    private let store: IsolationConfigurationStore
    private let sentinel: IsolationAccessSentinel
    private let dependencies: IsolationBootstrapDependencies

    init(
        store: IsolationConfigurationStore,
        sentinel: IsolationAccessSentinel,
        dependencies: IsolationBootstrapDependencies
    ) {
        self.store = store
        self.sentinel = sentinel
        self.dependencies = dependencies
    }

    @discardableResult
    func install(
        arguments: [String],
        environment: [String: String],
        attestationSink: @Sendable (IsolationStartupAttestation) throws -> Void = { _ in }
    ) throws -> IsolationStartupAttestation {
        guard store.configuration == nil else { throw IsolationBootstrapError.alreadyInstalled }
        let isolationArguments = arguments.filter { $0.hasPrefix("--cider-isolation-") }
        guard !isolationArguments.isEmpty else {
            let configuration = IsolationConfiguration.production
            try store.install(configuration)
            let attestation = IsolationStartupAttestation(configuration: configuration)
            try attestationSink(attestation)
            return attestation
        }

        #if !DEBUG
        throw IsolationBootstrapError.unavailableInThisBuild
        #else
        try sentinel.assertUntouched()
        let configuration = try validatedDogfoodConfiguration(
            isolationArguments: isolationArguments,
            environment: environment
        )
        try dependencies.installProcessEnvironment(ciderProcessEnvironment(configuration))
        try store.install(configuration)
        let attestation = IsolationStartupAttestation(configuration: configuration)
        try attestationSink(attestation)
        return attestation
        #endif
    }

    #if DEBUG
    private func validatedDogfoodConfiguration(
        isolationArguments: [String],
        environment: [String: String]
    ) throws -> IsolationConfiguration {
        guard isolationArguments.count == 4,
              isolationArguments.filter({ $0 == Self.activationArgument }).count == 1,
              isolationArguments.filter({ $0 == Self.acknowledgementArgument }).count == 1,
              let rootValue = singleValue(prefix: Self.rootArgumentPrefix, in: isolationArguments),
              let runIDValue = singleValue(prefix: Self.runIDArgumentPrefix, in: isolationArguments),
              let runID = UUID(uuidString: runIDValue)
        else { throw IsolationBootstrapError.invalidArguments }

        let nonce = try requiredEnvironment(Self.nonceEnvironmentKey, environment: environment)
        let sandboxDigest = try requiredEnvironment(Self.sandboxDigestEnvironmentKey, environment: environment)
        try validateHexDigest(sandboxDigest, name: "sandbox policy")

        let root = try canonicalRoot(rawPath: rootValue)
        let markerURL = root.appendingPathComponent("isolation-marker.json")
        try validateSecureFile(markerURL, uid: dependencies.uid(), exactMode: 0o600, executable: false)
        let markerData = try readNoFollow(markerURL)
        let marker = try decodeMarker(markerData)

        guard marker.schemaVersion == 1 else {
            throw IsolationBootstrapError.markerInvalid("unsupported schema")
        }
        guard marker.runID == runID.uuidString.lowercased() else {
            throw IsolationBootstrapError.markerInvalid("run ID mismatch")
        }
        guard marker.nonce == nonce else {
            throw IsolationBootstrapError.markerInvalid("nonce mismatch")
        }
        guard marker.sandboxPolicyDigest == sandboxDigest else {
            throw IsolationBootstrapError.markerInvalid("sandbox policy mismatch")
        }
        guard marker.expectedUID == UInt32(dependencies.uid()) else {
            throw IsolationBootstrapError.markerInvalid("UID mismatch")
        }
        guard let bundleID = dependencies.bundleID(), marker.expectedBundleID == bundleID else {
            throw IsolationBootstrapError.markerInvalid("bundle mismatch")
        }
        guard let buildCommit = dependencies.buildCommit(), marker.expectedBuildCommit == buildCommit else {
            throw IsolationBootstrapError.markerInvalid("build mismatch")
        }
        try validateHexDigest(marker.hermesExecutableDigest, name: "Hermes executable")

        try validateSecureDirectory(root, uid: dependencies.uid())
        try rejectRedirectsAndInsecureComponents(beneath: root, uid: dependencies.uid())
        try rejectProductionOverlap(root: root, productionRoots: dependencies.productionRoots())

        guard let endpoint = URL(string: marker.hermesEndpoint) else {
            throw IsolationBootstrapError.endpointInvalid("malformed URL")
        }
        try validateEndpoint(endpoint)
        guard !dependencies.endpointIsOccupied(endpoint) else {
            throw IsolationBootstrapError.endpointInvalid("endpoint is occupied")
        }

        let executable = root.appendingPathComponent("hermes/runtime/bin/hermes")
        try validateSecureFile(executable, uid: dependencies.uid(), exactMode: nil, executable: true)
        let executableDigest = try IsolationDigest.sha256(fileURL: executable)
        guard executableDigest == marker.hermesExecutableDigest else {
            throw IsolationBootstrapError.digestMismatch("Hermes executable")
        }

        let keyURL = root.appendingPathComponent("hermes/secrets/hermes-api-key")
        try validateSecureFile(keyURL, uid: dependencies.uid(), exactMode: 0o600, executable: false)
        let keyData = try readNoFollow(keyURL)
        guard keyData.count >= 32,
              let apiKey = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              apiKey.utf8.count >= 32,
              !apiKey.contains("\n")
        else { throw IsolationBootstrapError.weakAPIKey }

        let configuration = IsolationConfiguration.dogfood(
            schemaVersion: marker.schemaVersion,
            runID: runID,
            root: root,
            markerDigest: IsolationDigest.sha256(markerData),
            expectedUID: dependencies.uid(),
            expectedBundleID: bundleID,
            expectedBuildCommit: buildCommit,
            sandboxPolicyDigest: sandboxDigest,
            nonceDigest: IsolationDigest.sha256(Data(nonce.utf8)),
            hermesExecutableDigest: executableDigest,
            hermesEndpoint: endpoint,
            hermesAPIKey: apiKey
        )
        try validateDerivedPaths(configuration)
        return configuration
    }

    private func singleValue(prefix: String, in arguments: [String]) -> String? {
        let values = arguments.filter { $0.hasPrefix(prefix) }
        guard values.count == 1 else { return nil }
        let value = String(values[0].dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private func requiredEnvironment(_ key: String, environment: [String: String]) throws -> String {
        guard let value = environment[key], !value.isEmpty else {
            throw IsolationBootstrapError.missingFactor(key)
        }
        return value
    }

    private func canonicalRoot(rawPath: String) throws -> URL {
        guard rawPath.hasPrefix("/"),
              !rawPath.contains("~"),
              !rawPath.split(separator: "/", omittingEmptySubsequences: false).contains("."),
              !rawPath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              rawPath == rawPath.precomposedStringWithCanonicalMapping
        else { throw IsolationBootstrapError.pathInvalid("root syntax") }

        let url = URL(fileURLWithPath: rawPath, isDirectory: true)
        guard url.path == rawPath else {
            throw IsolationBootstrapError.pathInvalid("root is not standardized")
        }
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(rawPath, &resolved) != nil else {
            throw IsolationBootstrapError.pathInvalid("root does not exist")
        }
        let canonical = String(decoding: resolved.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        guard canonical == rawPath else {
            throw IsolationBootstrapError.pathInvalid("root is not canonical: \(rawPath) -> \(canonical)")
        }
        return url
    }

    private func validateSecureDirectory(_ url: URL, uid: uid_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == uid,
              (info.st_mode & 0o777) == 0o700
        else { throw IsolationBootstrapError.insecureMetadata(url.path) }
    }

    private func validateSecureFile(
        _ url: URL,
        uid: uid_t,
        exactMode: mode_t?,
        executable: Bool
    ) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == uid,
              info.st_nlink == 1,
              (info.st_mode & 0o022) == 0,
              exactMode == nil || (info.st_mode & 0o777) == exactMode,
              !executable || (info.st_mode & 0o100) != 0
        else { throw IsolationBootstrapError.insecureMetadata(url.path) }
    }

    private func readNoFollow(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw IsolationBootstrapError.insecureMetadata(url.path) }
        defer { close(descriptor) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw IsolationBootstrapError.insecureMetadata(url.path) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private func rejectRedirectsAndInsecureComponents(beneath root: URL, uid: uid_t) throws {
        let keys: [URLResourceKey] = [
            .isSymbolicLinkKey, .isAliasFileKey, .isMountTriggerKey, .volumeIdentifierKey
        ]
        let rootVolume = try root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        var normalizedRelativePaths = Set<String>()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw IsolationBootstrapError.pathInvalid("cannot inspect root") }
        for case let url as URL in enumerator {
            let relativePath = String(url.path.dropFirst(root.path.count))
                .precomposedStringWithCanonicalMapping
                .lowercased()
            guard normalizedRelativePaths.insert(relativePath).inserted else {
                throw IsolationBootstrapError.pathInvalid("case or Unicode collision: \(url.path)")
            }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true || values.isAliasFile == true || values.isMountTrigger == true ||
                String(describing: values.volumeIdentifier) != String(describing: rootVolume) {
                throw IsolationBootstrapError.pathInvalid("redirecting component: \(url.path)")
            }
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  info.st_uid == uid,
                  (info.st_mode & 0o022) == 0,
                  (info.st_mode & S_IFMT) != S_IFREG || info.st_nlink == 1,
                  (info.st_mode & S_IFMT) != S_IFDIR || (info.st_mode & 0o777) == 0o700
            else { throw IsolationBootstrapError.insecureMetadata(url.path) }
        }
    }

    private func rejectProductionOverlap(root: URL, productionRoots: [URL]) throws {
        for production in productionRoots {
            let isolatedPath = comparisonPath(root.path)
            let productionPath = comparisonPath(canonicalPathIfExisting(production))
            if isEqualOrAncestor(isolatedPath, productionPath) || isEqualOrAncestor(productionPath, isolatedPath) {
                throw IsolationBootstrapError.productionOverlap(production.path)
            }
            guard FileManager.default.fileExists(atPath: production.path) else { continue }
            let isolatedID = try root.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            let productionID = try production.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            if let isolatedID, let productionID,
               String(describing: isolatedID) == String(describing: productionID) {
                throw IsolationBootstrapError.productionOverlap(production.path)
            }
        }
    }

    private func comparisonPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func canonicalPathIfExisting(_ url: URL) -> String {
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &resolved) != nil else { return url.path }
        return String(decoding: resolved.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }

    private func isEqualOrAncestor(_ ancestor: String, _ candidate: String) -> Bool {
        candidate == ancestor || candidate.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    private func validateEndpoint(_ endpoint: URL) throws {
        guard endpoint.scheme == "http",
              endpoint.host == "127.0.0.1",
              endpoint.port != nil,
              endpoint.port != 8642,
              endpoint.port! >= 1024,
              endpoint.port! <= 65535,
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/"
        else { throw IsolationBootstrapError.endpointInvalid("must be direct non-production loopback HTTP") }
    }

    private func validateHexDigest(_ digest: String, name: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy(allowed.contains)
        else { throw IsolationBootstrapError.digestMismatch(name) }
    }

    private func validateDerivedPaths(_ configuration: IsolationConfiguration) throws {
        guard let root = configuration.root else { throw IsolationBootstrapError.pathInvalid("missing root") }
        let paths = [
            configuration.ciderHome,
            configuration.vaultRoot,
            configuration.databaseURL,
            configuration.diagnosticsRoot,
            configuration.cachesRoot,
            configuration.temporaryRoot,
            configuration.logsRoot,
            configuration.hermesHome,
            configuration.hermesStateDatabaseURL,
            configuration.hermesSessionsRoot,
            configuration.hermesExecutable,
            configuration.hermesWorkingDirectory,
            configuration.hermesAPIKeyFile,
            configuration.hermesGatewayLockRoot
        ].compactMap { $0 }
        guard paths.allSatisfy({ isEqualOrAncestor(root.path, $0.path) && $0.path != root.path }) else {
            throw IsolationBootstrapError.pathInvalid("derived path escaped root")
        }
    }

    private func ciderProcessEnvironment(_ configuration: IsolationConfiguration) -> [String: String] {
        guard let ciderHome = configuration.ciderHome,
              let temporaryRoot = configuration.temporaryRoot,
              let logsRoot = configuration.logsRoot
        else { return [:] }
        return [
            "CFFIXED_USER_HOME": ciderHome.path,
            "CIDER_PERF_LOG_PATH": logsRoot.appendingPathComponent("performance.log").path,
            "HOME": ciderHome.path,
            "TMPDIR": temporaryRoot.path
        ]
    }

    private struct Marker: Decodable {
        let schemaVersion: Int
        let runID: String
        let nonce: String
        let expectedBuildCommit: String
        let expectedBundleID: String
        let expectedUID: UInt32
        let sandboxPolicyDigest: String
        let hermesExecutableDigest: String
        let hermesEndpoint: String
    }

    private func decodeMarker(_ data: Data) throws -> Marker {
        let allowed: Set<String> = [
            "schemaVersion", "runID", "nonce", "expectedBuildCommit", "expectedBundleID",
            "expectedUID", "sandboxPolicyDigest", "hermesExecutableDigest", "hermesEndpoint"
        ]
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == allowed
        else { throw IsolationBootstrapError.markerInvalid("partial or unknown fields") }
        do {
            return try JSONDecoder().decode(Marker.self, from: data)
        } catch {
            throw IsolationBootstrapError.markerInvalid("cannot decode")
        }
    }
    #endif
}

enum IsolationRuntime {
    private static let store = IsolationConfigurationStore()
    private static let sentinel = IsolationAccessSentinel()

    static var configuration: IsolationConfiguration {
        if let configuration = store.configuration { return configuration }
        if ProcessInfo.processInfo.arguments.contains(IsolationBootstrap.activationArgument) {
            sentinel.record("configuration")
        }
        return .production
    }

    static var userDefaults: UserDefaults {
        recordPathAccess("IsolationRuntime.userDefaults")
        guard let suiteName = configuration.defaultsSuiteName else { return .standard }
        return UserDefaults(suiteName: suiteName)!
    }

    static func recordPathAccess(_ accessor: String) {
        guard store.configuration == nil,
              ProcessInfo.processInfo.arguments.contains(IsolationBootstrap.activationArgument)
        else { return }
        sentinel.record(accessor)
    }

    @discardableResult
    static func installAtProcessStart(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        attestationSink: @Sendable (IsolationStartupAttestation) throws -> Void = { _ in }
    ) throws -> IsolationStartupAttestation {
        try IsolationBootstrap(store: store, sentinel: sentinel, dependencies: .live).install(
            arguments: arguments,
            environment: environment,
            attestationSink: attestationSink
        )
    }
}
