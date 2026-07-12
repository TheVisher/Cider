import Foundation
import Testing

@Suite("Codex Usage Settings source safety")
struct CodexUsageSettingsStructureTests {
    @Test("Advanced Settings composes view-lifetime usage state without new navigation clutter")
    func advancedComposition() throws {
        let settings = try source("Sources/Cider/Views/Settings/SettingsView.swift")
        let content = try source("Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift")
        let enums = try source("Sources/Cider/Views/Settings/SettingsEnums.swift")

        #expect(settings.contains("@StateObject var codexUsageState = CodexUsageObservableState()"))
        #expect(content.contains("case .dataDirectories:"))
        #expect(content.contains("CodexUsageSettingsView(usageState: codexUsageState)"))
        #expect(!enums.contains("case codexUsage"))
    }

    @Test("Usage UI is manual, accessible, responsive, and contains no auto-refresh hooks")
    func manualAccessibleLayout() throws {
        let view = try source("Sources/Cider/Views/Settings/CodexUsageSettingsView.swift")

        #expect(view.contains("Button(action:"))
        #expect(view.contains(".accessibilityLabel("))
        #expect(view.contains(".accessibilityHint("))
        #expect(view.contains(".accessibilityValue("))
        #expect(view.contains(".disabled(content.isLoading)"))
        #expect(view.contains(".accessibilityElement(children: .combine)"))
        #expect(view.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(view.contains("ViewThatFits(in: .horizontal)"))
        #expect(!view.contains("ScrollView(.horizontal"))
        #expect(!view.contains(".accessibilityElement(children: .ignore)"))
        for forbidden in [".onAppear", ".task", "Timer", "autorefresh", "autoRefresh"] {
            #expect(!view.contains(forbidden))
        }
    }

    @Test("Usage surface does not integrate forbidden identity, history, credit, or vault systems")
    func forbiddenIntegrations() throws {
        let files = [
            try source("Sources/Cider/Views/Settings/CodexUsageSettingsView.swift"),
            try source("Sources/Cider/Views/Settings/CodexUsageSettingsPresentation.swift"),
        ].joined(separator: "\n")

        for forbidden in [
            "CiderVault", "Hermes", "AuthService", "Conversation", "accountID", "reset-credit",
            "accessToken", "stdout", "stderr", "Process(", "CodexUsageProcessRunner(",
        ] {
            #expect(!files.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
