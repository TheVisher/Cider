import AppKit
import Foundation
import os

/// AppKit ownership for the explicit local export destination. The workspace
/// supplies only canonical room identity and never handles repository or file IO.
@MainActor
enum AgentRoomsRoomExportPresenter {
    private static let logger = Logger(subsystem: "com.cider.app", category: "RoomExport")

    struct FailurePresentation: Equatable, Sendable {
        let title: String
        let detail: String
    }

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
        Task {
            do {
                _ = try await exporter.exportForPresentation(roomID: roomID, to: destination)
            } catch {
                let presentation = failurePresentation(for: error)
                logger.error("Room export failed with a bounded local export error.")
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = presentation.title
                alert.informativeText = presentation.detail
                alert.runModal()
            }
        }
    }

    nonisolated static func failurePresentation(for error: Error) -> FailurePresentation {
        let detail = (error as? AgentRoomsRoomExportError) == .destinationExists
            ? "Choose a new export name. Cider does not overwrite existing files or folders."
            : "The conversation was not changed. Choose a new local destination and try again."
        return FailurePresentation(
            title: "Cider couldn’t export this conversation",
            detail: detail
        )
    }

    private static func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let components = title.components(separatedBy: forbidden)
        let sanitized = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Cider Conversation" : sanitized).prefix(80))
    }
}
