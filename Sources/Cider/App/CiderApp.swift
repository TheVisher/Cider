import SwiftUI

struct CiderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Public entry point called by the thin CiderLauncher executable and the
/// Xcode App target's main.swift. Keeps CiderApp itself internal.
@MainActor
public func launchCider() {
    CiderApp.main()
}
