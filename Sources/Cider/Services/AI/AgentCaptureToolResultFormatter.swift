import Foundation

enum AgentCaptureToolResultFormatter {
    @MainActor
    static func jsonString(
        message: String,
        captureResult: CiderCaptureResult,
        finalBookmark: Bookmark? = nil,
        additionalPartialFailures: [[String: Any]] = []
    ) -> String {
        let captureDict = finalBookmark == nil
            ? captureResult.toDictionary()
            : captureResult.toDictionary(finalBookmark: finalBookmark)
        var itemDict = (captureDict["item"] as? [String: Any]) ?? [:]
        if let itemID = itemDict["id"] as? String,
           let itemType = itemDict["type"] as? String {
            itemDict["ref"] = "\(itemType):\(itemID)"
        }

        var partialFailures: [[String: Any]] = []
        if let partialSuccess = captureDict["partialSuccess"] as? [String: Any] {
            partialFailures.append(partialSuccess)
        }
        partialFailures.append(contentsOf: additionalPartialFailures)

        var payload: [String: Any] = [
            "toolResultVersion": 1,
            "kind": "capture",
            "ok": partialFailures.isEmpty,
            "message": message,
            "item": itemDict,
            "duplicate": captureDict["duplicate"] as? [String: Any] ?? [:],
            "routing": captureDict["routing"] as? [String: Any] ?? [:],
            "partialFailures": partialFailures,
            "nextSafeAction": captureResult.nextSafeAction,
            "capture": captureDict,
        ]
        if let captureEventID = captureDict["captureEventID"] {
            payload["captureEventID"] = captureEventID
        }
        if let captureEventOwner = captureDict["captureEventOwner"] {
            payload["captureEventOwner"] = captureEventOwner
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return message
        }
        return json
    }

    static func partialFailure(status: String, reason: String) -> [String: Any] {
        [
            "status": status,
            "reason": reason,
        ]
    }
}
