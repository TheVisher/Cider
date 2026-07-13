import Foundation

struct AgentRoomsAssetReceipt: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case attachment, generatedArtifact }

    let id: String
    let kind: Kind
    let title: String
    let contentType: String
    let sizeLabel: String
    let provenance: String
    let truthBoundary: String
    let availability: String
    let openRoute: AgentRoomsCiderOpenRoute?
}

struct AgentRoomsAssetCollection: Equatable, Sendable {
    enum State: String, Equatable, Sendable { case available, rejected }

    let state: State
    let rows: [AgentRoomsAssetReceipt]
    let detail: String
}

enum AgentRoomsAssetDisclosurePresentation {
    static func detail(for collection: AgentRoomsAssetCollection) -> String {
        collection.rows.contains(where: { $0.openRoute != nil })
            ? "\(collection.detail) · Expand for Open actions"
            : collection.detail
    }
}

@MainActor
enum AgentRoomsCanonicalAssetResolver {
    static func openRoute(for target: HermesCiderAssetReference) -> AgentRoomsCiderOpenRoute? {
        guard let id = UUID(uuidString: target.id) else { return nil }
        switch target.kind {
        case "vault_file":
            guard VaultFileService.shared.file(for: id) != nil else { return nil }
            return .vaultFile(fileID: id)
        case "project_artifact":
            guard let note = NotesStorage.shared.notes.first(where: { $0.id == id }),
                  note.projectID == target.projectID,
                  note.artifactType == target.artifactType
            else { return nil }
            return .note(noteID: id)
        default:
            return nil
        }
    }
}

@MainActor
enum AgentRoomsAssetProjector {
    static let maximumFactCount = HermesCiderAssetFactContract.maximumCount
    static let maximumDisplayNameLength = 160
    static let maximumTitleLength = 160
    static let maximumContentTypeLength = 127
    static let maximumIdentifierLength = 120
    static let maximumByteSize: Int64 = 1_125_899_906_842_624 // 1 PiB

    static func attachments(
        factState: HermesStructuredFactState,
        facts: [HermesCiderAttachment],
        canonicalOpenRoute: @MainActor (HermesCiderAssetReference) -> AgentRoomsCiderOpenRoute? = {
            AgentRoomsCanonicalAssetResolver.openRoute(for: $0)
        }
    ) -> AgentRoomsAssetCollection? {
        project(
            factState: factState,
            facts: facts.map {
                Fact(
                    id: $0.id,
                    target: $0.target,
                    displayName: $0.displayName,
                    contentType: $0.contentType,
                    byteSize: $0.byteSize,
                    provenance: $0.provenance,
                    source: $0.source,
                    sourceRef: $0.sourceRef
                )
            },
            kind: .attachment,
            requiredSourcePrefix: "attachment",
            allowedProvenance: ["user_attachment", "source_attachment"],
            canonicalOpenRoute: canonicalOpenRoute
        )
    }

    static func generatedArtifacts(
        factState: HermesStructuredFactState,
        facts: [HermesCiderGeneratedArtifact],
        canonicalOpenRoute: @MainActor (HermesCiderAssetReference) -> AgentRoomsCiderOpenRoute? = {
            AgentRoomsCanonicalAssetResolver.openRoute(for: $0)
        }
    ) -> AgentRoomsAssetCollection? {
        project(
            factState: factState,
            facts: facts.map {
                Fact(
                    id: $0.id,
                    target: $0.target,
                    displayName: $0.displayName,
                    contentType: $0.contentType,
                    byteSize: $0.byteSize,
                    provenance: $0.provenance,
                    source: $0.source,
                    sourceRef: $0.sourceRef
                )
            },
            kind: .generatedArtifact,
            requiredSourcePrefix: "generated_artifact",
            allowedProvenance: ["cider_generated"],
            canonicalOpenRoute: canonicalOpenRoute
        )
    }

    static func validatesAttachments(_ facts: [HermesCiderAttachment]) -> Bool {
        attachments(factState: .validated, facts: facts, canonicalOpenRoute: { _ in nil })?.state == .available
    }

    static func validatesGeneratedArtifacts(_ facts: [HermesCiderGeneratedArtifact]) -> Bool {
        generatedArtifacts(factState: .validated, facts: facts, canonicalOpenRoute: { _ in nil })?.state == .available
    }

    private struct Fact: Equatable {
        let id: String
        let target: HermesCiderAssetReference
        let displayName: String
        let contentType: String
        let byteSize: Int64?
        let provenance: String
        let source: String
        let sourceRef: String
    }

