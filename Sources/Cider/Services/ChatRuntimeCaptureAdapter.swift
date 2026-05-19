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
        guard let captureText = explicitCaptureText(from: text, hasLocalAttachments: !attachments.isEmpty) else {
            return nil
        }
        let chatID = String(update.chatID)
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
            metadata: [
                "runtime": "telegram",
                "source_update_id": String(update.updateID),
            ]
        )
    }

    private static func explicitCaptureText(from text: String, hasLocalAttachments: Bool) -> String? {
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
                return hasLocalAttachments ? "" : nil
            }
            return trimmed
        }
        if hasLocalAttachments,
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
        text
            .components(separatedBy: .newlines)
            .compactMap { line -> ChatAttachment? in
                let marker = "Local image copy:"
                guard line.localizedCaseInsensitiveContains(marker),
                      let markerRange = line.range(of: marker, options: .caseInsensitive) else {
                    return nil
                }
                let path = line[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { return nil }
                return ChatAttachment(
                    id: nil,
                    filename: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path,
                    remoteURL: nil
                )
            }
    }
}
