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

        guard let value = pasteboard.string(forType: .string) else {
            return
        }

        let config = CiderConfig.load()
        if config.confirmCopiedURLBeforeSave {
            guard BookmarksStorage.shared.previewNormalizedURLString(from: value) != nil else { return }

            NotificationCenter.default.post(
                name: .showBookmarkClipboardReviewToast,
                object: nil,
                userInfo: ["urlString": value]
            )
            return
        }

        guard BookmarksStorage.shared.add(urlString: value, title: nil) != nil else { return }

        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "message": "Saved copied URL",
                "isSuccess": true,
            ]
        )
    }
}
