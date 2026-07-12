import Foundation
import Testing
@testable import Cider

struct HermesAPIClientTests {
    @Test("capabilities decode Hermes Runs and SSE support")
    func capabilitiesDecodeRunsSupport() throws {
        let json = """
        {
          "object": "hermes.api_server.capabilities",
          "platform": "hermes-agent",
          "model": "hermes-agent",
          "features": {
            "chat_completions": true,
            "chat_completions_streaming": true,
            "responses_api": true,
            "responses_streaming": true,
            "run_submission": true,
            "run_status": true,
            "run_events_sse": true,
            "run_stop": true,
            "tool_progress_events": true,
            "session_continuity_header": "X-Hermes-Session-Id",
            "cors": false
          }
        }
        """

        let decoded = try JSONDecoder().decode(HermesAPICapabilities.self, from: Data(json.utf8))

        #expect(decoded.object == "hermes.api_server.capabilities")
        #expect(decoded.platform == "hermes-agent")
        #expect(decoded.features.runSubmission)
        #expect(decoded.features.runStatus)
        #expect(decoded.features.runEventsSSE)
        #expect(decoded.features.runStop)
        #expect(decoded.features.sessionContinuityHeader == "X-Hermes-Session-Id")
    }

    @Test("client key takes precedence and server key remains a compatible fallback")
    func resolvesAPIKeyAliases() {
        #expect(HermesAPIClient.resolvedAPIKey(environment: [
            "HERMES_API_SERVER_KEY": "client-key",
            "API_SERVER_KEY": "server-key"
        ]) == "client-key")
        #expect(HermesAPIClient.resolvedAPIKey(environment: [
            "API_SERVER_KEY": "server-key"
        ]) == "server-key")
        #expect(HermesAPIClient.resolvedAPIKey(environment: [
            "HERMES_API_SERVER_KEY": "   ",
            "API_SERVER_KEY": "server-key"
        ]) == "server-key")
        #expect(HermesAPIClient.resolvedAPIKey(environment: [:]) == nil)
    }

    @Test("SSE parser extracts Hermes run events")
    func sseParserExtractsRunEvents() throws {
        let sse = """
        data: {"event":"message.delta","run_id":"run_1","delta":"Hel"}

        data: {"event":"message.delta","run_id":"run_1","delta":"lo"}

        data: {"event":"tool.started","run_id":"run_1","tool":"terminal","preview":"pwd"}

        data: {"event":"run.completed","run_id":"run_1","output":"Hello"}

        """

        let events = try HermesSSEParser.events(from: Data(sse.utf8))
        let bridgeEvents = events.compactMap(\.bridgeEvent)

        #expect(bridgeEvents == [
            .messageDelta("Hel"),
            .messageDelta("lo"),
            .toolStarted(name: "terminal", preview: "pwd"),
            .completed(output: "Hello")
        ])
    }

    @Test("SSE parser extracts approval request events")
    func sseParserExtractsApprovalRequestEvents() throws {
        let sse = """
        data: {"event":"approval.requested","run_id":"run_1","preview":"Allow Hermes to edit this file?"}

        """

        let events = try HermesSSEParser.events(from: Data(sse.utf8))
        let bridgeEvents = events.compactMap(\.bridgeEvent)

        #expect(bridgeEvents == [
            .approvalRequested("Allow Hermes to edit this file?")
        ])
    }

    @Test("terminal status decodes explicit bounded Cider references")
    func statusDecodesCiderReferences() throws {
        let json = """
        {
          "run_id": "run-809",
          "status": "completed",
          "cider_references": [{
            "kind": "task",
            "id": "8d2bd6",
            "title": "Show source-backed receipts",
            "board_id": "2afee0",
            "source": "cider",
            "source_ref": "kanban_card:2afee0/8d2bd6"
          }]
        }
        """

        let decoded = try JSONDecoder().decode(HermesRunStatusResponse.self, from: Data(json.utf8))
        #expect(decoded.ciderReferences.count == 1)
        #expect(decoded.ciderReferences.first?.boardID == "2afee0")
        #expect(decoded.ciderReferences.first?.sourceRef == "kanban_card:2afee0/8d2bd6")
    }

    @Test("malformed terminal references fail closed without losing the normal result")
    func malformedStatusReferenceFailsClosed() throws {
        let json = """
        {
          "run_id": "run-809",
          "status": "completed",
          "output": "Normal transcript result",
          "cider_references": [{
            "kind": "task",
            "id": "8d2bd6",
            "board_id": "2afee0"
          }]
        }
        """

        let decoded = try JSONDecoder().decode(HermesRunStatusResponse.self, from: Data(json.utf8))
        #expect(decoded.output == "Normal transcript result")
        #expect(decoded.ciderReferences.isEmpty)
    }

    @Test("current Hermes terminal envelope preserves plain saved URL output without invented metadata")
    func currentTerminalEnvelopeShape() throws {
        let json = #"""
        {
          "object": "hermes.run",
          "run_id": "run-backpack",
          "status": "completed",
          "session_id": "session-backpack",
          "output": "I found the saved backpack:\nhttps://chromeindustries.com/products/cohesive-35l-backpack",
          "usage": {"input_tokens": 100, "output_tokens": 20, "total_tokens": 120},
          "last_event": "run.completed"
        }
        """#

        let decoded = try JSONDecoder().decode(HermesRunStatusResponse.self, from: Data(json.utf8))

        #expect(decoded.output?.hasSuffix("https://chromeindustries.com/products/cohesive-35l-backpack") == true)
        #expect(decoded.ciderReferences.isEmpty)
    }
}
