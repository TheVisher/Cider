import SwiftUI

struct CiderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Public entry point called by the thin CiderLauncher executable and the
/// Xcode App target's main.swift. Keeps CiderApp itself internal.
@MainActor
public func launchCider() {
    do {
        try CiderLaunchOrdering.run(
            bootstrap: {
                try IsolationRuntime.installAtProcessStart(
                    attestationSink: IsolationAttestationSink.writeInsideIsolationRoot
                )
            },
            appMain: { CiderApp.main() }
        )
    } catch {
        fatalError("Cider isolation bootstrap failed before application construction: \(error.localizedDescription)")
    }
}

enum CiderLaunchOrdering {
    @MainActor
    static func run(
        bootstrap: () throws -> IsolationStartupAttestation,
        appMain: () -> Void
    ) throws {
        _ = try bootstrap()
        appMain()
    }
}
