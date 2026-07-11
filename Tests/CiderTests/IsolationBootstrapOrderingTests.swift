import Foundation
import Testing
@testable import Cider

@Suite("CID-782 isolation bootstrap ordering", .serialized)
struct IsolationBootstrapOrderingTests {
    @Test("bootstrap completes before app main without launching AppKit")
    @MainActor
    func bootstrapBeforeAppMain() throws {
        var events: [String] = []
        try CiderLaunchOrdering.run(
            bootstrap: {
                events.append("bootstrap-start")
                events.append("bootstrap-frozen")
                return IsolationStartupAttestation(configuration: .production)
            },
            appMain: {
                events.append("app-main")
            }
        )
        #expect(events == ["bootstrap-start", "bootstrap-frozen", "app-main"])
    }

    @Test("bootstrap error prevents app main")
    @MainActor
    func bootstrapFailureStopsLaunch() {
        var appMainCalled = false
        #expect(throws: IsolationBootstrapError.self) {
            try CiderLaunchOrdering.run(
                bootstrap: { throw IsolationBootstrapError.invalidArguments },
                appMain: { appMainCalled = true }
            )
        }
        #expect(!appMainCalled)
    }

    @Test("configuration install is one-shot even for identical values")
    func oneShotInstall() throws {
        let store = IsolationConfigurationStore()
        let bootstrap = IsolationBootstrap(
            store: store,
            sentinel: IsolationAccessSentinel(),
            dependencies: .live
        )
        _ = try bootstrap.install(arguments: ["Cider"], environment: [:])
        #expect(throws: IsolationBootstrapError.alreadyInstalled) {
            try bootstrap.install(arguments: ["Cider"], environment: [:])
        }
    }

    @Test("known accessor before dogfood install fails closed")
    func lateInstall() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let sentinel = IsolationAccessSentinel()
        sentinel.record("StoragePaths.cachedVaultDirectoryURL")
        let bootstrap = IsolationBootstrap(
            store: IsolationConfigurationStore(),
            sentinel: sentinel,
            dependencies: fixture.dependencies
        )
        #expect(throws: IsolationBootstrapError.accessBeforeInstall("StoragePaths.cachedVaultDirectoryURL")) {
            try bootstrap.install(arguments: fixture.arguments, environment: fixture.environment)
        }
    }

    @Test("attestation sink runs only after configuration is frozen")
    func attestationAfterFreeze() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let store = IsolationConfigurationStore()
        _ = try IsolationBootstrap(
            store: store,
            sentinel: IsolationAccessSentinel(),
            dependencies: fixture.dependencies
        ).install(arguments: fixture.arguments, environment: fixture.environment) { _ in
            #expect(store.configuration?.isDogfood == true)
        }
    }

    @Test("isolated integration disable plan is deterministic and production remains enabled")
    func integrationPlans() throws {
        let fixture = try IsolationFixture()
        defer { fixture.remove() }
        let dogfood = try fixture.install().integrationPlan
        #expect(dogfood == .dogfood)
        #expect(!dogfood.accessibilityPrompt)
        #expect(!dogfood.sparkle)
        #expect(!dogfood.spotlight)
        #expect(!dogfood.sync)
        #expect(!dogfood.telegram)
        #expect(!dogfood.clipboardMonitoring)
        #expect(!dogfood.globalEventMonitoring)
        #expect(!dogfood.notificationScheduling)
        #expect(!dogfood.servicesRegistration)
        #expect(!dogfood.fileWatching)
        #expect(!dogfood.agentTools)

        let production = IsolationConfiguration.IntegrationPlan.production
        #expect(production.accessibilityPrompt && production.sparkle && production.spotlight)
        #expect(production.sync && production.telegram && production.clipboardMonitoring)
        #expect(production.globalEventMonitoring && production.notificationScheduling)
        #expect(production.servicesRegistration && production.fileWatching && production.agentTools)
    }
}
