import AppKit
import Foundation

@MainActor
final class BookmarksClipboardMonitor {
    static let shared = BookmarksClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int
    private var isEnabled = false
    private var suspendUntil: Date?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    func suspendFor(seconds: TimeInterval) {
        let clamped = max(0, seconds)
        guard clamped > 0 else { return }

        let newDeadline = Date().addingTimeInterval(clamped)
        if let existing = suspendUntil {
            suspendUntil = max(existing, newDeadline)
        } else {
            suspendUntil = newDeadline
        }
    }

    private func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(
            timeInterval: 0.7,
            target: self,
            selector: #selector(pollClipboard),
            userInfo: nil,
            repeats: true
        )
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func pollClipboard() {
        if let suspendUntil, Date() < suspendUntil {
            return
        }
        if let suspendUntil, Date() >= suspendUntil {
            self.suspendUntil = nil
        }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let config = CiderConfig.load()

        // Check for image data first — when copying images from browsers, the
        // clipboard often contains both image data AND a text URL. Checking
        // images first prevents the URL path from intercepting image copies.
        if config.autoCaptureCopiedImages, hasImageData(pasteboard: pasteboard) {
            NotificationCenter.default.post(
                name: .showImageClipboardReviewToast,
                object: nil
            )
            return
        }

        // Check for URL string (if URL capture is enabled)
        if config.autoCaptureCopiedURLs, let value = pasteboard.string(forType: .string) {
            if config.confirmCopiedURLBeforeSave {
                if BookmarksStorage.shared.previewNormalizedURLString(from: value) != nil {
                    NotificationCenter.default.post(
                        name: .showBookmarkClipboardReviewToast,
                        object: nil,
                        userInfo: ["urlString": value]
                    )
                    return
                }
            } else if BookmarksStorage.shared.add(urlString: value, title: nil) != nil {
                NotificationCenter.default.post(
                    name: .showBookmarkCaptureToast,
                    object: nil,
                    userInfo: [
                        "message": "Saved copied URL",
                        "isSuccess": true,
                    ]
                )
                return
            }
        }
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")
    ]

    private func hasImageData(pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: Self.imageTypes) != nil
    }

    /// Reads image data from the general pasteboard. Called by the toast save action.
    static func readImageFromClipboard() -> Data? {
        let pasteboard = NSPasteboard.general
        for type in imageTypes {
            if let data = pasteboard.data(forType: type) {
                return data
            }
        }
        return nil
    }
}
