import Foundation

enum CiderAgentDecisionContract {
    static func dictionary(
        saved: Bool = true,
        needsReview: Bool,
        needsEnrichment: Bool = false,
        needsRouting: Bool = false,
        confidence: Double? = nil,
        blockingIssues: [String] = [],
        recommendedNextAction: String? = nil,
        safeNextCommands: [String] = [],
        humanQuestion: String? = nil
    ) -> [String: Any] {
        let requiresHumanReview = needsReview
        let useful = saved
            && !needsReview
            && !needsEnrichment
            && !needsRouting
            && blockingIssues.isEmpty
        let action = recommendedNextAction ?? defaultRecommendedAction(
            needsReview: needsReview,
            needsEnrichment: needsEnrichment,
            needsRouting: needsRouting
        )
        var dict: [String: Any] = [
            "saved": saved,
            "useful": useful,
            "needsReview": needsReview,
            "requiresHumanReview": requiresHumanReview,
            "needsEnrichment": needsEnrichment,
            "needsRouting": needsRouting,
            "agentMayRoute": !requiresHumanReview,
            "blockingIssues": orderedUnique(blockingIssues),
            "recommendedNextAction": action,
            "nextActions": [nextActionDictionary(action: action, requiresHumanReview: requiresHumanReview)],
            "safeNextCommands": safeNextCommands,
        ]
        if let confidence {
            dict["confidence"] = confidence
        }
        if let humanQuestion {
            dict["humanQuestion"] = humanQuestion
        } else if requiresHumanReview {
            dict["humanQuestion"] = needsRouting
                ? "Which destination should this item be routed to?"
                : "What should happen next for this unresolved item?"
        }
        return dict
    }

    static func merge(_ decision: [String: Any], into dict: inout [String: Any]) {
        for (key, value) in decision {
            dict[key] = value
        }
    }

    static func defaultRecommendedAction(
        needsReview: Bool,
        needsEnrichment: Bool,
        needsRouting: Bool
    ) -> String {
        if needsReview { return "review_route" }
        if needsEnrichment { return "enrich" }
        if needsRouting { return "route_item" }
        return "inspect_item"
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func nextActionDictionary(action: String, requiresHumanReview: Bool) -> [String: Any] {
        let readOnlyActions = Set(["inspect_item", "review_route", "inspect_existing_item"])
        let readOnly = readOnlyActions.contains(action)
        var dict: [String: Any] = [
            "action": action,
            "readOnly": readOnly,
            "requiresApproval": requiresHumanReview || !readOnly,
        ]
        if !readOnly {
            dict["mutationReason"] = "This action may change capture, routing, enrichment, or review state."
        }
        return dict
    }
}
