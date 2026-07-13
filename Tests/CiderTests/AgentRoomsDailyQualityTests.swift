import AppKit
import SwiftUI
import XCTest
@testable import Cider

final class AgentRoomsDailyQualityTests: XCTestCase {
    @MainActor
    func testNarrowLargeTextWorkspaceKeepsComposerAndDirectExportUsable() async throws {
        let model = AgentRoomsLiveChatModel(
            transport: DailyQualityReadyTransport(),
            turnCoordinator: HermesTurnCoordinator()
        )
        await model.startTestChat()
        let roomID = try XCTUnwrap(model.testRoom?.id)
        var exportedRoomID: UUID?
        let view = AgentRoomsWorkspaceView(
            state: .loaded(authority: .canonicalIncomplete, rooms: [], selectedRoomID: roomID),
            liveChat: model,
            onOpenLiveChat: {},
            onExportRoom: { roomID, _ in exportedRoomID = roomID }
        )
        .environment(\.dynamicTypeSize, .accessibility2)
        .frame(width: 520, height: 760)

        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 100, y: 100, width: 520, height: 760), display: false)
        window.contentView = CiderMainWindowHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        await settleUI()
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(findComposerField(in: window.contentView))
        let fieldFrame = field.convert(field.bounds, to: window.contentView)
        XCTAssertTrue(window.contentView?.bounds.contains(fieldFrame) == true)
        XCTAssertGreaterThan(fieldFrame.width, 120)
        let accessibleEditor = try XCTUnwrap(field.accessibilityChildren()?.first as? NSObject)
        let role = accessibleEditor.perform(NSSelectorFromString("accessibilityRole"))?
            .takeUnretainedValue() as? String
        XCTAssertEqual(role, NSAccessibility.Role.textField.rawValue)

        window.sendEvent(try shortcutEvent(in: window, character: "E", keyCode: 14))
        await settleUI()
        XCTAssertEqual(exportedRoomID?.uuidString, roomID)
    }

    func testLayoutAndReduceMotionPoliciesAreDeterministic() {
        XCTAssertEqual(
            AgentRoomsWorkspaceLayoutPolicy.mode(width: 1_000, usesAccessibilityText: false),
            .sideBySide
        )
        XCTAssertEqual(
            AgentRoomsWorkspaceLayoutPolicy.mode(width: 520, usesAccessibilityText: false),
            .stacked
        )
        XCTAssertEqual(
            AgentRoomsWorkspaceLayoutPolicy.mode(width: 1_000, usesAccessibilityText: true),
            .stacked
        )
        XCTAssertTrue(AgentRoomsTranscriptMotionPolicy.disablesScrollAnimations(reduceMotion: true))
        XCTAssertFalse(AgentRoomsTranscriptMotionPolicy.disablesScrollAnimations(reduceMotion: false))
    }

    func testExportErrorsAreBoundedAndDoNotExposeRawDetails() {
        let existing = AgentRoomsRoomExportPresenter.failurePresentation(
            for: AgentRoomsRoomExportError.destinationExists
        )
        XCTAssertEqual(existing.title, "Cider couldn’t export this conversation")
        XCTAssertTrue(existing.detail.contains("does not overwrite"))

        let privateError = NSError(
            domain: "SQL /Users/private/Cider.sqlite Authorization: Bearer secret",
            code: 1
        )
        let generic = AgentRoomsRoomExportPresenter.failurePresentation(for: privateError)
        XCTAssertFalse(generic.detail.contains("/Users"))
        XCTAssertFalse(generic.detail.contains("Bearer"))
        XCTAssertFalse(generic.detail.contains("SQL"))
    }

    @MainActor
    private func settleUI() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
    }

    @MainActor
    private func findComposerField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.placeholderString == "Message Hermes in Cider Test Chat" {
            return field
        }
        for subview in view.subviews {
            if let match = findComposerField(in: subview) { return match }
        }
        return nil
    }

    @MainActor
    private func shortcutEvent(in window: NSWindow, character: String, keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        ))
    }

}

private actor DailyQualityReadyTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        throw CancellationError()
    }

    func stop(runID: String) async throws {}
}
