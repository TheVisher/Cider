import CoreGraphics
import Foundation

enum LibraryDisplayMode: String, Codable, CaseIterable {
    case list
    case grid
    case masonry

    var displayName: String {
        switch self {
        case .list:
            "List"
        case .grid:
            "Grid"
        case .masonry:
            "Masonry"
        }
    }

    var icon: String {
        switch self {
        case .list:
            "list.bullet"
        case .grid:
            "square.grid.2x2"
        case .masonry:
            "rectangle.grid.1x2"
        }
    }
}

struct LibraryCardSizing {
    let scale: Double

    var cardMinWidth: CGFloat { interpolate(196, 240, 340, 520) }
    var gridThumbnailHeight: CGFloat { interpolate(124, 160, 220, 360) }
    var masonryThumbnailHeightFallback: CGFloat { interpolate(154, 200, 300, 420) }
    var listThumbnailWidth: CGFloat { interpolate(60, 80, 120, 180) }
    var listThumbnailHeight: CGFloat { interpolate(44, 60, 88, 130) }
    /// Minimum card width for notes (text-forward, wider)
    var noteCardMinWidth: CGFloat { interpolate(200, 250, 350, 520) }
    /// Text preview area height in grid mode for notes
    var notePreviewHeight: CGFloat { interpolate(80, 100, 140, 200) }
    /// Side image width in note cards
    var noteImageWidth: CGFloat { interpolate(60, 80, 110, 160) }
    /// Square thumbnail size in note list rows
    var noteListImageSize: CGFloat { interpolate(36, 44, 56, 72) }

    var isExtraLarge: Bool { scale > 2.5 }

    /// Bookmark-compatible CardSizing (for BookmarkCard / BookmarkListRow)
    var bookmarkSizing: CardSizing {
        CardSizing(scale: scale)
    }

    /// Note-compatible NoteCardSizing (for NoteCardView / NoteListRow)
    var noteSizing: NoteCardSizing {
        NoteCardSizing(scale: scale)
    }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        let stops = [a, b, c, d]
        let clamped = min(max(scale, 0), 3)
        let lower = Int(clamped)
        let upper = min(lower + 1, 3)
        let frac = CGFloat(clamped - Double(lower))
        return stops[lower] + frac * (stops[upper] - stops[lower])
    }
}

// MARK: - LibraryItem

enum LibraryItem: Identifiable {
    case bookmark(Bookmark)
    case note(Note)

    var id: String {
        switch self {
        case .bookmark(let bookmark):
            "bookmark-\(bookmark.id.uuidString)"
        case .note(let note):
            "note-\(note.id.uuidString)"
        }
    }

    /// Most recently modified/updated date — used for Continue section (recency).
    var date: Date {
        switch self {
        case .bookmark(let bookmark):
            bookmark.updatedAt
        case .note(let note):
            note.modifiedAt
        }
    }

    /// Original creation date — used for default sort order in library feeds.
    var createdDate: Date {
        switch self {
        case .bookmark(let bookmark):
            bookmark.createdAt
        case .note(let note):
            note.createdAt
        }
    }

    var title: String {
        switch self {
        case .bookmark(let bookmark):
            bookmark.title
        case .note(let note):
            note.title
        }
    }

    var folderID: UUID? {
        switch self {
        case .bookmark(let bookmark):
            bookmark.folderID
        case .note(let note):
            note.folderID
        }
    }
}
