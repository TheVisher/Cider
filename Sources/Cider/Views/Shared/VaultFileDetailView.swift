import AppKit
import AVKit
import PDFKit
import Quartz
import SwiftUI

struct VaultFileDetailView: View {
    let file: VaultFile
    var onDismiss: (() -> Void)? = nil

    @State private var image: NSImage?
    @State private var pdfDocument: PDFDocument?
    @State private var avPlayer: AVPlayer?
    @State private var textPreview: String?
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewArea

            if supportsZoom {
                zoomControls
                    .padding(Spacing.sm)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.lg)
            .task(id: file.id) {
                zoomScale = Self.defaultZoomScale
                await loadPreview()
            }
    }

    fileprivate static let defaultZoomScale: CGFloat = 1
    fileprivate static let minimumZoomScale: CGFloat = 1
    fileprivate static let maximumZoomScale: CGFloat = 3
    private static let zoomStep: CGFloat = 0.25

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        switch file.fileType {
        case .image:
            if let image {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: max(proxy.size.width, proxy.size.width * zoomScale),
                                height: max(proxy.size.height, proxy.size.height * zoomScale),
                                alignment: .center
                            )
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                    .scrollIndicators(.automatic)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            } else {
                iconPlaceholder
            }

        case .pdf:
            if let pdfDocument {
                PDFKitView(document: pdfDocument, zoomScale: zoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                iconPlaceholder
            }

        case .video, .audio:
            switch VaultFileMediaPreviewPolicy.presentation(for: file) {
            case .inlineVideo:
                if let avPlayer {
                VideoPlayer(player: avPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: VaultFileDesign.detailPreviewMinHeight,
                           maxHeight: VaultFileDesign.detailPreviewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                } else {
                    iconPlaceholder
                }
            case .externalAudio:
                ExternalAudioPreview(file: file)
            case .other:
                iconPlaceholder
            }

        case .document, .archive, .unknown:
            if VaultFileTextPreview.canPreview(file) {
                InlineTextFilePreview(text: textPreview)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                QuickLookPreview(url: file.absoluteURL, zoomScale: zoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private var supportsZoom: Bool {
        if VaultFileTextPreview.canPreview(file) {
            return false
        }
        switch file.fileType {
        case .image, .pdf, .document, .archive, .unknown:
            return true
        case .video, .audio:
            return false
        }
    }

    private var zoomControls: some View {
        HStack(spacing: Spacing.xxs) {
            zoomButton(
                systemImage: "minus.magnifyingglass",
                help: "Zoom out",
                disabled: zoomScale <= Self.minimumZoomScale
            ) {
                setZoomScale(zoomScale - Self.zoomStep)
            }

            Text(String(format: "%.0f%%", zoomScale * 100))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .monospacedDigit()
                .frame(width: 44)

            zoomButton(
                systemImage: "plus.magnifyingglass",
                help: "Zoom in",
                disabled: zoomScale >= Self.maximumZoomScale
            ) {
                setZoomScale(zoomScale + Self.zoomStep)
            }

            zoomButton(
                systemImage: "arrow.counterclockwise",
                help: "Reset zoom",
                disabled: zoomScale == Self.defaultZoomScale
            ) {
                setZoomScale(Self.defaultZoomScale)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                .allowsHitTesting(false)
        }
    }

    private func zoomButton(
        systemImage: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(CiderFont.label)
                .foregroundColor(disabled ? CiderColors.quaternary : CiderColors.secondary)
                .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func setZoomScale(_ scale: CGFloat) {
        zoomScale = min(max(scale, Self.minimumZoomScale), Self.maximumZoomScale)
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(CiderColors.surfaceInput)
            .frame(maxWidth: .infinity)
            .frame(height: VaultFileDesign.detailPlaceholderHeight)
            .overlay(
                Image(systemName: file.fileType.systemImageName)
                    .font(CiderFont.vaultDetailIcon)
                    .foregroundColor(CiderColors.tertiary)
            )
    }

    // MARK: - Helpers

    private func loadPreview() async {
        let url = file.absoluteURL
        switch file.fileType {
        case .image:
            let loaded: NSImage? = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }.value
            image = loaded

        case .pdf:
            pdfDocument = PDFDocument(url: url)

        case .video, .audio:
            if VaultFileMediaPreviewPolicy.presentation(for: file) == .inlineVideo {
                avPlayer = AVPlayer(url: url)
            }

        case .document, .unknown:
            guard VaultFileTextPreview.canPreview(file) else { break }
            let loaded = try? await Task.detached(priority: .userInitiated) {
                try VaultFileTextPreview.loadText(from: url)
            }.value
            textPreview = loaded

        default:
            break
        }
    }
}

enum VaultFileMediaPreviewPresentation: Equatable {
    case inlineVideo
    case externalAudio
    case other
}

enum VaultFileMediaPreviewPolicy {
    static func presentation(for file: VaultFile) -> VaultFileMediaPreviewPresentation {
        switch file.fileType {
        case .video: return .inlineVideo
        case .audio: return .externalAudio
        default: return .other
        }
    }
}

private struct ExternalAudioPreview: View {
    let file: VaultFile

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "waveform")
                .font(CiderFont.vaultDetailIcon)
                .foregroundColor(CiderColors.tertiary)

            Text("Audio preview unavailable")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.primary)

            Text("Open this audio file in your default media app.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)

            Button("Open Externally") {
                CiderOpenPolicy.shared.openIfAllowed(.localFile(file.absoluteURL))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: VaultFileDesign.detailPlaceholderHeight)
        .background(CiderColors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

enum VaultFileTextPreview {
    private static let previewableExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml", "xml",
        "log", "rtf", "ics", "vcf"
    ]

    static let maxPreviewBytes = 512 * 1024

    static func canPreview(_ file: VaultFile) -> Bool {
        guard file.fileType == .document || file.fileType == .unknown else { return false }
        let ext = (file.filename as NSString).pathExtension.lowercased()
        return previewableExtensions.contains(ext)
    }

    static func loadText(from url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxPreviewBytes + 1) ?? Data()
        let clipped = data.count > maxPreviewBytes
        let previewData = clipped ? data.prefix(maxPreviewBytes) : data[...]
        let text = String(decoding: previewData, as: UTF8.self)
        return clipped ? text + "\n\n[Preview truncated]" : text
    }
}

private struct InlineTextFilePreview: View {
    let text: String?

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text ?? "")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(CiderColors.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
    }
}

// MARK: - PDFKit SwiftUI Wrapper

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let zoomScale: CGFloat

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }

        if zoomScale <= 1 {
            nsView.autoScales = true
        } else {
            nsView.autoScales = false
            let fitScale = max(nsView.scaleFactorForSizeToFit, nsView.minScaleFactor)
            nsView.scaleFactor = min(fitScale * zoomScale, nsView.maxScaleFactor)
        }
    }
}

