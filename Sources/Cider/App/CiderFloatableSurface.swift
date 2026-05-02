import Foundation

enum CiderFloatableSurface: Hashable, Identifiable, Sendable {
    case note(UUID)
    case bookmark(UUID)
    case bookmarkMetadata(UUID)
    case contact(UUID)
    case dateCard(UUID)
    case todo(UUID)
    case vaultFile(UUID)
    case clipboard
    case aiAssistant
    case dropZone

    var id: String { stableKey }

    var stableKey: String {
        switch self {
        case .note(let id):
            "note:\(id.uuidString)"
        case .bookmark(let id):
            "bookmark:\(id.uuidString)"
        case .bookmarkMetadata(let id):
            "bookmarkMetadata:\(id.uuidString)"
        case .contact(let id):
            "contact:\(id.uuidString)"
        case .dateCard(let id):
            "dateCard:\(id.uuidString)"
        case .todo(let id):
            "todo:\(id.uuidString)"
        case .vaultFile(let id):
            "vaultFile:\(id.uuidString)"
        case .clipboard:
            "clipboard"
        case .aiAssistant:
            "aiAssistant"
        case .dropZone:
            "dropZone"
        }
    }

    var defaultTitle: String {
        switch self {
        case .note:
            "Note"
        case .bookmark:
            "Bookmark"
        case .bookmarkMetadata:
            "Bookmark Metadata"
        case .contact:
            "Contact"
        case .dateCard:
            "Date Card"
        case .todo:
            "Todo"
        case .vaultFile:
            "File"
        case .clipboard:
            "Clipboard"
        case .aiAssistant:
            "Chat"
        case .dropZone:
            "Drop Zone"
        }
    }

    var fallbackDescription: String {
        switch self {
        case .note(let id),
             .bookmark(let id),
             .bookmarkMetadata(let id),
             .contact(let id),
             .dateCard(let id),
             .todo(let id),
             .vaultFile(let id):
            id.uuidString
        case .clipboard:
            "Floating clipboard surface"
        case .aiAssistant:
            "Floating AI assistant surface"
        case .dropZone:
            "Drop files, links, text, or images here"
        }
    }
}

extension CiderFloatableSurface {
    init?(linkedRef ref: LibraryEntityRef) {
        switch ref.type {
        case .note:
            self = .note(ref.entityID)
        case .bookmark:
            self = .bookmarkMetadata(ref.entityID)
        case .contact:
            self = .contact(ref.entityID)
        case .dateCard:
            self = .dateCard(ref.entityID)
        case .todo:
            self = .todo(ref.entityID)
        case .vaultFile:
            self = .vaultFile(ref.entityID)
        case .externalFile, .session:
            return nil
        }
    }
}
