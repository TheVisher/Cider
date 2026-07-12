import AppKit
import SwiftUI
import XCTest
@testable import Cider

final class AgentRoomsComposerInteractionTests: XCTestCase {
    @MainActor
    func testComposerDraftSurvivesHostedWorkspaceReconstruction() async throws {
        let model = AgentRoomsLiveChatModel(
            transport: ComposerReadyTransport(),
            turnCoordinator: HermesTurnCoordinator()
        )
        let session = AgentRoomsSessionModel(liveChat: model)
        await session.startTestChat()
        let roomID = try XCTUnwrap(model.testRoom?.id)
        let state = AgentRoomsWorkspaceState.loaded(
            authority: .canonicalIncomplete,
            rooms: [],
            selectedRoomID: roomID
        )
        let route = HostedRoomsRoute()

        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 100, y: 100, width: 1_000, height: 700), display: false)
        window.contentView = CiderMainWindowHostingView(rootView:
            HostedRoomsNavigationHarness(route: route, state: state, session: session)
                .frame(width: 1_000, height: 700)
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        await settleUI()
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(findComposerField(in: window.contentView))
        let accessibilityTextField = try XCTUnwrap(field.accessibilityChildren()?.first as? NSObject)
        accessibilityTextField.perform(NSSelectorFromString("setAccessibilityValue:"), with: "continuity draft")
        await settleUI()

        XCTAssertEqual(field.stringValue, "continuity draft")

        route.showsRooms = false
        await settleUI()
        route.showsRooms = true
        await settleUI()
        window.contentView?.layoutSubtreeIfNeeded()

        let reconstructedField = try XCTUnwrap(findComposerField(in: window.contentView))
        XCTAssertEqual(reconstructedField.stringValue, "continuity draft")
        XCTAssertEqual(session.selectedRoomID, roomID)
    }

    @MainActor
    func testNativeClickMakesComposerEditableInCiderMainWindow() async throws {
        let transport = ComposerReadyTransport()
        let model = AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator()
        )
        await model.startTestChat()
        let roomID = try XCTUnwrap(model.testRoom?.id)
        let state = AgentRoomsWorkspaceState.loaded(
            authority: .canonicalIncomplete,
            rooms: [],
            selectedRoomID: roomID
        )
        let view = AgentRoomsWorkspaceView(
            state: state,
            liveChat: model,
            onOpenLiveChat: {}
        )
        .frame(width: 1_000, height: 700)

        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 100, y: 100, width: 1_000, height: 700), display: false)
        window.contentView = CiderMainWindowHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        await settleUI()
        window.contentView?.layoutSubtreeIfNeeded()

        let field = try XCTUnwrap(findComposerField(in: window.contentView))
        let centerInWindow = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        XCTAssertTrue(
            window.isLocationExcludedFromWindowDrag(centerInWindow),
            "The live composer must register its full interactive area as non-draggable"
        )
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: centerInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }

        await settleUI()
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.insertText("hello", replacementRange: editor.selectedRange())
        await settleUI()

        XCTAssertEqual(field.stringValue, "hello")

        let returnEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        window.sendEvent(returnEvent)
        await settleUI()

        let sentTexts = await transport.sentTexts()
        XCTAssertEqual(sentTexts, ["hello"])
    }

    @MainActor
    private func settleUI() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
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

}

@MainActor
private final class HostedRoomsRoute: ObservableObject {
    @Published var showsRooms = true
}

private struct HostedRoomsNavigationHarness: View {
    @ObservedObject var route: HostedRoomsRoute
    let state: AgentRoomsWorkspaceState
    @ObservedObject var session: AgentRoomsSessionModel

    var body: some View {
        if route.showsRooms {
            AgentRoomsWorkspaceView(state: state, session: session, onOpenLiveChat: {})
        } else {
            Text("Today")
        }
    }
}

private actor ComposerReadyTransport: HermesBridgeTransport {
    private var texts: [String] = []

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        texts.append(text)
        throw CancellationError()
    }

    func stop(runID: String) async throws {}
    func sentTexts() -> [String] { texts }
}
