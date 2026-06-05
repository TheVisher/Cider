import Foundation

struct DiscordAttachmentEnvelope: Sendable {
    let id: String
    let filename: String?
    let mimeType: String?
    let localPath: String?
    let remoteURL: String?
    let downloadFailedReason: String?

    init(
        id: String,
        filename: String? = nil,
        mimeType: String? = nil,
        localPath: String? = nil,
        remoteURL: String? = nil,
        downloadFailedReason: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.downloadFailedReason = downloadFailedReason
    }
}

struct DiscordUpdateEnvelope: Sendable {
    let messageID: String
    let channelID: String
    let threadID: String?
    let senderID: String
    let senderDisplayName: String?
    let text: String
    let attachments: [DiscordAttachmentEnvelope]

    init(
        messageID: String,
        channelID: String,
        threadID: String? = nil,
        senderID: String,
        senderDisplayName: String? = nil,
        text: String,
        attachments: [DiscordAttachmentEnvelope] = []
    ) {
        self.messageID = messageID
        self.channelID = channelID
        self.threadID = threadID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.text = text
        self.attachments = attachments
    }
}
