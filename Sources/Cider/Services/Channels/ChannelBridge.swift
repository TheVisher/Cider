import Foundation

protocol ChannelBridge: Sendable {
    var channel: AgentChannel { get }
    var displayName: String { get }

    func start() async throws
    func stop() async
    func health() async -> ChannelBridgeHealth
}

struct ChannelBridgeHealth: Sendable {
    let status: ChannelBridgeStatus
    let detail: String
    let lastInboundAt: Date?
    let lastOutboundAt: Date?
}

enum ChannelBridgeStatus: String, Sendable {
    case idle
    case available
    case degraded
    case unavailable
}
