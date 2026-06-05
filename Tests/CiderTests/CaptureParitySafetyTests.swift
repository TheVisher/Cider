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
               !source.contains(".addNoteCapture(")
                || !source.contains(".addDateCardCapture(") {
                violations.append("\(file): AI tools missing canonical note/date capture calls")
            }
            if file.hasSuffix("MLXToolExecutor.swift"),
               !source.contains(".addDateCardCapture(") {
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

    @Test("CLI event and contact create paths cannot bypass canonical capture")
    func cliEventAndContactCreatePathsCannotBypassCanonicalCapture() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cliURL = repoRoot.appendingPathComponent("Sources/CiderCLI/CiderCLI.swift")
        let source = try String(contentsOf: cliURL, encoding: .utf8)
        var violations: [String] = []

        if source.contains("source: \"event.create\"") {
            violations.append("Sources/CiderCLI/CiderCLI.swift: event create branch still records direct create provenance")
        }
        if source.contains("source: \"contact.create\"") {
            violations.append("Sources/CiderCLI/CiderCLI.swift: contact create branch still records direct create provenance")
        }
        if source.contains("storage.createDateCard(title:") {
            violations.append("Sources/CiderCLI/CiderCLI.swift: event create path still calls DateCardStorage directly")
        }
        if source.contains("storage.createContact(displayName: name)") {
            violations.append("Sources/CiderCLI/CiderCLI.swift: contact create path still calls ContactStorage directly")
        }

        #expect(violations.isEmpty, "Removed CLI event/contact create paths must not retain direct storage implementations:\n\(violations.joined(separator: "\n"))")
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

    @Test("clipboard viewer image and text saves pass source context")
    func clipboardViewerImageAndTextSavesPassSourceContext() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let file = "Sources/Cider/Views/Shared/ClipboardViewerView.swift"
        let source = try String(contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8)
        let imageBranch = try #require(
            snippet(from: "case .image:", to: "case .text, .richText:", in: source),
            "Could not find ClipboardViewer image save branch"
        )
        let saveAsNote = try #require(
            block(named: "private func saveAsNote", in: source),
            "Could not find ClipboardViewer saveAsNote"
        )
        var violations: [String] = []

        for (name, body) in [("image save", imageBranch), ("text save", saveAsNote)] {
            if !body.contains("sourceContext: CaptureSourceContext(") {
                violations.append("\(file): \(name) missing sourceContext")
            }
            if !body.contains("surface: \"clipboard_viewer\"") {
                violations.append("\(file): \(name) missing clipboard_viewer surface")
            }
            if !body.contains("channel: \"pasteboard\"") {
                violations.append("\(file): \(name) missing pasteboard channel")
            }
        }

        #expect(violations.isEmpty, "ClipboardViewer image/text saves must preserve source context:\n\(violations.joined(separator: "\n"))")
    }

    @Test("AI note creation passes AI source context")
    func aiNoteCreationPassesAISourceContext() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, marker: String, surface: String)] = [
            ("Sources/Cider/Services/AI/AIAssistantTools.swift", "struct CreateNoteTool: Tool", "ai_assistant"),
            ("Sources/Cider/Services/AI/MLXToolExecutor.swift", "private static func createNote", "mlx_tool"),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(expectation.file), encoding: .utf8)
            let body = try #require(
                block(named: expectation.marker, in: source),
                "Could not find \(expectation.marker) in \(expectation.file)"
            )
            if !body.contains("CiderCaptureService().addNoteCapture(") {
                violations.append("\(expectation.file): missing canonical note capture call")
            }
            if !body.contains("sourceContext: CaptureSourceContext(") {
                violations.append("\(expectation.file): missing sourceContext on AI note creation")
            }
            if !body.contains("surface: \"\(expectation.surface)\"") {
                violations.append("\(expectation.file): missing \(expectation.surface) surface")
            }
        }

        #expect(violations.isEmpty, "AI note creation must preserve tool source context:\n\(violations.joined(separator: "\n"))")
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

    @Test("bookmark-like capture receipts post rich toast payloads")
    func bookmarkLikeCaptureReceiptsPostRichToastPayloads() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            "Sources/Cider/ViewModels/BookmarksViewModel.swift",
            "Sources/Cider/Views/CiderPanelView+URLDrop.swift",
            "Sources/Cider/Services/BookmarksClipboardMonitor.swift",
            "Sources/Cider/Views/Shared/ClipboardViewerView.swift",
            "Sources/Cider/Services/CiderServicesProvider.swift",
            "Sources/Cider/App/AppDelegate+Toasts.swift",
        ]
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8)
            if source.contains("receipt.toastMessage(success:") {
                violations.append("\(file): still flattens a capture receipt into a toast message")
            }
            if source.contains("= CaptureReceipt(result:") || source.contains("let receipt = CaptureReceipt(result:") {
                violations.append("\(file): still builds legacy CaptureReceipt from a rich capture result")
            }
        }

        #expect(violations.isEmpty, "Bookmark-like capture surfaces should post UICaptureReceipt payloads:\n\(violations.joined(separator: "\n"))")
    }

    @Test("derived create wrappers record create provenance")
    func derivedCreateWrappersRecordCreateProvenance() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, requiredSnippets: [String])] = [
            (
                "Sources/Cider/Services/LibraryItemEditor.swift",
                [
                    "recordCreateProvenanceOrLog(",
                    "\"library.editor.event.create\"",
                    "\"library.editor.contact.create\"",
                ]
            ),
            (
                "Sources/Cider/Services/CiderBookmarkDateSuggestionApprovalService.swift",
                [
                    "recordCreateProvenanceOrLog(",
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

    @Test("derived create wrappers do not silently swallow create provenance failures")
    func derivedCreateWrappersDoNotSilentlySwallowCreateProvenanceFailures() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            "Sources/Cider/Services/LibraryItemEditor.swift",
            "Sources/Cider/Services/CiderBookmarkDateSuggestionApprovalService.swift",
        ]
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8)
            if source.contains("try? CiderRoutingDecisionService().recordCreateProvenance(") {
                violations.append("\(file): create provenance failures are silently swallowed with try?")
            }
        }

        #expect(violations.isEmpty, "Create provenance failures must be logged or surfaced, not silently swallowed:\n\(violations.joined(separator: "\n"))")
    }

    @Test("indexed item mutation services refresh content chunks after SQLite writes")
    func indexedItemMutationServicesRefreshContentChunksAfterSQLiteWrites() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let expectations: [(file: String, marker: String, ownerType: String)] = [
            ("Sources/Cider/Services/VaultBookmarkService.swift", "func updateURL", "bookmark"),
            ("Sources/Cider/Services/VaultBookmarkService.swift", "func updateDetails", "bookmark"),
            ("Sources/Cider/Services/VaultBookmarkService.swift", "func updateEnrichment", "bookmark"),
            ("Sources/Cider/Services/DateCardStorage.swift", "func updateDateCard", "dateCard"),
            ("Sources/Cider/Services/TodoCardStorage.swift", "func updateTodoCard", "todo"),
            ("Sources/Cider/Services/ContactStorage.swift", "func updateContact", "contact"),
            ("Sources/Cider/Services/VaultFileStorage.swift", "func updateTitle", "vaultFile"),
            ("Sources/Cider/Services/VaultFileStorage.swift", "func updateNotes", "vaultFile"),
        ]
        var violations: [String] = []

        for expectation in expectations {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(expectation.file), encoding: .utf8)
            let body = try #require(
                block(named: expectation.marker, in: source),
                "Could not find \(expectation.marker) in \(expectation.file)"
            )
            if !body.contains("SecondBrainItemMutationIndexer.rebuildAfterMutation(") {
                violations.append("\(expectation.file): \(expectation.marker) does not rebuild content chunks")
            }
            if !body.contains("ownerType: \"\(expectation.ownerType)\"") {
                violations.append("\(expectation.file): \(expectation.marker) does not rebuild \(expectation.ownerType) chunks")
            }
        }

        #expect(violations.isEmpty, "Indexed item mutations must refresh content chunks after SQLite writes:\n\(violations.joined(separator: "\n"))")
    }

    private func snippet(from startMarker: String, to endMarker: String, in source: String) -> String? {
        guard let startRange = source.range(of: startMarker),
              let endRange = source[startRange.upperBound...].range(of: endMarker) else {
            return nil
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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
