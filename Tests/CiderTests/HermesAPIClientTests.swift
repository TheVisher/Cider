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
}
