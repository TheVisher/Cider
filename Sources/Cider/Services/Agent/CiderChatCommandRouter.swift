import Foundation

struct CiderChatCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case localMessage(String)
        case showStatus
        case showLastResponse
        case resume(title: String)
        case sendToHermes(String)
        case startFreshChat
        case renameCurrentChat(String)
    }

    let name: String
    let argument: String?
    let action: Action
}

enum CiderChatCommandRouter {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case unsupportedCommand(String)
        case missingArgument(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedCommand(let command):
                return "Unknown Cider command: /\(command). Try /help."
            case .missingArgument(let command):
                return "Missing argument for /\(command). Try /help."
            }
        }
    }

    static let canonicalCiderTitle = "Cider"

    static func parse(_ text: String) throws -> CiderChatCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let body = String(trimmed.dropFirst())
        let parts = body.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let rawName = parts.first else {
            throw Error.unsupportedCommand("")
        }

        let name = rawName.lowercased()
        let argument = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let normalizedArgument = argument?.isEmpty == false ? argument : nil

        switch name {
        case "help":
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .localMessage(helpMessage)
            )
        case "status":
            return CiderChatCommand(name: name, argument: normalizedArgument, action: .showStatus)
        case "resume":
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .resume(title: normalizedArgument ?? canonicalCiderTitle)
            )
        case "last":
            return CiderChatCommand(name: name, argument: normalizedArgument, action: .showLastResponse)
        case "summary":
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .sendToHermes(summaryPrompt)
            )
        case "checkpoint":
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .sendToHermes(checkpointPrompt)
            )
        case "new":
            if normalizedArgument?.lowercased() == "confirm" {
                return CiderChatCommand(name: name, argument: normalizedArgument, action: .startFreshChat)
            }
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .localMessage(newConfirmationMessage)
            )
        case "title":
            guard let normalizedArgument else {
                throw Error.missingArgument(name)
            }
            return CiderChatCommand(
                name: name,
                argument: normalizedArgument,
                action: .renameCurrentChat(normalizedArgument)
            )
        default:
            throw Error.unsupportedCommand(name)
        }
    }

    private static let helpMessage = """
    Cider commands:
    /status - show the current Hermes connection
    /resume [title] - resume Cider or another named Hermes chat
    /last - show the last cached assistant response
    /summary - ask Hermes for a concise chat summary
    /checkpoint - ask Hermes to save durable context
    /new - start a fresh chat after confirmation
    /title <title> - rename a side chat
    """

    private static let summaryPrompt = """
    Please summarize the current Cider chat in a concise, useful way. Focus on decisions, open loops, and next actions.
    """

    private static let checkpointPrompt = """
    Please checkpoint the durable decisions, context, and next actions from this Cider chat. Keep it concise and avoid creating extra docs unless needed.
    """

    private static let newConfirmationMessage = """
    Starting fresh will leave the current Cider brain intact. Send /new confirm to start a separate fresh Hermes chat.
    """
}
