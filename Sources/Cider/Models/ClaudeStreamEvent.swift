import Foundation
import os.log

/// Parses Claude Code's `--output-format stream-json` stdout lines.
/// Each line is a JSON object with a `type` field.
enum ClaudeStreamEvent {
    case system(sessionID: String?, cwd: String?)
    case assistantText(String)
    case toolUse(name: String, input: String)
    case toolResult(name: String, output: String)
    case result(text: String, costUSD: Double?)
    case unknown(type: String)

    private static let logger = Logger(subsystem: "com.cider.app", category: "ClaudeStreamEvent")

    /// Parse a single JSON line from Claude Code stream output.
    /// Non-JSON lines (e.g. verbose logging) are silently skipped.
    static func parse(_ line: String) -> ClaudeStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Skip empty lines and non-JSON lines (verbose mode outputs plain text)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return nil
            }

            switch type {
            case "system":
                let sessionID = json["session_id"] as? String
                let cwd = json["cwd"] as? String
                return .system(sessionID: sessionID, cwd: cwd)

            case "assistant":
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    let text = content.compactMap { block -> String? in
                        guard block["type"] as? String == "text" else { return nil }
                        return block["text"] as? String
                    }.joined()
                    if !text.isEmpty { return .assistantText(text) }
                }
                return nil

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    return .assistantText(text)
                }
                return nil

            case "tool_use":
                let name = (json["name"] as? String) ?? "unknown"
                let input: String
                if let inputObj = json["input"] {
                    if let inputData = try? JSONSerialization.data(withJSONObject: inputObj, options: .fragmentsAllowed) {
                        input = String(data: inputData, encoding: .utf8) ?? ""
                    } else {
                        input = String(describing: inputObj)
                    }
                } else {
                    input = ""
                }
                return .toolUse(name: name, input: input)

            case "tool_result":
                let name = (json["name"] as? String) ?? "unknown"
                let output = (json["content"] as? String) ?? (json["output"] as? String) ?? ""
                return .toolResult(name: name, output: output)

            case "result":
                let text = (json["result"] as? String) ?? ""
                let costUSD = json["cost_usd"] as? Double
                return .result(text: text, costUSD: costUSD)

            default:
                return .unknown(type: type)
            }
        } catch {
            logger.debug("Failed to parse stream line: \(error.localizedDescription)")
            return nil
        }
    }
}
