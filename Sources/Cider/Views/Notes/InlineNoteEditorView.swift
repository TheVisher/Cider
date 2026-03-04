import SwiftUI

struct InlineNoteEditorView: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        VStack(spacing: 0) {
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

            if viewModel.selectedNote != nil || viewModel.activeExternalFile != nil {
                TipTapEditorView(viewModel: viewModel)
            } else {
                NotesEditorEmptyState(onCreateNew: { viewModel.createNewNote() })
            }

            if viewModel.isMetadataPanelVisible, let note = viewModel.selectedNote {
                Divider().background(CiderColors.separator)
                NoteMetadataBar(note: note, viewModel: viewModel)
            }

            NotesStatusBar(viewModel: viewModel)
        }
    }
}

// MARK: - Compact Formatting Toolbar (Title Bar)

struct NotesCompactToolbar: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var showTextStylePopover = false
    @State private var showTablePopover = false
    @State private var showSnapshotPopover = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            NotesToolbarButton(symbol: "arrow.uturn.backward", help: "Undo", action: viewModel.editorUndo)
            NotesToolbarButton(symbol: "arrow.uturn.forward", help: "Redo", action: viewModel.editorRedo)

            NotesToolbarDivider()

            Button {
                showTextStylePopover.toggle()
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(showTextStylePopover ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Text("Aa")
                            .font(.system(size: NotesDesign.toolbarIconSize + 1, weight: .semibold, design: .rounded))
                            .foregroundColor(showTextStylePopover ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Text Styles")
            .popover(isPresented: $showTextStylePopover, arrowEdge: .bottom) {
                NotesTextStylePopover(viewModel: viewModel)
            }

            NotesToolbarDivider()

            Button {
                showTablePopover.toggle()
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(showTablePopover ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: "tablecells")
                            .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                            .foregroundColor(showTablePopover ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Table")
            .popover(isPresented: $showTablePopover, arrowEdge: .bottom) {
                NotesTablePopover(viewModel: viewModel, isPresented: $showTablePopover)
            }

            NotesToolbarButton(symbol: "link.badge.plus", help: "Add Link", action: viewModel.editorPromptForLink)

            NotesToolbarDivider()

            Button {
                showSnapshotPopover.toggle()
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(showSnapshotPopover ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                            .foregroundColor(showSnapshotPopover ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Version History")
            .disabled(viewModel.selectedNote == nil || !viewModel.hasSnapshots)
            .popover(isPresented: $showSnapshotPopover, arrowEdge: .bottom) {
                NoteSnapshotPopover(viewModel: viewModel, isPresented: $showSnapshotPopover)
            }

            Button {
                viewModel.isMetadataPanelVisible.toggle()
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(viewModel.isMetadataPanelVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: viewModel.isMetadataPanelVisible ? "info.circle.fill" : "info.circle")
                            .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                            .foregroundColor(viewModel.isMetadataPanelVisible ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help(viewModel.isMetadataPanelVisible ? "Hide Info" : "Show Info")
        }
        .disabled(viewModel.selectedNote == nil && viewModel.activeExternalFile == nil)
    }
}

// MARK: - Text Style Popover

struct NotesTextStylePopover: View {
    @ObservedObject var viewModel: NotesViewModel

    private var fmt: EditorFormatState { viewModel.editorFormatState }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Inline styles
            HStack(spacing: Spacing.xs) {
                inlineToggle("B", font: .system(size: 13, weight: .bold), active: fmt.bold, action: viewModel.editorToggleBold)
                inlineToggle("I", font: .system(size: 13, weight: .regular, design: .serif).italic(), active: fmt.italic, action: viewModel.editorToggleItalic)
                inlineToggle("U", font: .system(size: 13, weight: .medium), active: fmt.underline, action: viewModel.editorToggleUnderline, underlined: true)
                inlineToggle("S", font: .system(size: 13, weight: .medium), active: fmt.strike, action: viewModel.editorToggleStrike, strikethrough: true)
                inlineToggleIcon("highlighter", active: fmt.highlight, action: viewModel.editorToggleHighlight)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            // Section 2: Text alignment
            HStack(spacing: Spacing.xs) {
                alignButton("text.alignleft", alignment: "left")
                alignButton("text.aligncenter", alignment: "center")
                alignButton("text.alignright", alignment: "right")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            Divider().padding(.horizontal, Spacing.sm)

            // Section 3: Paragraph styles
            VStack(alignment: .leading, spacing: 0) {
                paragraphRow("Title", active: fmt.heading == 1) { viewModel.editorSetHeading(1) }
                paragraphRow("Heading", active: fmt.heading == 2) { viewModel.editorSetHeading(2) }
                paragraphRow("Subheading", active: fmt.heading == 3) { viewModel.editorSetHeading(3) }
                paragraphRow("Body", active: fmt.heading == 0 && !fmt.codeBlock) { viewModel.editorSetParagraph() }
                paragraphRow("Monostyled", active: fmt.codeBlock) { viewModel.editorToggleCodeBlock() }
            }
            .padding(.vertical, Spacing.xs)

            Divider().padding(.horizontal, Spacing.sm)

            // Section 4: Lists
            VStack(alignment: .leading, spacing: 0) {
                listRow("list.bullet", title: "Bulleted List", active: fmt.bulletList, action: viewModel.editorToggleBulletList)
                listRow("list.number", title: "Numbered List", active: fmt.orderedList, action: viewModel.editorToggleOrderedList)
                listRow("checklist", title: "Task List", active: fmt.taskList, action: viewModel.editorToggleTaskList)
            }
            .padding(.vertical, Spacing.xs)

            Divider().padding(.horizontal, Spacing.sm)

            // Section 5: Block elements
            VStack(alignment: .leading, spacing: 0) {
                listRow("text.quote", title: "Block Quote", active: fmt.blockquote, action: viewModel.editorToggleBlockquote)
                listRow("minus", title: "Horizontal Rule", active: false, action: viewModel.editorInsertHorizontalRule)
            }
            .padding(.vertical, Spacing.xs)
        }
        .frame(width: 200)
    }

    // MARK: - Inline toggle button

    @ViewBuilder
    private func inlineToggle(
        _ label: String,
        font: Font,
        active: Bool,
        action: @escaping () -> Void,
        underlined: Bool = false,
        strikethrough: Bool = false
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .underline(underlined)
                .strikethrough(strikethrough)
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(active ? CiderColors.accentSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inlineToggleIcon(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(active ? CiderColors.accentSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alignment button

    @ViewBuilder
    private func alignButton(_ symbol: String, alignment: String) -> some View {
        let active = fmt.textAlign == alignment
        Button {
            switch alignment {
            case "left": viewModel.editorAlignLeft()
            case "center": viewModel.editorAlignCenter()
            case "right": viewModel.editorAlignRight()
            default: break
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(active ? CiderColors.accentSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paragraph style row

    @ViewBuilder
    private func paragraphRow(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)
                    .opacity(active ? 1 : 0)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List / block row

    @ViewBuilder
    private func listRow(_ symbol: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)
                    .opacity(active ? 1 : 0)

                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Table Popover

struct NotesTablePopover: View {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isPresented: Bool
    @State private var hoveredRow = 0
    @State private var hoveredCol = 0

    private let gridSize = 5
    private let cellSize: CGFloat = 18
    private let cellSpacing: CGFloat = 2

    private var fmt: EditorFormatState { viewModel.editorFormatState }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grid picker
            VStack(spacing: cellSpacing) {
                ForEach(1...gridSize, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(1...gridSize, id: \.self) { col in
                            let highlighted = hoveredRow > 0 && hoveredCol > 0 && row <= hoveredRow && col <= hoveredCol
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(highlighted ? CiderColors.controlAccent : CiderColors.separatorSubtle)
                                .frame(width: cellSize, height: cellSize)
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredRow = row
                                        hoveredCol = col
                                    }
                                }
                                .onTapGesture {
                                    viewModel.editorInsertTable(rows: row, cols: col)
                                    isPresented = false
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            .onHover { isHovered in
                if !isHovered {
                    hoveredRow = 0
                    hoveredCol = 0
                }
            }

            Text(hoveredRow > 0 && hoveredCol > 0 ? "\(hoveredCol) \u{00D7} \(hoveredRow)" : "Insert Table")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Spacing.sm)

            if fmt.inTable {
                Divider().padding(.horizontal, Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    tableRow("arrow.up", title: "Add Row Above", action: viewModel.editorAddRowBefore)
                    tableRow("arrow.down", title: "Add Row Below", action: viewModel.editorAddRowAfter)
                    tableRow("trash", title: "Delete Row", destructive: true, action: viewModel.editorDeleteRow)
                }
                .padding(.vertical, Spacing.xs)

                Divider().padding(.horizontal, Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    tableRow("arrow.left", title: "Add Column Left", action: viewModel.editorAddColumnBefore)
                    tableRow("arrow.right", title: "Add Column Right", action: viewModel.editorAddColumnAfter)
                    tableRow("trash", title: "Delete Column", destructive: true, action: viewModel.editorDeleteColumn)
                }
                .padding(.vertical, Spacing.xs)

                Divider().padding(.horizontal, Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    tableRow("rectangle.compress.vertical", title: "Merge Cells", action: viewModel.editorMergeCells)
                    tableRow("rectangle.expand.vertical", title: "Split Cell", action: viewModel.editorSplitCell)
                }
                .padding(.vertical, Spacing.xs)

                Divider().padding(.horizontal, Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    tableRow("tablecells.badge.ellipsis", title: "Toggle Header Row", action: viewModel.editorToggleHeaderRow)
                    tableRow("tablecells.badge.ellipsis", title: "Toggle Header Column", action: viewModel.editorToggleHeaderColumn)
                }
                .padding(.vertical, Spacing.xs)

                Divider().padding(.horizontal, Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    tableRow("trash", title: "Delete Table", destructive: true, action: viewModel.editorDeleteTable)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .frame(width: 200)
    }

    @ViewBuilder
    private func tableRow(
        _ symbol: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(destructive ? CiderColors.destructive : CiderColors.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(destructive ? CiderColors.destructive : CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NotesToolbarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovered ? CiderColors.separatorFirm : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: NotesDesign.toolbarIconSize, weight: .medium))
                        .foregroundColor(CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .hoverState($isHovered)
        .help(help)
    }
}

struct NotesToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(CiderColors.separatorSolid)
            .frame(width: 1, height: NotesDesign.toolbarDividerHeight)
            .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - External Change Banner

struct NotesExternalChangeBanner: View {
    let state: NotesExternalChangeState
    let onReload: () -> Void
    let onKeepMine: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)

            Text("This note changed outside Cider (\(state.modifiedAt.formatted(.relative(presentation: .named))))")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Button("Reload") {
                onReload()
            }
            .buttonStyle(.plain)
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.controlAccent)

            Button("Keep Mine") {
                onKeepMine()
            }
            .buttonStyle(.plain)
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(height: NotesDesign.toolbarHeight)
    }
}

// MARK: - Find Bar

struct NotesFindBar: View {
    @ObservedObject var viewModel: NotesViewModel

    private var statusText: String {
        guard !viewModel.findQuery.isEmpty else { return "" }
        guard viewModel.findMatchCount > 0 else { return "No matches" }
        return "\(viewModel.findMatchIndex)/\(viewModel.findMatchCount)"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.bodyMedium)
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
                    .font(CiderFont.body)
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

struct NotesFindTextField: NSViewRepresentable {
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

// MARK: - Snapshot Popover

struct NoteSnapshotPopover: View {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isPresented: Bool
    @State private var showAll = false

    private var choices: [NotesRecoverySnapshotChoice] {
        showAll ? viewModel.allRecoverySnapshotChoices : viewModel.recoverySnapshotChoices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Version History")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer()

                if viewModel.allRecoverySnapshotChoices.count > viewModel.recoverySnapshotChoices.count {
                    Button(showAll ? "Show Less" : "Show All") {
                        showAll.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.controlAccent)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            Divider().padding(.horizontal, Spacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(choices) { choice in
                        Button {
                            viewModel.restoreSnapshot(choice)
                            isPresented = false
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(CiderColors.tertiary)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(choice.title)
                                        .font(CiderFont.bodyMedium)
                                        .foregroundColor(CiderColors.primary)

                                    Text(choice.snapshotDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs + 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 260)
        .padding(.bottom, Spacing.xs)
    }
}

// MARK: - Metadata Bar

struct NoteMetadataBar: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                metadataChip(label: "Created", value: Self.dateFormatter.string(from: note.createdAt))
                metadataChip(label: "Modified", value: Self.dateFormatter.string(from: note.modifiedAt))
                metadataChip(label: "Characters", value: "\(viewModel.charCount)")
                if let folderID = note.folderID,
                   let folder = BookmarksStorage.shared.folders.first(where: { $0.id == folderID }) {
                    metadataChip(label: "Folder", value: folder.name)
                }
                if note.isPinned {
                    metadataChip(label: "Pinned", value: "Yes")
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private func metadataChip(label: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }
}

// MARK: - Empty State

struct NotesEditorEmptyState: View {
    let onCreateNew: () -> Void

    var body: some View {
        EmptyStateView(
            icon: "note.text",
            title: "No note selected",
            actionLabel: "Create New Note",
            action: onCreateNew
        )
    }
}

// MARK: - Status Bar

struct NotesStatusBar: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.selectedNote != nil {
                Text("\(viewModel.charCount) chars")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            Spacer()
            if viewModel.selectedNote != nil {
                Image(systemName: viewModel.hasPendingSave ? "clock.fill" : "checkmark.circle.fill")
                    .font(CiderFont.caption)
                    .foregroundColor(
                        viewModel.hasPendingSave
                            ? CiderColors.tertiary
                            : CiderColors.successMuted
                    )
                Text(viewModel.hasPendingSave ? "Saving..." : "Saved")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
    }
}
