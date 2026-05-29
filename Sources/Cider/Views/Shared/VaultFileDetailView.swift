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

    var body: some View {
        previewArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.lg)
            .task {
                await loadPreview()
            }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        switch file.fileType {
        case .image:
            if let image {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            } else {
                iconPlaceholder
            }

        case .pdf:
            if let pdfDocument {
                PDFKitView(document: pdfDocument)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                iconPlaceholder
            }

        case .video, .audio:
            if let avPlayer {
                VideoPlayer(player: avPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: file.fileType == .audio ? VaultFileDesign.audioPlayerHeight : VaultFileDesign.detailPreviewMinHeight,
                           maxHeight: file.fileType == .audio ? VaultFileDesign.audioPlayerMaxHeight : VaultFileDesign.detailPreviewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                iconPlaceholder
            }

        case .document, .archive, .unknown:
            QuickLookPreview(url: file.absoluteURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
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
            avPlayer = AVPlayer(url: url)

        default:
            break
        }
    }
}

// MARK: - PDFKit SwiftUI Wrapper

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

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
    }
}

// MARK: - Quick Look SwiftUI Wrapper

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), style: .normal)!
        view.previewItem = url as NSURL
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
            nsView.refreshPreviewItem()
        }
    }
}
