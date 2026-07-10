import AppKit
import Foundation

struct CaptureSourceContext: Equatable {
    var surface: String?
    var channel: String?
    var channelID: String?
    var threadID: String?
    var messageID: String?
    var senderID: String?
    var senderName: String?
    var originalText: String?
    var attachments: [Attachment] = []
    var metadata: [String: String] = [:]

    struct Attachment: Equatable {
        var id: String?
        var filename: String?
        var mimeType: String?
        var localPath: String?
        var remoteURL: String?
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let surface { dict["surface"] = surface }
        if let channel { dict["channel"] = channel }
        if let channelID { dict["channelID"] = channelID }
        if let threadID { dict["threadID"] = threadID }
        if let messageID { dict["messageID"] = messageID }
        if let senderID { dict["senderID"] = senderID }
        if let senderName { dict["senderName"] = senderName }
        if let originalText { dict["originalText"] = originalText }
        if !metadata.isEmpty { dict["metadata"] = metadata }
        if !attachments.isEmpty {
            dict["attachments"] = attachments.map { attachment in
                var item: [String: Any] = [:]
                if let id = attachment.id { item["id"] = id }
                if let filename = attachment.filename { item["filename"] = filename }
                if let mimeType = attachment.mimeType { item["mimeType"] = mimeType }
                if let localPath = attachment.localPath { item["localPath"] = localPath }
                if let remoteURL = attachment.remoteURL { item["remoteURL"] = remoteURL }
                return item
            }
        }
        return dict
    }
}

struct CiderCaptureResult {
    struct Source {
        var kind: String
        var url: String?
        var file: String?
        var text: String?
        var itemID: UUID
        var itemType: String
    }

    struct Item {
        var id: UUID
        var type: String
        var title: String
        var relativePath: String?
        var folderID: UUID?
        var folderName: String
    }

    struct Enrichment {
        var status: String
        var isEnriching: Bool
        var titleState: String
        var lastEnrichedAt: Date?
    }

    struct Duplicate {
        var status: String
        var existingItemID: UUID?
        var reason: String? = nil
        var evidence: String? = nil
    }

    struct Target {
        var kind: String
        var name: String
        var relativePath: String
        var folderID: UUID?
    }

    struct Routing {
        var decisionID: UUID?
        var candidateTarget: Target?
        var reviewNeeded: Bool
        var confidence: Double
        var reason: String
        var reviewState: String
        var status: String = "not_applicable"
        var statusReason: String? = nil

        var needsAgentRouteReview: Bool {
            reviewNeeded && status != "recorded"
        }

        var defaultNextSafeAction: String {
            needsAgentRouteReview ? "review_route" : "inspect_item"
        }
    }

    struct StagedIntent {
        enum Kind {
            case space(spaceName: String, area: String?)
            case project(projectName: String)
            case entity(entityName: String, entityType: String)
        }

        var kind: Kind
        var confidence: Double
        var reason: String
        var source: String

        var isSpaceIntent: Bool {
            if case .space = kind { return true }
            return false
        }

        var isProjectIntent: Bool {
            if case .project = kind { return true }
            return false
        }

        func toDictionary(storageDestination: String?) -> [String: Any] {
            var dict: [String: Any] = [
                "status": "staged",
                "confidence": confidence,
                "reason": reason,
                "source": source,
                "wouldRouteWithoutReview": false,
            ]
            if let storageDestination {
                dict["storageDestination"] = storageDestination
            }
            switch kind {
            case let .space(spaceName, area):
                dict["kind"] = "space"
                dict["spaceName"] = spaceName
                dict["rootRelativePath"] = "Spaces/\(spaceName)"
                if let area { dict["area"] = area }
            case let .project(projectName):
                dict["kind"] = "project"
                dict["projectName"] = projectName
            case let .entity(entityName, entityType):
                dict["kind"] = "entity"
                dict["entityName"] = entityName
                dict["entityType"] = entityType
            }
            return dict
        }
    }

    struct RouteIntent: Codable, Equatable {
        var route: String
        var source: String
        var confidence: Double
        var reason: String
        var provenance: [String]

        func toDictionary() -> [String: Any] {
            [
                "status": "candidate",
                "route": route,
                "source": source,
                "confidence": confidence,
                "reason": reason,
                "provenance": provenance,
                "wouldRouteWithoutReview": false,
                "truthBoundary": "reviewable_candidate_not_truth",
            ]
        }
    }

    struct PartialSuccess {
        var status: String
        var reason: String
        var requestedFolderID: UUID?
        var actualFolderID: UUID?
    }

    struct SideEffectStatus {
        struct IndexedChunk {
            var id: String
            var ownerType: String
            var ownerID: String
            var source: String
            var title: String
            var chunkIndex: Int

            func toDictionary() -> [String: Any] {
                [
                    "id": id,
                    "ownerType": ownerType,
                    "ownerID": ownerID,
                    "source": source,
                    "title": title,
                    "chunkIndex": chunkIndex,
                ]
            }
        }

