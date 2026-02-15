import SwiftUI
import AppKit

struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
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

                    if viewModel.selectedNote != nil, let state = viewModel.externalChangeState {
                        NotesExternalChangeBanner(
                            state: state,
                            onReload: { viewModel.reloadFromDiskAfterExternalChange() },
                            onKeepMine: { viewModel.keepMineAfterExternalChange() }
                        )
                        Divider()
                            .background(CiderColors.separator)
                    }

                    if viewModel.selectedNote != nil, viewModel.isFindBarVisible {
                        NotesFindBar(viewModel: viewModel)

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
        .padding(.horizontal, NotesDesign.panelTopPadding)
        .padding(.top, NotesDesign.panelTopPadding)
        .padding(
            .bottom,
            viewModel.isCollapsed
                ? NotesDesign.panelCollapsedBottomPadding
                : NotesDesign.panelTopPadding
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
    @State private var showRestoreSnapshotAlert = false
    @State private var pendingSnapshotChoice: NotesRecoverySnapshotChoice?

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
                        viewModel.showFindBar()
                    } label: {
                        Label("Find in Note", systemImage: "magnifyingglass")
                    }

                    Divider()

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

                Section("Recovery") {
                    if viewModel.recoverySnapshotChoices.isEmpty {
                        Button("No snapshots yet") {}
                            .disabled(true)
                    } else {
                        Menu {
                            ForEach(viewModel.recoverySnapshotChoices) { choice in
                                Button {
                                    queueSnapshotRestore(choice)
                                } label: {
                                    Text(
                                        "\(choice.title) (\(choice.snapshotDate.formatted(.relative(presentation: .named))))"
                                    )
                                }
                            }
                        } label: {
                            Label("Quick Restore", systemImage: "clock.arrow.circlepath")
                        }

                        Menu {
                            ForEach(Array(viewModel.allRecoverySnapshotChoices.prefix(12))) { choice in
                                Button {
                                    queueSnapshotRestore(choice)
                                } label: {
                                    Text(choice.title)
                                }
                            }

                            if viewModel.allRecoverySnapshotChoices.count > 12 {
                                Divider()
                                Text("Showing 12 newest snapshots")
                            }
                        } label: {
                            Label("All Snapshots", systemImage: "clock")
                        }
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

                Section("Selection Text Size") {
                    Button("Small") {
                        viewModel.editorSetTextSizeSmall()
                    }
                    Button("Normal") {
                        viewModel.editorSetTextSizeNormal()
                    }
                    Button("Large") {
                        viewModel.editorSetTextSizeLarge()
                    }
                    Button("Extra Large") {
                        viewModel.editorSetTextSizeExtraLarge()
                    }
                    Button("Reset Size") {
                        viewModel.editorResetTextSize()
                    }
                }

                Section("Note Text Size") {
                    ForEach(NotesEditorTextSize.allCases, id: \.self) { size in
                        Button {
                            viewModel.setNotesEditorTextSize(size)
                        } label: {
                            if viewModel.notesEditorTextSize == size {
                                Label(size.displayName, systemImage: "checkmark")
                            } else {
                                Text(size.displayName)
                            }
                        }
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

                Section("Table") {
                    Button("Insert Table") {
                        viewModel.editorInsertTable()
                    }
                    Button("Add Row Above") {
                        viewModel.editorAddRowBefore()
                    }
                    Button("Add Row Below") {
                        viewModel.editorAddRowAfter()
                    }
                    Button("Delete Row") {
                        viewModel.editorDeleteRow()
                    }
                    Button("Add Column Left") {
                        viewModel.editorAddColumnBefore()
                    }
                    Button("Add Column Right") {
                        viewModel.editorAddColumnAfter()
                    }
                    Button("Delete Column") {
                        viewModel.editorDeleteColumn()
                    }
                    Button("Merge Cells") {
                        viewModel.editorMergeCells()
                    }
                    Button("Split Cell") {
                        viewModel.editorSplitCell()
                    }
                    Button("Toggle Header Row") {
                        viewModel.editorToggleHeaderRow()
                    }
                    Button("Toggle Header Column") {
                        viewModel.editorToggleHeaderColumn()
                    }
                    Button("Delete Table") {
                        viewModel.editorDeleteTable()
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
        .alert("Restore snapshot?", isPresented: $showRestoreSnapshotAlert) {
            Button("Restore", role: .destructive) {
                if let choice = pendingSnapshotChoice {
                    viewModel.restoreSnapshot(choice)
                }
                pendingSnapshotChoice = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSnapshotChoice = nil
            }
        } message: {
            if let choice = pendingSnapshotChoice {
                Text(
                    "This replaces the current note with the \(choice.title.lowercased()) snapshot from \(choice.snapshotDate.formatted(date: .abbreviated, time: .shortened))."
                )
            } else {
                Text("This replaces the current note with the latest saved snapshot.")
            }
        }
    }

    private func queueSnapshotRestore(_ choice: NotesRecoverySnapshotChoice) {
        pendingSnapshotChoice = choice
        showRestoreSnapshotAlert = true
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
                    NotesToolbarDivider()
                    NotesToolbarButton(
                        symbol: "tablecells",
                        help: "Insert Table",
                        action: viewModel.editorInsertTable
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

private struct NotesExternalChangeBanner: View {
    let state: NotesExternalChangeState
    let onReload: () -> Void
    let onKeepMine: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CiderColors.secondary)

            Text("This note changed outside Cider (\(state.modifiedAt.formatted(.relative(presentation: .named))))")
                .font(.system(size: 11))
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Button("Reload") {
                onReload()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(CiderColors.controlAccent)

            Button("Keep Mine") {
                onKeepMine()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(height: NotesDesign.toolbarHeight)
    }
}

private struct NotesFindBar: View {
    @ObservedObject var viewModel: NotesViewModel

    private var statusText: String {
        guard !viewModel.findQuery.isEmpty else { return "" }
        guard viewModel.findMatchCount > 0 else { return "No matches" }
        return "\(viewModel.findMatchIndex)/\(viewModel.findMatchCount)"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CiderColors.tertiary)

            NotesFindTextField(
                text: Binding(
                    get: { viewModel.findQuery },
                    set: { viewModel.updateFindQuery($0) }
                ),
                placeholder: "Find in note",
                focusToken: viewModel.findFocusToken,
                onMoveUp: viewModel.findPreviousResult,
                onMoveDown: viewModel.findNextResult,
                onEscape: viewModel.hideFindBar
            )

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            NotesToolbarButton(symbol: "chevron.up", help: "Previous Match", action: viewModel.findPreviousResult)
                .disabled(viewModel.findQuery.isEmpty)
            NotesToolbarButton(symbol: "chevron.down", help: "Next Match", action: viewModel.findNextResult)
                .disabled(viewModel.findQuery.isEmpty)
            NotesToolbarButton(symbol: "xmark", help: "Close Find", action: viewModel.hideFindBar)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: NotesDesign.findBarHeight)
    }
}

private struct NotesFindTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: UUID
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 12)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onEscape = onEscape

        if nsView.stringValue != text {
            context.coordinator.isSyncingProgrammaticText = true
            nsView.stringValue = text
            context.coordinator.isSyncingProgrammaticText = false
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            context.coordinator.requestFocus(on: nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        var lastFocusToken: UUID?
        var isSyncingProgrammaticText = false
        var onMoveUp: () -> Void = {}
        var onMoveDown: () -> Void = {}
        var onEscape: () -> Void = {}

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isSyncingProgrammaticText else { return }
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveUp()
                return true

            case #selector(NSResponder.moveDown(_:)):
                onMoveDown()
                return true

            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true

            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                if flags.contains(.shift) {
                    onMoveUp()
                } else {
                    onMoveDown()
                }
                return true

            default:
                return false
            }
        }

        func requestFocus(on textField: NSTextField) {
            let focusDelays: [TimeInterval] = [0, 0.03, 0.1]
            for delay in focusDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textField] in
                    guard let textField, let window = textField.window else { return }
                    if window.firstResponder !== textField {
                        window.makeFirstResponder(textField)
                    }

                    if let editor = window.fieldEditor(false, for: textField) as? NSTextView {
                        editor.selectedRange = NSRange(
                            location: textField.stringValue.count,
                            length: 0
                        )
                    }
                }
            }
        }
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
                Image(systemName: viewModel.hasPendingSave ? "clock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(
                        viewModel.hasPendingSave
                            ? CiderColors.tertiary
                            : CiderColors.success.opacity(0.7)
                    )
                Text(viewModel.hasPendingSave ? "Saving..." : "Saved")
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
    }
}
