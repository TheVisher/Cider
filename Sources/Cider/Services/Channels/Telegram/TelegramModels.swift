import Foundation

struct TelegramBridgeConfiguration: Codable, Sendable {
    var isEnabled: Bool
    var botToken: String
    var allowedChatIDs: [Int64]
    var allowFirstChatToPair: Bool
    var sendReminders: Bool
    var pollingTimeoutSeconds: Int

    static let `default` = TelegramBridgeConfiguration(
        isEnabled: false,
        botToken: "",
        allowedChatIDs: [],
        allowFirstChatToPair: true,
        sendReminders: false,
        pollingTimeoutSeconds: 30
    )
}

struct TelegramBridgeState: Codable, Sendable {
    var lastProcessedUpdateID: Int
    var deliveredReminderIDs: Set<String>

    static let `default` = TelegramBridgeState(
        lastProcessedUpdateID: 0,
        deliveredReminderIDs: []
    )
}

struct TelegramUpdateEnvelope: Sendable {
    let updateID: Int
    let chatID: Int64
    let senderID: Int64
    let senderDisplayName: String?
    let text: String
}