        var status: String
        var reason: String?
        var ownerType: String?
        var ownerID: String?
        var captureEventID: UUID?
        var chunks: [IndexedChunk] = []

        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = ["status": status]
            if let reason { dict["reason"] = reason }
            if let ownerType { dict["ownerType"] = ownerType }
            if let ownerID { dict["ownerID"] = ownerID }
            if let captureEventID { dict["captureEventID"] = captureEventID.uuidString }
            if !chunks.isEmpty { dict["chunks"] = chunks.map { $0.toDictionary() } }
            return dict
        }
    }

    var command: String
    var source: Source
    var item: Item
    var enrichment: Enrichment
    var duplicate: Duplicate
    var routing: Routing
    var nextSafeAction: String
    var partialSuccess: PartialSuccess? = nil
    var captureEventID: UUID? = nil
    var sourceContext: CaptureSourceContext? = nil
    var provenance: SideEffectStatus = .init(
        status: "not_applicable",
        reason: "Capture provenance has not run.",
        ownerType: nil,
        ownerID: nil,
        captureEventID: nil
    )
    var indexing: SideEffectStatus = .init(
        status: "not_applicable",
        reason: "Capture indexing has not run.",
        ownerType: nil,
        ownerID: nil,
        captureEventID: nil
    )
    var captureQuality: [String: Any]? = nil
    var stagedIntents: [StagedIntent] = []
    var routeIntents: [RouteIntent] = []

    var captureEventOwner: SecondBrainOwnerRef? {
        captureEventID.map { SecondBrainOwnerRef(ownerType: "capture_event", ownerID: $0.uuidString) }
    }

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var sourceDict: [String: Any] = [
            "kind": source.kind,
            "itemID": source.itemID.uuidString,
            "itemType": source.itemType,
        ]
        if let url = source.url { sourceDict["url"] = url }
        if let file = source.file { sourceDict["file"] = file }
        if let text = source.text { sourceDict["text"] = text }

        var itemDict: [String: Any] = [
            "id": item.id.uuidString,
            "type": item.type,
            "title": item.title,
            "folderName": item.folderName,
        ]
        if let relativePath = item.relativePath { itemDict["relativePath"] = relativePath }
        if let folderID = item.folderID { itemDict["folderID"] = folderID.uuidString }

        var enrichmentDict: [String: Any] = [
            "status": enrichment.status,
            "isEnriching": enrichment.isEnriching,
            "titleState": enrichment.titleState,
        ]
        if let lastEnrichedAt = enrichment.lastEnrichedAt {
            enrichmentDict["lastEnrichedAt"] = formatter.string(from: lastEnrichedAt)
        }

        var duplicateDict: [String: Any] = [
            "status": duplicate.status,
        ]
        if let existingItemID = duplicate.existingItemID {
            duplicateDict["existingItemID"] = existingItemID.uuidString
        }
        if let reason = duplicate.reason { duplicateDict["reason"] = reason }
        if let evidence = duplicate.evidence { duplicateDict["evidence"] = evidence }

        var routingDict: [String: Any] = [
            "reviewNeeded": routing.reviewNeeded,
            "confidence": routing.confidence,
            "reason": routing.reason,
            "reviewState": routing.reviewState,
            "status": routing.status,
        ]
        if let statusReason = routing.statusReason { routingDict["statusReason"] = statusReason }
        if let decisionID = routing.decisionID { routingDict["decisionID"] = decisionID.uuidString }
        if let target = routing.candidateTarget {
            var targetDict: [String: Any] = [
                "kind": target.kind,
                "name": target.name,
                "relativePath": target.relativePath,
            ]
            if let folderID = target.folderID { targetDict["folderID"] = folderID.uuidString }
            routingDict["candidateTarget"] = targetDict
        }

        var dict: [String: Any] = [
            "command": command,
            "readOnly": false,
            "changed": true,
            "source": sourceDict,
            "item": itemDict,
            "enrichment": enrichmentDict,
            "duplicate": duplicateDict,
            "routing": routingDict,
            "provenance": provenance.toDictionary(),
            "indexing": indexing.toDictionary(),
            "nextSafeAction": nextSafeAction,
            "safeNextCommands": safeNextCommands(),
        ]
        let routingReadiness = routingReadinessDictionary()
        dict["routingReadiness"] = routingReadiness
        if var captureQuality {
            captureQuality["routingReadiness"] = routingReadiness
            dict["captureQuality"] = captureQuality
        }
        addStagedIntentDictionaries(to: &dict)
        addRouteIntentDictionaries(to: &dict)
        CiderAgentDecisionContract.merge(agentDecisionDictionary(), into: &dict)
        if let partialSuccess = partialSuccess ?? canonicalSideEffectPartialSuccess() {
            var partialDict: [String: Any] = [
                "status": partialSuccess.status,
                "reason": partialSuccess.reason,
            ]
            if let requestedFolderID = partialSuccess.requestedFolderID {
                partialDict["requestedFolderID"] = requestedFolderID.uuidString
            }
            if let actualFolderID = partialSuccess.actualFolderID {
                partialDict["actualFolderID"] = actualFolderID.uuidString
            }
            dict["partialSuccess"] = partialDict
        }
        if let captureEventID {
            dict["captureEventID"] = captureEventID.uuidString
            dict["captureEventOwner"] = [
                "ownerType": "capture_event",
                "ownerID": captureEventID.uuidString,
                "ref": "capture_event:\(captureEventID.uuidString)",
            ]
        }
        if let sourceContext {
            dict["sourceContext"] = sourceContext.toDictionary()
        }
        return dict
    }

    private func addRouteIntentDictionaries(to dict: inout [String: Any]) {
        guard !routeIntents.isEmpty else { return }
        let intents = routeIntents.map { $0.toDictionary() }
        dict["routeIntents"] = intents
        dict["routeIntent"] = intents[0]
    }

    private func addStagedIntentDictionaries(to dict: inout [String: Any]) {
        guard !stagedIntents.isEmpty else { return }
        let storageDestination = item.relativePath?.hasPrefix("Inbox/") == true
            ? item.relativePath?.components(separatedBy: "/").prefix(2).joined(separator: "/")
            : item.relativePath
        let intentDictionaries = stagedIntents.map {
            $0.toDictionary(storageDestination: storageDestination)
        }
        dict["intentStaging"] = [
            "status": "staged",
            "reviewNeeded": true,
            "safeNextAction": "review_intent",
            "intents": intentDictionaries,
        ]
        if let spaceIntent = intentDictionaries.first(where: { $0["kind"] as? String == "space" }) {
            dict["spaceIntent"] = spaceIntent
        }
        if let projectIntent = intentDictionaries.first(where: { $0["kind"] as? String == "project" }) {
            dict["projectIntent"] = projectIntent
        }
        if let entityIntent = intentDictionaries.first(where: { $0["kind"] as? String == "entity" }) {
            dict["entityIntent"] = entityIntent
        }
    }

    private func routingReadinessDictionary() -> [String: Any] {
        let routeReviewNeeded = routing.reviewNeeded || routing.reviewState == "needs_review"
        var dict: [String: Any] = [
            "status": routeReviewNeeded ? "needs_review" : "ready",
            "routeReviewNeeded": routeReviewNeeded,
            "agentMayRoute": false,
            "safeNextAction": routeReviewNeeded ? "review_route" : "inspect_item",
            "truthBoundary": "read_only_routing_readiness_no_route_mutation_or_auto_acceptance",
            "safeVerificationCommands": [
                "cider-cli item get \(item.type) \(item.id.uuidString) --json",
                "cider-cli routing explain \(item.id.uuidString) --json",
            ],
            "safeNextCommands": routeReviewNeeded
                ? [
                    "cider-cli routing explain \(item.id.uuidString) --json",
                    "cider-cli review list --item-type \(item.type) --state needs_review --limit 10 --json",
                ]
                : [
                    "cider-cli item get \(item.type) \(item.id.uuidString) --json",
                ],
        ]
        if let target = routing.candidateTarget {
            var targetDict: [String: Any] = [
                "kind": target.kind,
                "name": target.name,
                "relativePath": target.relativePath,
            ]
            if let folderID = target.folderID {
                targetDict["folderID"] = folderID.uuidString
            }
            dict["candidateTarget"] = targetDict
        }
        dict["reviewState"] = routing.reviewState
        dict["confidence"] = routing.confidence
        dict["reason"] = routing.reason
        return dict
    }

    private func agentDecisionDictionary() -> [String: Any] {
        let safeCommands = safeNextCommands()
        let qualityNeedsEnrichment = captureQuality?["needsEnrichment"] as? Bool ?? false
        let qualityBlockingIssues = captureQuality?["degradedReasons"] as? [String] ?? []
        let qualityRecommendedAction = captureQuality?["safeNextAction"] as? String
        let routingNeedsReview = routing.reviewNeeded
            || routing.reviewState == "needs_review"
            || routing.needsAgentRouteReview
        let needsIntentApproval = !stagedIntents.isEmpty
        let qualityNeedsReview = !qualityBlockingIssues.isEmpty
        let needsReview = routingNeedsReview || needsIntentApproval || qualityNeedsReview
        let needsRouting = routingNeedsReview
        let enrichmentComplete = !enrichment.isEnriching
            && ["complete", "metadata_complete", "not_applicable"].contains(enrichment.status)
        let nativeNeedsEnrichment = enrichment.isEnriching
            || enrichment.status == "pending"
            || enrichment.status == "failed"
            || (nextSafeAction == "enrich" && !enrichmentComplete)
        let needsEnrichment = nativeNeedsEnrichment || qualityNeedsEnrichment
        var blockingIssues: [String] = []
        if routingNeedsReview {
            blockingIssues.append("routing_needs_review")
        }
        if needsIntentApproval {
            blockingIssues.append("intent_approval_needed")
        }
        if enrichment.status == "failed" {
            blockingIssues.append("enrichment_failed")
        } else if nativeNeedsEnrichment {
            blockingIssues.append("enrichment_pending")
        }
        if canonicalSideEffectPartialSuccess() != nil {
            blockingIssues.append("canonical_side_effects_incomplete")
        }
        blockingIssues.append(contentsOf: qualityBlockingIssues)
        let recommendedNextAction: String
        if needsIntentApproval {
            recommendedNextAction = "review_intent"
        } else if qualityNeedsReview {
            recommendedNextAction = qualityRecommendedAction ?? nextSafeAction
        } else if routingNeedsReview {
            recommendedNextAction = "review_route"
        } else {
            recommendedNextAction = qualityRecommendedAction ?? nextSafeAction
        }
        var dict = CiderAgentDecisionContract.dictionary(
            saved: true,
            needsReview: needsReview,
            needsEnrichment: needsEnrichment,
            needsRouting: needsRouting,
            confidence: routing.confidence,
            blockingIssues: blockingIssues,
            recommendedNextAction: recommendedNextAction,
            safeNextCommands: safeCommands
        )
        dict["needsIntentApproval"] = needsIntentApproval
        if item.folderID == nil, item.relativePath?.hasPrefix("Inbox/") == true {
            dict["storedInInbox"] = true
            dict["destinationUnassigned"] = true
            dict["optionalClassification"] = true
        }
        return dict
    }

    private func safeNextCommands() -> [String] {
        var commands = ["cider-cli item get \(item.type) \(item.id.uuidString) --json"]
        if let existingItemID = duplicate.existingItemID {
            commands.append("cider-cli item get \(item.type) \(existingItemID.uuidString) --json")
        }
        if stagedIntents.contains(where: { $0.isSpaceIntent }) {
            commands.append("cider-cli item apply-intent \(item.type) \(item.id.uuidString) --intent space --json")
        }
        if stagedIntents.contains(where: { $0.isProjectIntent }) {
            commands.append("cider-cli item apply-intent \(item.type) \(item.id.uuidString) --intent project --json")
        }
        if routing.reviewNeeded || routing.needsAgentRouteReview {
            commands.append("cider-cli routing explain \(item.id.uuidString) --json")
            commands.append("cider-cli review list --item-type \(item.type) --state needs_review --limit 10 --json")
        }
        if canonicalSideEffectPartialSuccess() != nil {
            if indexing.status == "failed" || indexing.status == "unavailable" {
                commands.append("cider-cli item rebuild-chunks \(item.type) \(item.id.uuidString) --json")
                commands.append("cider-cli item rebuild-index --json")
            }
            commands.append("cider-cli storage audit --json")
        }
        return orderedUnique(commands)
    }

    private func orderedUnique(_ commands: [String]) -> [String] {
        var seen = Set<String>()
        return commands.filter { seen.insert($0).inserted }
    }

    private func canonicalSideEffectPartialSuccess() -> PartialSuccess? {
        let incomplete = [
            ("provenance", provenance.status),
            ("routing", routing.status),
            ("indexing", indexing.status),
        ].filter { _, status in
            status == "failed" || status == "unavailable"
        }
        guard !incomplete.isEmpty else { return nil }
        let names = incomplete.map(\.0).joined(separator: ", ")
        return .init(
            status: "canonical_side_effects_incomplete",
            reason: "Capture stored the source item, but canonical side effects are incomplete: \(names).",
            requestedFolderID: nil,
            actualFolderID: nil
        )
    }

    @MainActor
    func toDictionary(finalBookmark: Bookmark?) -> [String: Any] {
        guard item.type == "bookmark", let finalBookmark else { return toDictionary() }

        var finalResult = self
        finalResult.item.title = finalBookmark.title
        finalResult.item.relativePath = finalBookmark.relativePath
        finalResult.item.folderID = finalBookmark.folderID
        finalResult.item.folderName = finalBookmark.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
        finalResult.enrichment.status = Self.enrichmentStatus(for: finalBookmark)
        finalResult.enrichment.isEnriching = finalBookmark.isEnriching
        finalResult.enrichment.titleState = Self.titleState(for: finalBookmark)
        finalResult.enrichment.lastEnrichedAt = finalBookmark.lastEnrichedAt
        finalResult.stagedIntents = CiderCaptureIntentStagingService.stagedIntents(for: finalBookmark)
        finalResult.routeIntents = CiderCaptureIntentStagingService.routeIntents(for: finalBookmark)
        let captureQuality = Self.bookmarkCaptureQualityDictionary(for: finalBookmark)
        finalResult.captureQuality = captureQuality
        finalResult.indexing = Self.finalBookmarkIndexingStatus(
            from: finalResult.indexing,
            finalBookmark: finalBookmark
        )

        var dict = finalResult.toDictionary()
        if captureQuality["degraded"] as? Bool == true {
            let repairCommands = Self.bookmarkCaptureRepairCommands(for: finalBookmark)
            var commands = (dict["safeNextCommands"] as? [String]) ?? []
            for command in repairCommands where !commands.contains(command) {
                commands.append(command)
            }
            dict["safeNextCommands"] = commands
        }

        return dict
    }

    private static func finalBookmarkIndexingStatus(
        from indexing: SideEffectStatus,
        finalBookmark: Bookmark
    ) -> SideEffectStatus {
        guard indexing.status == "indexed" else { return indexing }
        var refreshed = indexing
        refreshed.chunks = indexing.chunks.map { chunk in
            var chunk = chunk
            if chunk.ownerType == "bookmark",
               chunk.ownerID == finalBookmark.id.uuidString,
               bookmarkTitleQuality(finalBookmark) == "rich" {
                chunk.title = finalBookmark.title
            }
            return chunk
        }
        return refreshed
    }

    private static func enrichmentStatus(for bookmark: Bookmark) -> String {
        if let status = bookmark.enrichmentStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            return status
        }
        if bookmark.metadataUpdatedAt != nil {
            return "metadata_complete"
        }
        return "pending"
    }

    private static func titleState(for bookmark: Bookmark) -> String {
        if bookmark.titleManuallySet { return "manual" }
        if bookmark.metadataUpdatedAt != nil { return "enriched" }
        return "host_derived"
    }

    @MainActor
    static func bookmarkCaptureQualityDictionary(for bookmark: Bookmark) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let metadataStatus = enrichmentStatus(for: bookmark)
        let metadataComplete = bookmark.metadataUpdatedAt != nil
            || metadataStatus == "complete"
            || metadataStatus == "metadata_complete"
        let titleQuality = bookmarkTitleQuality(bookmark)
        let thumbnailStatus = bookmarkThumbnailStatus(bookmark)
        let pathStatus = bookmarkPathStatus(bookmark)

        var degradedReasons: [String] = []
        if bookmark.isEnriching {
            degradedReasons.append("enrichment_running")
        }
        if !metadataComplete {
            degradedReasons.append("metadata_pending")
        }
        switch titleQuality {
        case "missing": degradedReasons.append("title_missing")
        case "generic": degradedReasons.append("title_generic")
        default: break
        }
        if thumbnailStatus == "missing" {
            degradedReasons.append("card_image_missing")
        } else if thumbnailStatus == "remote_only" {
            degradedReasons.append("card_image_not_local")
        }
        switch pathStatus {
        case "missing": degradedReasons.append("path_missing")
        case "stale_or_generic": degradedReasons.append("path_stale_or_generic")
        default: break
        }

        let cardComplete = metadataComplete
            && titleQuality == "rich"
            && thumbnailStatusIsLocalReady(thumbnailStatus)
            && pathStatus == "current"
        let onlyRemoteThumbnailDegraded = degradedReasons == ["card_image_not_local"]
        let semanticStatus: String
        if bookmark.isEnriching || !metadataComplete {
            semanticStatus = "pending"
        } else if onlyRemoteThumbnailDegraded {
            semanticStatus = "complete"
        } else if degradedReasons.isEmpty {
            semanticStatus = "complete"
        } else {
            semanticStatus = "degraded"
        }
        let thumbnailReadiness = bookmarkThumbnailReadiness(
            bookmark,
            thumbnailStatus: thumbnailStatus,
            localReady: thumbnailStatusIsLocalReady(thumbnailStatus)
        )
        let safeNextAction = onlyRemoteThumbnailDegraded
            ? "verify_or_localize_thumbnail"
            : (degradedReasons.isEmpty ? "inspect_visible_card" : "repair_or_refetch_metadata")

        var dict: [String: Any] = [
            "lifecycleStatus": bookmark.isEnriching ? "enriching" : (metadataComplete ? "metadata_committed" : "pending"),
            "semanticStatus": semanticStatus,
            "metadataStatus": metadataStatus,
            "metadataComplete": metadataComplete,
            "cardStatus": cardComplete ? "complete" : (metadataComplete ? "degraded" : "pending"),
            "cardComplete": cardComplete,
            "visibleCardCurrent": cardComplete,
            "titleQuality": titleQuality,
            "thumbnailStatus": thumbnailStatus,
            "thumbnailReadiness": thumbnailReadiness,
            "pathStatus": pathStatus,
            "degraded": !degradedReasons.isEmpty,
            "degradedReasons": degradedReasons,
            "fallbackReason": thumbnailReadiness["fallbackReason"] ?? degradedReasons.first ?? NSNull(),
            "safeNextAction": safeNextAction,
            "safeVerificationCommands": bookmarkThumbnailVerificationCommands(for: bookmark),
            "safeNextCommands": bookmarkThumbnailNextCommands(for: bookmark, thumbnailStatus: thumbnailStatus),
        ]
        if let metadataUpdatedAt = bookmark.metadataUpdatedAt {
            dict["metadataUpdatedAt"] = formatter.string(from: metadataUpdatedAt)
        }
        if let lastEnrichedAt = bookmark.lastEnrichedAt {
            dict["lastEnrichedAt"] = formatter.string(from: lastEnrichedAt)
        }
        dict["canonicalCommitAt"] = formatter.string(from: bookmark.updatedAt)
        return dict
    }

    private static func bookmarkThumbnailReadiness(
        _ bookmark: Bookmark,
        thumbnailStatus: String,
        localReady: Bool
    ) -> [String: Any] {
        var readiness: [String: Any] = [
            "status": thumbnailStatus,
            "localReady": localReady,
            "provider": bookmarkProvider(for: bookmark),
            "safeVerificationCommands": bookmarkThumbnailVerificationCommands(for: bookmark),
            "safeNextCommands": bookmarkThumbnailNextCommands(for: bookmark, thumbnailStatus: thumbnailStatus),
        ]
        if thumbnailStatus == "remote_only" {
            readiness["fallbackReason"] = "remote_provider_image_without_local_thumbnail"
            readiness["remoteImageURL"] = bookmark.thumbnailRemoteURLString ?? NSNull()
        } else if thumbnailStatus == "missing" {
            readiness["fallbackReason"] = "no_provider_or_local_thumbnail"
        }
        if let relativePath = bookmark.thumbnailRelativePath {
            readiness["thumbnailRelativePath"] = relativePath
        }
        return readiness
    }

    static func bookmarkThumbnailVerificationCommands(for bookmark: Bookmark) -> [String] {
        [
            "cider-cli item get bookmark \(bookmark.id.uuidString) --json",
            "cider-cli item context bookmark \(bookmark.id.uuidString) --json",
        ]
    }

    @MainActor
    static func bookmarkThumbnailLocalizationPlanDictionary(for bookmark: Bookmark) -> [String: Any] {
        let thumbnailStatus = bookmarkThumbnailStatus(bookmark)
        let localReady = thumbnailStatusIsLocalReady(thumbnailStatus)
        let provider = knownThumbnailProvider(for: bookmark) ?? "unknown"
        let fallbackReason: String
        if thumbnailStatus == "remote_only" {
            fallbackReason = "remote_provider_image_without_local_thumbnail"
        } else if thumbnailStatus == "missing" {
            fallbackReason = "no_provider_or_local_thumbnail"
        } else {
            fallbackReason = "local_thumbnail_ready"
        }
        let safeVerificationCommands = bookmarkThumbnailVerificationCommands(for: bookmark)
        let safeNextCommands = bookmarkThumbnailNextCommands(for: bookmark, thumbnailStatus: thumbnailStatus)
        let applyCommands = safeNextCommands.filter { $0.contains(" review enrich ") }

        var thumbnailState: [String: Any] = [
            "localReady": localReady,
            "thumbnailStatus": thumbnailStatus,
            "provider": provider,
            "providerUnknown": provider == "unknown",
            "fallbackReason": fallbackReason,
            "visibleCardCurrent": localReady,
        ]
        if let remote = bookmark.thumbnailRemoteURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remote.isEmpty {
            thumbnailState["remoteImageURL"] = remote
        }
        if let relativePath = bookmark.thumbnailRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !relativePath.isEmpty {
            thumbnailState["thumbnailRelativePath"] = relativePath
        }
        if let originalPath = bookmark.originalImageRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !originalPath.isEmpty {
            thumbnailState["originalImageRelativePath"] = originalPath
        }

        var stableSelectors: [String: Any] = [
            "itemID": bookmark.id.uuidString,
            "itemRef": "bookmark:\(bookmark.id.uuidString)",
            "url": bookmark.urlString,
        ]
        if let relativePath = bookmark.relativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !relativePath.isEmpty {
            stableSelectors["relativePath"] = relativePath
        }

        return [
            "command": "item.thumbnail-plan",
            "readOnly": true,
            "changed": false,
            "itemType": "bookmark",
            "itemID": bookmark.id.uuidString,
            "url": bookmark.urlString,
            "title": bookmark.title,
            "stableSelectors": stableSelectors,
            "thumbnailState": thumbnailState,
            "localReady": localReady,
            "thumbnailStatus": thumbnailStatus,
            "fallbackReason": fallbackReason,
            "safeNextAction": localReady ? "inspect_visible_card" : "verify_or_localize_thumbnail",
            "safeVerificationCommands": safeVerificationCommands,
            "safeNextCommands": safeNextCommands,
            "applyCommands": applyCommands,
            "applyCommandCaveat": "The enrich/apply command may perform network/provider work and mutate stored bookmark metadata or thumbnail files; run it only with explicit user approval.",
            "truthBoundary": "read_only_thumbnail_plan_from_stored_bookmark_metadata_no_network_or_mutation",
            "readinessBoundary": "localReady requires an existing non-empty local thumbnail asset; remote provider URLs are not downloaded by this command",
        ]
    }

    static func bookmarkThumbnailNextCommands(for bookmark: Bookmark, thumbnailStatus: String? = nil) -> [String] {
        let status = thumbnailStatus ?? bookmarkThumbnailStatus(bookmark)
        var commands = bookmarkThumbnailVerificationCommands(for: bookmark)
        if status == "remote_only" || status == "missing" {
            commands.append("cider-cli review enrich \(bookmark.id.uuidString) --actor agent --timeout 20 --json")
            commands.append("cider-cli storage audit --json")
        }
        return orderedUniqueStrings(commands)
    }

    private static func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for value in values where seen.insert(value).inserted {
            unique.append(value)
        }
        return unique
    }

    private static func bookmarkProvider(for bookmark: Bookmark) -> String {
        guard let host = URLComponents(string: bookmark.urlString)?.host?
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .lowercased() else {
            return "unknown"
        }
        if host.contains("tiktok.com") { return "tiktok" }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "youtube" }
        if host.contains("instagram.com") { return "instagram" }
        if host.contains("x.com") || host.contains("twitter.com") { return "x" }
        return host
    }

    private static func knownThumbnailProvider(for bookmark: Bookmark) -> String? {
        guard let provider = bookmarkProvider(for: bookmark).split(separator: ".").first.map(String.init),
              ["tiktok", "youtube", "instagram", "x"].contains(provider) else {
            return nil
        }
        return provider
    }

    private static func bookmarkTitleQuality(_ bookmark: Bookmark) -> String {
        let title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "missing" }
        guard title.lowercased() != "untitled" else { return "missing" }

        guard let host = URLComponents(string: bookmark.urlString)?.host?
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .lowercased() else {
            return "rich"
        }
        let normalizedTitle = normalizedQualityToken(title)
        let hostLabels = host.split(separator: ".").map(String.init)
        let hostStem = hostLabels.dropLast().joined(separator: ".")
        let genericCandidates = [
            host,
            hostStem,
            host.replacingOccurrences(of: ".", with: " "),
            hostStem.replacingOccurrences(of: ".", with: " "),
        ]
        if genericCandidates.contains(where: { normalizedQualityToken($0) == normalizedTitle }) {
            return "generic"
        }
        return "rich"
    }

    private static func bookmarkThumbnailStatus(_ bookmark: Bookmark) -> String {
        if let carouselImagePaths = bookmark.carouselImagePaths,
           carouselImagePaths.contains(where: localCaptureAssetExists(relativePath:)) {
            return "local_carousel"
        }
        if let thumbnailRelativePath = bookmark.thumbnailRelativePath,
           localCaptureAssetExists(relativePath: thumbnailRelativePath) {
            return "local"
        }
        if let originalImageRelativePath = bookmark.originalImageRelativePath,
           localCaptureAssetExists(relativePath: originalImageRelativePath) {
            return "local_original"
        }
        if localCanonicalThumbnailAssetExists(for: bookmark.id) {
            return "local"
        }
        if let thumbnailRemoteURLString = bookmark.thumbnailRemoteURLString,
           !thumbnailRemoteURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "remote_only"
        }
        return "missing"
    }

    private static func thumbnailStatusIsLocalReady(_ status: String) -> Bool {
        switch status {
        case "local", "local_carousel", "local_original":
            return true
        default:
            return false
        }
    }

    private static func localCanonicalThumbnailAssetExists(for bookmarkID: UUID) -> Bool {
        let thumbnailsDirectory = StoragePaths.cachedDirectoryURL(for: .bookmarks)
            .appendingPathComponent(".thumbnails", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        let prefix = bookmarkID.uuidString + "."
        return files.contains { url in
            guard url.lastPathComponent.hasPrefix(prefix),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                return false
            }
            return fileSize > 0
        }
    }

    private static func localCaptureAssetExists(relativePath: String) -> Bool {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let candidateURLs = [
            StoragePaths.cachedDirectoryURL(for: .bookmarks).appendingPathComponent(trimmed),
            StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(trimmed),
        ]
        return candidateURLs.contains { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                return false
            }
            return fileSize > 0
        }
    }

    private static func bookmarkCaptureRepairCommands(for bookmark: Bookmark) -> [String] {
        [
            "cider-cli review enrich \(bookmark.id.uuidString) --actor agent --timeout 20 --json",
            "cider-cli item rebuild-chunks bookmark \(bookmark.id.uuidString) --json",
        ]
    }

    fileprivate static func fileCaptureQualityDictionary(for file: VaultFile) -> [String: Any] {
        let readableText = readableTextFileContent(relativePath: file.relativePath)
        let fileType = file.fileType.rawValue
        let bodyExtractionStatus: String
        let bodyIndexed: Bool
        let indexedTextStatus: String
        var degradedReasons: [String] = []

        if let readableText, !readableText.isEmpty {
            bodyExtractionStatus = "not_required"
            bodyIndexed = true
            indexedTextStatus = "body_text_indexed"
        } else if fileBodyExtractionIsApplicable(file) {
            bodyExtractionStatus = "unsupported"
            bodyIndexed = false
            indexedTextStatus = "metadata_only"
            degradedReasons.append("file_body_not_extracted")
            degradedReasons.append("file_body_not_indexed")
        } else {
            bodyExtractionStatus = "not_applicable"
            bodyIndexed = false
            indexedTextStatus = "metadata_only"
        }

        let semanticStatus = degradedReasons.isEmpty ? "complete" : "degraded"
        return [
            "kind": "file",
            "lifecycleStatus": "stored",
            "semanticStatus": semanticStatus,
            "fileType": fileType,
            "bodyExtractionStatus": bodyExtractionStatus,
            "bodyIndexed": bodyIndexed,
            "indexedTextStatus": indexedTextStatus,
            "metadataIndexed": true,
            "degraded": !degradedReasons.isEmpty,
            "degradedReasons": degradedReasons,
            "needsEnrichment": !degradedReasons.isEmpty,
            "duplicateStatus": "unsupported",
            "safeNextAction": degradedReasons.isEmpty ? "inspect_item" : "report_file_indexing_gap",
        ]
    }

    private static func fileBodyExtractionIsApplicable(_ file: VaultFile) -> Bool {
        switch file.fileType {
        case .document, .pdf:
            return true
        case .image:
            return file.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        case .video, .audio, .archive, .unknown:
            return false
        }
    }

    fileprivate static func readableTextFileContent(relativePath: String) -> String? {
        guard isReadableTextFile(relativePath: relativePath) else { return nil }

        let fileURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath)
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        for encoding in [String.Encoding.utf8, .utf16, .ascii, .isoLatin1] {
            guard let text = String(data: data, encoding: encoding) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private static func isReadableTextFile(relativePath: String) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return [
            "txt",
            "text",
            "md",
            "markdown",
            "csv",
            "tsv",
            "json",
            "jsonl",
            "yaml",
            "yml",
            "xml",
            "html",
            "htm",
            "log",
        ].contains(ext)
    }

    @MainActor
    private static func bookmarkPathStatus(_ bookmark: Bookmark) -> String {
        guard let relativePath = bookmark.relativePath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !relativePath.isEmpty else {
            return "missing"
        }
        let currentBase = stripDuplicateSuffix(
            (relativePath as NSString).lastPathComponent as NSString
        ).deletingPathExtension
        let expectedBase = BookmarkFileService.shared.sanitizedFilename(
            bookmark.title.isEmpty ? "Untitled" : bookmark.title
        )
        return normalizedQualityToken(currentBase) == normalizedQualityToken(expectedBase)
            ? "current"
            : "stale_or_generic"
    }

    private static func stripDuplicateSuffix(_ filename: NSString) -> NSString {
        let stripped = (filename as String).replacingOccurrences(
            of: #" \(\d+\)(?=(\.[^.]+)?$)"#,
            with: "",
            options: .regularExpression
        )
        return stripped as NSString
    }

    private static func normalizedQualityToken(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

enum CiderCaptureError: LocalizedError {
    case missingSource
    case unsupportedSource(String)
    case storeFailed(String)
    case fileNotFound(String)
    case fileCopyFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Capture source is required."
        case .unsupportedSource(let source):
            return "Unsupported capture source: \(source)"
        case .storeFailed(let source):
            return "Could not store capture source: \(source)"
        case .fileNotFound(let path):
            return "Capture file does not exist: \(path)"
        case .fileCopyFailed(let path):
            return "Could not copy capture file into the vault: \(path)"
        }
    }
}

