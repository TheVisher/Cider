import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Message Presentation Tests")
@MainActor
struct AgentRoomsMessagePresentationTests {
    @Test("native Markdown preserves source while presenting emphasis lists links and code")
    func nativeMarkdownPresentation() throws {
        let source = """
        ## Daily plan

        Keep **Cider history** local and use [the safe reference](https://example.com/reference).

        - First item
        2. Second item with `inline code`

        ```swift
        let roomID = "canonical"
        ```
        """

        let document = AgentRoomsMessagePresentation.document(source: source)

        #expect(document.source == source)
        #expect(document.blocks.map(\.kind) == [
            .heading(level: 2),
            .paragraph,
            .unorderedListItem(depth: 0),
            .orderedListItem(depth: 0, ordinal: 2),
            .code(language: "swift", isComplete: true),
        ])
        #expect(document.blocks[1].plainText == "Keep Cider history local and use the safe reference.")
        #expect(document.blocks[1].links == [URL(string: "https://example.com/reference")!])
        #expect(document.blocks[4].plainText == "let roomID = \"canonical\"")
    }

    @Test("unsafe links and HTML never become executable presentation actions")
    func unsafeLinksAndHTMLAreInert() {
        let source = """
        [web](https://example.com) [script](javascript:alert('x')) [file](file:///tmp/private)
        <script>open('/tmp/private')</script>
        """

        let document = AgentRoomsMessagePresentation.document(source: source)

        #expect(document.source == source)
        #expect(document.blocks.flatMap(\.links) == [URL(string: "https://example.com")!])
        #expect(AgentRoomsSafeLinkPolicy.isAllowed(URL(string: "https://example.com")!))
        #expect(!AgentRoomsSafeLinkPolicy.isAllowed(URL(string: "javascript:alert('x')")!))
        #expect(!AgentRoomsSafeLinkPolicy.isAllowed(URL(fileURLWithPath: "/tmp/private")))
    }

    @Test("unfinished fences stay readable and retain stable block identity across streaming deltas")
    func streamingFenceIdentity() throws {
        let first = AgentRoomsMessagePresentation.document(source: "Before\n\n```swift\nlet value =")
        let second = AgentRoomsMessagePresentation.document(source: "Before\n\n```swift\nlet value = 1")
        let terminal = AgentRoomsMessagePresentation.document(source: "Before\n\n```swift\nlet value = 1\n```")

        let firstCode = try #require(first.blocks.last)
        let secondCode = try #require(second.blocks.last)
        let terminalCode = try #require(terminal.blocks.last)
        #expect(firstCode.kind == .code(language: "swift", isComplete: false))
        #expect(secondCode.kind == .code(language: "swift", isComplete: false))
        #expect(terminalCode.kind == .code(language: "swift", isComplete: true))
        #expect(firstCode.id == secondCode.id)
        #expect(secondCode.id == terminalCode.id)
        #expect(secondCode.plainText == "let value = 1")
    }

    @Test("per-session presentation cache reparses only a changed message")
    func presentationCacheIsMessageScoped() {
        let store = AgentRoomsMessagePresentationStore()
        let first = AgentRoomMessage(id: "one", role: .agent, author: "Hermes", body: "First")
        let second = AgentRoomMessage(id: "two", role: .agent, author: "Hermes", body: "Second")

        _ = store.document(for: first)
        _ = store.document(for: second)
        _ = store.document(for: first)
        #expect(store.parseCount == 2)

        var changedSecond = second
        changedSecond.body += " delta"
        _ = store.document(for: changedSecond)
        _ = store.document(for: first)
        #expect(store.parseCount == 3)
    }

    @Test("activity presentation removes ANSI and transport payload noise without rewriting source detail")
    func calmActivityPresentation() {
        let activity = AgentRoomsLiveActivity(
            id: UUID(),
            kind: .toolStarted,
            detail: "\u{001B}[31m{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{}}\u{001B}[0m"
        )

        let presentation = AgentRoomsActivityPresentation.project(activity)

        #expect(activity.detail.contains("jsonrpc"))
        #expect(presentation.label == "Using a tool")
        #expect(presentation.summary == "Runtime activity available")
        #expect(!presentation.accessibilityLabel.contains("jsonrpc"))
        #expect(!presentation.accessibilityLabel.contains("[31m"))
    }

    @Test("connection and terminal states expose calm reconnect and interruption semantics")
    func calmStatusPresentation() {
        let unavailable = AgentRoomsChatStatusPresentation.project(
            transportState: .blocked,
            turnState: .idle,
            receipt: nil,
            message: AgentRoomsLiveChatModel.unavailableMessage
        )
        #expect(unavailable.state == .unavailable)
        #expect(unavailable.title == "Hermes is unavailable")
        #expect(unavailable.allowsReconnect)

        let unavailableAfterCompletion = AgentRoomsChatStatusPresentation.project(
            transportState: .blocked,
            turnState: .completed,
            receipt: nil,
            message: AgentRoomsLiveChatModel.unavailableMessage
        )
        #expect(unavailableAfterCompletion.state == .unavailable)
        #expect(unavailableAfterCompletion.allowsReconnect)

        let accepted = AgentRoomsChatStatusPresentation.project(
            transportState: .ready,
            turnState: .failed,
            receipt: AgentRoomReceipt(
                id: "receipt",
                title: "Hermes response interrupted",
                detail: "Accepted by Hermes · Cannot retry safely",
                status: .failed,
                continuity: .liveContinuation,
                sourceBackedTransport: true,
                sourceIdentity: AgentRoomsLiveChatModel.receiptSourceIdentity,
                runIdentity: "run-accepted"
            ),
            message: AgentRoomsLiveChatModel.acceptedInterruptionMessage
        )
        #expect(accepted.state == .failed)
        #expect(accepted.detail == "Accepted by Hermes · Cannot retry safely")
        #expect(!accepted.allowsReconnect)
    }
}
