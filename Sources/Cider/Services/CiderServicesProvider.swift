import AppKit

/// Handles macOS Services menu requests ("Send to Cider").
/// Two service entries: one for text (URLs + plain text), one for images.
/// Requires a proper .app bundle to appear in the Services menu.
@MainActor
final class CiderServicesProvider: NSObject {

    // MARK: - Text Service (public.utf8-plain-text)

    @objc nonisolated func sendTextToCider(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = pasteboard.string(forType: .string)
        Task { @MainActor [weak self] in
            self?.handleText(text)
        }
    }

    private func handleText(_ text: String?) {
        guard let text, !text.isEmpty else { return }

        // Check if it looks like a URL
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let saved = BookmarksStorage.shared.add(urlString: url.absoluteString, title: nil) != nil
            postToast(message: saved ? "Saved from Services" : "Could not save URL", isSuccess: saved)
            return
        }

        // Plain text → new note
        var note = NotesStorage.shared.createNew()
        note.content = text
        NotesStorage.shared.save(note: note)
        postToast(message: "Created note from Services", isSuccess: true)
    }

    // MARK: - Image Service (public.png / public.jpeg / public.tiff)

    @objc nonisolated func sendImageToCider(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let imageData = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
        Task { @MainActor [weak self] in
            self?.handleImage(imageData)
        }
    }

    private func handleImage(_ data: Data?) {
        guard let data else { return }
        let bookmark = BookmarksStorage.shared.addImageBookmark(title: "Image from Services")
        BookmarksStorage.shared.assignThumbnail(for: bookmark.id, imageData: data)
        postToast(message: "Saved image from Services", isSuccess: true)
    }

    // MARK: - Toast

    private func postToast(message: String, isSuccess: Bool) {
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: ["message": message, "isSuccess": isSuccess]
        )
    }
}