enum CiderCaptureIntentStagingService {
    struct Input {
        var title: String?
        var urlString: String?
        var sourceFile: String?
        var sourceText: String?
        var sourceContext: CaptureSourceContext?

        var combinedOriginalText: String {
            [
                title,
                urlString,
                sourceFile,
                sourceText,
                sourceContext?.originalText,
                sourceContext?.metadata.values.joined(separator: " "),
            ]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        var combinedText: String {
            combinedOriginalText
                .lowercased()
        }
    }

    static func stagedIntents(for bookmark: Bookmark) -> [CiderCaptureResult.StagedIntent] {
        stagedIntents(for: Input(
            title: bookmark.title,
            urlString: bookmark.urlString,
            sourceFile: nil,
            sourceText: bookmark.notes,
            sourceContext: nil
        ))
    }

    static func routeIntents(for bookmark: Bookmark) -> [CiderCaptureResult.RouteIntent] {
        routeIntents(for: Input(
            title: bookmark.title,
            urlString: bookmark.urlString,
            sourceFile: nil,
            sourceText: bookmark.notes,
            sourceContext: nil
        ))
    }

    static func stagedIntents(for input: Input) -> [CiderCaptureResult.StagedIntent] {
        let semanticIntents = stagedSemanticIntents(for: input)
        let providerIntents = stagedProviderIntents(for: input)
        return semanticIntents + providerIntents + stagedProjectIntents(in: input.combinedText)
    }

