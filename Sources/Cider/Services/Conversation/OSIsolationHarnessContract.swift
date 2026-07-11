import Foundation

// CID-784 is deliberately an offline proof contract. These value types and the
// validator below do not discover, launch, read, write, connect to, or activate
// anything. A separate, explicitly approved harness must supply all evidence.

struct OSIsolationHarnessContract: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    enum HarnessKind: String, Codable, Sendable {
        case disposableMacOSVM
        case restrictedAccountSandbox
    }

    enum AuthenticationStrategy: String, Codable, Sendable {
        case guestOnlyDeviceCodeOAuth
        case temporaryScopedAPIKey
    }

    struct ResourceIdentity: Codable, Equatable, Sendable {
        var path: String
        var volumeIdentity: String
        var fileIdentity: String
    }

    struct Digests: Codable, Equatable, Sendable {
        var run: String
        var build: String
        var guestImage: String
        var fixture: String
        var sandboxPolicy: String
        var networkPolicy: String
        var ciderRuntime: String
        var hermesRuntime: String
    }

    struct NetworkDestination: Codable, Equatable, Hashable, Sendable {
        enum Role: String, Codable, Hashable, Sendable { case authentication, model }

        var role: Role
        var origin: String
    }

    var schemaVersion: Int
    var kind: HarnessKind
    var runID: String
    var digests: Digests
    var isolatedRoot: ResourceIdentity
    var forbiddenProductionResources: [ResourceIdentity]
    var hostProductionUID: UInt32
    var guestUID: UInt32
    var endpointPort: UInt16
    var allowedNetworkDestinations: [NetworkDestination]
    var authenticationStrategy: AuthenticationStrategy

    func deterministicJSON() throws -> Data {
        try OSIsolationHarnessJSON.encode(self)
    }
}

struct OSIsolationHarnessEvidence: Codable, Equatable, Sendable {
    struct ProcessAttestation: Codable, Equatable, Sendable {
        enum Role: String, Codable, Sendable { case cider, hermes }

        var role: Role
        var pid: Int32
        var parentPID: Int32
        var startedAt: String
        var executablePath: String
        var codeIdentity: String
        var executableDigest: String
        var uid: UInt32
    }

    struct Disk: Codable, Equatable, Sendable {
        enum Role: String, Codable, Sendable { case guestDisk, sealedFixtureDisk }

        var role: Role
        var volumeIdentity: String
        var fileIdentity: String
        var mountPath: String
        var readOnly: Bool
        var mutable: Bool
    }

    struct DeviceInventory: Codable, Equatable, Sendable {
        var disks: [Disk]
        var hostDirectoryShares: [String]
        var clipboardEnabled: Bool
        var dragDropEnabled: Bool
        var hostSockets: [String]
        var hostCredentialDevices: [String]
    }

    struct EndpointEvidence: Codable, Equatable, Sendable {
        var address: String
        var port: UInt16
        var listenerPID: Int32
        var listenerExecutableDigest: String
        var listenerCodeIdentity: String
        var apiKeyAuthenticationSucceeded: Bool
        var credentialProofDigest: String
        var secretIncluded: Bool
    }

    struct NegativeProbe: Codable, Equatable, Sendable {
        enum Target: String, Codable, Sendable {
            case hostLAN
            case arbitraryInternet
            case productionCiderVault
            case productionHermesProfile
            case productionCodexProfile
        }

        var target: Target
        var attempted: Bool
        var accessSucceeded: Bool
        var evidenceDigest: String
    }

    struct NetworkEvidence: Codable, Equatable, Sendable {
        var defaultDeny: Bool
        var unrestrictedInternet: Bool
        var hostLANAllowed: Bool
        var allowedDestinations: [OSIsolationHarnessContract.NetworkDestination]
        var observedDestinations: [String]
        var negativeProbes: [NegativeProbe]
    }

