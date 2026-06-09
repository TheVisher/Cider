import Foundation

struct ChatCaptureChannel: RawRepresentable, Codable, Equatable, Sendable {
    var rawValue: String

    static let telegram = ChatCaptureChannel(rawValue: "telegram")!
    static let discord = ChatCaptureChannel(rawValue: "discord")!
    static let iMessage = ChatCaptureChannel(rawValue: "imessage")!

    init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        self.rawValue = normalized
    }
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

struct ChatCaptureIntakeResult: @unchecked Sendable {
    enum Status: String, Equatable {
        case captured
        case needsReview
    }

    var status: Status
    var reason: String
    var captureResult: CiderCaptureResult?
    var captureResults: [CiderCaptureResult] = []
    var captureEventID: UUID? = nil
    var safeNextCommands: [String] = []
}

extension ChatCaptureIntakeResult {
    var compactAcknowledgement: String {
        switch status {
        case .captured:
            return capturedAcknowledgement
        case .needsReview:
            return reviewAcknowledgement
        }
    }

    private var capturedAcknowledgement: String {
        let results = captureResults.isEmpty
            ? captureResult.map { [$0] } ?? []
            : captureResults
        guard let first = results.first else {
            return "Saved to Cider."
        }

        if results.count > 1 {
            let type = pluralItemType(for: first.item.type, count: results.count)
            let firstTitle = sanitized(first.item.title, fallback: "Untitled")
            var acknowledgement = "Saved \(results.count) \(type). First: \(firstTitle). Review each receipt if routing looks off."
            if let attachmentReviewSentence {
                acknowledgement += " \(attachmentReviewSentence)"
            }
            return acknowledgement
        }

        let receipt = UICaptureReceipt(result: first)
        var parts: [String] = []
        let type = itemTypeLabel(for: receipt.item.type)
        let title = sanitized(receipt.item.title, fallback: "Untitled")

        switch receipt.state {
        case .duplicate:
            parts.append("Duplicate \(type): \(title).")
        case .savedWithReview:
            parts.append("Saved \(type): \(title).")
            parts.append("Needs review: \(sanitized(receipt.routing.reason, fallback: receipt.safeNextActionLabel)).")
        case .partialSideEffects:
            parts.append("Saved \(type): \(title).")
            parts.append("Partial save: \(partialReason(for: receipt)).")
        case .saved:
            parts.append("Saved \(type): \(title).")
        case .failed:
            parts.append("Could not save \(type): \(title).")
        }

        if let destination = receipt.item.relativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !destination.isEmpty,
           receipt.state != .duplicate {
            parts.insert("\(destination).", at: min(1, parts.count))
        }
        if let attachmentReviewSentence {
            parts.append(attachmentReviewSentence)
        }

        return parts.joined(separator: " ")
    }

    private var reviewAcknowledgement: String {
        if let captureEventID {
            var parts = ["Needs review: unsupported chat attachment recorded.", "Event: \(captureEventID.uuidString)."]
            if let command = safeNextCommands.first {
                parts.append("Next: \(command)")
            }
            return parts.joined(separator: " ")
        }

        return "Needs review: \(sentence(reason))"
    }

    private var attachmentReviewSentence: String? {
        guard captureEventID != nil else { return nil }
        var parts = ["Attachment review needed."]
        if let command = safeNextCommands.first {
            parts.append("Next: \(command)")
        }
        return parts.joined(separator: " ")
    }

    private func partialReason(for receipt: UICaptureReceipt) -> String {
        let reason = [
            receipt.indexing.reason,
            receipt.provenance.reason,
            receipt.routing.statusReason,
            receipt.routing.reason,
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return sentence(reason ?? receipt.safeNextActionLabel)
    }

    private func sentence(_ value: String) -> String {
        let trimmed = sanitized(value, fallback: "Review needed")
        return trimmed.hasSuffix(".") ? trimmed : "\(trimmed)."
    }

    private func sanitized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func itemTypeLabel(for type: String?) -> String {
        switch type {
        case "bookmark":
            return "bookmark"
        case "note":
            return "note"
        case "todo":
            return "todo"
        case "dateCard":
            return "event"
        case "contact":
            return "contact"
        case "vaultFile":
            return "file"
        default:
            return "item"
        }
    }

    private func pluralItemType(for type: String?, count: Int) -> String {
        let singular = itemTypeLabel(for: type)
        guard count != 1 else { return singular }
        switch singular {
        case "todo":
            return "todos"
        default:
            return "\(singular)s"
        }
    }
}

@MainActor
final class ChatCaptureIntakeService {
    private let captureService: CiderCaptureService
    private let database: CiderDatabase?

