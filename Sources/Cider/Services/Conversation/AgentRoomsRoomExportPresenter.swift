import AppKit
import Foundation
import os

/// AppKit ownership for the explicit local export destination. The workspace
/// supplies only canonical room identity and never handles repository or file IO.
@MainActor
enum AgentRoomsRoomExportPresenter {
    private static let logger = Logger(subsystem: "com.cider.app", category: "RoomExport")

    static func requestExport(
        roomID: UUID,
        roomTitle: String,
        exporter: any AgentRoomsRoomExporting
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeFileName(roomTitle)).cider-room"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Creates a local folder with readable Markdown and a JSON manifest. Nothing is uploaded or shared."

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            _ = try exporter.export(roomID: roomID, to: destination)
        } catch {
            logger.error("Room export failed: \(String(describing: error), privacy: .public)")
            let exportError = error as? AgentRoomsRoomExportError
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cider couldn’t export this conversation"
            alert.informativeText = exportError == .destinationExists
                ? "Choose a new export name. Cider does not overwrite existing files or folders."
                : "The conversation was not changed. Choose a new local destination and try again."
            alert.runModal()
        }
    }

    private static func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let components = title.components(separatedBy: forbidden)
        let sanitized = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Cider Conversation" : sanitized).prefix(80))
    }
}
