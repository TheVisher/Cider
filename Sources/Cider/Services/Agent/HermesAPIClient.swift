import Foundation

struct HermesAPICapabilities: Decodable, Equatable, Sendable {
    struct Features: Decodable, Equatable, Sendable {
        let chatCompletions: Bool
        let chatCompletionsStreaming: Bool
        let responsesAPI: Bool
        let responsesStreaming: Bool
        let runSubmission: Bool
        let runStatus: Bool
        let runEventsSSE: Bool
        let runStop: Bool
        let toolProgressEvents: Bool
        let sessionContinuityHeader: String?

        enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case chatCompletionsStreaming = "chat_completions_streaming"
            case responsesAPI = "responses_api"
            case responsesStreaming = "responses_streaming"
            case runSubmission = "run_submission"
            case runStatus = "run_status"
            case runEventsSSE = "run_events_sse"
            case runStop = "run_stop"
            case toolProgressEvents = "tool_progress_events"
            case sessionContinuityHeader = "session_continuity_header"
        }
    }

    let object: String
    let platform: String
    let model: String
    let features: Features
}

struct HermesRunCreateResponse: Decodable, Equatable, Sendable {
    let runID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

struct HermesRunStatusResponse: Decodable, Equatable, Sendable {
    let object: String?
    let runID: String
    let status: String
    let sessionID: String?
    let output: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case object
        case runID = "run_id"
        case status
        case sessionID = "session_id"
        case output
        case error
    }
}

struct HermesRunSSEEvent: Decodable, Equatable, Sendable {
    let event: String
    let runID: String?
    let delta: String?
    let output: String?
    let error: String?
    let tool: String?
    let preview: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case event
        case runID = "run_id"
        case delta
        case output
        case error
        case tool
        case preview
        case status
    }

    var bridgeEvent: HermesRunEvent? {
        switch event {
        case "message.delta":
            return .messageDelta(delta ?? "")
        case "tool.started":
            return .toolStarted(name: tool, preview: preview)
        case "tool.completed":
            return .toolCompleted(name: tool, isError: status == "error")
        case "reasoning.available":
            return .reasoningAvailable(preview ?? "")
        case "approval.requested":
            return .approvalRequested(preview)
        case "run.completed":
            return .completed(output: output ?? "")
        case "run.failed":
            return .failed(error ?? "Hermes run failed")
        case "run.cancelled":
            return .cancelled
        default:
            return nil
        }
    }
}

enum HermesAPIClientError: Error, LocalizedError, Equatable {
    case unavailable
    case invalidResponse(Int)
    case missingRequiredCapabilities

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Hermes API server is not available"
        case .invalidResponse(let status):
            return "Hermes API server returned HTTP \(status)"
        case .missingRequiredCapabilities:
            return "Hermes API server does not support Runs/SSE"
        }
    }
}

enum HermesSSEParser {
    static func events(from data: Data) throws -> [HermesRunSSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return try text
            .components(separatedBy: "\n\n")
            .compactMap { block -> HermesRunSSEEvent? in
                let line = block
                    .components(separatedBy: "\n")
                    .first { $0.hasPrefix("data: ") }
                guard let payload = line?.dropFirst("data: ".count),
                      let payloadData = String(payload).data(using: .utf8)
                else { return nil }
                return try decoder.decode(HermesRunSSEEvent.self, from: payloadData)
            }
    }
}

struct HermesAPIClient: Sendable {
    var baseURL: URL
    var apiKey: String?
    var session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8642")!,
        apiKey: String? = ProcessInfo.processInfo.environment["HERMES_API_SERVER_KEY"],
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func capabilities() async throws -> HermesAPICapabilities {
        var request = URLRequest(url: endpoint("v1", "capabilities"))
        request.httpMethod = "GET"
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIClientError.unavailable
        }
        guard http.statusCode == 200 else {
            throw HermesAPIClientError.invalidResponse(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(HermesAPICapabilities.self, from: data)
        guard decoded.features.runSubmission,
              decoded.features.runStatus,
              decoded.features.runEventsSSE
        else {
            throw HermesAPIClientError.missingRequiredCapabilities
        }
        return decoded
    }

    func createRun(input: String, sessionID: String?) async throws -> HermesRunCreateResponse {
        var request = URLRequest(url: endpoint("v1", "runs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        var body: [String: Any] = ["input": input]
        if let sessionID, !sessionID.isEmpty {
            body["session_id"] = sessionID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIClientError.unavailable
        }
        guard http.statusCode == 202 else {
            throw HermesAPIClientError.invalidResponse(http.statusCode)
        }
        return try JSONDecoder().decode(HermesRunCreateResponse.self, from: data)
    }

    func runStatus(runID: String) async throws -> HermesRunStatusResponse {
        var request = URLRequest(url: endpoint("v1", "runs", runID))
        request.httpMethod = "GET"
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIClientError.unavailable
        }
        guard http.statusCode == 200 else {
            throw HermesAPIClientError.invalidResponse(http.statusCode)
        }
        return try JSONDecoder().decode(HermesRunStatusResponse.self, from: data)
    }

    func runEvents(runID: String) -> AsyncThrowingStream<HermesRunSSEEvent, Error> {
        let endpointURL = endpoint("v1", "runs", runID, "events")
        let apiKey = apiKey
        let session = session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpointURL)
                    request.httpMethod = "GET"
                    if let apiKey, !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesAPIClientError.unavailable
                    }
                    guard http.statusCode == 200 else {
                        throw HermesAPIClientError.invalidResponse(http.statusCode)
                    }

                    var block = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            try Self.yieldEventBlock(block, continuation: continuation)
                            block = ""
                        } else {
                            block += line + "\n"
                        }
                    }
                    try Self.yieldEventBlock(block, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stopRun(runID: String) async throws {
        var request = URLRequest(url: endpoint("v1", "runs", runID, "stop"))
        request.httpMethod = "POST"
        authorize(&request)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIClientError.unavailable
        }
        guard http.statusCode == 200 else {
            throw HermesAPIClientError.invalidResponse(http.statusCode)
        }
    }

    private func authorize(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func endpoint(_ components: String...) -> URL {
        components.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private static func yieldEventBlock(
        _ block: String,
        continuation: AsyncThrowingStream<HermesRunSSEEvent, Error>.Continuation
    ) throws {
        guard !block.isEmpty else { return }
        guard let line = block
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("data: ") })
        else { return }
        let payload = String(line.dropFirst("data: ".count))
        guard let data = payload.data(using: .utf8) else { return }
        let event = try JSONDecoder().decode(HermesRunSSEEvent.self, from: data)
        continuation.yield(event)
    }
}
