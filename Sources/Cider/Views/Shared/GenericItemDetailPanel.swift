import SwiftUI

/// A reusable panel chrome for non-bookmark item types (date cards, contacts, etc.).
/// Provides the same toolbar, drag handle, acrylic background, and view-mode switcher
/// as DetailSlideOutView, but with a single scrollable content column instead of a
/// hero + metadata sidebar split.
struct GenericItemDetailPanel<Content: View, ToolbarExtra: View, TrailingExtra: View>: View {
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
    var onClose: () -> Void
    var onModeChange: (DetailViewMode) -> Void
    @ViewBuilder var toolbarExtra: () -> ToolbarExtra
    @ViewBuilder var trailingExtra: () -> TrailingExtra
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

                if scrollsContent {
                    ScrollView {
                        content()
                            .padding(Spacing.md)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
                } else {
                    content()
                        .frame(maxHeight: .infinity)
                }
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

                trailingExtra()

                DetailViewModePicker(currentMode: detailViewMode, onChange: onModeChange)
            }
        }
    }

}

// MARK: - Convenience initializer for callers without toolbar extras

extension GenericItemDetailPanel where ToolbarExtra == EmptyView, TrailingExtra == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onResize: @escaping (CGFloat) -> Void = { _ in },
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
        self.onResize = onResize
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.toolbarExtra = { EmptyView() }
        self.trailingExtra = { EmptyView() }
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

extension GenericItemDetailPanel where TrailingExtra == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        onResize: @escaping (CGFloat) -> Void = { _ in },
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
        self.onResize = onResize
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.toolbarExtra = toolbarExtra
        self.trailingExtra = { EmptyView() }
        self.content = content
    }
}
