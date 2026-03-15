import AppKit
import Foundation
import os

@MainActor
final class BrowserSessionsViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.cider", category: "BrowserSessionsViewModel")

    @Published var isCapturing = false
    @Published var captureError: String?

    private let storage = BrowserSessionStorage.shared

    var sessions: [BrowserSession] {
        storage.sessions
    }

    // MARK: - Capture

    func captureAndSave(name: String, fromBundleID: String? = nil, fromAppName: String? = nil) async {
        isCapturing = true
        captureError = nil

        let results: [BrowserCaptureResult]
        if let bundleID = fromBundleID, let appName = fromAppName {
            if let result = await BrowserTabCaptureService.captureFromBrowser(bundleID: bundleID, appName: appName) {
                results = [result]
            } else {
                results = []
            }
        } else {
            results = await BrowserTabCaptureService.captureAllBrowsers()
        }

        isCapturing = false

        let allTabs = results.flatMap(\.tabs)
        guard !allTabs.isEmpty else {
            captureError = "No tabs found. Make sure a browser is open and Cider has Automation permission in System Settings > Privacy > Automation."
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = trimmed.isEmpty ? "Session \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))" : trimmed

        let sourceName: String? = results.count == 1 ? results[0].appName : nil
        let sourceBundleID: String? = results.count == 1 ? results[0].bundleID : nil

        let session = BrowserSession(
            name: sessionName,
            tabs: allTabs,
            sourceBrowserBundleID: sourceBundleID,
            sourceBrowserName: sourceName
        )

        storage.save(session)
        Self.logger.info("Saved session '\(sessionName)' with \(allTabs.count) tabs")
    }

    // MARK: - Restore

    func restore(_ session: BrowserSession, toBrowserBundleID: String?) {
        for tab in session.tabs {
            guard let url = tab.url else { continue }
            if let bundleID = toBrowserBundleID {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                openURLSafely(url)
            }
        }
    }

    // MARK: - Delete

    func delete(_ id: UUID) {
        if let trashItem = storage.delete(id) {
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .session, trashItem: trashItem))
        }
    }

    // MARK: - Running Browsers

    func runningBrowsers() -> [(bundleID: String, appName: String)] {
        BrowserTabCaptureService.runningBrowsers()
    }
}
