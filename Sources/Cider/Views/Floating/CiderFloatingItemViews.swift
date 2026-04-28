import SwiftUI

typealias CiderFloatingDockAction = @MainActor @Sendable () -> Void

struct CiderFloatingItemView: View {
    let surface: CiderFloatableSurface
    var onDock: CiderFloatingDockAction?

    @ObservedObject private var bookmarks = VaultBookmarkService.shared
    @ObservedObject private var notes = NotesStorage.shared
    @ObservedObject private var dateCards = DateCardStorage.shared
    @ObservedObject private var contacts = ContactStorage.shared
    @ObservedObject private var todos = TodoCardStorage.shared

    var body: some View {
        Group {
            switch surface {
            case .note(let id):
                if let note = notes.notes.first(where: { $0.id == id }) {
                    FloatingNoteDetail(note: note, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Note not found", surface: surface)
                }
            case .bookmark(let id), .bookmarkMetadata(let id):
                if let bookmark = bookmarks.bookmarks.first(where: { $0.id == id }) {
                    FloatingBookmarkDetail(bookmark: bookmark, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Bookmark not found", surface: surface)
                }
            case .contact(let id):
                if let contact = contacts.contact(for: id) {
                    FloatingContactDetail(contact: contact, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Contact not found", surface: surface)
                }
            case .dateCard(let id):
                if let dateCard = dateCards.dateCard(for: id) {
                    FloatingDateCardDetail(dateCard: dateCard, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Date card not found", surface: surface)
                }
            case .todo(let id):
                if let todo = todos.todoCard(for: id) {
                    FloatingTodoDetail(todo: todo, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Todo not found", surface: surface)
                }
            case .clipboard:
                FloatingMissingItemView(title: "Clipboard opens in its dedicated panel", surface: surface)
            case .aiAssistant:
                FloatingMissingItemView(title: "AI Assistant opens in its dedicated panel", surface: surface)
            case .dropZone:
                FloatingMissingItemView(title: "Drop zone is handled by the drop surface", surface: surface)
            }
        }
        .environment(\.floatingCiderDockAction, onDock)
    }
}

private struct FloatingNoteDetail: View {
    let note: Note
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    private var content: String {
        NotesStorage.shared.loadContent(for: note)
    }

    var body: some View {
        GenericItemDetailPanel(
            title: note.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in }
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Empty note")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    Text(content)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !note.tags.isEmpty {
                    Text(note.tags.joined(separator: ", "))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
        }
    }
}

private struct FloatingBookmarkDetail: View {
    let bookmark: Bookmark
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: bookmark.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                AIDetailActionsButton(
                    bookmarkTitle: bookmark.title,
                    bookmarkURL: bookmark.urlString
                )
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                BookmarkDetailsHeroPreview(
                    bookmark: bookmark,
                    draft: BookmarkDetailsDraft(bookmark: bookmark)
                )
                .frame(height: 180)

                FloatingDetailRow(label: "URL", value: bookmark.urlString)

                if !bookmark.notes.isEmpty {
                    FloatingDetailRow(label: "Notes", value: bookmark.notes)
                }

                if !bookmark.tags.isEmpty {
                    FloatingDetailRow(label: "Tags", value: bookmark.tags.joined(separator: ", "))
                }
            }
        }
    }
}

private struct FloatingContactDetail: View {
    let contact: ContactCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: contact.displayName,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: { AIDetailActionsButton(contactName: contact.displayName) }
        ) {
            ContactDetailView(contact: contact, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingDateCardDetail: View {
    let dateCard: DateCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: dateCard.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: { AIDetailActionsButton(eventTitle: dateCard.title) }
        ) {
            DateCardDetailView(dateCard: dateCard, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingTodoDetail: View {
    let todo: TodoCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: todo.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: { AIDetailActionsButton(todoTitle: todo.title) }
        ) {
            TodoDetailView(todoCard: todo, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingMissingItemView: View {
    let title: String
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in }
        ) {
            Text(title)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct FloatingDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
private func dock(_ surface: CiderFloatableSurface, action: CiderFloatingDockAction?) {
    if let action {
        action()
    } else {
        NotificationCenter.default.post(name: .dockCiderSurface, object: surface)
    }
}

private struct FloatingCiderDockActionKey: EnvironmentKey {
    static let defaultValue: CiderFloatingDockAction? = nil
}

private extension EnvironmentValues {
    var floatingCiderDockAction: CiderFloatingDockAction? {
        get { self[FloatingCiderDockActionKey.self] }
        set { self[FloatingCiderDockActionKey.self] = newValue }
    }
}