    struct AuthenticationEvidence: Codable, Equatable, Sendable {
        var strategy: OSIsolationHarnessContract.AuthenticationStrategy
        var credentialIdentityDigest: String
        var guestOnly: Bool
        var temporaryAndScoped: Bool
        var copiedHostAuthentication: Bool
        var copiedHostProfile: Bool
        var copiedHostKeychain: Bool
        var copiedCodexProfile: Bool
        var copiedHermesProfile: Bool
    }

    struct ToolDisableEvidence: Codable, Equatable, Sendable {
        var terminal: Bool
        var file: Bool
        var browser: Bool
        var mcp: Bool
        var messaging: Bool
        var cron: Bool
        var delegation: Bool
        var gateways: Bool

        var anyEnabled: Bool {
            terminal || file || browser || mcp || messaging || cron || delegation || gateways
        }
    }

    struct FileManifestEntry: Codable, Equatable, Sendable {
        var path: String
        var sha256: String
        var size: UInt64
        var timestamp: String
        var mode: UInt16
        var ownerUID: UInt32
    }

    struct DatabaseEvidence: Codable, Equatable, Sendable {
        var integritySummary: String
        var integrityDigest: String
        var paritySummary: String
        var parityDigest: String
    }

    struct MutablePathEvidence: Codable, Equatable, Sendable {
        var declaredMutablePaths: [String]
        var observedWritePaths: [String]
        var writesOutsideIsolatedRoot: [String]
    }

    struct RestrictedAccountEvidence: Codable, Equatable, Sendable {
        var filesystemDefaultDeny: Bool
        var networkDefaultDeny: Bool
        var productionPathNegativeProbes: [NegativeProbe]
        var sandboxPolicyDigest: String
    }

    struct TeardownEvidence: Codable, Equatable, Sendable {
        var stoppedPIDs: [Int32]
        var portClosed: Bool
        var credentialsDestroyed: Bool
        var vmDeleted: Bool
        var snapshotsDeleted: Bool
        var persistentHarnessRemaining: Bool
        var completedAt: String
        var finalEvidenceHash: String
    }

    struct ActivationEvidence: Codable, Equatable, Sendable {
        var coordinatorSaveInvoked: Bool
        var shadowActivation: Bool
        var productionDataUsed: Bool
    }

    var schemaVersion: Int
    var contractDigest: String
    var runID: String
    var runStartedAt: String
    var runEndedAt: String
    var processes: [ProcessAttestation]
    var devices: DeviceInventory
    var endpoint: EndpointEvidence
    var network: NetworkEvidence
    var authentication: AuthenticationEvidence
    var toolsEnabled: ToolDisableEvidence
    var preFixtureManifest: [FileManifestEntry]
    var postFixtureManifest: [FileManifestEntry]
    var database: DatabaseEvidence
    var mutablePaths: MutablePathEvidence
    var restrictedAccount: RestrictedAccountEvidence?
    var teardown: TeardownEvidence
    var activation: ActivationEvidence

    func deterministicJSON() throws -> Data {
        try OSIsolationHarnessJSON.encode(self)
    }
}

struct OSIsolationHarnessProof: Codable, Equatable, Sendable {
    var contract: OSIsolationHarnessContract
    var evidence: OSIsolationHarnessEvidence

    func deterministicJSON() throws -> Data {
        try OSIsolationHarnessJSON.encode(self)
    }
}