    init(captureService: CiderCaptureService = CiderCaptureService(), database: CiderDatabase? = nil) {
        self.captureService = captureService
        self.database = database
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
                captureResult: result,
                captureResults: [result]
            )
        }

        let localAttachments = input.attachments.compactMap { attachment -> (ChatAttachment, String)? in
            guard let localPath = attachment.localPath?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            return localPath.isEmpty ? nil : (attachment, localPath)
        }
        if !localAttachments.isEmpty {
            let unsupportedAttachments = unsupportedAttachments(from: input.attachments)
            let results = try localAttachments.map { attachment, localPath in
                try captureService.addFileCapture(
                    sourcePath: localPath,
                    title: attachment.filename,
                    folderID: nil,
                    sourceContext: sourceContext(for: input)
                )
            }
            let reviewEventID: UUID?
            if unsupportedAttachments.isEmpty {
                reviewEventID = nil
            } else {
                var reviewInput = input
                reviewInput.attachments = unsupportedAttachments
                reviewEventID = try recordUnsupportedAttachmentReview(for: reviewInput)
            }
            let safeNextCommands = reviewEventID.map {
                ["cider-cli item backlinks capture_event \($0.uuidString) --json"]
            } ?? []
            return ChatCaptureIntakeResult(
                status: .captured,
                reason: localAttachments.count == 1
                    ? "Captured local chat attachment through canonical capture service."
                    : "Captured \(localAttachments.count) local chat attachments through canonical capture service.",
                captureResult: results.first,
                captureResults: results,
                captureEventID: reviewEventID,
                safeNextCommands: safeNextCommands
            )
        }

