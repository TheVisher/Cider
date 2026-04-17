import Foundation

struct TelegramBridgeConfiguration: Codable, Sendable {
    var isEnabled: Bool
    var botToken: String
    var allowedChatIDs: [Int64]
    var allowFirstChatToPair: Bool
    var sendReminders: Bool
    var sendDailyDigest: Bool
    var sendWeeklyDigest: Bool
    var dailyDigestHour: Int
    var dailyDigestWeekdaysOnly: Bool
    var dailyDigestResurfaceCount: Int
    var dailyDigestResurfaceMinAgeDays: Int
    var dailyDigestResurfaceCooldownDays: Int
    var pollingTimeoutSeconds: Int

    static let `default` = TelegramBridgeConfiguration(
        isEnabled: false,
        botToken: "",
        allowedChatIDs: [],
        allowFirstChatToPair: true,
        sendReminders: false,
        sendDailyDigest: true,
        sendWeeklyDigest: true,
        dailyDigestHour: 6,
        dailyDigestWeekdaysOnly: true,
        dailyDigestResurfaceCount: 3,
        dailyDigestResurfaceMinAgeDays: 30,
        dailyDigestResurfaceCooldownDays: 14,
        pollingTimeoutSeconds: 30
    )

    init(
        isEnabled: Bool,
        botToken: String,
        allowedChatIDs: [Int64],
        allowFirstChatToPair: Bool,
        sendReminders: Bool,
        sendDailyDigest: Bool,
        sendWeeklyDigest: Bool,
        dailyDigestHour: Int,
        dailyDigestWeekdaysOnly: Bool,
        dailyDigestResurfaceCount: Int,
        dailyDigestResurfaceMinAgeDays: Int,
        dailyDigestResurfaceCooldownDays: Int,
        pollingTimeoutSeconds: Int
    ) {
        self.isEnabled = isEnabled
        self.botToken = botToken
        self.allowedChatIDs = allowedChatIDs
        self.allowFirstChatToPair = allowFirstChatToPair
        self.sendReminders = sendReminders
        self.sendDailyDigest = sendDailyDigest
        self.sendWeeklyDigest = sendWeeklyDigest
        self.dailyDigestHour = dailyDigestHour
        self.dailyDigestWeekdaysOnly = dailyDigestWeekdaysOnly
        self.dailyDigestResurfaceCount = dailyDigestResurfaceCount
        self.dailyDigestResurfaceMinAgeDays = dailyDigestResurfaceMinAgeDays
        self.dailyDigestResurfaceCooldownDays = dailyDigestResurfaceCooldownDays
        self.pollingTimeoutSeconds = pollingTimeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        botToken = try container.decodeIfPresent(String.self, forKey: .botToken) ?? ""
        allowedChatIDs = try container.decodeIfPresent([Int64].self, forKey: .allowedChatIDs) ?? []
        allowFirstChatToPair = try container.decodeIfPresent(Bool.self, forKey: .allowFirstChatToPair) ?? true
        sendReminders = try container.decodeIfPresent(Bool.self, forKey: .sendReminders) ?? false
        sendDailyDigest = try container.decodeIfPresent(Bool.self, forKey: .sendDailyDigest) ?? true
        sendWeeklyDigest = try container.decodeIfPresent(Bool.self, forKey: .sendWeeklyDigest) ?? true
        dailyDigestHour = try container.decodeIfPresent(Int.self, forKey: .dailyDigestHour) ?? 6
        dailyDigestWeekdaysOnly = try container.decodeIfPresent(Bool.self, forKey: .dailyDigestWeekdaysOnly) ?? true
        dailyDigestResurfaceCount = try container.decodeIfPresent(Int.self, forKey: .dailyDigestResurfaceCount) ?? 3
        dailyDigestResurfaceMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .dailyDigestResurfaceMinAgeDays) ?? 30
        dailyDigestResurfaceCooldownDays = try container.decodeIfPresent(Int.self, forKey: .dailyDigestResurfaceCooldownDays) ?? 14
        pollingTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .pollingTimeoutSeconds) ?? 30
    }
}

struct TelegramBridgeState: Codable, Sendable {
    var lastProcessedUpdateID: Int
    var deliveredReminderIDs: Set<String>
    var deliveredDailyDigestKeys: Set<String>
    var deliveredWeeklyDigestKeys: Set<String>
    var resurfacedItemDates: [String: Date]

    static let `default` = TelegramBridgeState(
        lastProcessedUpdateID: 0,
        deliveredReminderIDs: [],
        deliveredDailyDigestKeys: [],
        deliveredWeeklyDigestKeys: [],
        resurfacedItemDates: [:]
    )

    init(
        lastProcessedUpdateID: Int,
        deliveredReminderIDs: Set<String>,
        deliveredDailyDigestKeys: Set<String>,
        deliveredWeeklyDigestKeys: Set<String>,
        resurfacedItemDates: [String: Date]
    ) {
        self.lastProcessedUpdateID = lastProcessedUpdateID
        self.deliveredReminderIDs = deliveredReminderIDs
        self.deliveredDailyDigestKeys = deliveredDailyDigestKeys
        self.deliveredWeeklyDigestKeys = deliveredWeeklyDigestKeys
        self.resurfacedItemDates = resurfacedItemDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastProcessedUpdateID = try container.decodeIfPresent(Int.self, forKey: .lastProcessedUpdateID) ?? 0
        deliveredReminderIDs = try container.decodeIfPresent(Set<String>.self, forKey: .deliveredReminderIDs) ?? []
        deliveredDailyDigestKeys = try container.decodeIfPresent(Set<String>.self, forKey: .deliveredDailyDigestKeys) ?? []
        deliveredWeeklyDigestKeys = try container.decodeIfPresent(Set<String>.self, forKey: .deliveredWeeklyDigestKeys) ?? []
        resurfacedItemDates = try container.decodeIfPresent([String: Date].self, forKey: .resurfacedItemDates) ?? [:]
    }
}

struct TelegramUpdateEnvelope: Sendable {
    let updateID: Int
    let chatID: Int64
    let senderID: Int64
    let senderDisplayName: String?
    let text: String
}
