import SwiftUI

/// Centered floating detail modal over the canvas.
/// Split layout: hero content (left) + metadata sidebar (right).
struct CanvasDetailOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    // MARK: - Layout Constants

    private static let modalWidth: CGFloat = 800
    private static let minHeight: CGFloat = 400
    private static let sidebarWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Modal
            modalContent
                .frame(width: Self.modalWidth, height: modalHeight)
                .background { modalBackground }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                        .allowsHitTesting(false)
                }
                .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
        }
    }

    // MARK: - Modal Content

    @ViewBuilder
    private var modalContent: some View {
        if let selectedID = viewModel.selectedItemID,
           let uuid = UUID(uuidString: selectedID) {
            VStack(spacing: 0) {
                toolbar(for: uuid)

                Divider()
                    .background(CiderColors.separator)
                    .padding(.leading, Spacing.md + Spacing.xxs)

                // Split content area
                HStack(spacing: 0) {
                    heroColumn(for: uuid)

                    // Vertical separator
                    Rectangle()
                        .fill(CiderColors.separator)
                        .frame(width: 1)

                    metadataSidebar(for: uuid)
                        .frame(width: Self.sidebarWidth)
                        .background(CiderColors.surfaceInput)
                }
            }
        } else {
            unknownItemPlaceholder
        }
    }

    // MARK: - Helpers

    private var modalHeight: CGFloat {
        let target = canvasSize.height * 0.8
        let maxH = canvasSize.height - Spacing.xxl * 2
        return min(max(target, Self.minHeight), maxH)
    }

    private var modalBackground: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
            CiderColors.acrylicOverlayTint
            CiderColors.surfaceSubtle
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            onDismiss()
        }
    }

    private var unknownItemPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: Spacing.xxxl))
                .foregroundColor(CiderColors.tertiary)
            Text("Item not found")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private func toolbar(for uuid: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Title + domain
            toolbarTitle(for: uuid)

            Spacer(minLength: 0)

            // Actions (bookmark-only)
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                toolbarActions(for: bookmark)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.xs + 1)
    }

    @ViewBuilder
    private func toolbarTitle(for uuid: UUID) -> some View {
        if let bookmark = viewModel.bookmarkLookup[uuid] {
            VStack(alignment: .leading, spacing: 0) {
                Text(bookmark.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if bookmark.hasURL {
                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }
        } else if let note = viewModel.noteLookup[uuid] {
            Text(note.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        } else if let todo = viewModel.todoLookup[uuid] {
            Text(todo.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
    }

    private func toolbarActions(for bookmark: Bookmark) -> some View {
        HStack(spacing: Spacing.xs) {
            // Copy URL
            if bookmark.hasURL {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(bookmark.urlString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy URL")
            }

            // Open in browser
            if let url = bookmark.url {
                Button {
                    openURLSafely(url)
                } label: {
                    Image(systemName: "safari")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Browser")
            }
        }
    }

    // MARK: - Hero Column (Left)

    @ViewBuilder
    private func heroColumn(for uuid: UUID) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Sidebar (Right)

    @ViewBuilder
    private func metadataSidebar(for uuid: UUID) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
