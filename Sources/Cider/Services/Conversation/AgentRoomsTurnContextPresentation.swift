import Foundation

struct AgentRoomsContextCheckpoint: Equatable, Sendable {
    enum State: String, Equatable, Sendable { case available, omitted, rejected }

    let state: State
    let title: String
    let detail: String
    let provenance: String
    let truthBoundary: String
    let selectedContext: [AgentRoomsCiderObjectReceipt]
    let citations: [AgentRoomsCiderObjectReceipt]
}

struct AgentRoomsApprovalPresentation: Identifiable, Equatable, Sendable {
    enum Risk: String, Equatable, Sendable { case low, medium, high, critical }
    enum Scope: String, Equatable, Sendable { case read, write, external, delete }
    enum Status: String, Equatable, Sendable { case requested, approved, rejected, cancelled, expired }

    let id: String
    let action: String
    let target: String
    let risk: Risk
    let scope: Scope
    let status: Status
    let provenance: String
    let isReadOnly = true
}

struct AgentRoomsApprovalCheckpoint: Equatable, Sendable {
    enum State: String, Equatable, Sendable { case available, rejected }

    let state: State
    let detail: String
    let requests: [AgentRoomsApprovalPresentation]
}

@MainActor
enum AgentRoomsContextCheckpointProjector {
    static let truthBoundary = "Selected context and citations do not independently verify assistant prose"
    private static let maximumCheckpointIDLength = 120

    static func project(
        factState: HermesStructuredFactState,
        checkpoint: HermesCiderContextCheckpoint?,
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference? = {
            AgentRoomsCanonicalSavedBookmarkResolver.thumbnail(bookmarkID: $0)
        }
    ) -> AgentRoomsContextCheckpoint? {
        switch factState {
        case .notReported:
            guard checkpoint == nil else { return nil }
            return omitted(
                state: .omitted,
                detail: "No structured Cider context checkpoint was reported for this turn."
            )
        case .rejected:
            guard checkpoint == nil else { return nil }
            return omitted(
                state: .rejected,
                detail: "Cider withheld unsupported or malformed context details."
            )
        case .validated:
            guard let checkpoint,
                  let checkpointID = safeIdentifier(checkpoint.id),
                  checkpoint.source == "cider",
                  checkpoint.sourceRef == "context_checkpoint:\(checkpointID)",
                  checkpoint.selected.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
                  checkpoint.citations.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
                  (checkpoint.selected + checkpoint.citations).allSatisfy({
                      AgentRoomsTurnFactPrivacyPolicy.isSafeDisplayText($0.title)
                  })
            else { return nil }

            if checkpoint.selected.isEmpty && checkpoint.citations.isEmpty {
                guard let reason = checkpoint.omissionReason else { return nil }
                let detail: String
                switch reason {
                case "no_context_selected":
                    detail = "Cider selected no canonical context for this turn."
                case "not_available":
                    detail = "Canonical context was not available for this turn."
                case "policy_filtered":
                    detail = "Cider withheld context that did not pass the sharing boundary."
                default:
                    return nil
                }
                return omitted(state: .omitted, detail: detail)
            }

            guard checkpoint.omissionReason == nil,
                  !checkpoint.selected.isEmpty,
                  let selected = AgentRoomsCiderReceiptProjector.project(
                    checkpoint.selected,
                    bookmarkThumbnail: bookmarkThumbnail
                  )
            else { return nil }
            let citations: [AgentRoomsCiderObjectReceipt]
            if checkpoint.citations.isEmpty {
                citations = []
            } else {
                guard let projected = AgentRoomsCiderReceiptProjector.project(
                    checkpoint.citations,
                    bookmarkThumbnail: bookmarkThumbnail
                ) else { return nil }
                citations = projected
            }
            let selectedByIdentity = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
            guard citations.allSatisfy({ selectedByIdentity[$0.id] == $0 }) else { return nil }

            return AgentRoomsContextCheckpoint(
                state: .available,
                title: "Context checkpoint",
                detail: "\(selected.count) selected · \(citations.count) cited",
                provenance: "Cider canonical selection · \(checkpointID)",
                truthBoundary: truthBoundary,
                selectedContext: selected,
                citations: citations
            )
        }
    }

    private static func omitted(
        state: AgentRoomsContextCheckpoint.State,
        detail: String
    ) -> AgentRoomsContextCheckpoint {
        AgentRoomsContextCheckpoint(
            state: state,
            title: "Context checkpoint",
            detail: detail,
            provenance: "Cider turn boundary",
            truthBoundary: truthBoundary,
            selectedContext: [],
            citations: []
        )
    }