    static func routeIntents(for input: Input) -> [CiderCaptureResult.RouteIntent] {
        var intents = routeSemanticIntents(for: input)
        guard let urlString = input.urlString ?? firstURLString(in: input.combinedText),
              let components = URLComponents(string: urlString),
              let rawHost = components.host?.lowercased() else {
            return intents
        }
        let host = canonicalIntentHost(rawHost)
        let path = components.path.lowercased()
        if rawHost.matchesDomain("rottentomatoes.com") {
            let route = path.contains("/tv/") ? "media/shows" : "media/movies"
            intents.append(.init(
                route: route,
                source: "capture.intent.url_provider",
                confidence: 0.78,
                reason: "Rotten Tomatoes URL provider metadata indicates an obvious \(route == "media/shows" ? "TV/show" : "movie") media route candidate.",
                provenance: routeIntentProvenance(host: host, path: components.path)
            ))
            return intents
        }
        if rawHost.matchesDomain("imdb.com"), path.contains("/title/") {
            intents.append(.init(
                route: "media/movies",
                source: "capture.intent.url_provider",
                confidence: 0.78,
                reason: "IMDb title URL provider metadata indicates an obvious movie media route candidate.",
                provenance: routeIntentProvenance(host: host, path: components.path)
            ))
            return intents
        }
        if rawHost.matchesDomain("tiktok.com") {
            intents.append(.init(
                route: "media/social-video",
                source: "capture.intent.url_provider",
                confidence: 0.62,
                reason: "TikTok URL provider metadata indicates a social-video source; preserve it as a secondary reviewable signal.",
                provenance: routeIntentProvenance(host: host, path: components.path)
            ))
        }
        return intents
    }

    static func stagedContactIntents(for input: Input) -> [CiderCaptureResult.StagedIntent] {
        stagedIntents(for: input).filter { intent in
            if case .project = intent.kind { return true }
            return false
        }
    }

    private static func stagedProviderIntents(for input: Input) -> [CiderCaptureResult.StagedIntent] {
        guard let urlString = input.urlString ?? firstURLString(in: input.combinedText),
              let components = URLComponents(string: urlString),
              let host = components.host?.lowercased() else {
            return stagedTextIntents(in: input.combinedText)
        }

        var intents: [CiderCaptureResult.StagedIntent] = []
        let path = components.path.lowercased()
        let text = input.combinedText
        if host.matchesDomain("rottentomatoes.com") {
            let area = path.contains("/tv/") ? "Shows" : "Movies"
            intents.append(.init(
                kind: .space(spaceName: "Media", area: area),
                confidence: 0.78,
                reason: "Rotten Tomatoes URLs are media references; keep the capture in Inbox for review while preserving the likely Media intent.",
                source: "capture.intent.url_provider"
            ))
        } else if host.matchesDomain("imdb.com") {
            let area = path.contains("/video") || text.contains("trailer") ? "Trailers" : "Movies"
            intents.append(.init(
                kind: .space(spaceName: "Media", area: area),
                confidence: 0.78,
                reason: "IMDb URLs are media references; keep the capture in Inbox for review while preserving the likely Media intent.",
                source: "capture.intent.url_provider"
            ))
        } else if host.matchesDomain("steampowered.com") || host.matchesDomain("steamcommunity.com") {
            intents.append(.init(
                kind: .space(spaceName: "Media", area: "Games"),
                confidence: 0.82,
                reason: "Steam URLs are game references; keep the capture in Inbox for review while preserving the likely Games intent.",
                source: "capture.intent.url_provider"
            ))
        } else if host.matchesDomain("tiktok.com") {
            intents.append(stagedTikTokIntent())
        } else if host.matchesDomain("allrecipes.com")
                    || host.matchesDomain("seriouseats.com")
                    || host.matchesDomain("smittenkitchen.com") {
            intents.append(.init(
                kind: .space(spaceName: "Recipes", area: nil),
                confidence: 0.76,
                reason: "Recipe-site URLs are recipe references; keep the capture in Inbox for review while preserving the likely Recipes intent.",
                source: "capture.intent.url_provider"
            ))
        }

        return intents.isEmpty ? stagedTextIntents(in: text) : intents
    }

    private static func canonicalIntentHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func routeIntentProvenance(host: String, path: String) -> [String] {
        [
            "url_host:\(host)",
            "url_path:\(path.isEmpty ? "/" : path)",
        ]
    }

    private static func stagedTikTokIntent() -> CiderCaptureResult.StagedIntent {
        return .init(
            kind: .space(spaceName: "Media", area: "Social Video"),
            confidence: 0.62,
            reason: "TikTok URLs are social video references; keep the capture in Inbox for review while preserving the likely media intent.",
            source: "capture.intent.url_provider"
        )
    }

    private static func stagedSemanticIntents(for input: Input) -> [CiderCaptureResult.StagedIntent] {
        var intents: [CiderCaptureResult.StagedIntent] = []
        let text = input.combinedText
        if hasFamilyTripPlaceSignals(in: text), let entityName = tripPlaceEntityName(from: input) {
            intents.append(.init(
                kind: .entity(entityName: entityName, entityType: "place"),
                confidence: 0.79,
                reason: "The title or body describes a real-world kids/family trip idea at a named place; stage that place intent ahead of any embedded social-video source URL.",
                source: "capture.intent.trip_place_signal"
            ))
        } else if hasRealWorldPlaceSignals(in: text), let entityName = placeEntityName(from: input) {
            intents.append(.init(
                kind: .entity(entityName: entityName, entityType: "place"),
                confidence: 0.72,
                reason: "The title or extracted text identifies a named real-world place; stage that place intent ahead of any embedded social-video source URL.",
                source: "capture.intent.place_signal"
            ))
        }
        if hasRestaurantPlaceSignals(in: text) && !hasPayrollDeductionRecordSignals(in: text) {
            intents.append(.init(
                kind: .space(spaceName: "Food", area: "Restaurants"),
                confidence: 0.74,
                reason: "The capture text identifies a restaurant or place-to-try; keep the item in Inbox for review while staging the likely restaurant intent.",
                source: "capture.intent.social_restaurant_signal"
            ))
        }
        return intents
    }

    private static func routeSemanticIntents(for input: Input) -> [CiderCaptureResult.RouteIntent] {
        guard hasFamilyTripPlaceSignals(in: input.combinedText),
              let entityName = tripPlaceEntityName(from: input) else {
            guard hasRealWorldPlaceSignals(in: input.combinedText),
                  let entityName = placeEntityName(from: input) else {
                return []
            }
            return [
                .init(
                    route: "places/place",
                    source: "capture.intent.place_signal",
                    confidence: 0.72,
                    reason: "The title or extracted text identifies \(entityName) as a named real-world place; expose this as a reviewable place route intent.",
                    provenance: ["text_signal:named_place", "entity:\(entityName)"]
                )
            ]
        }
        return [
            .init(
                route: "places/family-trip",
                source: "capture.intent.trip_place_signal",
                confidence: 0.79,
                reason: "The title or body describes a kids/family trip idea at \(entityName); expose this as a reviewable place/trip route intent.",
                provenance: ["text_signal:kids_family_trip_place", "entity:\(entityName)"]
            )
        ]
    }

    private static func hasFamilyTripPlaceSignals(in text: String) -> Bool {
        let familySignals = ["kid", "kids", "family", "children"]
        let tripSignals = ["trip idea", "fun trip", "day trip", "place to go", "place to try", "outing"]
        let placeSignals = ["arcade", "lynnwood", "seattle", "wa ", "washington", "address"]
        return familySignals.contains { text.contains($0) }
            && tripSignals.contains { text.contains($0) }
            && placeSignals.contains { text.contains($0) }
    }

    private static func hasRealWorldPlaceSignals(in text: String) -> Bool {
        let placeKindSignals = ["arcade", "game-room", "game room", "interactive"]
        let locationSignals = ["lynnwood", "seattle", "bellevue", "wa ", "washington", "address"]
        return placeKindSignals.contains { text.contains($0) }
            && locationSignals.contains { text.contains($0) }
    }

    private static func tripPlaceEntityName(from input: Input) -> String? {
        for raw in [input.title, input.sourceText, input.sourceContext?.originalText].compactMap({ $0 }) {
            if let name = tripPlaceEntityName(in: raw) {
                return name
            }
        }
        return nil
    }

    private static func placeEntityName(from input: Input) -> String? {
        for raw in [input.title, input.sourceText, input.sourceContext?.originalText].compactMap({ $0 }) {
            if let name = cheArcadeEntityName(in: raw) {
                return name
            }
        }
        return nil
    }

