import AppKit
import SwiftUI

enum BookmarkHeroMode: String { case thumbnail, web, reader }

struct DetailSlideOutView: View {
    @Binding var draft: BookmarkDetailsDraft
    var bookmark: Bookmark?
    var errorMessage: String?
    var folders: [Folder]
    var width: CGFloat = 0
    var maxWidth: CGFloat = 0
    var detailViewMode: DetailViewMode
    @Binding var isMetadataVisible: Bool
    @Binding var heroMode: BookmarkHeroMode
    var webViewStore: DetailWebViewStore
    var onResize: (CGFloat) -> Void = { _ in }
    var onDelete: () -> Void
    var onFolderChanged: (UUID?) -> Void
    var onOpenURL: () -> Void
    var onCopyURL: () -> Void
    var onSave: () -> Void
    var onFloat: (() -> Void)? = nil
    var onCancel: () -> Void
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil
    var onOpenKanbanCard: ((String, String) -> Void)? = nil
    var onOpenHubNavigationTarget: ((LibraryHubNavigationTarget) -> Void)? = nil
    var onModeChange: (DetailViewMode) -> Void
    var showDragHandle: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    @State private var webViewIsLoading: Bool = false
    @State private var preloadTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle (slide-out mode only)
            if showDragHandle {
                SlideOutDragHandle(width: width, maxWidth: maxWidth, onResize: onResize)
                    .frame(width: SlideOutDesign.dragHandleWidth)
            }

            // Content column — toolbar + divider + hero/title + metadata
            VStack(spacing: 0) {
                if detailViewMode != .page {
                    toolbar
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.xxs)
                        .padding(.bottom, Spacing.xs + 1)
                        .transaction { transaction in
                            if detailViewMode == .slideOut {
                                transaction.animation = nil
                            }
                        }

                    Divider()
                        .background(CiderColors.separator)
                        .padding(.leading, Spacing.md + Spacing.xxs)
                        .padding(.trailing, isMetadataVisible ? 0 : Spacing.md + Spacing.xxs)
                }

                // Content area — hero/title + metadata sidebar
                HStack(alignment: .top, spacing: 0) {
                    // Left column — title header + hero fills remaining height
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        if detailViewMode != .page {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(draft.title)
                                    .font(CiderFont.heroTitle(scale: textScale))
                                    .foregroundColor(CiderColors.primary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: Spacing.xs) {
                                    if draft.hasURL {
                                        Text(draft.hostDisplay)
                                            .font(CiderFont.labelMedium(scale: textScale))
                                            .foregroundColor(CiderColors.secondary)
                                        Text("\u{2022}")
                                            .font(CiderFont.captionSemibold(scale: textScale))
                                            .foregroundColor(CiderColors.tertiary)
                                    }
                                    Text(draft.updatedAt.formatted(.relative(presentation: .named)))
                                        .font(CiderFont.label(scale: textScale))
                                        .foregroundColor(CiderColors.tertiary)
                                }
                            }
                            .transaction { transaction in
                                if detailViewMode == .slideOut {
                                    transaction.animation = nil
                                }
                            }
                        }