    private static func safeIdentifier(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= maximumCheckpointIDLength,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }
        return value
    }
}

@MainActor
enum AgentRoomsApprovalProjector {
    static let maximumApprovalCount = 8
    private static let maximumIDLength = 120
    private static let maximumActionLength = 80

    static func project(
        factState: HermesStructuredFactState,
        requests: [HermesApprovalRequest],
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference? = {
            AgentRoomsCanonicalSavedBookmarkResolver.thumbnail(bookmarkID: $0)
        }
    ) -> [AgentRoomsApprovalPresentation]? {
        guard factState == .validated,
              !requests.isEmpty,
              requests.count <= maximumApprovalCount
        else { return nil }

        var byID: [String: AgentRoomsApprovalPresentation] = [:]
        for request in requests {
            guard let row = project(request, bookmarkThumbnail: bookmarkThumbnail) else { return nil }
            if let existing = byID[row.id] {
                guard existing == row else { return nil }
            } else {
                byID[row.id] = row
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    static func checkpoint(
        factState: HermesStructuredFactState,
        requests: [HermesApprovalRequest],
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference? = {
            AgentRoomsCanonicalSavedBookmarkResolver.thumbnail(bookmarkID: $0)
        }
    ) -> AgentRoomsApprovalCheckpoint? {
        switch factState {
        case .notReported:
            return requests.isEmpty ? nil : AgentRoomsApprovalCheckpoint(
                state: .rejected,
                detail: "Cider withheld unsupported approval details.",
                requests: []
            )
        case .rejected:
            return AgentRoomsApprovalCheckpoint(
                state: .rejected,
                detail: "Cider withheld unsupported or malformed approval details.",
                requests: []
            )
        case .validated:
            guard let rows = project(
                factState: factState,
                requests: requests,
                bookmarkThumbnail: bookmarkThumbnail
            ) else {
                return AgentRoomsApprovalCheckpoint(
                    state: .rejected,
                    detail: "Cider withheld unsupported or malformed approval details.",
                    requests: []
                )
            }
            return AgentRoomsApprovalCheckpoint(
                state: .available,
                detail: rows.count == 1 ? "1 source-backed request · Read-only" : "\(rows.count) source-backed requests · Read-only",
                requests: rows
            )
        }
    }

    private static func project(
        _ request: HermesApprovalRequest,
        bookmarkThumbnail: @MainActor (UUID) -> AgentRoomsBookmarkThumbnailReference?
    ) -> AgentRoomsApprovalPresentation? {
        guard let id = safeIdentifier(request.id, limit: maximumIDLength),
              request.source == "hermes_runs_api",
              request.sourceRef == "approval:\(id)",
              let action = safeLabel(request.action, limit: maximumActionLength),
              let risk = AgentRoomsApprovalPresentation.Risk(rawValue: request.risk),
              let scope = AgentRoomsApprovalPresentation.Scope(rawValue: request.scope),
              let status = AgentRoomsApprovalPresentation.Status(rawValue: request.status)
        else { return nil }

        let target: String
        if let rawTarget = request.target {
            guard AgentRoomsTurnFactPrivacyPolicy.isSafeDisplayText(rawTarget.title),
                  let receipt = AgentRoomsCiderReceiptProjector.project(
                    [rawTarget],
                    bookmarkThumbnail: bookmarkThumbnail
                  )?.first
            else { return nil }
            target = "\(receipt.title) · \(receipt.identifier)"
        } else {
            target = "No canonical target reported"
        }
        return AgentRoomsApprovalPresentation(
            id: id,
            action: action,
            target: target,
            risk: risk,
            scope: scope,
            status: status,
            provenance: "Hermes Runs API · Source-backed request"
        )
    }

    private static func safeIdentifier(_ raw: String, limit: Int) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= limit,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }
        return value
    }

    private static func safeLabel(_ raw: String, limit: Int) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= limit,
              !value.localizedCaseInsensitiveContains("token"),
              !value.localizedCaseInsensitiveContains("secret"),
              !value.localizedCaseInsensitiveContains("password"),
              !value.localizedCaseInsensitiveContains("api_key"),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) || $0 == "-"
              })
        else { return nil }
        return value
    }
}

private enum AgentRoomsTurnFactPrivacyPolicy {
    static func isSafeDisplayText(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasPrefix("~/"),
              !value.contains("\\"),
              !lower.contains("/users/"),
              !lower.contains("file://"),
              !lower.contains(".ssh"),
              !lower.contains(".env"),
              !lower.contains("api_key"),
              !lower.contains("password"),
              !lower.contains("bearer "),
              !lower.contains("token="),
              !lower.contains("secret=")
        else { return false }
        return true
    }
}