// MARK: - Quick Look SwiftUI Wrapper

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    let zoomScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = VaultFileDetailView.minimumZoomScale
        scrollView.maxMagnification = VaultFileDetailView.maximumZoomScale

        let previewView = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 600), style: .normal)!
        previewView.previewItem = url as NSURL
        previewView.autoresizingMask = [.width, .height]
        scrollView.documentView = previewView
        context.coordinator.previewView = previewView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let previewView = context.coordinator.previewView else { return }

        if (previewView.previewItem as? NSURL) as URL? != url {
            previewView.previewItem = url as NSURL
            previewView.refreshPreviewItem()
        }

        let visibleBounds = nsView.contentView.bounds
        if !visibleBounds.isEmpty {
            previewView.frame = NSRect(
                x: 0,
                y: 0,
                width: max(visibleBounds.width, 400),
                height: max(visibleBounds.height, 600)
            )
        }

        let clampedZoom = min(max(zoomScale, nsView.minMagnification), nsView.maxMagnification)
        if abs(nsView.magnification - clampedZoom) > 0.001 {
            nsView.setMagnification(
                clampedZoom,
                centeredAt: NSPoint(x: nsView.contentView.bounds.midX, y: nsView.contentView.bounds.midY)
            )
        }
    }

    final class Coordinator {
        var previewView: QLPreviewView?
    }
}