    private static func cheArcadeEntityName(in raw: String) -> String? {
        let pattern = #"(?i)\bc\.?\s*h\.?\s*e\.?\s+arcade\s+in\s+([A-Za-z ]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges > 1,
              let locationRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        let location = String(raw[locationRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.:;,-#"))
        guard !location.isEmpty else { return nil }
        return "C.H.E Arcade in \(location)"
    }

    private static func tripPlaceEntityName(in raw: String) -> String? {
        let patterns = [
            #"(?i)kids trip idea:\s*([^\n]+)"#,
            #"(?i)kids trip idea[-–]\s*([^\n]+)"#,
            #"(?i)fun trip for the kids[^.\n]*?\bat\s+([^.\n]+)"#,
            #"(?i)trip idea[^.\n]*?\bat\s+([^.\n]+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: raw) else {
                continue
            }
            let candidate = String(raw[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.:;,-"))
            if !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }

    private static func hasRestaurantPlaceSignals(in text: String) -> Bool {
        let restaurantSignals = [
            "restaurant", "restaurants", "place to try", "places to try", "food court",
            "menu", "address", "sushi", "bb.q", "wings", "tokuni", "tengu"
        ]
        let localSignals = [
            "seattle", "lynnwood", "northgate", "wa ", "washington", "h-mart", "h mart"
        ]
        let foodSignals = [
            "#food", "foodie", "asian food", "chicken", "deok-bokki", "corn cheese"
        ]
        let hasRestaurant = restaurantSignals.contains { text.contains($0) }
        let hasLocalPlace = localSignals.contains { text.contains($0) }
        let hasFoodContext = foodSignals.contains { text.contains($0) }
        return hasLocalPlace && (hasRestaurant || hasFoodContext)
    }

    private static func hasPayrollDeductionRecordSignals(in text: String) -> Bool {
        let payrollAnchors = ["paycheck", "pay period", "payroll"]
        let payrollFields = [
            "gross pay", "net pay", "taxes", "withholding", "deductions",
            "pretax", "401(k)",
        ]
        let fieldCount = payrollFields.reduce(into: 0) { count, signal in
            if text.contains(signal) { count += 1 }
        }
        return payrollAnchors.contains { text.contains($0) } && fieldCount >= 3
    }

    private static func firstURLString(in text: String) -> String? {
        let pattern = #"https?://[^\s<>"')\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func stagedTextIntents(in haystack: String) -> [CiderCaptureResult.StagedIntent] {
        if haystack.contains("steam") || haystack.contains("steampowered") {
            return [
                .init(
                    kind: .space(spaceName: "Media", area: "Games"),
                    confidence: 0.66,
                    reason: "The capture text mentions Steam, so it may be a game reference; keep it in Inbox for review while preserving the likely Games intent.",
                    source: "capture.intent.text_signal"
                )
            ]
        }
        if haystack.contains("watch party")
            || haystack.contains("watch-party")
            || haystack.contains("movie night")
            || haystack.contains("tv night")
            || haystack.contains("premiere night")
            || haystack.contains("trailer night") {
            let area: String
            if haystack.contains("tv") || haystack.contains("show") || haystack.contains("season") {
                area = "Shows"
            } else if haystack.contains("trailer") {
                area = "Trailers"
            } else {
                area = "Movies"
            }
            return [
                .init(
                    kind: .space(spaceName: "Media", area: area),
                    confidence: 0.64,
                    reason: "The capture text looks like a media watch event, so keep it in Inbox for review while preserving the likely Media intent.",
                    source: "capture.intent.text_signal"
                )
            ]
        }
        if haystack.contains("recipe") || haystack.contains("ingredients") {
            return [
                .init(
                    kind: .space(spaceName: "Recipes", area: nil),
                    confidence: 0.62,
                    reason: "The capture text looks recipe-related; keep it in Inbox for review while preserving the likely Recipes intent.",
                    source: "capture.intent.text_signal"
                )
            ]
        }
        return []
    }

    private static func stagedProjectIntents(in haystack: String) -> [CiderCaptureResult.StagedIntent] {
        guard haystack.contains("cider ios")
            || haystack.contains("codex ios")
            || haystack.contains("openaidevs") else {
            return []
        }
        return [
            .init(
                kind: .project(projectName: "Cider iOS"),
                confidence: 0.68,
                reason: "The capture mentions Codex/OpenAI Developers in an iOS app context, so it likely belongs with Cider iOS project references.",
                source: "capture.intent.project_reference"
            )
        ]
    }
}

@MainActor
final class CiderCaptureService {
    private let bookmarkService: VaultBookmarkService
    private let notesStorage: NotesStorage
    private let todoStorage: TodoCardStorage
    private let dateCardStorage: DateCardStorage
    private let contactStorage: ContactStorage
    private let vaultFileStorage: VaultFileStorage
    private let routingDecisionService: CiderRoutingDecisionService?
    private let database: CiderDatabase?
    private let noteAssignmentHandler: (UUID, UUID?) -> Bool
    private let thumbnailAssignmentHandler: (UUID, Data, String?) -> Bool
    private let todoUpdateHandler: (TodoCard) -> Bool
    private let dateCardUpdateHandler: (DateCard) -> Bool
    private let contactUpdateHandler: (ContactCard) -> Bool

    init(
        bookmarkService: VaultBookmarkService = .shared,
        notesStorage: NotesStorage = .shared,
        todoStorage: TodoCardStorage = .shared,
        dateCardStorage: DateCardStorage = .shared,
        contactStorage: ContactStorage = .shared,
        vaultFileStorage: VaultFileStorage = .shared,
        database: CiderDatabase? = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil,
        routingDecisionService: CiderRoutingDecisionService? = CiderRoutingDecisionService(),
        noteAssignmentHandler: ((UUID, UUID?) -> Bool)? = nil,
        thumbnailAssignmentHandler: ((UUID, Data, String?) -> Bool)? = nil,
        todoUpdateHandler: ((TodoCard) -> Bool)? = nil,
        dateCardUpdateHandler: ((DateCard) -> Bool)? = nil,
        contactUpdateHandler: ((ContactCard) -> Bool)? = nil
    ) {
        self.bookmarkService = bookmarkService
        self.notesStorage = notesStorage
        self.todoStorage = todoStorage
        self.dateCardStorage = dateCardStorage
        self.contactStorage = contactStorage
        self.vaultFileStorage = vaultFileStorage
        self.database = database
        self.routingDecisionService = routingDecisionService
        self.noteAssignmentHandler = noteAssignmentHandler ?? { [notesStorage] noteID, folderID in
            notesStorage.assignNote(noteID, toFolder: folderID)
        }
        self.thumbnailAssignmentHandler = thumbnailAssignmentHandler ?? { [bookmarkService] bookmarkID, imageData, preferredFileExtension in
            bookmarkService.assignThumbnail(
                for: bookmarkID,
                imageData: imageData,
                preferredFileExtension: preferredFileExtension
            )
        }
        self.todoUpdateHandler = todoUpdateHandler ?? { [todoStorage] todo in
            todoStorage.updateTodoCard(todo)
        }
        self.dateCardUpdateHandler = dateCardUpdateHandler ?? { [dateCardStorage] dateCard in
            dateCardStorage.updateDateCard(dateCard)
        }
        self.contactUpdateHandler = contactUpdateHandler ?? { [contactStorage] contact in
            contactStorage.updateContact(contact)
        }
    }

    func add(
        _ rawSource: String,
        title: String? = nil,
        folderID: UUID? = nil,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw CiderCaptureError.missingSource }

        switch inferredKind(for: source) {
        case .url:
            return try addBookmarkCapture(urlString: source, title: title, folderID: folderID, sourceContext: sourceContext)
        case .file:
            return try addFile(source, title: title, folderID: folderID, sourceContext: sourceContext)
        case .todo:
            return try addTodo(source, title: title, folderID: folderID, sourceContext: sourceContext)
        case .note:
            return try addNote(source, title: title, folderID: folderID, sourceContext: sourceContext)
        }
    }

    func addBookmarkCapture(
        urlString source: String,
        title: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        guard bookmarkService.previewNormalizedURLString(from: source) != nil else {
            throw CiderCaptureError.unsupportedSource(source)
        }

        let existingIDs = Set(bookmarkService.bookmarks.map(\.id))
        guard let captured = bookmarkService.add(urlString: source, title: title, folderID: folderID) else {
            throw CiderCaptureError.storeFailed(source)
        }

        let bookmark = bookmarkService.bookmarks.first(where: { $0.id == captured.id }) ?? captured
        let isDuplicate = existingIDs.contains(bookmark.id)
        let target = routingTarget(for: bookmark)
        let reviewNeeded = folderID != nil && bookmark.folderID == nil
        let reviewState = reviewNeeded ? "needs_review" : "accepted"
        let reason: String
        if reviewNeeded {
            reason = "The requested deterministic bookmark destination could not be applied, so Cider kept the capture in Inbox/Bookmarks for review."
        } else if bookmark.folderID == nil {
            reason = "No deterministic destination was supplied; Cider stored the bookmark in Inbox/Bookmarks as neutral staging."
        } else {
            reason = "Capture used the supplied deterministic target."
        }
        let routingStatus = recordRoutingDecisionStatus(
            itemID: bookmark.id,
            itemType: "bookmark",
            target: target,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            reviewState: reviewState
        )

        var result = CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "url",
                url: source,
                file: nil,
                text: nil,
                itemID: bookmark.id,
                itemType: "bookmark"
            ),
            item: .init(
                id: bookmark.id,
                type: "bookmark",
                title: bookmark.title,
                relativePath: bookmark.relativePath,
                folderID: bookmark.folderID,
                folderName: target.name
            ),
            enrichment: .init(
                status: enrichmentStatus(for: bookmark),
                isEnriching: bookmark.isEnriching,
                titleState: titleState(for: bookmark),
                lastEnrichedAt: bookmark.lastEnrichedAt
            ),
            duplicate: .init(
                status: isDuplicate ? "duplicate" : "new",
                existingItemID: isDuplicate ? bookmark.id : nil
            ),
            routing: .init(
                decisionID: routingStatus.decisionID,
                candidateTarget: target,
                reviewNeeded: reviewNeeded,
                confidence: reviewNeeded ? 0.0 : 1.0,
                reason: reason,
                reviewState: reviewState,
                status: routingStatus.status,
                statusReason: routingStatus.reason
            ),
            nextSafeAction: isDuplicate ? "inspect_existing_item" : "enrich"
        )
        result.stagedIntents = CiderCaptureIntentStagingService.stagedIntents(for: bookmark)
        result.routeIntents = CiderCaptureIntentStagingService.routeIntents(for: bookmark)
        return indexCapturedItem(attachCaptureEvent(to: result, sourceContext: sourceContext))
    }

    private func addNote(
        _ source: String,
        title: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext?
    ) throws -> CiderCaptureResult {
        try addNoteCapture(title: title, content: source, folderID: folderID, sourceContext: sourceContext)
    }

    func addNoteCapture(
        title: String?,
        content: String,
        folderID: UUID?,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        let manualTitle = normalizedTitle(title)
        let derivedTitle = derivedTextTitle(from: content)
        let note = notesStorage.createNew(initialContent: content)
        if let noteTitle = manualTitle ?? derivedTitle {
            notesStorage.rename(note: note, to: noteTitle)
        }
        var assignmentSucceeded: Bool?
        if let folderID {
            assignmentSucceeded = noteAssignmentHandler(note.id, folderID)
        }
        guard let stored = notesStorage.notes.first(where: { $0.id == note.id }) else {
            throw CiderCaptureError.storeFailed(content)
        }
        try ensureCapturedNoteCanonicalRow(stored)
        let partialSuccess = assignmentPartialSuccess(
            itemType: "note",
            requestedFolderID: folderID,
            actualFolderID: stored.folderID,
            assignmentSucceeded: assignmentSucceeded
        )

        let target = routingTarget(
            itemType: "note",
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Notes"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "note",
            target: target,
            reviewNeeded: folderID != nil && stored.folderID == nil,
            acceptedReason: folderID == nil
                ? "No deterministic destination was supplied; Cider stored the note in Inbox/Notes as neutral staging."
                : "Capture used the supplied deterministic target.",
            reviewReason: "The requested deterministic note destination could not be applied, so Cider kept the capture in Inbox/Notes for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: content,
            itemID: stored.id,
            itemType: "note",
            title: stored.title,
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: manualTitle == nil ? "derived" : "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: partialSuccess,
            sourceContext: sourceContext,
            stagedIntents: CiderCaptureIntentStagingService.stagedIntents(for: .init(
                title: stored.title,
                urlString: nil,
                sourceFile: nil,
                sourceText: content,
                sourceContext: sourceContext
            ))
        )
    }

    func addScreenCaptureNoteCapture(
        title: String,
        ocrText: String,
        screenshot: NSImage?,
        sourceURL: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        let manualTitle = normalizedTitle(title)
        let finalTitle = manualTitle ?? "Screen Capture"
        let note = notesStorage.createFromCapture(
            title: finalTitle,
            ocrText: ocrText,
            screenshot: screenshot,
            sourceURL: sourceURL
        )
        var assignmentSucceeded: Bool?
        if let folderID {
            assignmentSucceeded = noteAssignmentHandler(note.id, folderID)
        }
        guard let stored = notesStorage.notes.first(where: { $0.id == note.id }) else {
            throw CiderCaptureError.storeFailed(finalTitle)
        }
        let partialSuccess = assignmentPartialSuccess(
            itemType: "note",
            requestedFolderID: folderID,
            actualFolderID: stored.folderID,
            assignmentSucceeded: assignmentSucceeded
        )

        let target = routingTarget(
            itemType: "note",
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Notes"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "note",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured a screen capture as a note and kept it in Inbox/Notes for review."
        )

        return sharedResult(
            sourceKind: "screen_capture",
            sourceURL: sourceURL,
            sourceFile: nil,
            sourceText: ocrText,
            itemID: stored.id,
            itemType: "note",
            title: stored.title,
            relativePath: stored.relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: manualTitle == nil ? "derived" : "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: partialSuccess,
            sourceContext: sourceContext,
            stagedIntents: CiderCaptureIntentStagingService.stagedIntents(for: .init(
                title: stored.title,
                urlString: sourceURL,
                sourceFile: nil,
                sourceText: ocrText,
                sourceContext: sourceContext
            ))
        )
    }

    func addImageBookmarkCapture(
        title: String,
        imageData: Data,
        preferredFileExtension: String?,
        sourceFile: String?,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        let finalTitle = normalizedTitle(title) ?? "Dropped Image"
        let created = bookmarkService.addImageBookmark(title: finalTitle)
        let didAssignThumbnail = thumbnailAssignmentHandler(
            created.id,
            imageData,
            preferredFileExtension
        )
        let bookmark = bookmarkService.bookmarks.first(where: { $0.id == created.id }) ?? created
        let target = routingTarget(for: bookmark)
        let routing = try recordRouting(
            itemID: bookmark.id,
            itemType: "bookmark",
            target: target,
            reviewNeeded: bookmark.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured an image bookmark and kept it in Inbox/Bookmarks for review."
        )

        var result = sharedResult(
            sourceKind: "image",
            sourceURL: nil,
            sourceFile: sourceFile,
            sourceText: nil,
            itemID: bookmark.id,
            itemType: "bookmark",
            title: bookmark.title,
            relativePath: bookmark.relativePath,
            folderID: bookmark.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: "manual",
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: thumbnailPartialSuccess(didAssignThumbnail: didAssignThumbnail),
            sourceContext: sourceContext
        )
        result.stagedIntents = CiderCaptureIntentStagingService.stagedIntents(for: .init(
            title: bookmark.title,
            urlString: bookmark.urlString,
            sourceFile: sourceFile,
            sourceText: bookmark.notes,
            sourceContext: sourceContext
        ))
        return result
    }

    private func addTodo(
        _ source: String,
        title: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext?
    ) throws -> CiderCaptureResult {
        try addTodoCapture(
            title: normalizedTitle(title) ?? derivedTodoTitle(from: source),
            sourceText: source,
            dueDate: nil,
            priority: nil,
            folderID: folderID,
            titleState: normalizedTitle(title) == nil ? "derived" : "manual",
            sourceContext: sourceContext
        )
    }

    func addTodoCapture(
        title: String,
        sourceText: String?,
        dueDate: Date?,
        priority: TodoPriority?,
        folderID: UUID?,
        titleState: String = "manual",
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        if let existing = existingOpenTodoDuplicate(title: title, dueDate: dueDate) {
            let relativePath = itemRelativePathFromDatabase(itemID: existing.id) ?? "Inbox/Todos"
            let target = routingTarget(
                itemType: "todo",
                relativePath: relativePath,
                folderID: existing.folderID,
                fallbackInboxPath: "Inbox/Todos"
            )
            let routing = try recordRouting(
                itemID: existing.id,
                itemType: "todo",
                target: target,
                reviewNeeded: existing.folderID == nil,
                acceptedReason: "Capture matched an existing open todo and preserved its current location.",
                reviewReason: "Capture matched an existing open Inbox/Todos item instead of creating a duplicate."
            )

            return sharedResult(
                sourceKind: "text",
                sourceURL: nil,
                sourceFile: nil,
                sourceText: sourceText ?? title,
                itemID: existing.id,
                itemType: "todo",
                title: existing.title,
                relativePath: relativePath,
                folderID: existing.folderID,
                folderName: target.name,
                enrichmentStatus: "not_applicable",
                titleState: titleState,
                duplicateStatus: "duplicate",
                duplicateExistingItemID: existing.id,
                routing: routing,
                nextSafeAction: "inspect_existing_item",
                sourceContext: sourceContext
            )
        }

        var todo = todoStorage.createTodoCard(title: title, dueDate: dueDate, priority: priority)
        var assignmentSucceeded: Bool?
        if let folderID {
            todo.folderID = folderID
            assignmentSucceeded = todoUpdateHandler(todo)
        }
        guard let stored = todoStorage.todoCards.first(where: { $0.id == todo.id }) else {
            throw CiderCaptureError.storeFailed(title)
        }
        let partialSuccess = assignmentPartialSuccess(
            itemType: "todo",
            requestedFolderID: folderID,
            actualFolderID: stored.folderID,
            assignmentSucceeded: assignmentSucceeded
        )

        let relativePath = itemRelativePathFromDatabase(itemID: stored.id) ?? "Inbox/Todos"
        let target = routingTarget(
            itemType: "todo",
            relativePath: relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Todos"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "todo",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured task-like text as a todo and kept it in Inbox/Todos for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: sourceText ?? title,
            itemID: stored.id,
            itemType: "todo",
            title: stored.title,
            relativePath: relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: titleState,
            duplicateStatus: "new",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: partialSuccess,
            sourceContext: sourceContext
        )
    }

    func addDateCardCapture(
        title: String,
        sourceText: String?,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        location: String?,
        folderID: UUID?,
        titleState: String = "manual",
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        var card = dateCardStorage.createDateCard(
            title: title,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay
        )
        var needsUpdate = false
        let details = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let details, !details.isEmpty {
            card.details = details
            needsUpdate = true
        }
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedLocation, !trimmedLocation.isEmpty {
            card.location = trimmedLocation
            needsUpdate = true
        }
        if let folderID {
            card.folderID = folderID
            needsUpdate = true
        }

        var assignmentSucceeded: Bool?
        if needsUpdate {
            let updated = dateCardUpdateHandler(card)
            if folderID != nil {
                assignmentSucceeded = updated
            }
        }
        guard let stored = dateCardStorage.dateCards.first(where: { $0.id == card.id }) else {
            throw CiderCaptureError.storeFailed(title)
        }
        let partialSuccess = assignmentPartialSuccess(
            itemType: "event",
            requestedFolderID: folderID,
            actualFolderID: stored.folderID,
            assignmentSucceeded: assignmentSucceeded
        )

        let relativePath = itemRelativePathFromDatabase(itemID: stored.id) ?? "Inbox/Date Cards"
        let target = routingTarget(
            itemType: "dateCard",
            relativePath: relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Date Cards"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "event",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured event-like text as a date card and kept it in Inbox/Date Cards for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: sourceText ?? title,
            itemID: stored.id,
            itemType: "event",
            title: stored.title,
            relativePath: relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: titleState,
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: partialSuccess,
            sourceContext: sourceContext,
            stagedIntents: CiderCaptureIntentStagingService.stagedIntents(for: .init(
                title: stored.title,
                urlString: nil,
                sourceFile: nil,
                sourceText: [
                    details,
                    trimmedLocation
                ].compactMap { $0 }.joined(separator: " "),
                sourceContext: sourceContext
            ))
        )
    }

    func addContactCapture(
        displayName: String,
        sourceText: String?,
        relationshipLabel: String?,
        email: String?,
        phone: String?,
        folderID: UUID?,
        titleState: String = "manual",
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        var contact = contactStorage.createContact(displayName: displayName)
        var needsUpdate = false
        let relationship = relationshipLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let relationship, !relationship.isEmpty {
            contact.relationshipLabel = relationship
            needsUpdate = true
        }
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedEmail, !trimmedEmail.isEmpty {
            contact.email = trimmedEmail
            needsUpdate = true
        }
        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPhone, !trimmedPhone.isEmpty {
            contact.phone = trimmedPhone
            needsUpdate = true
        }
        if let folderID {
            contact.folderID = folderID
            needsUpdate = true
        }

        var assignmentSucceeded: Bool?
        if needsUpdate {
            let updated = contactUpdateHandler(contact)
            if folderID != nil {
                assignmentSucceeded = updated
            }
        }
        guard let stored = contactStorage.contacts.first(where: { $0.id == contact.id }) else {
            throw CiderCaptureError.storeFailed(displayName)
        }
        let partialSuccess = assignmentPartialSuccess(
            itemType: "contact",
            requestedFolderID: folderID,
            actualFolderID: stored.folderID,
            assignmentSucceeded: assignmentSucceeded
        )

        let relativePath = itemRelativePathFromDatabase(itemID: stored.id) ?? "Inbox/Contacts"
        let target = routingTarget(
            itemType: "contact",
            relativePath: relativePath,
            folderID: stored.folderID,
            fallbackInboxPath: "Inbox/Contacts"
        )
        let routing = try recordRouting(
            itemID: stored.id,
            itemType: "contact",
            target: target,
            reviewNeeded: stored.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider captured contact-like text as a contact and kept it in Inbox/Contacts for review."
        )

        return sharedResult(
            sourceKind: "text",
            sourceURL: nil,
            sourceFile: nil,
            sourceText: sourceText ?? displayName,
            itemID: stored.id,
            itemType: "contact",
            title: stored.displayName,
            relativePath: relativePath,
            folderID: stored.folderID,
            folderName: target.name,
            enrichmentStatus: "not_applicable",
            titleState: titleState,
            duplicateStatus: "not_checked",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            partialSuccess: partialSuccess,
            sourceContext: sourceContext,
            stagedIntents: CiderCaptureIntentStagingService.stagedContactIntents(for: .init(
                title: stored.displayName,
                urlString: nil,
                sourceFile: nil,
                sourceText: [
                    sourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                    relationship,
                    trimmedEmail
                ].compactMap { $0 }.joined(separator: " "),
                sourceContext: sourceContext
            ))
        )
    }

    private func addFile(
        _ source: String,
        title: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext?
    ) throws -> CiderCaptureResult {
        try addFileCapture(sourcePath: source, title: title, folderID: folderID, sourceContext: sourceContext)
    }

    func addFileCapture(
        sourcePath: String,
        title: String?,
        folderID: UUID?,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderCaptureResult {
        let source = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw CiderCaptureError.missingSource }
        let sourceURL = URL(fileURLWithPath: NSString(string: source).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw CiderCaptureError.fileNotFound(source)
        }

        let fileType = VaultFileType.from(extension: sourceURL.pathExtension)
        let destinationDirectory = fileDestinationDirectory(fileType: fileType, folderID: folderID)
        try FileManager.default.createDirectory(at: destinationDirectory.url, withIntermediateDirectories: true)
        let destinationURL = uniqueDestinationURL(for: sourceURL, in: destinationDirectory.url)
        do {
            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            throw CiderCaptureError.fileCopyFailed(source)
        }

        let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let file = VaultFile(
            id: UUID(),
            filename: destinationURL.lastPathComponent,
            relativePath: destinationDirectory.relativePathPrefix.isEmpty
                ? destinationURL.lastPathComponent
                : "\(destinationDirectory.relativePathPrefix)/\(destinationURL.lastPathComponent)",
            fileType: fileType,
            fileSize: Int64(values?.fileSize ?? 0),
            createdAt: values?.creationDate ?? Date(),
            modifiedAt: values?.contentModificationDate ?? Date(),
            folderID: destinationDirectory.folderID,
            title: normalizedTitle(title)
        )
        vaultFileStorage.persistVaultFileToDatabase(file)
        recordVaultFileCreateAudit(file)

        let target = routingTarget(
            itemType: "vaultFile",
            relativePath: file.relativePath,
            folderID: file.folderID,
            fallbackInboxPath: destinationDirectory.relativePathPrefix
        )
        let routing = try recordRouting(
            itemID: file.id,
            itemType: "vaultFile",
            target: target,
            reviewNeeded: file.folderID == nil,
            acceptedReason: "Capture used the supplied deterministic target.",
            reviewReason: "Cider imported the file and kept it in \(target.relativePath) for review."
        )

        var result = sharedResult(
            sourceKind: "file",
            sourceURL: nil,
            sourceFile: sourceURL.path,
            sourceText: nil,
            itemID: file.id,
            itemType: "vaultFile",
            title: file.displayTitle,
            relativePath: file.relativePath,
            folderID: file.folderID,
            folderName: target.name,
            enrichmentStatus: fileType == .image ? "pending" : "not_applicable",
            titleState: file.title == nil ? "filename_derived" : "manual",
            duplicateStatus: "unsupported",
            duplicateReason: "duplicate_check_not_implemented_for_file_capture",
            routing: routing,
            nextSafeAction: routing.defaultNextSafeAction,
            captureQuality: CiderCaptureResult.fileCaptureQualityDictionary(for: file),
            sourceContext: sourceContext
        )
        result.stagedIntents = CiderCaptureIntentStagingService.stagedIntents(for: .init(
            title: file.displayTitle,
            urlString: nil,
            sourceFile: "\(sourceURL.path) \(file.relativePath)",
            sourceText: CiderCaptureResult.readableTextFileContent(relativePath: file.relativePath),
            sourceContext: sourceContext
        ))
        return result
    }

    private func enrichmentStatus(for bookmark: Bookmark) -> String {
        if let status = bookmark.enrichmentStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            return status
        }
        if bookmark.metadataUpdatedAt != nil {
            return "metadata_complete"
        }
        return "pending"
    }