enum OSIsolationHarnessDiagnosticCode: String, Codable, CaseIterable, Sendable {
    case activationForbidden = "activation.forbidden"
    case authenticationInvalid = "authentication.invalid"
    case contractBindingInvalid = "contract.binding.invalid"
    case deviceIsolationInvalid = "device.isolation.invalid"
    case digestInvalid = "digest.invalid"
    case endpointInvalid = "endpoint.invalid"
    case fixtureManifestInvalid = "fixture.manifest.invalid"
    case fixtureMutable = "fixture.mutable"
    case identityInvalid = "identity.invalid"
    case integrityInvalid = "integrity.invalid"
    case networkPolicyInvalid = "network.policy.invalid"
    case negativeProbeInvalid = "negative.probe.invalid"
    case pathContainmentInvalid = "path.containment.invalid"
    case processAttestationInvalid = "process.attestation.invalid"
    case productionOverlap = "production.overlap"
    case restrictedBoundaryInvalid = "restricted.boundary.invalid"
    case restrictedBoundaryWeaker = "restricted.boundary.weaker"
    case schemaUnsupported = "schema.unsupported"
    case teardownInvalid = "teardown.invalid"
    case timestampInvalid = "timestamp.invalid"
    case toolsEnabled = "tools.enabled"
}

struct OSIsolationHarnessDiagnostic: Codable, Equatable, Sendable, Comparable {
    enum Severity: String, Codable, Sendable { case error, warning }

    let code: OSIsolationHarnessDiagnosticCode
    let severity: Severity

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.code.rawValue, lhs.severity.rawValue) < (rhs.code.rawValue, rhs.severity.rawValue)
    }
}

struct OSIsolationHarnessValidation: Codable, Equatable, Sendable {
    static let maximumDiagnostics = OSIsolationHarnessDiagnosticCode.allCases.count

    let diagnostics: [OSIsolationHarnessDiagnostic]

    var accepted: Bool { !diagnostics.contains { $0.severity == .error } }

    func deterministicJSON() throws -> Data {
        try OSIsolationHarnessJSON.encode(self)
    }
}

