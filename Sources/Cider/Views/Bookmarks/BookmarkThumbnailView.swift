import AppKit
import SwiftUI

struct BookmarkThumbnailView: View {
    enum ThumbnailMode {
        case list
        case grid
        case masonry
    }

    let bookmark: Bookmark
    let mode: ThumbnailMode
    var onAspectRatioResolved: ((CGFloat?) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?
    @State private var rendersAsIconOverlay = false

    private var palette: (Color, Color) {
        BookmarkVisualStyle.gradient(for: bookmark)
    }

    private var thumbnailFingerprint: String {
        let path = bookmark.thumbnailFileURL?.path ?? ""
        let ts = String(bookmark.metadataUpdatedAt?.timeIntervalSince1970 ?? -1)
        let remote = bookmark.thumbnailRemoteURLString ?? ""
        return "\(path)|\(ts)|\(remote)"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.clear)
            .overlay(content: thumbnailContent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .task(id: thumbnailFingerprint) {
                await loadThumbnailAsync()
            }
    }

    @ViewBuilder
    private func thumbnailContent() -> some View {
        if let thumbnailImage, !shouldSuppressDownloadedThumbnail {
            if rendersAsIconOverlay {
                iconOverlayGradient(for: thumbnailImage)
            } else {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: mode == .masonry ? .fit : .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if bookmark.isEnriching {
            BookmarkShimmerPlaceholder()
        } else {
            fallbackGradient
        }
    }

    private var shouldSuppressDownloadedThumbnail: Bool {
        let fingerprint = (bookmark.thumbnailRemoteURLString ?? "").lowercased()
        if fingerprint.isEmpty { return false }

        let blockedFragments = [
            "if-you-are-looking-for-an-image",
            "if_you_are_looking_for_an_image",
            "/removed.",
            "/deleted.",
            "/default.",
            "/self.",
            "/nsfw.",
            "/spoiler.",
            "preview.redd.it/default",
            "preview.redd.it/self",
            "preview.redd.it/nsfw",
            "preview.redd.it/spoiler",
        ]

        return blockedFragments.contains { fragment in
            fingerprint.contains(fragment)
        }
    }

    private var fallbackGradient: some View {
        gradientBackground
        .overlay {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Spacer(minLength: 0)

                Text(String(bookmark.hostDisplay.prefix(1)).uppercased())
                    .font(.system(size: (mode == .list ? BookmarksDesign.listFallbackLetterSize : BookmarksDesign.cardFallbackLetterSize) * textScale, weight: .black))
                    .foregroundColor(CiderColors.textOnColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.sm)
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [palette.0.opacity(CiderColors.gradientTint), palette.1.opacity(CiderColors.gradientTint)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconOverlayGradient(for image: NSImage) -> some View {
        gradientBackground
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: iconOverlaySize * textScale,
                        height: iconOverlaySize * textScale
                    )
                    .padding(.top, mode == .list ? Spacing.xl : Spacing.sm)
                    .shadow(color: CiderColors.shadowLight, radius: 2, x: 0, y: 1)
            }
    }

    private var iconOverlaySize: CGFloat {
        switch mode {
        case .list:
            return BookmarksDesign.thumbnailIconOverlaySizeList
        case .grid, .masonry:
            return BookmarksDesign.thumbnailIconOverlaySizeGrid
        }
    }

    private func loadThumbnailAsync() async {
        guard let fileURL = bookmark.thumbnailFileURL else {
            thumbnailImage = nil
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
            return
        }

        let remoteURLString = bookmark.thumbnailRemoteURLString

        let result: (NSImage, Bool, CGFloat?)? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            guard width > 0, height > 0 else { return nil }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

            let isIconOverlay = Self.shouldRenderAsIconOverlay(
                width: width, height: height, remoteURLString: remoteURLString
            )
            let aspectRatio: CGFloat? = isIconOverlay ? nil : height / width

            return (nsImage, isIconOverlay, aspectRatio)
        }.value

        guard !Task.isCancelled else { return }

        if let (image, isIcon, aspectRatio) = result, !shouldSuppressDownloadedThumbnail {
            thumbnailImage = image
            rendersAsIconOverlay = isIcon
            onAspectRatioResolved?(aspectRatio)
        } else {
            thumbnailImage = nil
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
        }
    }

    nonisolated private static func shouldRenderAsIconOverlay(
        width: CGFloat, height: CGFloat, remoteURLString: String?
    ) -> Bool {
        let aspectRatio = width / height
        let isSquareish = abs(aspectRatio - 1) <= BookmarksDesign.thumbnailIconCandidateMaxAspectDelta
        let maxDimension = max(width, height)
        let minDimension = min(width, height)
        let isTinySquareAsset =
            isSquareish &&
            minDimension >= BookmarksDesign.thumbnailIconCandidateMinDimension &&
            maxDimension <= BookmarksDesign.thumbnailIconCandidateMaxDimension

        let remoteFingerprint = (remoteURLString ?? "").lowercased()
        let hasIconURLHint =
            remoteFingerprint.contains("favicon") ||
            remoteFingerprint.contains("apple-touch-icon") ||
            remoteFingerprint.contains("mask-icon") ||
            remoteFingerprint.hasSuffix(".ico")

        return hasIconURLHint || isTinySquareAsset
    }
}

struct BookmarkShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerProgress: CGFloat = -0.9

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        CiderColors.surfaceInput,
                        CiderColors.borderSelected,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceMotion {
                    let bandWidth = max(
                        BookmarksDesign.thumbnailShimmerBandMinWidth,
                        proxy.size.width * BookmarksDesign.thumbnailShimmerBandWidthRatio
                    )
                    let travel = proxy.size.width + bandWidth
                    LinearGradient(
                        colors: [
                            Color.clear,
                            CiderColors.shimmerPeak,
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: bandWidth)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmerProgress * travel)
                    .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.smooth(duration: BookmarksDesign.thumbnailShimmerDuration).repeatForever(autoreverses: false)) {
                shimmerProgress = 1.2
            }
        }
        .onDisappear {
            shimmerProgress = -0.9
        }
    }
}
