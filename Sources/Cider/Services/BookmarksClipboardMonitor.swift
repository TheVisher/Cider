import AppKit
import Foundation

@MainActor
final class BookmarksClipboardMonitor {
    static let shared = BookmarksClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int
    private var isEnabled = false
    private var suspendUntil: Date?
    private var pendingImageRetry: DispatchWorkItem?

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

        pendingImageRetry?.cancel()
        pendingImageRetry = nil

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
        pendingImageRetry?.cancel()
        pendingImageRetry = nil
    }

    @objc private func pollClipboard() {
        if let suspendUntil, Date() < suspendUntil {
            return
        }
        if let suspendUntil, Date() >= suspendUntil {
            self.suspendUntil = nil
            // Skip any clipboard changes that occurred during suspension
            // (e.g. browser capture restoring the pasteboard after reading the URL)
            lastChangeCount = NSPasteboard.general.changeCount
        }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        pendingImageRetry?.cancel()
        pendingImageRetry = nil

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

        // If image capture is enabled but no image was found, the source app
        // may still be writing image data to the pasteboard asynchronously.
        // Schedule a retry to catch lazily-provided image data.
        if config.autoCaptureCopiedImages {
            let retryCount = changeCount
            let work = DispatchWorkItem { [weak self] in
                self?.retryImageCheck(expectedChangeCount: retryCount)
            }
            pendingImageRetry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        // Check for URL string (if URL capture is enabled)
        if config.autoCaptureCopiedURLs, let value = pasteboard.string(forType: .string) {
            if config.confirmCopiedURLBeforeSave {
                if VaultBookmarkService.shared.previewNormalizedURLString(from: value) != nil {
                    NotificationCenter.default.post(
                        name: .showBookmarkClipboardReviewToast,
                        object: nil,
                        userInfo: ["urlString": value]
                    )
                    return
                }
            } else if VaultBookmarkService.shared.add(urlString: value, title: nil) != nil {
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

    private func retryImageCheck(expectedChangeCount: Int) {
        guard suspendUntil == nil else { return }
        let pasteboard = NSPasteboard.general
        // Only retry if the clipboard hasn't changed again since we scheduled
        guard pasteboard.changeCount == expectedChangeCount else { return }
        guard hasImageData(pasteboard: pasteboard) else { return }
        NotificationCenter.default.post(
            name: .showImageClipboardReviewToast,
            object: nil
        )
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("com.compuserve.gif")
    ]

    private func hasImageData(pasteboard: NSPasteboard) -> Bool {
        for type in Self.imageTypes {
            if pasteboard.data(forType: type) != nil {
                return true
            }
        }
        return false
    }

    /// Reads image data from the general pasteboard. Called by the toast save action.
    /// Checks GIF first so animated content is preserved when clipboard has both PNG and GIF.
    static func readImageFromClipboard() -> Data? {
        let pasteboard = NSPasteboard.general
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        if let gifData = pasteboard.data(forType: gifType) {
            return gifData
        }
        for type in imageTypes {
            if let data = pasteboard.data(forType: type) {
                return data
            }
        }
        return nil
    }
}
