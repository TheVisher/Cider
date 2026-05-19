import Foundation
import Testing

struct CaptureParitySafetyTests {
    @Test("app and agent note creation use the canonical capture service")
    func noteCreationUsesCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+QuickActions.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Services/AI/MLXToolExecutor.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let functionName = relativePath.contains("MLXToolExecutor")
                ? "private static func createNote"
                : "func createNoteAndOpen"
            let body = try #require(block(named: functionName, in: source), "Could not find \(functionName) in \(relativePath)")

            if !body.contains("CiderCaptureService().addNoteCapture(") {
                violations.append("\(relativePath): \(functionName) does not create notes through CiderCaptureService")
            }
            if body.contains("NotesStorage.shared.createNew(") {
                violations.append("\(relativePath): \(functionName) still creates notes through NotesStorage directly")
            }
        }

        #expect(violations.isEmpty, "Note capture paths must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("empty-note editor entrypoints use the canonical capture service")
    func emptyNoteEditorEntrypointsUseCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, marker: String)] = [
            (
                "Sources/Cider/ViewModels/NotesViewModel.swift",
                "func createNewNote"
            ),
            (
                "Sources/Cider/Views/CiderPanelView.swift",
                ".onReceive(NotificationCenter.default.publisher(for: .toggleNoteEditor))"
            ),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let fileURL = repoRoot.appendingPathComponent(expectation.file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let body = try #require(
                block(named: expectation.marker, in: source),
                "Could not find \(expectation.marker) in \(expectation.file)"
            )

            if !body.contains("CiderCaptureService().addNoteCapture(") {
                violations.append("\(expectation.file): \(expectation.marker) does not create empty notes through CiderCaptureService")
            }
            if body.contains("NotesStorage.shared.createNew(") {
                violations.append("\(expectation.file): \(expectation.marker) still creates empty notes through NotesStorage directly")
            }
        }

        #expect(violations.isEmpty, "Empty-note editor entrypoints must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("AI-created notes and reminders use the canonical capture service")
    func aiCreatedNotesAndRemindersUseCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            "Sources/Cider/Services/AI/AIAssistantTools.swift",
            "Sources/Cider/Services/AI/MLXToolExecutor.swift",
        ]
        var violations: [String] = []

        for file in files {
            let fileURL = repoRoot.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            if source.contains("NotesStorage.shared.createNew(") {
                violations.append("\(file): AI note creation still uses NotesStorage directly")
            }
            if source.contains("createDateCard(title:") {
                violations.append("\(file): AI reminder creation still uses DateCardStorage directly")
            }
            if file.hasSuffix("AIAssistantTools.swift"),
               !source.contains("CiderCaptureService().addNoteCapture(")
                || !source.contains("CiderCaptureService().addDateCardCapture(") {
                violations.append("\(file): AI tools missing canonical note/date capture calls")
            }
            if file.hasSuffix("MLXToolExecutor.swift"),
               !source.contains("CiderCaptureService().addDateCardCapture(") {
                violations.append("\(file): MLX reminder tool missing canonical date capture call")
            }
        }

        #expect(violations.isEmpty, "AI-created notes and reminders must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("quick-create event contact and todo creation use the canonical capture service")
    func quickCreateDomainItemsUseCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+SidebarFooter.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")

            if source.contains("DateCardStorage.shared.createDateCard("),
               !source.contains("CiderCaptureService().addDateCardCapture(") {
                violations.append("\(relativePath): quick-create events still create date cards through DateCardStorage directly")
            }
            if source.contains("ContactStorage.shared.createContact("),
               !source.contains("CiderCaptureService().addContactCapture(") {
                violations.append("\(relativePath): quick-create contacts still create contacts through ContactStorage directly")
            }
            if source.contains("TodoCardStorage.shared.addTodoCard(") || source.contains("TodoCardStorage.shared.createTodoCard("),
               !source.contains("CiderCaptureService().addTodoCapture(") {
                violations.append("\(relativePath): quick-create todos still create todos through TodoCardStorage directly")
            }
        }

        #expect(violations.isEmpty, "Quick-create paths must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("screen capture notes and visual intake text file saves use canonical capture service")
    func visualIntakeUsesCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/App/AppDelegate+ScreenCapture.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Views/Shared/ClipboardViewerView.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/App/CiderDropZoneContext.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")

            if source.contains("NotesStorage.shared.createFromCapture("),
               !source.contains("CiderCaptureService().addScreenCaptureNoteCapture(") {
                violations.append("\(relativePath): screen capture notes still use NotesStorage.createFromCapture directly")
            }
            if source.contains("storage.createNew()") || source.contains("NotesStorage.shared.createNew("),
               !source.contains("CiderCaptureService().addNoteCapture(") {
                violations.append("\(relativePath): visual intake note saves still create notes directly")
            }
            if source.contains("copyFileToVaultInbox("),
               !source.contains("CiderCaptureService().addFileCapture(") {
                violations.append("\(relativePath): drop-zone files still copy into the vault without capture service provenance")
            }
        }

        #expect(violations.isEmpty, "Visual intake paths must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("clipboard and drop-zone image bookmarks use canonical capture service")
    func imageBookmarkIntakeUsesCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/Views/Shared/ClipboardViewerView.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/App/CiderDropZoneContext.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/App/AppDelegate+Toasts.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")

            if source.contains("VaultBookmarkService.shared.addImageBookmark("),
               !source.contains("CiderCaptureService().addImageBookmarkCapture(") {
                violations.append("\(relativePath): image bookmark intake still creates bookmarks outside the capture service")
            }
        }

        #expect(violations.isEmpty, "Image bookmark intake paths must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("macOS Services intake uses canonical capture service")
    func macOSServicesIntakeUsesCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileURL = repoRoot.appendingPathComponent("Sources/Cider/Services/CiderServicesProvider.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var violations: [String] = []

        if source.contains("NotesStorage.shared.createNew()"),
           !source.contains("CiderCaptureService().addNoteCapture(") {
            violations.append("CiderServicesProvider.swift: text Services intake still creates notes directly")
        }
        if source.contains("VaultBookmarkService.shared.addImageBookmark("),
           !source.contains("CiderCaptureService().addImageBookmarkCapture(") {
            violations.append("CiderServicesProvider.swift: image Services intake still creates image bookmarks directly")
        }

        #expect(violations.isEmpty, "macOS Services intake must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
    }

    @Test("capture intake surfaces pass source context")
    func captureIntakeSurfacesPassSourceContext() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, surface: String, requiredSnippets: [String])] = [
            (
                "Sources/Cider/App/CiderDropZoneContext.swift",
                "drop_zone",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"drop_zone\"",
                ]
            ),
            (
                "Sources/Cider/Services/CiderServicesProvider.swift",
                "macos_services",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"macos_services\"",
                ]
            ),
            (
                "Sources/Cider/App/AppDelegate+ScreenCapture.swift",
                "screen_capture",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"screen_capture\"",
                ]
            ),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let fileURL = repoRoot.appendingPathComponent(expectation.file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for snippet in expectation.requiredSnippets where !source.contains(snippet) {
                violations.append("\(expectation.file): missing \(snippet) for \(expectation.surface) provenance")
            }
        }

        #expect(violations.isEmpty, "Capture intake surfaces must pass source context:\n\(violations.joined(separator: "\n"))")
    }

    @Test("bookmark adapter and URL intake preserve source context")
    func bookmarkAdapterAndURLIntakePreserveSourceContext() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, requiredSnippets: [String])] = [
            (
                "Sources/Cider/Services/CiderCaptureService.swift",
                [
                    "sourceContext: CaptureSourceContext? = nil",
                    "sourceContext: sourceContext",
                ]
            ),
            (
                "Sources/Cider/ViewModels/BookmarksViewModel.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"active_browser\"",
                    "surface: \"pasteboard\"",
                ]
            ),
            (
                "Sources/Cider/Services/BookmarksClipboardMonitor.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"clipboard_monitor\"",
                ]
            ),
            (
                "Sources/Cider/App/CiderDropZoneContext.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"drop_zone\"",
                ]
            ),
            (
                "Sources/Cider/Views/CiderPanelView+URLDrop.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"url_drop\"",
                ]
            ),
            (
                "Sources/Cider/Views/Shared/ClipboardViewerView.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"clipboard_viewer\"",
                ]
            ),
            (
                "Sources/Cider/App/AppDelegate+Toasts.swift",
                [
                    "sourceContext: CaptureSourceContext(",
                    "surface: \"clipboard_review_toast\"",
                ]
            ),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let fileURL = repoRoot.appendingPathComponent(expectation.file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for snippet in expectation.requiredSnippets where !source.contains(snippet) {
                violations.append("\(expectation.file): missing \(snippet)")
            }
        }

        #expect(violations.isEmpty, "Bookmark URL intake must preserve source context:\n\(violations.joined(separator: "\n"))")
    }

    @Test("derived create wrappers record create provenance")
    func derivedCreateWrappersRecordCreateProvenance() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, requiredSnippets: [String])] = [
            (
                "Sources/Cider/Services/LibraryItemEditor.swift",
                [
                    "recordCreateProvenance(",
                    "\"library.editor.event.create\"",
                    "\"library.editor.contact.create\"",
                ]
            ),
            (
                "Sources/Cider/Services/CiderBookmarkDateSuggestionApprovalService.swift",
                [
                    "recordCreateProvenance(",
                    "\"bookmark.date_suggestion.date_card.create\"",
                    "\"bookmark.date_suggestion.todo.create\"",
                ]
            ),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let fileURL = repoRoot.appendingPathComponent(expectation.file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for snippet in expectation.requiredSnippets where !source.contains(snippet) {
                violations.append("\(expectation.file): missing \(snippet)")
            }
        }

        #expect(violations.isEmpty, "Derived create wrappers must preserve routing provenance:\n\(violations.joined(separator: "\n"))")
    }

    private func block(named marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker) else { return nil }
        let tail = source[markerRange.lowerBound...]
        guard let openBrace = tail.firstIndex(of: "{") else { return nil }
        var depth = 0
        var cursor = openBrace
        while cursor < source.endIndex {
            let char = source[cursor]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[markerRange.lowerBound...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }
}