    private static func project(
        factState: HermesStructuredFactState,
        facts: [Fact],
        kind: AgentRoomsAssetReceipt.Kind,
        requiredSourcePrefix: String,
        allowedProvenance: Set<String>,
        canonicalOpenRoute: @MainActor (HermesCiderAssetReference) -> AgentRoomsCiderOpenRoute?
    ) -> AgentRoomsAssetCollection? {
        switch factState {
        case .notReported:
            return facts.isEmpty ? nil : rejected(kind: kind)
        case .rejected:
            return rejected(kind: kind)
        case .validated:
            guard !facts.isEmpty, facts.count <= maximumFactCount else { return rejected(kind: kind) }
        }

        var byID: [String: Fact] = [:]
        var byTarget: [String: Fact] = [:]
        for fact in facts {
            guard validate(
                fact,
                kind: kind,
                requiredSourcePrefix: requiredSourcePrefix,
                allowedProvenance: allowedProvenance
            ) else { return rejected(kind: kind) }
            if let existing = byID[fact.id], existing != fact { return rejected(kind: kind) }
            if let existing = byTarget[fact.target.sourceRef], existing != fact { return rejected(kind: kind) }
            byID[fact.id] = fact
            byTarget[fact.target.sourceRef] = fact
        }

        let rows = byID.values.sorted { $0.id < $1.id }.map { fact in
            let route = canonicalOpenRoute(fact.target)
            return AgentRoomsAssetReceipt(
                id: "\(requiredSourcePrefix):\(fact.id)",
                kind: kind,
                title: fact.displayName,
                contentType: fact.contentType,
                sizeLabel: byteSizeLabel(fact.byteSize),
                provenance: provenanceLabel(fact.provenance),
                truthBoundary: kind == .attachment
                    ? "Source-backed attachment fact, not uploaded here"
                    : "Source-backed generated artifact fact, not executed or shared here",
                availability: route == nil ? "Open unavailable" : "Cider-owned · Ready to open",
                openRoute: route
            )
        }
        return AgentRoomsAssetCollection(
            state: .available,
            rows: rows,
            detail: rows.count == 1 ? "1 source-backed item" : "\(rows.count) source-backed items"
        )
    }

    private static func validate(
        _ fact: Fact,
        kind: AgentRoomsAssetReceipt.Kind,
        requiredSourcePrefix: String,
        allowedProvenance: Set<String>
    ) -> Bool {
        guard let id = UUID(uuidString: fact.id),
              fact.id == id.uuidString,
              fact.source == "cider",
              fact.sourceRef == "\(requiredSourcePrefix):\(fact.id)",
              allowedProvenance.contains(fact.provenance),
              safeDisplayText(fact.displayName, limit: maximumDisplayNameLength),
              safeContentType(fact.contentType),
              fact.byteSize.map({ $0 >= 0 && $0 <= maximumByteSize }) ?? true,
              validateTarget(fact.target, kind: kind)
        else { return false }
        return true
    }

    private static func validateTarget(
        _ target: HermesCiderAssetReference,
        kind: AgentRoomsAssetReceipt.Kind
    ) -> Bool {
        guard target.source == "cider",
              let id = UUID(uuidString: target.id),
              target.id == id.uuidString,
              safeDisplayText(target.title, limit: maximumTitleLength)
        else { return false }

        switch (kind, target.kind) {
        case (.attachment, "vault_file"), (.generatedArtifact, "vault_file"):
            return target.projectID == nil
                && target.artifactType == nil
                && target.sourceRef == "vaultFile:\(target.id)"
        case (.generatedArtifact, "project_artifact"):
            return safeIdentifier(target.projectID) != nil
                && safeIdentifier(target.artifactType) != nil
                && target.sourceRef == "note:\(target.id)"
        default:
            return false
        }
    }

    private static func safeDisplayText(_ raw: String, limit: Int) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == raw
            && value.count <= limit
            && AgentRoomsTurnFactPrivacyPolicy.isSafeDisplayText(value)
            && !value.contains("/")
    }

    private static func safeIdentifier(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= maximumIdentifierLength,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else { return nil }
        return value
    }

    private static func safeContentType(_ raw: String) -> Bool {
        guard raw.count <= maximumContentTypeLength,
              raw == raw.lowercased(),
              let slash = raw.firstIndex(of: "/"),
              slash != raw.startIndex,
              raw.index(after: slash) != raw.endIndex,
              raw[raw.index(after: slash)...].contains("/") == false
        else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-/")
        return raw.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func byteSizeLabel(_ size: Int64?) -> String {
        guard let size else { return "Size unavailable" }
        if size < 1_024 { return "\(size) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(size)
        var unit = -1
        repeat {
            value /= 1_024
            unit += 1
        } while value >= 1_024 && unit < units.count - 1
        let rendered = value.rounded() == value
            ? String(Int64(value))
            : String(format: "%.1f", value)
        return "\(rendered) \(units[unit])"
    }

    private static func provenanceLabel(_ raw: String) -> String {
        switch raw {
        case "user_attachment": "User attachment · Cider-owned"
        case "source_attachment": "Source attachment · Cider-owned"
        case "cider_generated": "Generated by Cider · Cider-owned"
        default: "Cider-owned"
        }
    }

    private static func rejected(kind: AgentRoomsAssetReceipt.Kind) -> AgentRoomsAssetCollection {
        AgentRoomsAssetCollection(
            state: .rejected,
            rows: [],
            detail: kind == .attachment
                ? "Cider withheld unsupported or malformed attachment details."
                : "Cider withheld unsupported or malformed generated artifact details."
        )
    }
}
