import AppKit
import SwiftUI

struct BookmarksPanelView: View {
    @ObservedObject var viewModel: BookmarksViewModel

    var body: some View {
        ZStack {
            PaletteBackgroundView(cornerRadius: BookmarksDesign.panelCornerRadius)

            VStack(spacing: 0) {
                titleBar

                if !viewModel.isCollapsed {
                    Divider()
                        .background(CiderColors.separator)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        TextField("Search bookmarks", text: $viewModel.searchText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView(showsIndicators: false) {
                            BookmarksBrowserView(
                                bookmarks: viewModel.filteredBookmarks,
                                displayMode: Binding(
                                    get: { viewModel.displayMode },
                                    set: { viewModel.setDisplayMode($0) }
                                ),
                                onOpenBookmark: { viewModel.open($0) },
                                onDeleteBookmark: { viewModel.delete($0) },
                                onAddBookmark: { viewModel.addBookmark(urlString: $0, title: $1) },
                                onAssignThumbnailFromDroppedString: { viewModel.assignThumbnail(for: $0, droppedString: $1) },
                                onAssignThumbnailFromLocalFileURL: { viewModel.assignThumbnail(for: $0, fileURL: $1) },
                                onAssignThumbnailFromImageData: { viewModel.assignThumbnail(for: $0, imageData: $1, preferredFileExtension: $2) },
                                onCaptureFromActiveBrowser: { viewModel.captureBookmarkFromActiveBrowserOrClipboard() },
                                onAddFromPasteboard: { viewModel.addBookmarkFromPasteboard() }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isCollapsed {
                BookmarksResizeHandle()
            }
        }
        .padding(.horizontal, BookmarksDesign.panelTopPadding)
        .padding(.top, BookmarksDesign.panelTopPadding)
        .padding(
            .bottom,
            viewModel.isCollapsed
                ? BookmarksDesign.panelCollapsedBottomPadding
                : BookmarksDesign.panelTopPadding
        )
    }

    @ViewBuilder
    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                BookmarksTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close bookmarks panel") {
                    NotificationCenter.default.post(name: .dismissBookmarks, object: nil)
                }
                BookmarksTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: viewModel.isCollapsed ? "Expand bookmarks" : "Collapse to strip"
                ) {
                    NotificationCenter.default.post(name: .toggleBookmarksCollapse, object: nil)
                }
                BookmarksTrafficLightButton(
                    color: .systemGreen,
                    symbol: "safari",
                    help: "Capture active browser tab"
                ) {
                    _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
                }
            }

            Text("Bookmarks")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CiderColors.primary)

            Text("\(viewModel.filteredBookmarks.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: Spacing.sm)

            Button {
                _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
            } label: {
                Label("Capture", systemImage: "safari")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: BookmarksDesign.buttonTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.controlAccent.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .help("Capture active browser tab (Option+Shift+B)")

            Button {
                NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
            } label: {
                Label("Palette", systemImage: "command")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: BookmarksDesign.toolbarHeight)
    }
}

// MARK: - Resize Handle

private struct BookmarksResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> BookmarksResizeHandleNSView {
        let view = BookmarksResizeHandleNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: BookmarksResizeHandleNSView, context: Context) {}
}

private final class BookmarksResizeHandleNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(
            systemSymbolName: "arrow.down.backward.and.arrow.up.forward",
            accessibilityDescription: "Resize"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        if let symbol {
            let size = symbol.size
            let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.35)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.frameResize(position: .bottomRight, directions: [.inward, .outward]).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let initialFrame = window.frame
        let initialMouse = NSEvent.mouseLocation

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                let width = max(BookmarksDesign.panelMinWidth, initialFrame.width + dx)
                let height = max(BookmarksDesign.panelMinHeight, initialFrame.height - dy)
                let y = initialFrame.origin.y + (initialFrame.height - height)

                window.setFrame(
                    NSRect(x: initialFrame.origin.x, y: y, width: width, height: height),
                    display: true
                )

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }
}

private struct BookmarksTrafficLightButton: View {
    let color: NSColor
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: NotesDesign.trafficLightDiameter, height: NotesDesign.trafficLightDiameter)
                .overlay {
                    if isHovered {
                        Image(systemName: symbol)
                            .font(.system(size: NotesDesign.trafficLightSymbolSize, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.65))
                    }
                }
                .frame(width: NotesDesign.trafficLightTapTarget, height: NotesDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .help(help)
    }
}
