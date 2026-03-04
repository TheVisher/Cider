import AppKit
import SwiftUI
import WebKit

enum BookmarkHeroMode { case thumbnail, web, reader }

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
    var onResize: (CGFloat) -> Void = { _ in }
    var onDelete: () -> Void
    var onFolderChanged: (UUID?) -> Void
    var onOpenURL: () -> Void
    var onCopyURL: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    var onModeChange: (DetailViewMode) -> Void
    var showDragHandle: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    // Sidebar's own move transition is suppressed on first appearance to prevent
    // it from compounding with the parent panel's slide-in transition. Enabled
    // after first render so the info-button toggle animates correctly.
    @State private var sidebarTransitionEnabled: Bool = false
    @State private var webViewActivated: Bool = false
    @State private var webViewIsLoading: Bool = false
    @State private var readerViewActivated: Bool = false
    @State private var readerIsLoading: Bool = false

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

                            // Web layer
                            if webViewActivated, let url = bookmark?.url {
                                ZStack {
                                    BookmarkWebView(url: url, isLoading: $webViewIsLoading, isActive: heroMode == .web)

                                    if webViewIsLoading {
                                        ProgressView()
                                            .controlSize(.large)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(CiderColors.surfaceSubtle.opacity(0.6))
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

                            // Reader layer
                            if readerViewActivated, let url = bookmark?.url {
                                ZStack {
                                    BookmarkReaderView(url: url, isLoading: $readerIsLoading, bookmarkID: bookmark?.id)

                                    if readerIsLoading {
                                        ProgressView()
                                            .controlSize(.large)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(CiderColors.surfaceSubtle.opacity(0.6))
                                    }
                                }
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
                            onCancel: onCancel
                        )
                        .background(CiderColors.surfaceInput)
                        .overlay(alignment: .leading) {
                            CiderColors.separator
                                .frame(width: Spacing.hairline)
                        }
                        .transition(sidebarTransitionEnabled
                            ? .move(edge: .trailing).combined(with: .opacity)
                            : .identity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .onChange(of: bookmark?.id) { _, _ in
            heroMode = .thumbnail
            webViewActivated = false
            webViewIsLoading = false
            readerViewActivated = false
            readerIsLoading = false
        }
        .onAppear {
            // Enable the sidebar's own transition only after the first render,
            // so it doesn't compound with the parent panel's slide-in animation.
            DispatchQueue.main.async { sidebarTransitionEnabled = true }
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
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")

            Spacer(minLength: 0)

            // Hero mode buttons (URL bookmarks only)
            if draft.hasURL {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) { heroMode = .thumbnail }
                } label: {
                    Image(systemName: "photo")
                        .font(CiderFont.label)
                        .foregroundColor(heroMode == .thumbnail ? CiderColors.controlAccent : CiderColors.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Preview")

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        if heroMode == .reader {
                            heroMode = .thumbnail
                        } else {
                            if !readerViewActivated { readerViewActivated = true }
                            heroMode = .reader
                        }
                    }
                } label: {
                    Image(systemName: "doc.richtext")
                        .font(CiderFont.label)
                        .foregroundColor(heroMode == .reader ? CiderColors.controlAccent : CiderColors.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reader view")

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        if heroMode == .web {
                            heroMode = .thumbnail
                        } else {
                            if !webViewActivated { webViewActivated = true }
                            heroMode = .web
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(CiderFont.label)
                        .foregroundColor(heroMode == .web ? CiderColors.controlAccent : CiderColors.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("View live page")
            }

            // Metadata sidebar toggle
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isMetadataVisible.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isMetadataVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: isMetadataVisible ? "info.circle.fill" : "info.circle")
                            .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                            .foregroundColor(isMetadataVisible ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help(isMetadataVisible ? "Hide metadata" : "Show metadata")

            // Mode toggle
            DetailViewModePicker(currentMode: detailViewMode, onChange: onModeChange)
        }
    }

}

// MARK: - Bookmark Page Toolbar (Title Bar Controls)

struct BookmarkPageToolbar: View {
    var hasURL: Bool
    @Binding var heroMode: BookmarkHeroMode
    @Binding var isMetadataVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if hasURL {
                toolbarButton("photo", active: heroMode == .thumbnail, help: "Preview") {
                    withAnimation(reduceMotion ? .none : .snappy) { heroMode = .thumbnail }
                }
                toolbarButton("doc.richtext", active: heroMode == .reader, help: "Reader view") {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        heroMode = heroMode == .reader ? .thumbnail : .reader
                    }
                }
                toolbarButton("globe", active: heroMode == .web, help: "View live page") {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        heroMode = heroMode == .web ? .thumbnail : .web
                    }
                }
            }

            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isMetadataVisible.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isMetadataVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: isMetadataVisible ? "info.circle.fill" : "info.circle")
                            .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                            .foregroundColor(isMetadataVisible ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help(isMetadataVisible ? "Hide metadata" : "Show metadata")
        }
    }

    @ViewBuilder
    private func toolbarButton(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(CiderFont.label)
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
