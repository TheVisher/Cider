import AppKit
import Foundation
import ImageIO

@MainActor
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()

    private var timer: Timer?
    private var lastChangeCount: Int
    private var isEnabled = false
    private var suspendUntil: Date?

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")
    ]

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

    // MARK: - Private

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
        // Check suspension
        if let suspendUntil, Date() < suspendUntil {
            return
        }
        if let suspendUntil, Date() >= suspendUntil {
            self.suspendUntil = nil
            lastChangeCount = NSPasteboard.general.changeCount
        }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let appName = sourceApp?.localizedName
        let bundleID = sourceApp?.bundleIdentifier

        // Check image first (browsers often include both image + URL)
        if let imageItem = readImage(from: pasteboard, appName: appName, bundleID: bundleID) {
            ClipboardStorage.shared.insert(imageItem)
            return
        }

        // Check URL (string that looks like a URL)
        if let str = pasteboard.string(forType: .string), isLikelyURL(str) {
            let item = ClipboardItem(
                type: .url,
                textContent: str.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceAppName: appName,
                sourceAppBundleID: bundleID
            )
            ClipboardStorage.shared.insert(item)
            return
        }

        // Check RTF
        if pasteboard.data(forType: .rtf) != nil,
           let str = pasteboard.string(forType: .string), !str.isEmpty {
            let item = ClipboardItem(
                type: .richText,
                textContent: str,
                sourceAppName: appName,
                sourceAppBundleID: bundleID
            )
            ClipboardStorage.shared.insert(item)
            return
        }

        // Plain text
        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            let item = ClipboardItem(
                type: .text,
                textContent: str,
                sourceAppName: appName,
                sourceAppBundleID: bundleID
            )
            ClipboardStorage.shared.insert(item)
            return
        }
    }

    // MARK: - Image Handling

    private func readImage(
        from pasteboard: NSPasteboard,
        appName: String?,
        bundleID: String?
    ) -> ClipboardItem? {
        var rawData: Data?
        var detectedExt = "png"
        for type in Self.imageTypes {
            if let data = pasteboard.data(forType: type) {
                rawData = data
                if type == NSPasteboard.PasteboardType("public.jpeg") {
                    detectedExt = "jpeg"
                } else if type == .tiff {
                    detectedExt = "tiff"
                }
                break
            }
        }
        guard let data = rawData else { return nil }

        let originalSize = imageSize(from: data)

        var item = ClipboardItem(
            type: .image,
            imageData: data,
            imageSize: originalSize,
            sourceAppName: appName,
            sourceAppBundleID: bundleID
        )
        item.imageFileExtension = detectedExt
        return item
    }

    private func imageSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - URL Detection

    private func isLikelyURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), trimmed.count < 2048 else { return false }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, host.contains(".")
        else { return false }
        return true
    }
}