enum OSIsolationHarnessValidator {
    static func validate(_ proof: OSIsolationHarnessProof) -> OSIsolationHarnessValidation {
        let contract = proof.contract
        let evidence = proof.evidence
        var findings = Set<OSIsolationHarnessDiagnosticCode>()
        var warnings = Set<OSIsolationHarnessDiagnosticCode>()

        if contract.schemaVersion != OSIsolationHarnessContract.supportedSchemaVersion ||
            evidence.schemaVersion != OSIsolationHarnessContract.supportedSchemaVersion {
            findings.insert(.schemaUnsupported)
        }

        let contractDigests = [
            contract.digests.run, contract.digests.build, contract.digests.guestImage,
            contract.digests.fixture, contract.digests.sandboxPolicy, contract.digests.networkPolicy,
            contract.digests.ciderRuntime, contract.digests.hermesRuntime
        ]
        if !contractDigests.allSatisfy(isSHA256) ||
            !isSHA256(evidence.contractDigest) ||
            !isSHA256(evidence.authentication.credentialIdentityDigest) ||
            !isSHA256(evidence.endpoint.credentialProofDigest) ||
            !isSHA256(evidence.teardown.finalEvidenceHash) {
            findings.insert(.digestInvalid)
        }

        if !isIdentity(contract.runID) || contract.runID != evidence.runID {
            findings.insert(.contractBindingInvalid)
        }
        if !validResource(contract.isolatedRoot) || contract.forbiddenProductionResources.isEmpty ||
            !contract.forbiddenProductionResources.allSatisfy(validResource) {
            findings.insert(.identityInvalid)
        }
        if contract.forbiddenProductionResources.contains(where: {
            pathsOverlap(contract.isolatedRoot.path, $0.path) ||
                sameResource(contract.isolatedRoot, $0)
        }) {
            findings.insert(.productionOverlap)
        }

        if !validTimestamp(evidence.runStartedAt) || !validTimestamp(evidence.runEndedAt) ||
            evidence.runStartedAt >= evidence.runEndedAt {
            findings.insert(.timestampInvalid)
        }

        let processRoles = Dictionary(grouping: evidence.processes, by: \.role)
        let cider = processRoles[.cider]?.first
        let hermes = processRoles[.hermes]?.first
        let processesValid = evidence.processes.count == 2 && processRoles.count == 2 &&
            evidence.processes.allSatisfy {
                $0.pid > 1 && $0.parentPID > 0 && $0.pid != $0.parentPID &&
                    $0.uid == contract.guestUID && isCanonicalAbsolutePath($0.executablePath) &&
                    isIdentity($0.codeIdentity) && isSHA256($0.executableDigest) &&
                    validTimestamp($0.startedAt) && $0.startedAt >= evidence.runStartedAt &&
                    $0.startedAt <= evidence.runEndedAt
            } && cider?.executableDigest == contract.digests.ciderRuntime &&
            hermes?.executableDigest == contract.digests.hermesRuntime
        if !processesValid { findings.insert(.processAttestationInvalid) }

        let guestDisks = evidence.devices.disks.filter { $0.role == .guestDisk }
        let fixtureDisks = evidence.devices.disks.filter { $0.role == .sealedFixtureDisk }
        if evidence.devices.disks.count != 2 || guestDisks.count != 1 || fixtureDisks.count != 1 ||
            !evidence.devices.disks.allSatisfy({ disk in
                isIdentity(disk.volumeIdentity) && isIdentity(disk.fileIdentity) &&
                    isDescendant(disk.mountPath, of: contract.isolatedRoot.path) &&
                    !contract.forbiddenProductionResources.contains(where: { forbidden in
                        forbidden.volumeIdentity == disk.volumeIdentity && forbidden.fileIdentity == disk.fileIdentity
                    })
            }) ||
            !evidence.devices.hostDirectoryShares.isEmpty || evidence.devices.clipboardEnabled ||
            evidence.devices.dragDropEnabled || !evidence.devices.hostSockets.isEmpty ||
            !evidence.devices.hostCredentialDevices.isEmpty {
            findings.insert(.deviceIsolationInvalid)
        }
        if fixtureDisks.first?.readOnly != true || fixtureDisks.first?.mutable != false {
            findings.insert(.fixtureMutable)
        }

        if contract.endpointPort == 8642 || contract.endpointPort == 0 ||
            evidence.endpoint.address != "127.0.0.1" || evidence.endpoint.port != contract.endpointPort ||
            evidence.endpoint.port == 8642 || evidence.endpoint.listenerPID != hermes?.pid ||
            evidence.endpoint.listenerExecutableDigest != contract.digests.hermesRuntime ||
            evidence.endpoint.listenerCodeIdentity != hermes?.codeIdentity ||
            !evidence.endpoint.apiKeyAuthenticationSucceeded || evidence.endpoint.secretIncluded {
            findings.insert(.endpointInvalid)
        }

        let requiredNetworkProbes: Set<OSIsolationHarnessEvidence.NegativeProbe.Target> = [.hostLAN, .arbitraryInternet]
        let networkProbes = Set(evidence.network.negativeProbes.map(\.target))
        if !evidence.network.defaultDeny || evidence.network.unrestrictedInternet || evidence.network.hostLANAllowed ||
            contract.allowedNetworkDestinations.isEmpty ||
            Set(contract.allowedNetworkDestinations.map(\.role)) != [.authentication, .model] ||
            contract.allowedNetworkDestinations.contains(where: { !validDestination($0.origin) }) ||
            Set(contract.allowedNetworkDestinations).count != contract.allowedNetworkDestinations.count ||
            Set(evidence.network.allowedDestinations) != Set(contract.allowedNetworkDestinations) ||
            !Set(evidence.network.observedDestinations).isSubset(of: Set(contract.allowedNetworkDestinations.map(\.origin))) {
            findings.insert(.networkPolicyInvalid)
        }
        if !requiredNetworkProbes.isSubset(of: networkProbes) ||
            evidence.network.negativeProbes.contains(where: { !$0.attempted || $0.accessSucceeded || !isSHA256($0.evidenceDigest) }) {
            findings.insert(.negativeProbeInvalid)
        }

        let auth = evidence.authentication
        let strategySpecificAuthValid = switch contract.authenticationStrategy {
        case .guestOnlyDeviceCodeOAuth: auth.guestOnly && !auth.temporaryAndScoped
        case .temporaryScopedAPIKey: auth.guestOnly && auth.temporaryAndScoped
        }
        if auth.strategy != contract.authenticationStrategy || !strategySpecificAuthValid ||
            auth.copiedHostAuthentication || auth.copiedHostProfile || auth.copiedHostKeychain ||
            auth.copiedCodexProfile || auth.copiedHermesProfile {
            findings.insert(.authenticationInvalid)
        }
        if evidence.toolsEnabled.anyEnabled { findings.insert(.toolsEnabled) }

        validateManifest(
            evidence.preFixtureManifest,
            root: contract.isolatedRoot.path,
            uid: contract.guestUID,
            earliest: nil,
            latest: evidence.runStartedAt,
            findings: &findings
        )
        validateManifest(
            evidence.postFixtureManifest,
            root: contract.isolatedRoot.path,
            uid: contract.guestUID,
            earliest: evidence.runStartedAt,
            latest: evidence.runEndedAt,
            findings: &findings
        )
        if evidence.preFixtureManifest.map(\.path).sorted() != evidence.postFixtureManifest.map(\.path).sorted() {
            findings.insert(.fixtureManifestInvalid)
        }
        if !isIdentity(evidence.database.integritySummary) || !isSHA256(evidence.database.integrityDigest) ||
            !isIdentity(evidence.database.paritySummary) || !isSHA256(evidence.database.parityDigest) {
            findings.insert(.integrityInvalid)
        }

        let mutable = evidence.mutablePaths
        if mutable.declaredMutablePaths.isEmpty || !mutable.writesOutsideIsolatedRoot.isEmpty ||
            !(mutable.declaredMutablePaths + mutable.observedWritePaths).allSatisfy({ isDescendant($0, of: contract.isolatedRoot.path) }) ||
            !Set(mutable.observedWritePaths).isSubset(of: Set(mutable.declaredMutablePaths)) {
            findings.insert(.pathContainmentInvalid)
        }

        switch contract.kind {
        case .disposableMacOSVM:
            if evidence.restrictedAccount != nil { findings.insert(.restrictedBoundaryInvalid) }
        case .restrictedAccountSandbox:
            warnings.insert(.restrictedBoundaryWeaker)
            let restricted = evidence.restrictedAccount
            let requiredPaths: Set<OSIsolationHarnessEvidence.NegativeProbe.Target> = [
                .productionCiderVault, .productionHermesProfile, .productionCodexProfile
            ]
            if contract.guestUID == contract.hostProductionUID || restricted == nil ||
                restricted?.filesystemDefaultDeny != true || restricted?.networkDefaultDeny != true ||
                restricted?.sandboxPolicyDigest != contract.digests.sandboxPolicy ||
                !isSHA256(restricted?.sandboxPolicyDigest ?? "") ||
                !requiredPaths.isSubset(of: Set(restricted?.productionPathNegativeProbes.map(\.target) ?? [])) ||
                restricted?.productionPathNegativeProbes.contains(where: {
                    !$0.attempted || $0.accessSucceeded || !isSHA256($0.evidenceDigest)
                }) != false {
                findings.insert(.restrictedBoundaryInvalid)
            }
        }

        let expectedPIDs = evidence.processes.map(\.pid).sorted()
        let teardown = evidence.teardown
        let vmTeardownValid = contract.kind != .disposableMacOSVM || (teardown.vmDeleted && teardown.snapshotsDeleted)
        if teardown.stoppedPIDs.sorted() != expectedPIDs || Set(teardown.stoppedPIDs).count != teardown.stoppedPIDs.count ||
            !teardown.portClosed || !teardown.credentialsDestroyed || teardown.persistentHarnessRemaining ||
            !vmTeardownValid || !validTimestamp(teardown.completedAt) || teardown.completedAt < evidence.runEndedAt {
            findings.insert(.teardownInvalid)
        }

        if evidence.activation.coordinatorSaveInvoked || evidence.activation.shadowActivation ||
            evidence.activation.productionDataUsed {
            findings.insert(.activationForbidden)
        }

        let errors = findings.map { OSIsolationHarnessDiagnostic(code: $0, severity: .error) }
        let notices = warnings.map { OSIsolationHarnessDiagnostic(code: $0, severity: .warning) }
        return OSIsolationHarnessValidation(
            diagnostics: Array((errors + notices).sorted().prefix(OSIsolationHarnessValidation.maximumDiagnostics))
        )
    }