    private func titleState(for bookmark: Bookmark) -> String {
        if bookmark.titleManuallySet { return "manual" }
        if bookmark.metadataUpdatedAt != nil { return "enriched" }
        return "host_derived"
    }

    private func routingTarget(for bookmark: Bookmark) -> CiderCaptureResult.Target {
        if let folderID = bookmark.folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return .init(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }

        return .init(
            kind: "inbox",
            name: "Inbox/Bookmarks",
            relativePath: "Inbox/Bookmarks",
            folderID: nil
        )
    }

    private enum CaptureKind {
        case url
        case note
        case todo
        case file
    }

    private func inferredKind(for source: String) -> CaptureKind {
        if bookmarkService.previewNormalizedURLString(from: source) != nil {
            return .url
        }

        let expandedPath = NSString(string: source).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            return .file
        }

        let lowercased = source.lowercased()
        let todoPrefixes = ["todo:", "task:", "reminder:", "remember to ", "remind me to "]
        if todoPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return .todo
        }

        return .note
    }

    private func sharedResult(
        sourceKind: String,
        sourceURL: String?,
        sourceFile: String?,
        sourceText: String?,
        itemID: UUID,
        itemType: String,
        title: String,
        relativePath: String?,
        folderID: UUID?,
        folderName: String,
        enrichmentStatus: String,
        titleState: String,
        duplicateStatus: String,
        duplicateExistingItemID: UUID? = nil,
        duplicateReason: String? = nil,
        duplicateEvidence: String? = nil,
        routing: CiderCaptureResult.Routing,
        nextSafeAction: String,
        partialSuccess: CiderCaptureResult.PartialSuccess? = nil,
        captureQuality: [String: Any]? = nil,
        sourceContext: CaptureSourceContext? = nil,
        stagedIntents: [CiderCaptureResult.StagedIntent] = []
    ) -> CiderCaptureResult {
        var result = CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: sourceKind,
                url: sourceURL,
                file: sourceFile,
                text: sourceText,
                itemID: itemID,
                itemType: itemType
            ),
            item: .init(
                id: itemID,
                type: itemType,
                title: title,
                relativePath: relativePath,
                folderID: folderID,
                folderName: folderName
            ),
            enrichment: .init(
                status: enrichmentStatus,
                isEnriching: false,
                titleState: titleState,
                lastEnrichedAt: nil
            ),
            duplicate: .init(
                status: duplicateStatus,
                existingItemID: duplicateExistingItemID,
                reason: duplicateReason,
                evidence: duplicateEvidence
            ),
            routing: routing,
            nextSafeAction: nextSafeAction,
            partialSuccess: partialSuccess
        )
        result.captureQuality = captureQuality
        result.stagedIntents = stagedIntents
        return indexCapturedItem(attachCaptureEvent(to: result, sourceContext: sourceContext))
    }

    private func existingOpenTodoDuplicate(title: String, dueDate: Date?) -> TodoCard? {
        let normalizedTitle = normalizedTodoDuplicateTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }
        return todoStorage.todoCards.first { candidate in
            !candidate.isCompleted
                && normalizedTodoDuplicateTitle(candidate.title) == normalizedTitle
                && todoDueDatesMatch(candidate.dueDate, dueDate)
        }
    }

    private func normalizedTodoDuplicateTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func todoDueDatesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.timeIntervalSince(rhs)) < 1
        default:
            return false
        }
    }

    private func attachCaptureEvent(
        to result: CiderCaptureResult,
        sourceContext: CaptureSourceContext?
    ) -> CiderCaptureResult {
        var result = result
        let eventID = UUID()
        let resolvedContext = sourceContext ?? CaptureSourceContext(
            surface: "cider",
            channel: nil,
            channelID: nil,
            threadID: nil,
            messageID: nil,
            senderID: nil,
            senderName: nil,
            originalText: result.source.text,
            attachments: [],
            metadata: [:]
        )
        result.sourceContext = resolvedContext

        guard let database, database.isOpen else {
            result.provenance = .init(
                status: "unavailable",
                reason: "Capture provenance could not be recorded because no writable database is available.",
                ownerType: "capture_event",
                ownerID: nil,
                captureEventID: nil
            )
            return result
        }
        do {
            let metadata = DatabaseHelpers.encodeJSON(resolvedContext.metadata) ?? "{}"
            let stmt = try database.prepare("""
                INSERT INTO capture_events (
                    id, source_kind, surface, channel, channel_id, thread_id, message_id,
                    sender_id, sender_name, source_url, source_file, source_text,
                    attachment_count, metadata, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            stmt.bind(eventID.uuidString, at: 1)
                .bind(result.source.kind, at: 2)
                .bind(resolvedContext.surface, at: 3)
                .bind(resolvedContext.channel, at: 4)
                .bind(resolvedContext.channelID, at: 5)
                .bind(resolvedContext.threadID, at: 6)
                .bind(resolvedContext.messageID, at: 7)
                .bind(resolvedContext.senderID, at: 8)
                .bind(resolvedContext.senderName, at: 9)
                .bind(result.source.url, at: 10)
                .bind(result.source.file, at: 11)
                .bind(resolvedContext.originalText ?? result.source.text, at: 12)
                .bind(resolvedContext.attachments.count, at: 13)
                .bind(metadata, at: 14)
                .bind(DatabaseHelpers.encode(Date()), at: 15)
            try stmt.step()

            let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
            let itemOwner = SecondBrainOwnerRef(
                ownerType: ownerType(forCaptureItemType: result.item.type),
                ownerID: result.item.id.uuidString
            )
            let secondBrainStore = SecondBrainStore(database: database)
            try secondBrainStore.recordRelation(SecondBrainRelation(
                sourceOwner: captureOwner,
                targetOwner: itemOwner,
                relationType: "produced_item",
                evidence: "Capture event produced \(result.item.type) \(result.item.title).",
                source: "capture.add",
                actor: "system",
                confidence: 1,
                metadata: [
                    "command": result.command,
                    "source_kind": result.source.kind,
                    "item_type": result.item.type,
                ]
            ))
            try persistCaptureAttachments(
                resolvedContext.attachments,
                eventID: eventID,
                captureOwner: captureOwner,
                itemOwner: itemOwner,
                itemTitle: result.item.title,
                database: database,
                secondBrainStore: secondBrainStore
            )
            result.captureEventID = eventID
            result.provenance = .init(
                status: "recorded",
                reason: nil,
                ownerType: "capture_event",
                ownerID: eventID.uuidString,
                captureEventID: eventID
            )
        } catch {
            result.provenance = .init(
                status: "failed",
                reason: "Capture provenance failed: \(error.localizedDescription)",
                ownerType: "capture_event",
                ownerID: nil,
                captureEventID: nil
            )
            return result
        }
        return result
    }

    private func indexCapturedItem(_ result: CiderCaptureResult) -> CiderCaptureResult {
        var result = result
        let owner = SecondBrainOwnerRef(
            ownerType: ownerType(forCaptureItemType: result.item.type),
            ownerID: result.item.id.uuidString
        )
        guard let database, database.isOpen else {
            result.indexing = .init(
                status: "unavailable",
                reason: "Capture indexing could not run because no writable database is available.",
                ownerType: owner.ownerType,
                ownerID: owner.ownerID,
                captureEventID: nil
            )
            return result
        }
        do {
            let chunks = try retryingTransientSQLiteLocks {
                _ = try SecondBrainItemContentIndexingService(database: database).rebuild(owner: owner)
                return try indexedChunkTrace(owner: owner, database: database)
            }
            result.indexing = .init(
                status: "indexed",
                reason: nil,
                ownerType: owner.ownerType,
                ownerID: owner.ownerID,
                captureEventID: result.captureEventID,
                chunks: chunks
            )
        } catch {
            result.indexing = .init(
                status: "failed",
                reason: "Capture indexing failed: \(error.localizedDescription)",
                ownerType: owner.ownerType,
                ownerID: owner.ownerID,
                captureEventID: nil
            )
            return result
        }
        return result
    }

    private func retryingTransientSQLiteLocks<T>(
        attempts: Int = 12,
        initialDelay: TimeInterval = 0.08,
        _ operation: () throws -> T
    ) throws -> T {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try operation()
            } catch {
                lastError = error
                guard isTransientSQLiteLock(error), attempt + 1 < attempts else {
                    throw error
                }
                Thread.sleep(forTimeInterval: initialDelay * Double(attempt + 1))
            }
        }
        throw lastError ?? CiderCaptureError.storeFailed("capture indexing")
    }

    private func isTransientSQLiteLock(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("database is locked")
            || message.contains("database is busy")
            || message.contains("sqlite_busy")
            || message.contains("sqlite_locked")
    }

    private func ensureCapturedNoteCanonicalRow(_ note: Note) throws {
        guard let database, database.isOpen else {
            return
        }
        try retryingTransientSQLiteLocks {
            try notesStorage.persistNoteCanonicalRow(database, note: note)
        }
    }

    func refreshItemIndexing(_ result: CiderCaptureResult) -> CiderCaptureResult {
        indexCapturedItem(result)
    }

    private func indexedChunkTrace(
        owner: SecondBrainOwnerRef,
        database: CiderDatabase,
        limit: Int = 20
    ) throws -> [CiderCaptureResult.SideEffectStatus.IndexedChunk] {
        let normalizedLimit = max(1, min(limit, 50))
        let stmt = try database.prepare("""
            SELECT id, source, title, chunk_index
            FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY chunk_index ASC, title COLLATE NOCASE ASC
            LIMIT ?;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
            .bind(normalizedLimit, at: 3)

        var chunks: [CiderCaptureResult.SideEffectStatus.IndexedChunk] = []
        while try stmt.step() {
            chunks.append(
                CiderCaptureResult.SideEffectStatus.IndexedChunk(
                    id: stmt.string(at: 0),
                    ownerType: owner.ownerType,
                    ownerID: owner.ownerID,
                    source: stmt.string(at: 1),
                    title: stmt.string(at: 2),
                    chunkIndex: stmt.int(at: 3)
                )
            )
        }
        return chunks
    }

    private func persistCaptureAttachments(
        _ attachments: [CaptureSourceContext.Attachment],
        eventID: UUID,
        captureOwner: SecondBrainOwnerRef,
        itemOwner: SecondBrainOwnerRef,
        itemTitle: String,
        database: CiderDatabase,
        secondBrainStore: SecondBrainStore
    ) throws {
        guard !attachments.isEmpty else { return }

        let now = DatabaseHelpers.encode(Date())
        for (index, attachment) in attachments.enumerated() {
            let attachmentID = UUID()
            let metadata = DatabaseHelpers.encodeJSON([
                "capture_event_id": eventID.uuidString,
                "attachment_index": String(index),
            ]) ?? "{}"
            let byteSize = attachment.localPath.flatMap { localPath -> Int64? in
                let attrs = try? FileManager.default.attributesOfItem(atPath: localPath)
                return attrs?[.size] as? Int64
            }

            let stmt = try database.prepare("""
                INSERT INTO capture_attachments (
                    id, capture_event_id, attachment_index, source_attachment_id,
                    filename, mime_type, local_path, remote_url, byte_size,
                    metadata, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            stmt.bind(attachmentID.uuidString, at: 1)
                .bind(eventID.uuidString, at: 2)
                .bind(index, at: 3)
                .bind(attachment.id, at: 4)
                .bind(attachment.filename, at: 5)
                .bind(attachment.mimeType, at: 6)
                .bind(attachment.localPath, at: 7)
                .bind(attachment.remoteURL, at: 8)
                .bind(byteSize, at: 9)
                .bind(metadata, at: 10)
                .bind(now, at: 11)
            try stmt.step()

            let attachmentOwner = SecondBrainOwnerRef(
                ownerType: "capture_attachment",
                ownerID: attachmentID.uuidString
            )
            try secondBrainStore.recordRelation(SecondBrainRelation(
                sourceOwner: captureOwner,
                targetOwner: attachmentOwner,
                relationType: "had_attachment",
                evidence: attachment.filename.map { "Capture event included attachment \($0)." }
                    ?? "Capture event included an attachment.",
                source: "capture.add",
                actor: "system",
                confidence: 1,
                metadata: captureAttachmentRelationMetadata(
                    attachment: attachment,
                    eventID: eventID,
                    attachmentIndex: index
                )
            ))
            try secondBrainStore.recordRelation(SecondBrainRelation(
                sourceOwner: attachmentOwner,
                targetOwner: itemOwner,
                relationType: "associated_item",
                evidence: attachment.filename.map { "Attachment \($0) was associated with \(itemTitle)." }
                    ?? "Capture attachment was associated with \(itemTitle).",
                source: "capture.add",
                actor: "system",
                confidence: 1,
                metadata: captureAttachmentRelationMetadata(
                    attachment: attachment,
                    eventID: eventID,
                    attachmentIndex: index
                )
            ))
        }
    }

    private func captureAttachmentRelationMetadata(
        attachment: CaptureSourceContext.Attachment,
        eventID: UUID,
        attachmentIndex: Int
    ) -> [String: String] {
        var metadata: [String: String] = [
            "capture_event_id": eventID.uuidString,
            "attachment_index": String(attachmentIndex),
        ]
        if let id = attachment.id { metadata["source_attachment_id"] = id }
        if let filename = attachment.filename { metadata["filename"] = filename }
        if let mimeType = attachment.mimeType { metadata["mime_type"] = mimeType }
        if let remoteURL = attachment.remoteURL { metadata["remote_url"] = remoteURL }
        return metadata
    }

    private func ownerType(forCaptureItemType itemType: String) -> String {
        switch itemType {
        case "event": return "dateCard"
        default: return itemType
        }
    }

    private func assignmentPartialSuccess(
        itemType: String,
        requestedFolderID: UUID?,
        actualFolderID: UUID?,
        assignmentSucceeded: Bool?
    ) -> CiderCaptureResult.PartialSuccess? {
        guard let requestedFolderID,
              assignmentSucceeded == false || actualFolderID != requestedFolderID
        else {
            return nil
        }
        return .init(
            status: "assignment_failed",
            reason: "\(itemType) folder assignment failed; Cider stored the source item and left it in review.",
            requestedFolderID: requestedFolderID,
            actualFolderID: actualFolderID
        )
    }

    private func thumbnailPartialSuccess(didAssignThumbnail: Bool) -> CiderCaptureResult.PartialSuccess? {
        guard !didAssignThumbnail else { return nil }
        return .init(
            status: "thumbnail_assignment_failed",
            reason: "Image bookmark thumbnail assignment failed; Cider stored the bookmark and left it in review.",
            requestedFolderID: nil,
            actualFolderID: nil
        )
    }

    private func recordRouting(
        itemID: UUID,
        itemType: String,
        target: CiderCaptureResult.Target,
        reviewNeeded: Bool,
        acceptedReason: String,
        reviewReason: String
    ) throws -> CiderCaptureResult.Routing {
        let reviewState = reviewNeeded ? "needs_review" : "accepted"
        let reason = reviewNeeded ? reviewReason : acceptedReason
        let routingStatus = recordRoutingDecisionStatus(
            itemID: itemID,
            itemType: itemType,
            target: target,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            reviewState: reviewState
        )
        return .init(
            decisionID: routingStatus.decisionID,
            candidateTarget: target,
            reviewNeeded: reviewNeeded,
            confidence: reviewNeeded ? 0.0 : 1.0,
            reason: reason,
            reviewState: reviewState,
            status: routingStatus.status,
            statusReason: routingStatus.reason
        )
    }

    private func recordRoutingDecisionStatus(
        itemID: UUID,
        itemType: String,
        target: CiderCaptureResult.Target,
        confidence: Double,
        reason: String,
        reviewState: String
    ) -> (decisionID: UUID?, status: String, reason: String?) {
        guard let routingDecisionService else {
            return (
                nil,
                "unavailable",
                "Capture routing could not be recorded because no routing decision service is available."
            )
        }
        do {
            let decision = try routingDecisionService.recordDecision(
                itemID: itemID,
                itemType: itemType,
                target: target.routingDecisionTarget,
                confidence: confidence,
                reason: reason,
                actor: "agent",
                source: "capture.add",
                reviewState: reviewState
            )
            return (decision.id, "recorded", nil)
        } catch {
            return (nil, "failed", "Capture routing failed: \(error.localizedDescription)")
        }
    }

    private func routingTarget(
        itemType: String,
        relativePath: String?,
        folderID: UUID?,
        fallbackInboxPath: String
    ) -> CiderCaptureResult.Target {
        if let folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return .init(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }

        let inboxPath: String
        if let relativePath, relativePath.hasPrefix("Inbox/") {
            let parts = relativePath.split(separator: "/").prefix(2).map(String.init)
            inboxPath = parts.count == 2 ? parts.joined(separator: "/") : fallbackInboxPath
        } else {
            inboxPath = fallbackInboxPath
        }

        return .init(
            kind: "inbox",
            name: inboxPath,
            relativePath: inboxPath,
            folderID: nil
        )
    }

    private func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func derivedTextTitle(from source: String) -> String? {
        let line = source
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(80))
    }

    func derivedTodoTitle(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let prefixes = ["todo:", "task:", "reminder:", "remember to ", "remind me to "]
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let title = trimmed[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Untitled Todo" : title
        }
        return trimmed.isEmpty ? "Untitled Todo" : trimmed
    }

    private func itemRelativePathFromDatabase(itemID: UUID) -> String? {
        guard let database else { return nil }
        do {
            let stmt = try database.prepare("SELECT relative_path FROM items WHERE id = ?;")
            stmt.bind(itemID.uuidString, at: 1)
            guard try stmt.step() else { return nil }
            return stmt.optionalString(at: 0)
        } catch {
            return nil
        }
    }

    private func fileDestinationDirectory(
        fileType: VaultFileType,
        folderID: UUID?
    ) -> (url: URL, relativePathPrefix: String, folderID: UUID?) {
        if let folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return (
                StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(folder.relativePath),
                folder.relativePath,
                folder.id
            )
        }

        let inboxSubdirectory: String
        switch fileType {
        case .image:
            inboxSubdirectory = "Images"
        case .video:
            inboxSubdirectory = "Videos"
        default:
            inboxSubdirectory = "Files"
        }
        let relativePath = "\(StoragePaths.inboxDir)/\(inboxSubdirectory)"
        return (
            StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath),
            relativePath,
            nil
        )
    }

    private func recordVaultFileCreateAudit(_ file: VaultFile) {
        MutationAuditService(database: database).record(
            action: "create",
            itemType: "vaultFile",
            itemID: file.id,
            after: [
                "title": file.displayTitle,
                "filename": file.filename,
                "relativePath": file.relativePath,
                "fileType": file.fileType.rawValue,
                "fileSize": "\(file.fileSize)",
            ],
            metadata: ["source": "capture.add"],
            source: .agent
        )
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let base = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let ext = (sourceURL.lastPathComponent as NSString).pathExtension
        var candidate = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let filename = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directoryURL.appendingPathComponent(filename)
            counter += 1
        }
        return candidate
    }
}

struct CiderBookmarkCaptureAdapterResult {
    var bookmark: Bookmark
    var captureResult: CiderCaptureResult
}

@MainActor
final class CiderBookmarkCaptureAdapter {
    private let bookmarkService: VaultBookmarkService
    private let database: CiderDatabase?

    init(
        bookmarkService: VaultBookmarkService = .shared,
        database: CiderDatabase? = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
    ) {
        self.bookmarkService = bookmarkService
        self.database = database
    }

    func addURLBookmark(
        urlString: String,
        title: String? = nil,
        folderID: UUID? = nil,
        sourceContext: CaptureSourceContext? = nil
    ) throws -> CiderBookmarkCaptureAdapterResult {
        let captureResult = try CiderCaptureService(
            bookmarkService: bookmarkService,
            database: database
        ).add(
            urlString,
            title: title,
            folderID: folderID,
            sourceContext: sourceContext
        )
        guard captureResult.item.type == "bookmark",
              let bookmark = bookmarkService.bookmarks.first(where: { $0.id == captureResult.item.id })
        else {
            throw CiderCaptureError.storeFailed(urlString)
        }
        return CiderBookmarkCaptureAdapterResult(bookmark: bookmark, captureResult: captureResult)
    }
}

private extension CiderCaptureResult.Target {
    var routingDecisionTarget: CiderRoutingDecisionTarget {
        CiderRoutingDecisionTarget(
            kind: kind,
            name: name,
            relativePath: relativePath,
            folderID: folderID
        )
    }
}

private extension String {
    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}
