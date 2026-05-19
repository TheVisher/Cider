import Foundation

enum ChatCaptureChannel: String, Codable, Equatable, Sendable {
    case telegram
    case discord
}

enum ChatCaptureIntent: String, Codable, Equatable, Sendable {
    case capture
    case ask
}

struct ChatAttachment: Codable, Equatable, Sendable {
    var id: String?
    var filename: String?
    var mimeType: String?
    var localPath: String?
    var remoteURL: String?
}

struct ChatCaptureInput: Codable, Equatable, Sendable {
    var channel: ChatCaptureChannel
    var channelID: String?
    var threadID: String?
    var messageID: String?
    var senderID: String?
    var senderName: String?
    var text: String
    var attachments: [ChatAttachment] = []
    var intent: ChatCaptureIntent
    var metadata: [String: String] = [:]
}

struct ChatCaptureIntakeResult {
    enum Status: String, Equatable {
        case captured
        case needsReview
    }

    var status: Status
    var reason: String
    var captureResult: CiderCaptureResult?
}

@MainActor
final class ChatCaptureIntakeService {
    private let captureService: CiderCaptureService

    init(captureService: CiderCaptureService = CiderCaptureService()) {
        self.captureService = captureService
    }

    func capture(_ input: ChatCaptureInput) throws -> ChatCaptureIntakeResult {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.intent == .capture else {
            return ChatCaptureIntakeResult(
                status: .needsReview,
                reason: "Chat message is not an explicit capture intent.",
                captureResult: nil
            )
        }
        if !text.isEmpty {
            let result = try captureService.add(
                text,
                title: nil,
                folderID: nil,
                sourceContext: sourceContext(for: input, text: text)
            )
            return ChatCaptureIntakeResult(
                status: .captured,
                reason: "Captured through canonical capture service.",
                captureResult: result
            )
        }

        if let localAttachment = input.attachments.first(where: { attachment in
            guard let localPath = attachment.localPath?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !localPath.isEmpty
        }), let localPath = localAttachment.localPath {
            let result = try captureService.addFileCapture(
                sourcePath: localPath,
                title: localAttachment.filename,
                folderID: nil,
                sourceContext: sourceContext(for: input)
            )
            return ChatCaptureIntakeResult(
                status: .captured,
                reason: "Captured local chat attachment through canonical capture service.",
                captureResult: result
            )
        }

        if !input.attachments.isEmpty {
            return ChatCaptureIntakeResult(
                status: .needsReview,
                reason: "Chat message contains unsupported attachment content without a local file path.",
                captureResult: nil
            )
        }

        return ChatCaptureIntakeResult(
            status: .needsReview,
            reason: "No captureable text or supported attachment content was provided.",
            captureResult: nil
        )
    }

    func sourceContext(for input: ChatCaptureInput, text: String? = nil) -> CaptureSourceContext {
        CaptureSourceContext(
            surface: "chat",
            channel: input.channel.rawValue,
            channelID: input.channelID,
            threadID: input.threadID,
            messageID: input.messageID,
            senderID: input.senderID,
            senderName: input.senderName,
            originalText: text ?? input.text,
            attachments: input.attachments.map { attachment in
                CaptureSourceContext.Attachment(
                    id: attachment.id,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    localPath: attachment.localPath,
                    remoteURL: attachment.remoteURL
                )
            },
            metadata: input.metadata
        )
    }
}
