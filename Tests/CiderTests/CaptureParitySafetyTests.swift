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
