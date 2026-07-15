import Foundation

enum ConversationAttachmentInputSource: String, Codable, Equatable, Sendable {
    case filePicker = "file_picker"
    case dragAndDrop = "drag_and_drop"

    var displayName: String {
        switch self {
        case .filePicker: "Picked file"
        case .dragAndDrop: "Dropped file"
        }
    }
}

enum ConversationAttachmentKind: String, Codable, Equatable, Sendable {
    case text
    case image
}

enum ConversationAttachmentTransportCapability: Equatable, Sendable {
    case supported
    case unsupported(reason: String)
}

struct ConversationStagedAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let vaultFileID: UUID
    let displayName: String
    let kind: ConversationAttachmentKind
    let contentType: String
    let byteSize: Int64
    let sha256: String
    let inputSource: ConversationAttachmentInputSource
    let provenance: String
    let textPreview: String?
    let imagePreviewData: Data?
    let sourceURL: URL
    let validatedMetadata: LocalFileValidatedMetadata
}

struct ConversationAttachmentTransportPayload: Equatable, Sendable {
    let id: UUID
    let displayName: String
    let contentType: String
    let byteSize: Int64
    let sha256: String
    let data: Data
}

struct ConversationAcceptedAttachment: Equatable, Sendable {
    let fact: HermesCiderAttachment
    let payload: ConversationAttachmentTransportPayload
}

enum ConversationAttachmentInputError: Error, Equatable, LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let reason): reason
        }
    }
}
