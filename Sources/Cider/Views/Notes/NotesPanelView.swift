import SwiftUI
import AppKit

struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        ZStack {
            PaletteBackgroundView(
                cornerRadius: NotesDesign.cornerRadius,
                shadowStyle: viewModel.isCollapsed ? .compact : .full
            )

            VStack(spacing: 0) {
                NotesTitleBar(viewModel: viewModel)

                if !viewModel.isCollapsed {
                    Divider()
                        .background(CiderColors.separator)

                    if viewModel.isFormattingToolbarPinned {
                        NotesFormattingToolbar(viewModel: viewModel)

                        Divider()
                            .background(CiderColors.separator)
                    }

                    if viewModel.selectedNote != nil {
                        TipTapEditorView(viewModel: viewModel)
                    } else {
                        NotesEmptyState(onCreateNew: { viewModel.createNewNote() })
                    }

                    NotesStatusBar(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isCollapsed {
                NotesResizeHandle()
            }
        }
        .padding(.horizontal, NotesDesign.shadowPadding)
        .padding(.top, NotesDesign.panelTopPadding)
        .padding(
            .bottom,
            viewModel.isCollapsed
                ? NotesDesign.panelCollapsedBottomPadding
                : (NotesDesign.shadowPadding + NotesDesign.panelBottomPadding)
        )
    }
}

// MARK: - Resize Handle

/// AppKit-based resize handle to avoid SwiftUI DragGesture coordinate feedback loops.
private struct NotesResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

private final class ResizeHandleNSView: NSView {
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
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(systemSymbolName: "arrow.down.backward.and.arrow.up.forward",
                             accessibilityDescription: "Resize")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        if let symbol {
            let size = symbol.size
            let origin = NSPoint(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2)
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

        // Run our own event-tracking loop (same pattern as performDrag).
        // This completely owns mouse tracking until mouseUp.
        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                let w = max(NotesDesign.panelMinWidth, initialFrame.width + dx)
                let h = max(NotesDesign.panelMinHeight, initialFrame.height - dy)
                let y = initialFrame.origin.y + (initialFrame.height - h)

                window.setFrame(
                    NSRect(x: initialFrame.origin.x, y: y, width: w, height: h),
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

// MARK: - Title Bar

private struct NotesTitleBar: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var isEditingTitle = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                NotesTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close notes panel") {
                    viewModel.dismiss()
                }
                NotesTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: viewModel.isCollapsed ? "Expand note" : "Collapse to header"
                ) {
                    viewModel.toggleCollapsed()
                }
                NotesTrafficLightButton(
                    color: .systemGreen,
                    symbol: "arrow.up.right",
                    help: "Move to next display"
                ) {
                    viewModel.moveToNextDisplay()
                }
            }

            // Editable title
            if isEditingTitle {
                TextField("Note title", text: $viewModel.editingTitle, onCommit: {
                    viewModel.renameCurrentNote(to: viewModel.editingTitle)
                    isEditingTitle = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CiderColors.primary)
            } else {
                Text(viewModel.selectedNote?.title ?? "Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        if viewModel.selectedNote != nil {
                            isEditingTitle = true
                        }
                    }
            }

            Spacer()

            // Note switcher dropdown
            Menu {
                Button {
                    viewModel.createNewNote()
                } label: {
                    Label("New Note", systemImage: "plus")
                }

                if !viewModel.notes.isEmpty {
                    Divider()
                    ForEach(viewModel.notes) { note in
                        Button {
                            NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                        } label: {
                            if note.id == viewModel.selectedNote?.id {
                                Label(note.title, systemImage: "checkmark")
                            } else {
                                Text(note.title)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(CiderColors.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Switch note")

            // Formatting menu
            Menu {
                Button {
                    viewModel.toggleFormattingToolbarPinned()
                } label: {
                    Label(
                        viewModel.isFormattingToolbarPinned ? "Unpin Toolbar" : "Pin Toolbar",
                        systemImage: viewModel.isFormattingToolbarPinned ? "pin.slash" : "pin"
                    )
                }

                Divider()

                Section("History") {
                    Button {
                        viewModel.editorUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    Button {
                        viewModel.editorRedo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                }

                Section("Alignment") {
                    Button {
                        viewModel.editorAlignLeft()
                    } label: {
                        Label("Align Left", systemImage: "text.alignleft")
                    }
                    Button {
                        viewModel.editorAlignCenter()
                    } label: {
                        Label("Align Center", systemImage: "text.aligncenter")
                    }
                    Button {
                        viewModel.editorAlignRight()
                    } label: {
                        Label("Align Right", systemImage: "text.alignright")
                    }
                }

                Section("Text Style") {
                    Button {
                        viewModel.editorToggleBold()
                    } label: {
                        Label("Bold", systemImage: "bold")
                    }
                    Button {
                        viewModel.editorToggleItalic()
                    } label: {
                        Label("Italic", systemImage: "italic")
                    }
                    Button {
                        viewModel.editorToggleUnderline()
                    } label: {
                        Label("Underline", systemImage: "underline")
                    }
                    Button {
                        viewModel.editorPromptForLink()
                    } label: {
                        Label("Add Link", systemImage: "link.badge.plus")
                    }
                    Button {
                        viewModel.editorRemoveLink()
                    } label: {
                        Label("Remove Link", systemImage: "link.badge.minus")
                    }
                }

                Section("Lists") {
                    Button {
                        viewModel.editorToggleBulletList()
                    } label: {
                        Label("Bullet List", systemImage: "list.bullet")
                    }
                    Button {
                        viewModel.editorToggleOrderedList()
                    } label: {
                        Label("Numbered List", systemImage: "list.number")
                    }
                    Button {
                        viewModel.editorToggleTaskList()
                    } label: {
                        Label("Task List", systemImage: "checklist")
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CiderColors.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .disabled(viewModel.selectedNote == nil)
            .help("Formatting")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: NotesDesign.titleBarHeight)
    }
}

private struct NotesTrafficLightButton: View {
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

// MARK: - Formatting Toolbar

private struct NotesFormattingToolbar: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    NotesToolbarButton(symbol: "arrow.uturn.backward", help: "Undo", action: viewModel.editorUndo)
                    NotesToolbarButton(symbol: "arrow.uturn.forward", help: "Redo", action: viewModel.editorRedo)
                    NotesToolbarDivider()
                    NotesToolbarButton(symbol: "bold", help: "Bold", action: viewModel.editorToggleBold)
                    NotesToolbarButton(symbol: "italic", help: "Italic", action: viewModel.editorToggleItalic)
                    NotesToolbarButton(
                        symbol: "underline",
                        help: "Underline",
                        action: viewModel.editorToggleUnderline
                    )
                    NotesToolbarDivider()
                    NotesToolbarButton(
                        symbol: "text.alignleft",
                        help: "Align Left",
                        action: viewModel.editorAlignLeft
                    )
                    NotesToolbarButton(
                        symbol: "text.aligncenter",
                        help: "Align Center",
                        action: viewModel.editorAlignCenter
                    )
                    NotesToolbarButton(
                        symbol: "text.alignright",
                        help: "Align Right",
                        action: viewModel.editorAlignRight
                    )
                    NotesToolbarDivider()
                    NotesToolbarButton(
                        symbol: "link.badge.plus",
                        help: "Add Link",
                        action: viewModel.editorPromptForLink
                    )
                    NotesToolbarButton(
                        symbol: "link.badge.minus",
                        help: "Remove Link",
                        action: viewModel.editorRemoveLink
                    )
                    NotesToolbarDivider()
                    NotesToolbarButton(
                        symbol: "list.bullet",
                        help: "Bullet List",
                        action: viewModel.editorToggleBulletList
                    )
                    NotesToolbarButton(
                        symbol: "list.number",
                        help: "Numbered List",
                        action: viewModel.editorToggleOrderedList
                    )
                    NotesToolbarButton(
                        symbol: "checklist",
                        help: "Task List",
                        action: viewModel.editorToggleTaskList
                    )
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
            }
            .disabled(viewModel.selectedNote == nil)

            NotesToolbarButton(
                symbol: "pin.slash",
                help: "Unpin Toolbar",
                action: { viewModel.setFormattingToolbarPinned(false) }
            )
            .padding(.trailing, Spacing.md)
        }
        .frame(height: NotesDesign.toolbarHeight)
    }
}

private struct NotesToolbarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.separator.opacity(isHovered ? 0.45 : 0.22))
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                        .foregroundColor(CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered in
            isHovered = hovered
        }
        .help(help)
    }
}

private struct NotesToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(CiderColors.separator.opacity(0.7))
            .frame(width: 1, height: NotesDesign.toolbarDividerHeight)
            .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Empty State

private struct NotesEmptyState: View {
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)
            Text("No note selected")
                .font(.system(size: 13))
                .foregroundColor(CiderColors.secondary)
            Button("Create New Note") {
                onCreateNew()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(CiderColors.controlAccent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Bar

private struct NotesStatusBar: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.selectedNote != nil {
                Text("\(viewModel.charCount) chars")
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.tertiary)
            }
            Spacer()
            if viewModel.selectedNote != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.success.opacity(0.7))
                Text("Saved")
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
    }
}