                        ZStack {
                            // Thumbnail layer
                            BookmarkDetailsHeroPreview(bookmark: bookmark, draft: draft, isPageMode: detailViewMode == .page)
                                .shadow(
                                    color: CiderColors.shadowMedium,
                                    radius: BookmarksDesign.detailsFloatingLiftBlur,
                                    x: 0,
                                    y: BookmarksDesign.detailsFloatingLiftYOffset
                                )
                                .opacity(heroMode == .thumbnail ? 1 : 0)
                                .allowsHitTesting(heroMode == .thumbnail)

                            // Web layer — only instantiate when preload is ready or user switched to web mode
                            if let url = bookmark?.url, heroMode == .web || webViewStore.webViewReady {
                                ZStack {
                                    BookmarkWebView(url: url, isLoading: $webViewIsLoading, isActive: heroMode == .web, store: webViewStore)

                                    if !webViewStore.webViewReady {
                                        ProgressView()
                                            .controlSize(.large)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(CiderColors.surfaceSubtle)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
                                )
                                .opacity(heroMode == .web ? 1 : 0)
                                .allowsHitTesting(heroMode == .web)
                            }

                            // Reader layer (always present — content from cached extraction)
                            if let url = bookmark?.url, webViewStore.readerReady {
                                BookmarkReaderView(url: url, bookmarkID: bookmark?.id, store: webViewStore)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                            .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
                                    )
                                    .opacity(heroMode == .reader ? 1 : 0)
                                    .allowsHitTesting(heroMode == .reader)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right column — metadata sidebar (toggleable)
                    // No outer ScrollView — the sidebar manages its own scrolling
                    // and needs a bounded height to pin the footer to the bottom.
                    if isMetadataVisible {
                        BookmarkMetadataSidebar(
                            draft: $draft,
                            bookmark: bookmark,
                            errorMessage: errorMessage,
                            folders: folders,
                            width: BookmarksDesign.detailsSidebarFixedWidth,
                            showBackground: false,
                            onDelete: onDelete,
                            onFolderChanged: onFolderChanged,
                            onOpenURL: onOpenURL,
                            onCopyURL: onCopyURL,
                            onSave: onSave,
                            onCancel: onCancel,
                            onOpenLinkedRef: onOpenLinkedRef,
                            onOpenKanbanCard: onOpenKanbanCard,
                            onOpenHubNavigationTarget: onOpenHubNavigationTarget
                        )
                        .background(CiderColors.surfaceInput)
                        .overlay(alignment: .leading) {
                            CiderColors.separator
                                .frame(width: Spacing.hairline)
                        }
                        .transition(
                            .detailSlideOutSidebar(
                                style: DetailSlideOutMotionPolicy.sidebarTransitionStyle()
                            )
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .compositingGroup()
        .onChange(of: heroMode) { _, newMode in
            // Persist per-bookmark hero mode preference
            if let id = bookmark?.id {
                VaultBookmarkService.shared.setPreferredHeroMode(newMode.rawValue, for: id)
            }
        }
        .onChange(of: webViewStore.readerFailed) { _, failed in
            if failed, heroMode == .reader {
                withAnimation(reduceMotion ? .none : .snappy) { heroMode = .thumbnail }
            }
        }
        .onChange(of: bookmark?.id) { _, newID in
            webViewIsLoading = false
            webViewStore.reset()
            // Restore per-bookmark hero mode and reader availability
            if let bm = newID.flatMap({ id in VaultBookmarkService.shared.bookmarks.first { $0.id == id } }) {
                let isReaderUnavailable = bm.readerUnavailable == true
                let restored = bm.preferredHeroMode.flatMap(BookmarkHeroMode.init(rawValue:)) ?? .thumbnail
                heroMode = (restored == .reader && isReaderUnavailable) ? .thumbnail : restored
                schedulePreload(for: bm)
            } else {
                heroMode = .thumbnail
                preloadTask?.cancel()
            }
        }
        .onAppear {
            if let bm = bookmark, bm.hasURL {
                schedulePreload(for: bm)
            }
        }
        .onDisappear {
            preloadTask?.cancel()
        }
        .background {
            if detailViewMode != .page {
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                    CiderColors.acrylicOverlayTint
                    CiderColors.surfaceSubtle
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .overlay {
            if detailViewMode != .page {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Button State

    private var readerButtonDisabled: Bool {
        webViewStore.readerFailed || (!webViewStore.readerReady && heroMode != .reader)
    }

    private var readerButtonHelp: String {
        if webViewStore.readerFailed { return "Reader content not available for this page" }
        if !webViewStore.readerReady { return "Extracting reader content..." }
        return "Reader view"
    }

    private func schedulePreload(for bookmark: Bookmark) {
        preloadTask?.cancel()
        guard bookmark.hasURL, let url = bookmark.url else { return }

        let bookmarkID = bookmark.id
        let delay = DetailSlideOutMotionPolicy.preloadDelay(for: detailViewMode)
        preloadTask = Task { @MainActor in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            webViewStore.preload(url: url, bookmarkID: bookmarkID)
        }
    }

    // MARK: - Hero Mode Button

    @ViewBuilder
    private func heroModeButton(symbol: String, mode: BookmarkHeroMode, isLoading: Bool, isDisabled: Bool, help: String) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                heroMode = heroMode == mode ? .thumbnail : mode
            }
        } label: {
            ZStack {
                Image(systemName: symbol)
                    .font(CiderFont.label)
                    .foregroundColor(isDisabled ? CiderColors.quaternary : (heroMode == mode ? CiderColors.controlAccent : CiderColors.tertiary))
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
            }
            .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            // Close button
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: DetailToolbarDesign.largeButtonSize, height: DetailToolbarDesign.largeButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")

            // AI actions
            if let bookmark {
                AIDetailActionsButton(
                    bookmarkTitle: bookmark.title,
                    bookmarkURL: bookmark.urlString
                )
            }

            Spacer(minLength: 0)

            // Hero mode buttons (URL bookmarks only)
            if draft.hasURL {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) { heroMode = .thumbnail }
                } label: {
                    Image(systemName: "photo")
                        .font(CiderFont.label)
                        .foregroundColor(heroMode == .thumbnail ? CiderColors.controlAccent : CiderColors.tertiary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Preview")

                heroModeButton(
                    symbol: "doc.richtext",
                    mode: .reader,
                    isLoading: !webViewStore.readerReady && !webViewStore.readerFailed,
                    isDisabled: readerButtonDisabled,
                    help: readerButtonHelp
                )

                heroModeButton(
                    symbol: "globe",
                    mode: .web,
                    isLoading: heroMode == .web && !webViewStore.webViewReady,
                    isDisabled: false,
                    help: webViewStore.webViewReady ? "View live page" : "Loading page..."
                )
            }

            ItemMetadataToggleButton(isVisible: $isMetadataVisible)

            if let onFloat {
                Button(action: onFloat) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(CiderFont.label)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Float")
            }

            // Mode toggle
            DetailViewModePicker(currentMode: detailViewMode, onChange: onModeChange)
        }
    }

}

// MARK: - Bookmark Page Toolbar (Title Bar Controls)

struct BookmarkPageToolbar: View {
    var hasURL: Bool
    var readerFailed: Bool
    var readerReady: Bool
    var webViewReady: Bool
    @Binding var heroMode: BookmarkHeroMode
    @Binding var isMetadataVisible: Bool
    var onFloat: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readerDisabled: Bool {
        readerFailed || (!readerReady && heroMode != .reader)
    }

    private var readerHelp: String {
        if readerFailed { return "Reader content not available for this page" }
        if !readerReady { return "Extracting reader content..." }
        return "Reader view"
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if hasURL {
                toolbarButton("photo", active: heroMode == .thumbnail, help: "Preview") {
                    withAnimation(reduceMotion ? .none : .snappy) { heroMode = .thumbnail }
                }
                toolbarButton("doc.richtext", active: heroMode == .reader, disabled: readerDisabled, loading: !readerReady && !readerFailed, help: readerHelp) {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        heroMode = heroMode == .reader ? .thumbnail : .reader
                    }
                }
                toolbarButton("globe", active: heroMode == .web, loading: heroMode == .web && !webViewReady, help: webViewReady ? "View live page" : "Loading page...") {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        heroMode = heroMode == .web ? .thumbnail : .web
                    }
                }
            }

            if let onFloat {
                toolbarButton("rectangle.on.rectangle", active: false, help: "Float", action: onFloat)
            }

            ItemMetadataToggleButton(isVisible: $isMetadataVisible)
        }
    }

    @ViewBuilder
    private func toolbarButton(_ symbol: String, active: Bool, disabled: Bool = false, loading: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .font(CiderFont.label)
                    .foregroundColor(disabled ? CiderColors.quaternary : (active ? CiderColors.controlAccent : CiderColors.tertiary))
                    .opacity(loading ? 0 : 1)

                if loading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
            }
            .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

// MARK: - Design Constants

enum SlideOutDesign {
    static let dragHandleWidth: CGFloat = 6
}

// MARK: - Drag Handle (AppKit event-loop pattern)

struct SlideOutDragHandle: NSViewRepresentable {
    var width: CGFloat
    var maxWidth: CGFloat
    var onResize: (CGFloat) -> Void

    func makeNSView(context: Context) -> SlideOutDragHandleNSView {
        let view = SlideOutDragHandleNSView()
        view.currentWidth = width
        view.maxWidth = maxWidth
        view.onResize = onResize
        return view
    }

    func updateNSView(_ nsView: SlideOutDragHandleNSView, context: Context) {
        nsView.currentWidth = width
        nsView.maxWidth = maxWidth
        nsView.onResize = onResize
    }
}

final class SlideOutDragHandleNSView: NSView {
    var currentWidth: CGFloat = 400
    var maxWidth: CGFloat = 800
    var onResize: ((CGFloat) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - Drag

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startX = event.locationInWindow.x
        let startWidth = currentWidth

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let deltaX = startX - next.locationInWindow.x
                // Dragging left increases width (slide-out opens from the right)
                let clamped = min(maxWidth, max(BookmarksDesign.detailsSlideOutMinWidth, startWidth + deltaX))
                onResize?(clamped)
            case .leftMouseUp:
                keepRunning = false
            default:
                break
            }
        }
        NSCursor.arrow.set()
    }
}
