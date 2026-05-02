import SwiftUI

/// A reusable panel chrome for non-bookmark item types (date cards, contacts, etc.).
/// Provides the same toolbar, drag handle, acrylic background, and view-mode switcher
/// as DetailSlideOutView, but with a single scrollable content column instead of a
/// hero + metadata sidebar split.
struct GenericItemDetailPanel<Content: View, ToolbarExtra: View, TrailingExtra: View, Metadata: View>: View {
    var title: String
    var detailViewMode: DetailViewMode
    var width: CGFloat = 0
    var maxWidth: CGFloat = 0
    var showDragHandle: Bool = true
    var showTitle: Bool = true
    var scrollsContent: Bool = true
    var onRenameTitle: ((String) -> Void)? = nil
    var isEditingTitle: Binding<Bool>? = nil
    var onResize: (CGFloat) -> Void = { _ in }
    var onFloat: (() -> Void)? = nil
    var onClose: () -> Void
    var onModeChange: (DetailViewMode) -> Void
    var metadataVisible: Binding<Bool>?
    var metadataWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    @ViewBuilder var toolbarExtra: () -> ToolbarExtra
    @ViewBuilder var trailingExtra: () -> TrailingExtra
    @ViewBuilder var metadata: () -> Metadata
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: 0) {
            if showDragHandle {
                SlideOutDragHandle(width: width, maxWidth: maxWidth, onResize: onResize)
                    .frame(width: SlideOutDesign.dragHandleWidth)
            }

            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xxs)
                    .padding(.bottom, Spacing.xs + 1)

                Divider()
                    .background(CiderColors.separator)
                    .padding(.leading, Spacing.md + Spacing.xxs)
                    .padding(.trailing, Spacing.md + Spacing.xxs)

                HStack(alignment: .top, spacing: 0) {
                    if scrollsContent {
                        ScrollView {
                            content()
                                .padding(Spacing.md)
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        content()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if metadataVisible?.wrappedValue == true {
                        metadata()
                            .frame(width: metadataWidth)
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
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                CiderColors.acrylicOverlayTint
                CiderColors.surfaceSubtle
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        ZStack {
            // Center layer: toolbar extras (always centered)
            toolbarExtra()

            // Edge layer: close button + title (left), trailing extras + view modes (right)
            HStack(spacing: Spacing.sm) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: DetailToolbarDesign.largeButtonSize, height: DetailToolbarDesign.largeButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")

                if showTitle {
                    EditableTitleLabel(
                        title: title,
                        onRename: onRenameTitle,
                        isEditingExternal: isEditingTitle
                    )
                    .layoutPriority(-1)
                }

                Spacer(minLength: 0)

                if let metadataVisible {
                    ItemMetadataToggleButton(isVisible: metadataVisible)
                }

                trailingExtra()

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

                DetailViewModePicker(currentMode: detailViewMode, onChange: onModeChange)
            }
        }
    }

}

// MARK: - Convenience initializer for callers without toolbar extras

extension GenericItemDetailPanel where ToolbarExtra == EmptyView, TrailingExtra == EmptyView, Metadata == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onRenameTitle: ((String) -> Void)? = nil,
        isEditingTitle: Binding<Bool>? = nil,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.onRenameTitle = onRenameTitle
        self.isEditingTitle = isEditingTitle
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.metadataVisible = nil
        self.metadataWidth = BookmarksDesign.detailsSidebarFixedWidth
        self.toolbarExtra = { EmptyView() }
        self.trailingExtra = { EmptyView() }
        self.metadata = { EmptyView() }
        self.content = content
    }
}

// MARK: - Editable Title Label

/// Double-click to rename inline. Shows as a plain text label normally.
private struct EditableTitleLabel: View {
    let title: String
    var onRename: ((String) -> Void)?
    var isEditingExternal: Binding<Bool>?

    @State private var isEditing = false
    @State private var draftName = ""

    @Environment(\.textScale) private var textScale

    var body: some View {
        if isEditing, onRename != nil {
            TextField("Title", text: $draftName)
                .textFieldStyle(.plain)
                .font(CiderFont.labelMedium(scale: textScale))
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .fixedSize()
                .frame(maxWidth: GenericItemDetailDesign.titleFieldMaxWidth, alignment: .leading)
                .onSubmit { commit() }
                .lineLimit(1)
        } else {
            Text(title)
                .font(CiderFont.labelMedium(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    guard onRename != nil else { return }
                    draftName = title
                    setEditing(true)
                }
                .help(onRename != nil ? "Double-click to rename" : title)
        }
    }

    private func setEditing(_ value: Bool) {
        isEditing = value
        isEditingExternal?.wrappedValue = value
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != title {
            onRename?(trimmed)
        }
        setEditing(false)
    }
}

extension GenericItemDetailPanel where Metadata == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onRenameTitle: ((String) -> Void)? = nil,
        isEditingTitle: Binding<Bool>? = nil,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder toolbarExtra: @escaping () -> ToolbarExtra,
        @ViewBuilder trailingExtra: @escaping () -> TrailingExtra,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.onRenameTitle = onRenameTitle
        self.isEditingTitle = isEditingTitle
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.metadataVisible = nil
        self.metadataWidth = BookmarksDesign.detailsSidebarFixedWidth
        self.toolbarExtra = toolbarExtra
        self.trailingExtra = trailingExtra
        self.metadata = { EmptyView() }
        self.content = content
    }
}

extension GenericItemDetailPanel where ToolbarExtra == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onRenameTitle: ((String) -> Void)? = nil,
        isEditingTitle: Binding<Bool>? = nil,
        metadataVisible: Binding<Bool>,
        metadataWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder trailingExtra: @escaping () -> TrailingExtra,
        @ViewBuilder metadata: @escaping () -> Metadata,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.onRenameTitle = onRenameTitle
        self.isEditingTitle = isEditingTitle
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.metadataVisible = metadataVisible
        self.metadataWidth = metadataWidth
        self.toolbarExtra = { EmptyView() }
        self.trailingExtra = trailingExtra
        self.metadata = metadata
        self.content = content
    }
}

extension GenericItemDetailPanel where ToolbarExtra == EmptyView, Metadata == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onRenameTitle: ((String) -> Void)? = nil,
        isEditingTitle: Binding<Bool>? = nil,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder trailingExtra: @escaping () -> TrailingExtra,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.onRenameTitle = onRenameTitle
        self.isEditingTitle = isEditingTitle
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.metadataVisible = nil
        self.metadataWidth = BookmarksDesign.detailsSidebarFixedWidth
        self.toolbarExtra = { EmptyView() }
        self.trailingExtra = trailingExtra
        self.metadata = { EmptyView() }
        self.content = content
    }
}

extension GenericItemDetailPanel where TrailingExtra == EmptyView, Metadata == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onRenameTitle: ((String) -> Void)? = nil,
        isEditingTitle: Binding<Bool>? = nil,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder toolbarExtra: @escaping () -> ToolbarExtra,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.onRenameTitle = onRenameTitle
        self.isEditingTitle = isEditingTitle
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.metadataVisible = nil
        self.metadataWidth = BookmarksDesign.detailsSidebarFixedWidth
        self.toolbarExtra = toolbarExtra
        self.trailingExtra = { EmptyView() }
        self.metadata = { EmptyView() }
        self.content = content
    }
}
