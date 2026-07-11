import Foundation
import Testing
@testable import Cider

@Suite("CID-784 offline OS isolation harness contract")
struct OSIsolationHarnessContractTests {
    @Test("valid disposable VM evidence is accepted")
    func validDisposableVM() throws {
        let proof = makeProof()
        let result = OSIsolationHarnessValidator.validate(proof)
        #expect(result.accepted)
        #expect(result.diagnostics.isEmpty)
        #expect(try proof.contract.deterministicJSON() == proof.contract.deterministicJSON())
        #expect(try proof.evidence.deterministicJSON() == proof.evidence.deterministicJSON())
        #expect(try proof.deterministicJSON() == proof.deterministicJSON())
    }

    @Test("restricted account is conditionally accepted with an explicit weaker-boundary diagnostic")
    func validRestrictedAccount() {
        var proof = makeProof()
        proof.contract.kind = .restrictedAccountSandbox
        proof.evidence.teardown.vmDeleted = false
        proof.evidence.teardown.snapshotsDeleted = false
        proof.evidence.restrictedAccount = .init(
            filesystemDefaultDeny: true,
            networkDefaultDeny: true,
            productionPathNegativeProbes: [
                probe(.productionCiderVault), probe(.productionHermesProfile), probe(.productionCodexProfile)
            ],
            sandboxPolicyDigest: digest("e")
        )

        let result = OSIsolationHarnessValidator.validate(proof)
        #expect(result.accepted)
        #expect(result.diagnostics == [
            .init(code: .restrictedBoundaryWeaker, severity: .warning)
        ])
    }

    @Test("unsupported versions and unknown enums fail closed")
    func schemaAndEnumFailures() throws {
        var proof = makeProof()
        proof.contract.schemaVersion = 2
        assertRejected(proof, .schemaUnsupported)
        proof = makeProof()
        proof.evidence.schemaVersion = 0
        assertRejected(proof, .schemaUnsupported)

        let validJSON = String(decoding: try proof.deterministicJSON(), as: UTF8.self)
        let unknownKind = validJSON.replacingOccurrences(
            of: "\"kind\":\"disposableMacOSVM\"",
            with: "\"kind\":\"futureHarness\""
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OSIsolationHarnessProof.self, from: Data(unknownKind.utf8))
        }
        let missingField = validJSON.replacingOccurrences(of: "\"runID\":\"cid-784-run\",", with: "")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OSIsolationHarnessProof.self, from: Data(missingField.utf8))
        }
    }

    @Test("missing malformed digests identities timestamps manifests integrity probes and teardown reject")
    func malformedRequiredEvidence() {
        var cases: [(inout OSIsolationHarnessProof) -> Void] = []
        cases.append { $0.contract.digests.build = "" }
        cases.append { $0.contract.digests.fixture = String(repeating: "G", count: 64) }
        cases.append { $0.evidence.contractDigest = "short" }
        cases.append { $0.contract.runID = "" }
        cases.append { $0.contract.isolatedRoot.volumeIdentity = "" }
        cases.append { $0.contract.forbiddenProductionResources = [] }
        cases.append { $0.evidence.runStartedAt = "not-a-time" }
        cases.append { $0.evidence.preFixtureManifest = [] }
        cases.append { $0.evidence.database.integritySummary = "" }
        cases.append { $0.evidence.database.parityDigest = "bad" }
        cases.append { $0.evidence.network.negativeProbes = [] }
        cases.append { $0.evidence.teardown.stoppedPIDs = [] }
        cases.append { $0.evidence.teardown.finalEvidenceHash = "" }
        for mutate in cases {
            var proof = makeProof()
            mutate(&proof)
            #expect(!OSIsolationHarnessValidator.validate(proof).accepted)
        }
    }

    @Test("production overlap resource alias and path escapes reject")
    func productionOverlapAndEscapes() {
        for forbiddenPath in ["/isolated/run", "/isolated", "/isolated/run/production"] {
            var proof = makeProof()
            proof.contract.forbiddenProductionResources[0].path = forbiddenPath
            assertRejected(proof, .productionOverlap)
        }
        var alias = makeProof()
        alias.contract.forbiddenProductionResources[0].volumeIdentity = alias.contract.isolatedRoot.volumeIdentity
        alias.contract.forbiddenProductionResources[0].fileIdentity = alias.contract.isolatedRoot.fileIdentity
        assertRejected(alias, .productionOverlap)

        for escape in ["/isolated/run/../production", "/isolated/other/file", "relative/file"] {
            var proof = makeProof()
            proof.evidence.mutablePaths.observedWritePaths = [escape]
            assertRejected(proof, .pathContainmentInvalid)
        }
    }

    @Test("every host share device channel socket and credential attachment independently rejects")
    func hostAttachmentFailures() {
        let mutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.devices.hostDirectoryShares = ["/Users/host"] },
            { $0.evidence.devices.clipboardEnabled = true },
            { $0.evidence.devices.dragDropEnabled = true },
            { $0.evidence.devices.hostSockets = ["ssh-agent"] },
            { $0.evidence.devices.hostCredentialDevices = ["host-keychain"] },
            { $0.evidence.devices.disks.removeLast() },
            {
                $0.evidence.devices.disks[0].volumeIdentity = "host-volume"
                $0.evidence.devices.disks[0].fileIdentity = "cider-vault"
            }
        ]
        for mutate in mutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .deviceIsolationInvalid)
        }
        var mutableFixture = makeProof()
        mutableFixture.evidence.devices.disks[1].mutable = true
        assertRejected(mutableFixture, .fixtureMutable)
    }

    @Test("network must be exact default-deny with successful negative probes")
    func networkFailures() {
        let mutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.network.defaultDeny = false },
            { $0.evidence.network.unrestrictedInternet = true },
            { $0.evidence.network.hostLANAllowed = true },
            { $0.contract.allowedNetworkDestinations = [] },
            {
                $0.evidence.network.allowedDestinations.append(
                    .init(role: .model, origin: "https://example.com")
                )
            },
            { $0.evidence.network.observedDestinations.append("https://example.com") }
        ]
        for mutate in mutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .networkPolicyInvalid)
        }
        for index in 0..<2 {
            var proof = makeProof()
            proof.evidence.network.negativeProbes[index].accessSucceeded = true
            assertRejected(proof, .negativeProbeInvalid)
        }
        var missing = makeProof()
        missing.evidence.network.negativeProbes.removeLast()
        assertRejected(missing, .negativeProbeInvalid)
    }

    @Test("authentication strategy and every copied ambient credential source reject")
    func authenticationFailures() {
        let mutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.authentication.strategy = .temporaryScopedAPIKey },
            { $0.evidence.authentication.guestOnly = false },
            { $0.evidence.authentication.temporaryAndScoped = true },
            { $0.evidence.authentication.copiedHostAuthentication = true },
            { $0.evidence.authentication.copiedHostProfile = true },
            { $0.evidence.authentication.copiedHostKeychain = true },
            { $0.evidence.authentication.copiedCodexProfile = true },
            { $0.evidence.authentication.copiedHermesProfile = true }
        ]
        for mutate in mutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .authenticationInvalid)
        }

        var scopedKey = makeProof()
        scopedKey.contract.authenticationStrategy = .temporaryScopedAPIKey
        scopedKey.evidence.authentication.strategy = .temporaryScopedAPIKey
        scopedKey.evidence.authentication.temporaryAndScoped = true
        #expect(OSIsolationHarnessValidator.validate(scopedKey).accepted)
    }

    @Test("every tool class independently enabled rejects")
    func toolsFailures() {
        let mutations: [(inout OSIsolationHarnessEvidence.ToolDisableEvidence) -> Void] = [
            { $0.terminal = true }, { $0.file = true }, { $0.browser = true }, { $0.mcp = true },
            { $0.messaging = true }, { $0.cron = true }, { $0.delegation = true }, { $0.gateways = true }
        ]
        for mutate in mutations {
            var proof = makeProof()
            mutate(&proof.evidence.toolsEnabled)
            assertRejected(proof, .toolsEnabled)
        }
    }

    @Test("endpoint listener port PID digest identity and authentication must match")
    func endpointFailures() {
        let mutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.contract.endpointPort = 8642; $0.evidence.endpoint.port = 8642 },
            { $0.evidence.endpoint.address = "0.0.0.0" },
            { $0.evidence.endpoint.port = 19001 },
            { $0.evidence.endpoint.listenerPID = 999 },
            { $0.evidence.endpoint.listenerExecutableDigest = digest("9") },
            { $0.evidence.endpoint.listenerCodeIdentity = "other" },
            { $0.evidence.endpoint.apiKeyAuthenticationSucceeded = false },
            { $0.evidence.endpoint.secretIncluded = true }
        ]
        for mutate in mutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .endpointInvalid)
        }
    }

    @Test("process and manifest hash metadata integrity and parity mismatches reject")
    func attestationAndManifestFailures() {
        let processMutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.processes.removeLast() },
            { $0.evidence.processes[0].pid = -1 },
            { $0.evidence.processes[0].uid = 999 },
            { $0.evidence.processes[0].executableDigest = digest("9") },
            { $0.evidence.processes[0].startedAt = "2026-07-11T11:59:59Z" }
        ]
        for mutate in processMutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .processAttestationInvalid)
        }

        let manifestMutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.preFixtureManifest[0].sha256 = "bad" },
            { $0.evidence.preFixtureManifest[0].size = 0 },
            { $0.evidence.preFixtureManifest[0].mode = 0 },
            { $0.evidence.preFixtureManifest[0].ownerUID = 999 },
            { $0.evidence.preFixtureManifest[0].timestamp = "2026-07-11T12:00:01Z" },
            { $0.evidence.postFixtureManifest[0].path = "/isolated/run/other.db" },
            { $0.evidence.database.integrityDigest = "bad" },
            { $0.evidence.database.paritySummary = "" }
        ]
        for mutate in manifestMutations {
            var proof = makeProof()
            mutate(&proof)
            #expect(!OSIsolationHarnessValidator.validate(proof).accepted)
        }
    }

    @Test("restricted fallback requires distinct UID deny policies path probes and matching sandbox digest")
    func restrictedFailures() {
        func restrictedProof() -> OSIsolationHarnessProof {
            var proof = makeProof()
            proof.contract.kind = .restrictedAccountSandbox
            proof.evidence.teardown.vmDeleted = false
            proof.evidence.teardown.snapshotsDeleted = false
            proof.evidence.restrictedAccount = .init(
                filesystemDefaultDeny: true,
                networkDefaultDeny: true,
                productionPathNegativeProbes: [
                    probe(.productionCiderVault), probe(.productionHermesProfile), probe(.productionCodexProfile)
                ],
                sandboxPolicyDigest: digest("e")
            )
            return proof
        }
        let mutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.contract.guestUID = $0.contract.hostProductionUID },
            { $0.evidence.restrictedAccount = nil },
            { $0.evidence.restrictedAccount?.filesystemDefaultDeny = false },
            { $0.evidence.restrictedAccount?.networkDefaultDeny = false },
            { $0.evidence.restrictedAccount?.sandboxPolicyDigest = digest("9") },
            { $0.evidence.restrictedAccount?.productionPathNegativeProbes.removeLast() },
            { $0.evidence.restrictedAccount?.productionPathNegativeProbes[0].accessSucceeded = true }
        ]
        for mutate in mutations {
            var proof = restrictedProof()
            mutate(&proof)
            assertRejected(proof, .restrictedBoundaryInvalid)
        }
    }

    @Test("teardown credential VM snapshot persistence and no-activation flags fail independently")
    func teardownAndActivationFailures() {
        let teardownMutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.teardown.stoppedPIDs = [100] },
            { $0.evidence.teardown.portClosed = false },
            { $0.evidence.teardown.credentialsDestroyed = false },
            { $0.evidence.teardown.vmDeleted = false },
            { $0.evidence.teardown.snapshotsDeleted = false },
            { $0.evidence.teardown.persistentHarnessRemaining = true },
            { $0.evidence.teardown.completedAt = "2026-07-11T12:05:59Z" }
        ]
        for mutate in teardownMutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .teardownInvalid)
        }
        let activationMutations: [(inout OSIsolationHarnessProof) -> Void] = [
            { $0.evidence.activation.coordinatorSaveInvoked = true },
            { $0.evidence.activation.shadowActivation = true },
            { $0.evidence.activation.productionDataUsed = true }
        ]
        for mutate in activationMutations {
            var proof = makeProof()
            mutate(&proof)
            assertRejected(proof, .activationForbidden)
        }
    }

    @Test("diagnostics are deterministic sorted bounded and serialized proof cannot contain forbidden content")
    func deterministicSanitizedDiagnostics() throws {
        var proof = makeProof()
        proof.contract.schemaVersion = 99
        proof.contract.digests.run = "bad"
        proof.evidence.toolsEnabled.terminal = true
        proof.evidence.activation.productionDataUsed = true
        proof.evidence.teardown.credentialsDestroyed = false

        let first = OSIsolationHarnessValidator.validate(proof)
        let second = OSIsolationHarnessValidator.validate(proof)
        #expect(first == second)
        #expect(first.diagnostics == first.diagnostics.sorted())
        #expect(first.diagnostics.count <= OSIsolationHarnessValidation.maximumDiagnostics)
        #expect(try first.deterministicJSON() == first.deterministicJSON())

        let text = String(decoding: try proof.deterministicJSON(), as: UTF8.self).lowercased()
        for sentinel in [
            "api-key-secret", "oauth-token", "message content", "raw nonce", "cookie=",
            "environment dump", "private production content"
        ] {
            #expect(!text.contains(sentinel))
        }
    }
}

