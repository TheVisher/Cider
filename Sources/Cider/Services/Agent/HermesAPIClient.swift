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
        let runAttachments: Bool?
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
            case runAttachments = "run_attachments"
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
    let ciderReferences: [HermesCiderReference]
    let contextCheckpointFactState: HermesStructuredFactState
    let contextCheckpoint: HermesCiderContextCheckpoint?
    let approvalFactState: HermesStructuredFactState
    let approvalRequests: [HermesApprovalRequest]
    let attachmentFactState: HermesStructuredFactState
    let attachments: [HermesCiderAttachment]
    let generatedArtifactFactState: HermesStructuredFactState
    let generatedArtifacts: [HermesCiderGeneratedArtifact]

    enum CodingKeys: String, CodingKey {
        case object
        case runID = "run_id"
        case status
        case sessionID = "session_id"
        case output
        case error
        case ciderReferences = "cider_references"
        case contextCheckpoint = "cider_context_checkpoint"
        case approvalRequests = "approval_requests"
        case attachments = "cider_attachments"
        case generatedArtifacts = "generated_artifacts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(String.self, forKey: .status)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        ciderReferences = (try? container.decodeIfPresent([HermesCiderReference].self, forKey: .ciderReferences)) ?? []
        (contextCheckpointFactState, contextCheckpoint) = Self.decodeStructuredFact(
            HermesCiderContextCheckpoint.self,
            forKey: .contextCheckpoint,
            from: container
        )
        let approvalFact: (HermesStructuredFactState, [HermesApprovalRequest]?) = Self.decodeStructuredFact(
            [HermesApprovalRequest].self,
            forKey: .approvalRequests,
            from: container
        )
        approvalFactState = approvalFact.0
        approvalRequests = approvalFact.1 ?? []
        let attachmentFact: (HermesStructuredFactState, [HermesCiderAttachment]?) = Self.decodeStructuredFact(
            [HermesCiderAttachment].self,
            forKey: .attachments,
            from: container
        )
        let normalizedAttachments = attachmentFact.1.map(HermesCiderAssetFactContract.normalizedAttachments)
        attachmentFactState = attachmentFact.0 == .rejected
            ? .rejected
            : normalizedAttachments?.state ?? .notReported
        attachments = attachmentFactState == .validated ? normalizedAttachments?.values ?? [] : []
        let artifactFact: (HermesStructuredFactState, [HermesCiderGeneratedArtifact]?) = Self.decodeStructuredFact(
            [HermesCiderGeneratedArtifact].self,
            forKey: .generatedArtifacts,
            from: container
        )
        let normalizedArtifacts = artifactFact.1.map(HermesCiderAssetFactContract.normalizedGeneratedArtifacts)
        generatedArtifactFactState = artifactFact.0 == .rejected
            ? .rejected
            : normalizedArtifacts?.state ?? .notReported
        generatedArtifacts = generatedArtifactFactState == .validated ? normalizedArtifacts?.values ?? [] : []
    }

    private static func decodeStructuredFact<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> (HermesStructuredFactState, T?) {
        guard container.contains(key) else { return (.notReported, nil) }
        guard let value = try? container.decode(T.self, forKey: key) else { return (.rejected, nil) }
        return (.validated, value)
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
    let approval: HermesApprovalRequest?
    let approvalFactState: HermesStructuredFactState
    let contextCheckpoint: HermesCiderContextCheckpoint?
    let contextCheckpointFactState: HermesStructuredFactState
    let attachment: HermesCiderAttachment?
    let attachmentFactState: HermesStructuredFactState
    let generatedArtifact: HermesCiderGeneratedArtifact?
    let generatedArtifactFactState: HermesStructuredFactState

    enum CodingKeys: String, CodingKey {
        case event
        case runID = "run_id"
        case delta
        case output
        case error
        case tool
        case preview
        case status
        case approval
        case contextCheckpoint = "cider_context_checkpoint"
        case attachment = "cider_attachment"
        case generatedArtifact = "generated_artifact"
    }

    init(
        event: String,
        runID: String?,
        delta: String?,
        output: String?,
        error: String?,
        tool: String?,
        preview: String?,
        status: String?,
        approval: HermesApprovalRequest? = nil,
        approvalFactState: HermesStructuredFactState = .notReported,
        contextCheckpoint: HermesCiderContextCheckpoint? = nil,
        contextCheckpointFactState: HermesStructuredFactState = .notReported,
        attachment: HermesCiderAttachment? = nil,
        attachmentFactState: HermesStructuredFactState = .notReported,
        generatedArtifact: HermesCiderGeneratedArtifact? = nil,
        generatedArtifactFactState: HermesStructuredFactState = .notReported
    ) {
        self.event = event
        self.runID = runID
        self.delta = delta
        self.output = output
        self.error = error
        self.tool = tool
        self.preview = preview
        self.status = status
        self.approval = approval
        self.approvalFactState = approvalFactState
        self.contextCheckpoint = contextCheckpoint
        self.contextCheckpointFactState = contextCheckpointFactState
        self.attachment = attachment
        self.attachmentFactState = attachmentFactState
        self.generatedArtifact = generatedArtifact
        self.generatedArtifactFactState = generatedArtifactFactState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        if container.contains(.approval) {
            approval = try? container.decode(HermesApprovalRequest.self, forKey: .approval)
            approvalFactState = approval == nil ? .rejected : .validated
        } else {
            approval = nil
            approvalFactState = event.hasPrefix("approval.") ? .rejected : .notReported
        }
        if container.contains(.contextCheckpoint) {
            contextCheckpoint = try? container.decode(HermesCiderContextCheckpoint.self, forKey: .contextCheckpoint)
            contextCheckpointFactState = contextCheckpoint == nil ? .rejected : .validated
        } else {
            contextCheckpoint = nil
            contextCheckpointFactState = event.hasPrefix("context.") ? .rejected : .notReported
        }
        if container.contains(.attachment) {
            let decoded = try? container.decode(HermesCiderAttachment.self, forKey: .attachment)
            let normalized = decoded.map { HermesCiderAssetFactContract.normalizedAttachments([$0]) }
            attachmentFactState = normalized?.state == .validated ? .validated : .rejected
            attachment = attachmentFactState == .validated ? normalized?.values.first : nil
        } else {
            attachment = nil
            attachmentFactState = event.hasPrefix("attachment.") ? .rejected : .notReported
        }
        if container.contains(.generatedArtifact) {
            let decoded = try? container.decode(HermesCiderGeneratedArtifact.self, forKey: .generatedArtifact)
            let normalized = decoded.map { HermesCiderAssetFactContract.normalizedGeneratedArtifacts([$0]) }
            generatedArtifactFactState = normalized?.state == .validated ? .validated : .rejected
            generatedArtifact = generatedArtifactFactState == .validated ? normalized?.values.first : nil
        } else {
            generatedArtifact = nil
            generatedArtifactFactState = event.hasPrefix("artifact.") ? .rejected : .notReported
        }
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

    static func resolvedAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let clientKey = environment["HERMES_API_SERVER_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let clientKey, !clientKey.isEmpty {
            return clientKey
        }
        let serverKey = environment["API_SERVER_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return serverKey?.isEmpty == false ? serverKey : nil
    }

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8642")!,
        apiKey: String? = HermesAPIClient.resolvedAPIKey(),
        session: URLSession = .shared,
        isolationConfiguration: IsolationConfiguration? = nil
    ) {
        IsolationRuntime.recordPathAccess("HermesAPIClient.init")
        let isolation = isolationConfiguration ?? IsolationRuntime.configuration
        if isolation.isDogfood {
            self.baseURL = isolation.hermesEndpoint!
            self.apiKey = isolation.hermesAPIKey!
            self.session = Self.isolatedSession()
        } else {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.session = session
        }
    }

    private static func isolatedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: IsolationRedirectRejectingURLSessionDelegate.shared,
            delegateQueue: nil
        )
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

    func createRun(
        input: String,
        sessionID: String?,
        attachments: [ConversationAttachmentTransportPayload] = []
    ) async throws -> HermesRunCreateResponse {
        var request = URLRequest(url: endpoint("v1", "runs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        var body: [String: Any] = ["input": input]
        if let sessionID, !sessionID.isEmpty {
            body["session_id"] = sessionID
        }
        if !attachments.isEmpty {
            body["attachments"] = attachments.map { attachment in
                [
                    "id": attachment.id.uuidString,
                    "display_name": attachment.displayName,
                    "content_type": attachment.contentType,
                    "byte_size": attachment.byteSize,
                    "sha256": attachment.sha256,
                    "data_base64": attachment.data.base64EncodedString(),
                ] as [String: Any]
            }
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

private final class IsolationRedirectRejectingURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = IsolationRedirectRejectingURLSessionDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
