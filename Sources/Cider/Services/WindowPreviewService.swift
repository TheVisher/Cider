import AppKit
import Combine

// MARK: - Private Window Server APIs

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSHWCaptureWindowList")
private func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowIDs: UnsafeMutablePointer<CGWindowID>,
    _ windowCount: UInt32,
    _ options: UInt32
) -> CFArray?

private let kCGSCaptureIgnoreGlobalClipShape: UInt32 = 1 << 11

@MainActor
final class WindowPreviewService: ObservableObject {
    @Published var previews: [CGWindowID: NSImage] = [:]
    @Published var hasPermission: Bool = true

    @Published var isCapturing: Bool = false

    private var refreshTask: Task<Void, Never>?
    private var frozenWindowIDs: Set<CGWindowID> = []

    /// Capture interval (0.1 = 10fps)
    private let captureInterval: TimeInterval = 0.1

    private let connectionID: CGSConnectionID

    static let shared = WindowPreviewService()

    private init() {
        connectionID = CGSMainConnectionID()
    }

    func checkPermission() async {
        hasPermission = true
    }

    func requestPermission() {
        hasPermission = true
    }

    func startCapturing(windowIDs: [CGWindowID]) async {
        isCapturing = true
        refreshTask?.cancel()

        refreshTask = Task {
            while !Task.isCancelled && isCapturing {
                await captureSnapshots(for: windowIDs)
                try? await Task.sleep(nanoseconds: UInt64(captureInterval * 1_000_000_000))
            }
        }
    }

    func stopAllStreams() async {
        isCapturing = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func captureSnapshots(for windowIDs: [CGWindowID]) async {
        for windowID in windowIDs {
            guard !frozenWindowIDs.contains(windowID) else { continue }

            if let image = captureWindowPrivate(windowID: windowID) {
                previews[windowID] = image
            }
        }
    }

    private func captureWindowPrivate(windowID: CGWindowID) -> NSImage? {
        var wid = windowID

        guard let imageArray = CGSHWCaptureWindowList(
            connectionID,
            &wid,
            1,
            kCGSCaptureIgnoreGlobalClipShape
        ) else {
            return nil
        }

        let images = imageArray as [AnyObject]
        guard let cgImage = images.first as! CGImage? else {
            return nil
        }

        if isFrameMostlyBlack(cgImage) {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func isFrameMostlyBlack(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return false
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        let width = image.width
        let height = image.height

        guard bytesPerPixel >= 3, width > 0, height > 0 else { return false }

        let samplePoints = [
            (width / 4, height / 4),
            (width / 2, height / 4),
            (3 * width / 4, height / 4),
            (width / 4, height / 2),
            (width / 2, height / 2),
            (3 * width / 4, height / 2),
            (width / 4, 3 * height / 4),
            (width / 2, 3 * height / 4),
            (3 * width / 4, 3 * height / 4),
        ]

        var blackCount = 0
        let threshold: UInt8 = 15

        for (x, y) in samplePoints {
            let offset = y * bytesPerRow + x * bytesPerPixel
            guard offset + 2 < CFDataGetLength(data) else { continue }

            let b = ptr[offset]
            let g = ptr[offset + 1]
            let r = ptr[offset + 2]

            if r < threshold && g < threshold && b < threshold {
                blackCount += 1
            }
        }

        return blackCount >= 7
    }

    func stopStreams(for windowIDs: [CGWindowID]) async {}

    func clearPreview(for windowID: CGWindowID) {
        previews.removeValue(forKey: windowID)
    }

    func cleanupPreviews(keepingWindowIDs: Set<CGWindowID>) {
        let staleIDs = Set(previews.keys).subtracting(keepingWindowIDs)
        for id in staleIDs {
            previews.removeValue(forKey: id)
        }
    }

    func freezePreview(for windowID: CGWindowID) {
        frozenWindowIDs.insert(windowID)
    }

    func freezePreviews(for windowIDs: [CGWindowID]) {
        frozenWindowIDs.formUnion(windowIDs)
    }

    func unfreezePreview(for windowID: CGWindowID) {
        frozenWindowIDs.remove(windowID)
    }

    func unfreezePreviews(for windowIDs: [CGWindowID]) {
        for id in windowIDs {
            frozenWindowIDs.remove(id)
        }
    }

    func unfreezeAllPreviews() {
        frozenWindowIDs.removeAll()
    }

    func prepareForHiding(windowIDs: [CGWindowID]) {
        frozenWindowIDs.formUnion(windowIDs)
    }
}
