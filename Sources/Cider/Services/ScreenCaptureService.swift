import AppKit
import Foundation
import Vision
@preconcurrency import ScreenCaptureKit

/// Captures a user-selected screen region using a native overlay + ScreenCaptureKit.
/// No subprocess — TCC permission is attributed directly to Cider's process.
@MainActor
final class ScreenCaptureService {

    // MARK: - Permission

    /// Returns true if ScreenCaptureKit can access shareable content.
    /// Uses SCShareableContent rather than CGPreflight* which tests a different TCC category.
    static var hasPermission: Bool {
        get async {
            do {
                _ = try await SCShareableContent.current
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - Capture

    /// Shows a native region-selection overlay and returns the captured image.
    /// Takes a full-display screenshot via ScreenCaptureKit before showing the overlay,
    /// then crops to the user's selection.
    /// Throws `CaptureError.permissionDenied` if Screen Recording is not granted.
    /// Returns nil if the user cancels.
    static func capture() async throws -> NSImage? {

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return nil }

        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return nil }

        // Take full-display screenshot BEFORE showing the overlay (throws on permission denied)
        let cgFullShot = try await captureDisplay(displayID: displayID, screen: screen)

        // Show interactive selection overlay
        let selectionRect = await ScreenCaptureSelectionController.run(on: screen)
        guard let rect = selectionRect, rect.width > 4, rect.height > 4 else { return nil }

        // Convert view-local rect (NSScreen coords, y from bottom) to CGImage pixel rect (y from top)
        let scale = screen.backingScaleFactor
        let screenH = screen.frame.height
        let cgCropRect = CGRect(
            x: rect.origin.x * scale,
            y: (screenH - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let cropped = cgFullShot.cropping(to: cgCropRect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    enum CaptureError: Error {
        case permissionDenied
        case displayNotFound
        case captureFailed
    }

    private static func captureDisplay(displayID: CGDirectDisplayID, screen: NSScreen) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = scDisplay.width
        config.height = scDisplay.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.captureFailed
        }
    }

    // MARK: - OCR

    /// Run Vision OCR on an NSImage. Returns extracted text or nil.
    static func extractText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let results = request.results, !results.isEmpty
            else { return nil }

            let text = results
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }
}

// MARK: - Selection Overlay Controller

@MainActor
private enum ScreenCaptureSelectionController {

    static func run(on screen: NSScreen) async -> NSRect? {
        return await withCheckedContinuation { continuation in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true

            var resumed = false
            let view = ScreenCaptureSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size)
            ) { rect in
                guard !resumed else { return }
                resumed = true
                panel.orderOut(nil)
                continuation.resume(returning: rect)
            }

            panel.contentView = view
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        }
    }
}

// MARK: - Selection View

private final class ScreenCaptureSelectionView: NSView {
    private let onComplete: (NSRect?) -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    init(frame: NSRect, onComplete: @escaping (NSRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Semi-transparent dim overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)

        guard let sel = selectionRect, sel.width > 2, sel.height > 2 else { return }

        // Punch through dim to show live content in selection
        ctx.setBlendMode(.clear)
        ctx.fill(sel)
        ctx.setBlendMode(.normal)

        // Selection border
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(sel.insetBy(dx: -0.75, dy: -0.75))

        // Corner handles
        let h: CGFloat = 6
        let corners: [CGPoint] = [
            CGPoint(x: sel.minX, y: sel.minY), CGPoint(x: sel.maxX, y: sel.minY),
            CGPoint(x: sel.minX, y: sel.maxY), CGPoint(x: sel.maxX, y: sel.maxY)
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for c in corners {
            ctx.fill(CGRect(x: c.x - h / 2, y: c.y - h / 2, width: h, height: h))
        }

        // Dimensions label
        let label = "\(Int(sel.width)) × \(Int(sel.height))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = label as NSString
        let labelSize = str.size(withAttributes: attrs)
        let pad: CGFloat = 4
        var lx = sel.midX - labelSize.width / 2
        var ly = sel.maxY + 8
        if ly + labelSize.height > bounds.maxY - 8 { ly = sel.minY - labelSize.height - 8 }
        lx = max(pad, min(bounds.maxX - labelSize.width - pad, lx))

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(CGRect(x: lx - pad, y: ly - 2, width: labelSize.width + pad * 2, height: labelSize.height + 4))
        str.draw(at: CGPoint(x: lx, y: ly), withAttributes: attrs)
    }

    private var selectionRect: NSRect? {
        guard let s = startPoint, let c = currentPoint else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let rect = selectionRect
        startPoint = nil; currentPoint = nil
        guard let r = rect, r.width > 5, r.height > 5 else {
            onComplete(nil)
            return
        }
        onComplete(r)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            startPoint = nil; currentPoint = nil
            onComplete(nil)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}