    private static func validateManifest(
        _ manifest: [OSIsolationHarnessEvidence.FileManifestEntry],
        root: String,
        uid: UInt32,
        earliest: String?,
        latest: String,
        findings: inout Set<OSIsolationHarnessDiagnosticCode>
    ) {
        guard !manifest.isEmpty, Set(manifest.map(\.path)).count == manifest.count else {
            findings.insert(.fixtureManifestInvalid)
            return
        }
        for entry in manifest {
            if !isDescendant(entry.path, of: root) || !isSHA256(entry.sha256) || entry.size == 0 ||
                entry.mode == 0 || entry.mode > 0o777 || entry.ownerUID != uid {
                findings.insert(.fixtureManifestInvalid)
            }
            if !validTimestamp(entry.timestamp) || entry.timestamp > latest ||
                (earliest != nil && entry.timestamp < earliest!) {
                findings.insert(.timestampInvalid)
            }
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func isIdentity(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == value && (1...256).contains(value.utf8.count) &&
            !value.utf8.contains(where: { $0 < 32 || $0 == 127 })
    }

    private static func validTimestamp(_ value: String) -> Bool {
        guard value.count == 20 else { return false }
        let bytes = Array(value.utf8)
        guard bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58,
              bytes[16] == 58, bytes[19] == 90 else { return false }
        for index in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
            guard bytes[index] >= 48 && bytes[index] <= 57 else { return false }
        }
        guard let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(value.dropFirst(8).prefix(2)), (1...31).contains(day),
              let hour = Int(value.dropFirst(11).prefix(2)), (0...23).contains(hour),
              let minute = Int(value.dropFirst(14).prefix(2)), (0...59).contains(minute),
              let second = Int(value.dropFirst(17).prefix(2)), (0...59).contains(second)
        else { return false }
        return true
    }

    private static func isCanonicalAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path != "/" && !path.hasSuffix("/") && !path.contains("//") &&
            !path.split(separator: "/", omittingEmptySubsequences: true).contains(where: { $0 == "." || $0 == ".." }) &&
            path == path.precomposedStringWithCanonicalMapping
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        isCanonicalAbsolutePath(path) && isCanonicalAbsolutePath(root) && path.hasPrefix(root + "/")
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private static func validResource(_ resource: OSIsolationHarnessContract.ResourceIdentity) -> Bool {
        isCanonicalAbsolutePath(resource.path) && isIdentity(resource.volumeIdentity) && isIdentity(resource.fileIdentity)
    }

    private static func sameResource(
        _ lhs: OSIsolationHarnessContract.ResourceIdentity,
        _ rhs: OSIsolationHarnessContract.ResourceIdentity
    ) -> Bool {
        lhs.volumeIdentity == rhs.volumeIdentity && lhs.fileIdentity == rhs.fileIdentity
    }

    private static func validDestination(_ value: String) -> Bool {
        guard value.hasPrefix("https://"), value == value.lowercased(), !value.contains("@"),
              !value.contains("?"), !value.contains("#"), !value.hasSuffix("/"),
              value.dropFirst(8).contains(".")
        else { return false }
        return isIdentity(value)
    }
}

private enum OSIsolationHarnessJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