private func makeProof() -> OSIsolationHarnessProof {
    let root = OSIsolationHarnessContract.ResourceIdentity(
        path: "/isolated/run", volumeIdentity: "guest-volume", fileIdentity: "run-root"
    )
    let destinations: [OSIsolationHarnessContract.NetworkDestination] = [
        .init(role: .authentication, origin: "https://auth.openai.com"),
        .init(role: .model, origin: "https://api.openai.com")
    ]
    let contract = OSIsolationHarnessContract(
        schemaVersion: 1,
        kind: .disposableMacOSVM,
        runID: "cid-784-run",
        digests: .init(
            run: digest("a"), build: digest("b"), guestImage: digest("c"), fixture: digest("d"),
            sandboxPolicy: digest("e"), networkPolicy: digest("f"), ciderRuntime: digest("1"),
            hermesRuntime: digest("2")
        ),
        isolatedRoot: root,
        forbiddenProductionResources: [
            .init(path: "/Users/host/CiderVault", volumeIdentity: "host-volume", fileIdentity: "cider-vault"),
            .init(path: "/Users/host/.hermes", volumeIdentity: "host-volume", fileIdentity: "hermes-profile"),
            .init(path: "/Users/host/.codex", volumeIdentity: "host-volume", fileIdentity: "codex-profile")
        ],
        hostProductionUID: 501,
        guestUID: 702,
        endpointPort: 18642,
        allowedNetworkDestinations: destinations,
        authenticationStrategy: .guestOnlyDeviceCodeOAuth
    )
    let processes: [OSIsolationHarnessEvidence.ProcessAttestation] = [
        .init(
            role: .cider, pid: 100, parentPID: 50, startedAt: "2026-07-11T12:00:01Z",
            executablePath: "/isolated/run/cider/Cider.app/Contents/MacOS/Cider",
            codeIdentity: "com.cider.app.debug", executableDigest: digest("1"), uid: 702
        ),
        .init(
            role: .hermes, pid: 101, parentPID: 100, startedAt: "2026-07-11T12:00:02Z",
            executablePath: "/isolated/run/hermes/runtime/bin/hermes",
            codeIdentity: "hermes-runtime", executableDigest: digest("2"), uid: 702
        )
    ]
    let preEntry = OSIsolationHarnessEvidence.FileManifestEntry(
        path: "/isolated/run/fixture/cider.db", sha256: digest("3"), size: 4096,
        timestamp: "2026-07-11T11:59:00Z", mode: 0o400, ownerUID: 702
    )
    let postEntry = OSIsolationHarnessEvidence.FileManifestEntry(
        path: "/isolated/run/fixture/cider.db", sha256: digest("3"), size: 4096,
        timestamp: "2026-07-11T12:05:00Z", mode: 0o400, ownerUID: 702
    )
    let evidence = OSIsolationHarnessEvidence(
        schemaVersion: 1,
        contractDigest: digest("4"),
        runID: "cid-784-run",
        runStartedAt: "2026-07-11T12:00:00Z",
        runEndedAt: "2026-07-11T12:06:00Z",
        processes: processes,
        devices: .init(
            disks: [
                .init(
                    role: .guestDisk, volumeIdentity: "guest-volume", fileIdentity: "guest-disk",
                    mountPath: "/isolated/run/guest", readOnly: false, mutable: true
                ),
                .init(
                    role: .sealedFixtureDisk, volumeIdentity: "fixture-volume", fileIdentity: "fixture-disk",
                    mountPath: "/isolated/run/fixture", readOnly: true, mutable: false
                )
            ],
            hostDirectoryShares: [], clipboardEnabled: false, dragDropEnabled: false,
            hostSockets: [], hostCredentialDevices: []
        ),
        endpoint: .init(
            address: "127.0.0.1", port: 18642, listenerPID: 101,
            listenerExecutableDigest: digest("2"), listenerCodeIdentity: "hermes-runtime",
            apiKeyAuthenticationSucceeded: true, credentialProofDigest: digest("5"), secretIncluded: false
        ),
        network: .init(
            defaultDeny: true, unrestrictedInternet: false, hostLANAllowed: false,
            allowedDestinations: destinations,
            observedDestinations: destinations.map(\.origin),
            negativeProbes: [probe(.hostLAN), probe(.arbitraryInternet)]
        ),
        authentication: .init(
            strategy: .guestOnlyDeviceCodeOAuth, credentialIdentityDigest: digest("6"), guestOnly: true,
            temporaryAndScoped: false, copiedHostAuthentication: false, copiedHostProfile: false,
            copiedHostKeychain: false, copiedCodexProfile: false, copiedHermesProfile: false
        ),
        toolsEnabled: .init(
            terminal: false, file: false, browser: false, mcp: false, messaging: false,
            cron: false, delegation: false, gateways: false
        ),
        preFixtureManifest: [preEntry],
        postFixtureManifest: [postEntry],
        database: .init(
            integritySummary: "sqlite-ok", integrityDigest: digest("7"),
            paritySummary: "fixture-parity-ok", parityDigest: digest("8")
        ),
        mutablePaths: .init(
            declaredMutablePaths: ["/isolated/run/output"],
            observedWritePaths: ["/isolated/run/output"],
            writesOutsideIsolatedRoot: []
        ),
        restrictedAccount: nil,
        teardown: .init(
            stoppedPIDs: [100, 101], portClosed: true, credentialsDestroyed: true,
            vmDeleted: true, snapshotsDeleted: true, persistentHarnessRemaining: false,
            completedAt: "2026-07-11T12:07:00Z", finalEvidenceHash: digest("9")
        ),
        activation: .init(
            coordinatorSaveInvoked: false, shadowActivation: false, productionDataUsed: false
        )
    )
    return OSIsolationHarnessProof(contract: contract, evidence: evidence)
}

private func probe(
    _ target: OSIsolationHarnessEvidence.NegativeProbe.Target
) -> OSIsolationHarnessEvidence.NegativeProbe {
    .init(target: target, attempted: true, accessSucceeded: false, evidenceDigest: digest("a"))
}

private func digest(_ character: Character) -> String {
    String(repeating: character, count: 64)
}

private func assertRejected(
    _ proof: OSIsolationHarnessProof,
    _ code: OSIsolationHarnessDiagnosticCode,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let result = OSIsolationHarnessValidator.validate(proof)
    #expect(!result.accepted, sourceLocation: sourceLocation)
    #expect(result.diagnostics.contains { $0.code == code && $0.severity == .error }, sourceLocation: sourceLocation)
}