        if !input.attachments.isEmpty {
            let reviewEventID = try recordUnsupportedAttachmentReview(for: input)
            return ChatCaptureIntakeResult(
                status: .needsReview,
                reason: "Chat message contains unsupported attachment content without a local file path; Cider recorded it for review.",
                captureResult: nil,
                captureEventID: reviewEventID,
                safeNextCommands: reviewEventID.map {
                    ["cider-cli item backlinks capture_event \($0.uuidString) --json"]
                } ?? []
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

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    private func unsupportedAttachments(from attachments: [ChatAttachment]) -> [ChatAttachment] {
        attachments.filter { attachment in
            let localPath = attachment.localPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return localPath.isEmpty
        }
    }

    private func recordUnsupportedAttachmentReview(for input: ChatCaptureInput) throws -> UUID? {
        guard let db = resolvedDatabase, db.isOpen else {
            return nil
        }

        let eventID = UUID()
        let context = sourceContext(for: input)
        let metadata = DatabaseHelpers.encodeJSON(reviewMetadata(for: input)) ?? "{}"
        try db.withTransaction {
            let stmt = try db.prepare("""
                INSERT INTO capture_events (
                    id, source_kind, surface, channel, channel_id, thread_id, message_id,
                    sender_id, sender_name, source_url, source_file, source_text,
                    attachment_count, metadata, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            stmt.bind(eventID.uuidString, at: 1)
                .bind("chat_unsupported_attachment", at: 2)
                .bind(context.surface, at: 3)
                .bind(context.channel, at: 4)
                .bind(context.channelID, at: 5)
                .bind(context.threadID, at: 6)
                .bind(context.messageID, at: 7)
                .bind(context.senderID, at: 8)
                .bind(context.senderName, at: 9)
                .bind(nil as String?, at: 10)
                .bind(nil as String?, at: 11)
                .bind(context.originalText, at: 12)
                .bind(context.attachments.count, at: 13)
                .bind(metadata, at: 14)
                .bind(DatabaseHelpers.encode(Date()), at: 15)
            try stmt.step()

            try persistUnsupportedReviewAttachments(
                context.attachments,
                eventID: eventID,
                database: db
            )
        }

        try SecondBrainEnrichmentOutputService(database: db).record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString),
            kind: "unsupported_chat_attachment",
            value: unsupportedAttachmentValue(for: input),
            normalizedValue: "chat_unsupported_attachments:\(eventID.uuidString.lowercased())",
            label: "Unsupported chat attachment",
            evidence: "Chat capture included attachment metadata without a local file path.",
            source: "chat.capture",
            confidence: 1,
            reviewState: "needs_review",
            metadata: reviewMetadata(for: input)
        ))

        return eventID
    }

    private func persistUnsupportedReviewAttachments(
        _ attachments: [CaptureSourceContext.Attachment],
        eventID: UUID,
        database: CiderDatabase
    ) throws {
        let now = DatabaseHelpers.encode(Date())
        let store = SecondBrainStore(database: database)
        let captureOwner = SecondBrainOwnerRef(
            ownerType: "capture_event",
            ownerID: eventID.uuidString
        )
        for (index, attachment) in attachments.enumerated() {
            let attachmentID = UUID()
            let metadata = DatabaseHelpers.encodeJSON([
                "capture_event_id": eventID.uuidString,
                "attachment_index": String(index),
                "review_state": "needs_review",
            ]) ?? "{}"
            let stmt = try database.prepare("""
                INSERT INTO capture_attachments (
                    id, capture_event_id, attachment_index, source_attachment_id,
                    filename, mime_type, local_path, remote_url, byte_size,
                    metadata, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            stmt.bind(attachmentID.uuidString, at: 1)
                .bind(eventID.uuidString, at: 2)
                .bind(index, at: 3)
                .bind(attachment.id, at: 4)
                .bind(attachment.filename, at: 5)
                .bind(attachment.mimeType, at: 6)
                .bind(attachment.localPath, at: 7)
                .bind(attachment.remoteURL, at: 8)
                .bind(nil as Int64?, at: 9)
                .bind(metadata, at: 10)
                .bind(now, at: 11)
            try stmt.step()

            let attachmentOwner = SecondBrainOwnerRef(
                ownerType: "capture_attachment",
                ownerID: attachmentID.uuidString
            )
            try store.recordRelation(SecondBrainRelation(
                sourceOwner: captureOwner,
                targetOwner: attachmentOwner,
                relationType: "had_attachment",
                evidence: attachment.filename.map { "Unsupported chat capture attachment \($0) needs review." }
                    ?? "Unsupported chat capture attachment needs review.",
                source: "chat.capture",
                actor: "system",
                confidence: 1,
                metadata: unsupportedAttachmentRelationMetadata(
                    attachment: attachment,
                    eventID: eventID,
                    attachmentIndex: index
                )
            ))
        }
    }

    private func unsupportedAttachmentRelationMetadata(
        attachment: CaptureSourceContext.Attachment,
        eventID: UUID,
        attachmentIndex: Int
    ) -> [String: String] {
        var metadata: [String: String] = [
            "capture_event_id": eventID.uuidString,
            "attachment_index": String(attachmentIndex),
            "review_state": "needs_review",
        ]
        if let id = attachment.id { metadata["source_attachment_id"] = id }
        if let filename = attachment.filename { metadata["filename"] = filename }
        if let mimeType = attachment.mimeType { metadata["mime_type"] = mimeType }
        if let remoteURL = attachment.remoteURL { metadata["remote_url"] = remoteURL }
        return metadata
    }

    private func unsupportedAttachmentValue(for input: ChatCaptureInput) -> String {
        input.attachments
            .enumerated()
            .map { index, attachment in
                attachment.filename
                    ?? attachment.remoteURL
                    ?? attachment.id
                    ?? "attachment-\(index + 1)"
            }
            .joined(separator: ", ")
    }

    private func reviewMetadata(for input: ChatCaptureInput) -> [String: String] {
        var metadata = input.metadata
        metadata["reason"] = "unsupported_chat_attachment"
        metadata["attachmentCount"] = String(input.attachments.count)
        if let messageID = input.messageID { metadata["messageID"] = messageID }
        if let channelID = input.channelID { metadata["channelID"] = channelID }
        metadata["channel"] = input.channel.rawValue
        return metadata
    }
}
