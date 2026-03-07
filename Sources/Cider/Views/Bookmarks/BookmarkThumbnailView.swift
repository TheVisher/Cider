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
    var isHovered: Bool = false
    var onAspectRatioResolved: ((CGFloat?) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    /// Whether to show the animated GIF instead of the static thumbnail.
    private var shouldAnimate: Bool {
        bookmark.isAnimatedImage && isHovered && !reduceMotion && bookmark.animatedImageFileURL != nil
    }

    var body: some View {
        if bookmark.isCarousel, mode != .list {
            CarouselThumbnailView(
                bookmark: bookmark,
                mode: mode,
                isHovered: isHovered
            )
        } else {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.clear)
                .overlay(content: thumbnailContent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if bookmark.isAnimatedImage, thumbnailImage != nil {
                        gifBadge
                    } else if bookmark.isCarousel, mode == .list {
                        imageCountBadge
                    }
                }
                .task(id: thumbnailFingerprint) {
                    await loadThumbnailAsync()
                }
        }
    }

    private var imageCountBadge: some View {
        Text("\(bookmark.imageCount)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(CiderColors.textOnColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
            .padding(Spacing.xs)
    }

    @ViewBuilder
    private func thumbnailContent() -> some View {
        if let thumbnailImage, !shouldSuppressDownloadedThumbnail {
            if rendersAsIconOverlay {
                iconOverlayGradient(for: thumbnailImage)
            } else if shouldAnimate, let gifURL = bookmark.animatedImageFileURL {
                AnimatedGIFView(url: gifURL, contentMode: mode == .masonry ? .fit : .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var gifBadge: some View {
        Text("GIF")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(CiderColors.textOnColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
            .padding(Spacing.sm)
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

// MARK: - Carousel Thumbnail View

struct CarouselThumbnailView: View {
    let bookmark: Bookmark
    let mode: BookmarkThumbnailView.ThumbnailMode
    var isHovered: Bool = false

    @State private var currentPage: Int? = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var urls: [URL] { bookmark.carouselImageFileURLs }
    private var page: Int { currentPage ?? 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, _ in
                        CarouselPageImage(
                            url: urls[index],
                            fillMode: mode == .masonry ? .fit : .fill
                        )
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentPage)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                CarouselScrollWheelOverlay { delta in
                    navigatePage(delta: delta)
                }
            }

            // Navigation arrows on hover
            if isHovered, urls.count > 1 {
                HStack {
                    if page > 0 {
                        carouselArrowButton(systemName: "chevron.left", size: 10) {
                            navigatePage(delta: -1)
                        }
                    }
                    Spacer()
                    if page < urls.count - 1 {
                        carouselArrowButton(systemName: "chevron.right", size: 10) {
                            navigatePage(delta: 1)
                        }
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }

            // Page dots
            if urls.count > 1 {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<urls.count, id: \.self) { index in
                        Circle()
                            .fill(index == page ? CiderColors.textOnColor : CiderColors.textOnColor.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.sm)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                )
                .padding(.bottom, Spacing.sm)
            }

            // Image count badge
            VStack {
                HStack {
                    Text("\(page + 1)/\(urls.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(CiderColors.textOnColor)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                        )
                        .padding(Spacing.sm)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func navigatePage(delta: Int) {
        let target = max(0, min(page + delta, urls.count - 1))
        guard target != page else { return }
        withAnimation(.snappy) { currentPage = target }
    }

    private func carouselArrowButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(CiderColors.textOnColor)
                .frame(width: size + 12, height: size + 12)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }
}

struct CarouselPageImage: View {
    let url: URL
    var fillMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fillMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let w = CGFloat(cgImage.width)
            let h = CGFloat(cgImage.height)
            guard w > 0, h > 0 else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
        }.value
    }
}

// MARK: - Carousel Scroll Wheel Overlay

/// Intercepts scroll wheel events and converts horizontal/vertical scroll into page navigation.
struct CarouselScrollWheelOverlay: NSViewRepresentable {
    let onPageDelta: (Int) -> Void

    func makeNSView(context: Context) -> CarouselScrollWheelNSView {
        CarouselScrollWheelNSView(onPageDelta: onPageDelta)
    }

    func updateNSView(_ nsView: CarouselScrollWheelNSView, context: Context) {
        nsView.onPageDelta = onPageDelta
    }
}

final class CarouselScrollWheelNSView: NSView {
    var onPageDelta: (Int) -> Void
    private var accumulatedDelta: CGFloat = 0
    private let threshold: CGFloat = 30

    init(onPageDelta: @escaping (Int) -> Void) {
        self.onPageDelta = onPageDelta
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        // Use scrollingDeltaX for horizontal scroll, deltaY for vertical
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : -event.scrollingDeltaY

        if event.phase == .began {
            accumulatedDelta = 0
        }

        accumulatedDelta += delta

        if accumulatedDelta > threshold {
            accumulatedDelta = 0
            onPageDelta(1)
        } else if accumulatedDelta < -threshold {
            accumulatedDelta = 0
            onPageDelta(-1)
        }

        // Reset on end/cancelled
        if event.phase == .ended || event.phase == .cancelled {
            accumulatedDelta = 0
        }
    }
}

// MARK: - Animated GIF View

/// Displays an animated GIF/WebP/APNG using NSImageView.
/// For `.fill` content mode, the NSImageView is oversized to simulate aspect-fill
/// (NSImageView only supports aspect-fit natively) and the wrapper clips the overflow.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill

    func makeNSView(context: Context) -> AnimatedGIFWrapper {
        let wrapper = AnimatedGIFWrapper(contentMode: contentMode)
        if let image = NSImage(contentsOf: url) {
            wrapper.setImage(image)
        }
        context.coordinator.loadedURL = url
        return wrapper
    }

    func updateNSView(_ wrapper: AnimatedGIFWrapper, context: Context) {
        wrapper.contentFillMode = contentMode
        if context.coordinator.loadedURL != url, let image = NSImage(contentsOf: url) {
            wrapper.setImage(image)
            context.coordinator.loadedURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator {
        var loadedURL: URL
        init(url: URL) { loadedURL = url }
    }
}

/// Custom NSView that wraps NSImageView and handles aspect-fill by oversizing
/// the image view and clipping the container.
final class AnimatedGIFWrapper: NSView {
    var contentFillMode: ContentMode = .fill
    private let imageView = NSImageView()
    private var imageAspectRatio: CGFloat = 1.0 // width / height

    init(contentMode: ContentMode) {
        self.contentFillMode = contentMode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.isEditable = false
        imageView.canDrawSubviewsIntoLayer = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: NSImage) {
        imageView.image = image
        let size = image.size
        imageAspectRatio = size.height > 0 ? size.width / size.height : 1.0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let containerW = bounds.width
        let containerH = bounds.height
        guard containerW > 0, containerH > 0 else { return }

        if contentFillMode == .fit {
            imageView.frame = bounds
            return
        }

        // Aspect-fill: scale image to cover the container, then center
        let containerAspect = containerW / containerH
        let imageW: CGFloat
        let imageH: CGFloat
        if imageAspectRatio > containerAspect {
            // Image is wider — match height, overflow width
            imageH = containerH
            imageW = containerH * imageAspectRatio
        } else {
            // Image is taller — match width, overflow height
            imageW = containerW
            imageH = containerW / imageAspectRatio
        }
        imageView.frame = CGRect(
            x: (containerW - imageW) / 2,
            y: (containerH - imageH) / 2,
            width: imageW,
            height: imageH
        )
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
