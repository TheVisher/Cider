# Books Tab Vision

A dedicated tab for tracking reading — books, articles, papers, and long-form content. Separate from bookmarks (which are web links) and notes (which are written content).

---

## Status: Not Yet Implemented

This tab is planned but no work has started. Ideas below are initial brainstorming.

## Core Concept

A reading tracker and library manager. Add books you're reading, want to read, or have finished. Track progress, jot down highlights and thoughts, and see your reading history.

## Possible Features

### Library Views
- Cover grid (book covers in grid/masonry layout)
- List view (title, author, progress, status)
- Shelf view (books displayed spine-out on virtual shelves)

### Book Entry
- Manual add (title, author, cover image)
- ISBN / barcode lookup for auto-fill
- Import from Goodreads, StoryGraph, or other reading trackers
- Drag a cover image onto a book card

### Reading Status
- Want to Read / Currently Reading / Finished / Abandoned
- Progress tracking (page number or percentage)
- Start date / finish date
- Rating (stars or numeric)

### Notes Integration
- Per-book notes (highlights, thoughts, quotes)
- Link notes from the Notes tab to specific books
- Highlight extraction from e-readers (Kindle, Apple Books)

### Organization
- Shelves / collections (fiction, non-fiction, technical, etc.)
- Tags
- Search by title, author, genre

### Statistics
- Books read per month/year
- Pages read
- Reading streaks
- Genre distribution

## Data Model (Sketch)

```swift
struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var author: String
    var coverImagePath: String?
    var isbn: String?
    var status: ReadingStatus       // .wantToRead, .reading, .finished, .abandoned
    var progress: Double?           // 0-1 percentage
    var currentPage: Int?
    var totalPages: Int?
    var startDate: Date?
    var finishDate: Date?
    var rating: Int?                // 1-5
    var notes: String?
    var tags: [String]
    var shelfID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

enum ReadingStatus: String, Codable {
    case wantToRead
    case reading
    case finished
    case abandoned
}
```
