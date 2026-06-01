import Foundation

enum ChatRuntimeCaptureAdapter {
    @MainActor
    static func captureIfNeeded(
        fromTelegram update: TelegramUpdateEnvelope,
        intakeService: ChatCaptureIntakeService = ChatCaptureIntakeService()
    ) throws -> ChatCaptureIntakeResult? {
        guard let input = input(fromTelegram: update) else { return nil }
        return try intakeService.capture(input)
    }

    static func input(fromTelegram update: TelegramUpdateEnvelope) -> ChatCaptureInput? {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = telegramAttachments(from: text)
        guard let captureText = explicitCaptureText(from: text, hasAttachments: !attachments.isEmpty) else {
            return nil
        }
        let chatID = String(update.chatID)
        var metadata = [
            "runtime": "telegram",
            "source_update_id": String(update.updateID),
        ]
        if text.localizedCaseInsensitiveContains("Image download failed") {
            metadata["attachment_failure_reason"] = "telegram_image_download_failed"
        }
        return ChatCaptureInput(
            channel: .telegram,
            channelID: chatID,
            threadID: chatID,
            messageID: "telegram:\(update.updateID)",
            senderID: String(update.senderID),
            senderName: update.senderDisplayName,
            text: captureText,
            attachments: attachments,
            intent: .capture,
            metadata: metadata
        )
    }

    private static func explicitCaptureText(from text: String, hasAttachments: Bool) -> String? {
        let normalized = text.lowercased()
        let prefixes = [
            "save this",
            "save that",
            "capture this",
            "add this",
            "bookmark this",
        ]
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            let index = text.index(text.startIndex, offsetBy: prefix.count)
            let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            let trimmed = String(text[index...]).trimmingCharacters(in: trimSet)
            if trimmed.isEmpty {
                return hasAttachments ? "" : nil
            }
            return trimmed
        }
        if hasAttachments,
           ["caption: save", "caption: capture", "caption: add", "caption: bookmark"].contains(where: normalized.contains) {
            return ""
        }
        guard normalized.contains("http://") || normalized.contains("https://") || normalized.contains("www.") else {
            return nil
        }
        guard ["save", "capture", "bookmark", "add"].contains(where: normalized.contains) else {
            return nil
        }
        return text
    }

    private static func telegramAttachments(from text: String) -> [ChatAttachment] {
        let lines = text.components(separatedBy: .newlines)
        var pendingTelegramFileID: String?
        var attachments: [ChatAttachment] = []

        for line in lines {
            if let fileID = value(after: "Telegram image file_id:", in: line) {
                pendingTelegramFileID = fileID
                continue
            }

            if let path = value(after: "Local image copy:", in: line) {
                guard !path.isEmpty else { continue }
                attachments.append(ChatAttachment(
                    id: pendingTelegramFileID,
                    filename: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path,
                    remoteURL: nil
                ))
                pendingTelegramFileID = nil
            } else if line.localizedCaseInsensitiveContains("Image download failed"),
                      let fileID = pendingTelegramFileID,
                      !fileID.isEmpty {
                attachments.append(ChatAttachment(
                    id: fileID,
                    filename: nil,
                    mimeType: "image/jpeg",
                    localPath: nil,
                    remoteURL: nil
                ))
                pendingTelegramFileID = nil
            }
        }

        return attachments
    }

    private static func value(after marker: String, in line: String) -> String? {
        guard line.localizedCaseInsensitiveContains(marker),
              let markerRange = line.range(of: marker, options: .caseInsensitive) else {
            return nil
        }
        let value = line[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
