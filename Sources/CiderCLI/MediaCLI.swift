import Foundation
@testable import Cider

extension CiderCLI {
    static func handleMedia(subcommand: String?, args: [String], bookmarks: [Bookmark]) {
        switch subcommand {
        case "identify":
            let mode: MediaBackfillMode = args.contains("--apply") ? .apply : .dryRun
            let storage = MediaItemStorage()
            let service = MediaBackfillService(storage: storage, secondBrainStore: SecondBrainStore())

            do {
                let report = try service.identify(bookmarks: bookmarks, mode: mode)
                if jsonOutput {
                    outputJSON(mediaBackfillReportToDict(report, mode: mode))
                } else {
                    printMediaBackfillReport(report, mode: mode)
                }
            } catch {
                print("Error: Media identification failed: \(error.localizedDescription)")
            }

        default:
            print("Unknown media command: \(subcommand ?? "nil")")
            print("Commands: identify --dry-run|--apply")
        }
    }

    private static func printMediaBackfillReport(_ report: MediaBackfillReport, mode: MediaBackfillMode) {
        let modeLabel = mode == .apply ? "apply" : "dry-run"
        print("Media identify (\(modeLabel))")
        print("  Proposed: \(report.proposedItems.count)")
        print("  Review:   \(report.reviewItems.count)")
        print("  Skipped:  \(report.skippedCount)")
        if mode == .apply {
            print("  Created:  \(report.createdCount)")
            print("  Updated:  \(report.updatedCount)")
        }

        if !report.proposedItems.isEmpty {
            print("")
            print("Proposed MediaItems:")
            for item in report.proposedItems {
                let ids = item.externalIDs
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                print("  [\(item.id)] \(item.title) (\(item.type.rawValue), confidence \(String(format: "%.2f", item.confidence)))")
                if !ids.isEmpty {
                    print("    IDs: \(ids)")
                }
                if !item.sourceURLs.isEmpty {
                    print("    Sources: \(item.sourceURLs.joined(separator: ", "))")
                }
                if let reason = item.identificationReason {
                    print("    Reason: \(reason)")
                }
            }
        }

        if !report.reviewItems.isEmpty {
            print("")
            print("Needs Sorting / Review:")
            for item in report.reviewItems {
                let title = item.candidate?.title ?? "Untitled"
                let type = item.candidate?.type.rawValue ?? "unknown"
                print("  \(title) (\(type), confidence \(String(format: "%.2f", item.confidence)))")
                print("    \(item.reason)")
            }
        }
    }

    static func mediaBackfillReportToDict(_ report: MediaBackfillReport, mode: MediaBackfillMode) -> [String: Any] {
        let isApply = mode == .apply
        let changed = isApply && (
            report.createdCount > 0
                || report.updatedCount > 0
                || !report.actionRecords.isEmpty
        )
        var dict: [String: Any] = [
            "command": "media.identify",
            "mode": mode == .apply ? "apply" : "dry-run",
            "readOnly": !isApply,
            "changed": changed,
            "proposedCount": report.proposedItems.count,
            "reviewCount": report.reviewItems.count,
            "skippedCount": report.skippedCount,
            "createdCount": report.createdCount,
            "updatedCount": report.updatedCount,
            "proposedItems": report.proposedItems.map(mediaItemToDict),
            "reviewItems": report.reviewItems.map(mediaIdentificationResultToDict),
            "reviewLane": mediaReviewLaneToDict(report.reviewItems),
            "actionRecords": report.actionRecords.map(mediaBackfillActionRecordToDict),
        ]
        if isApply {
            dict["mutationReason"] = mediaApplyMutationReason
        }
        return dict
    }

    private static func mediaReviewLaneToDict(_ reviewItems: [MediaIdentificationResult]) -> [String: Any] {
        [
            "id": "media.identify.review",
            "title": "Media identification review",
            "count": reviewItems.count,
            "items": reviewItems.map(mediaIdentificationResultToDict),
            "safeActions": [
                "media identify --dry-run --json",
            ],
            "actions": mediaIdentifyActionsToDict(),
        ]
    }

    private static var mediaApplyMutationReason: String {
        "Writes MediaItem YAML and records media_item action provenance when a second-brain store is available."
    }

    private static func mediaIdentifyActionsToDict() -> [[String: Any]] {
        [
            [
                "command": "media identify --dry-run --json",
                "readOnly": true,
                "requiresApproval": false,
            ],
            [
                "command": "media identify --apply --json",
                "readOnly": false,
                "requiresApproval": true,
                "mutationReason": mediaApplyMutationReason,
            ],
        ]
    }

    private static func mediaBackfillActionRecordToDict(_ record: MediaBackfillActionRecord) -> [String: Any] {
        [
            "mediaItemID": record.mediaItemID,
            "action": record.action,
            "status": record.status,
            "summary": record.summary,
        ]
    }

    private static func mediaItemToDict(_ item: MediaItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "type": item.type.rawValue,
            "title": item.title,
            "canonicalTitle": item.canonicalTitle,
            "externalIDs": item.externalIDs,
            "genres": item.genres,
            "categories": item.categories,
            "status": item.status.rawValue,
            "sourceBookmarkIDs": item.sourceBookmarkIDs.map(\.uuidString),
            "sourceRelativePaths": item.sourceRelativePaths,
            "sourceURLs": item.sourceURLs,
            "confidence": item.confidence,
            "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
        ]
        if let year = item.year { dict["year"] = year }
        if let releaseDate = item.releaseDate { dict["releaseDate"] = releaseDate }
        if let posterImagePath = item.posterImagePath { dict["posterImagePath"] = posterImagePath }
        if let coverImageURL = item.coverImageURL { dict["coverImageURL"] = coverImageURL }
        if let reason = item.identificationReason { dict["identificationReason"] = reason }
        if let rawProviderPayloadPath = item.rawProviderPayloadPath { dict["rawProviderPayloadPath"] = rawProviderPayloadPath }
        return dict
    }

    private static func mediaIdentificationResultToDict(_ result: MediaIdentificationResult) -> [String: Any] {
        var dict: [String: Any] = [
            "disposition": String(describing: result.disposition),
            "confidence": result.confidence,
            "reason": result.reason,
        ]
        if let candidate = result.candidate {
            dict["candidate"] = [
                "id": candidate.id,
                "type": candidate.type.rawValue,
                "title": candidate.title,
                "canonicalTitle": candidate.canonicalTitle,
                "externalIDs": candidate.externalIDs,
                "confidence": candidate.confidence,
                "reason": candidate.reason,
            ]
        }
        return dict
    }
}
