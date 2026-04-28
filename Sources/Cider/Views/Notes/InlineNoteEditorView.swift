import SwiftUI

struct InlineNoteEditorView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
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

                if viewModel.selectedNote != nil {
                    if viewModel.noteEditorMode == .source {
                        NativeMarkdownEditorView(viewModel: viewModel)
                    } else {
                        TipTapEditorView(viewModel: viewModel)
                    }
                } else {
                    NotesEditorEmptyState(onCreateNew: { viewModel.createNewNote() })
                }

                NotesStatusBar(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity)

            if viewModel.isMetadataPanelVisible, let note = viewModel.selectedNote {
                NoteMetadataSidebar(note: note, viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Compact Formatting Toolbar (Title Bar)

struct NotesCompactToolbar: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            .font(NoteEditorDesign.textStyleButtonFont)
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
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(showTablePopover ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Table")
            .popover(isPresented: $showTablePopover, arrowEdge: .bottom) {
                NotesTablePopover(viewModel: viewModel, isPresented: $showTablePopover)
            }

            NotesToolbarDivider()

            NotesToolbarButton(symbol: "increase.indent", help: "Indent", action: viewModel.editorIndent)
            NotesToolbarButton(symbol: "decrease.indent", help: "Outdent", action: viewModel.editorOutdent)

            NotesToolbarDivider()

            NotesToolbarButton(symbol: "link.badge.plus", help: "Add Link", action: viewModel.editorPromptForLink)
            NotesToolbarButton(symbol: "photo", help: "Insert Image", action: viewModel.openImagePicker)

            NotesToolbarDivider()

            NotesEditorModePicker(viewModel: viewModel)

            NotesToolbarDivider()

            Button {
                showSnapshotPopover.toggle()
            } label: {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(showSnapshotPopover ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                    .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(showSnapshotPopover ? CiderColors.controlAccent : CiderColors.secondary)
                    }
            }
            .buttonStyle(.plain)
            .help("Version History")
            .disabled(viewModel.selectedNote == nil || !viewModel.hasSnapshots)
            .popover(isPresented: $showSnapshotPopover, arrowEdge: .bottom) {
                NoteSnapshotPopover(viewModel: viewModel, isPresented: $showSnapshotPopover)
            }

        }
        .disabled(viewModel.selectedNote == nil)
    }
}

struct NotesEditorModePicker: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        Picker("Editor Mode", selection: Binding(
            get: { viewModel.noteEditorMode },
            set: { viewModel.setNoteEditorMode($0) }
        )) {
            ForEach(NoteEditorMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 136)
        .help("Switch between rich editing and Markdown source")
    }
}

// MARK: - Text Style Popover

struct NotesTextStylePopover: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var lastHighlightColor: String = "rgba(234, 179, 8, 0.35)"

    private var fmt: EditorFormatState { viewModel.editorFormatState }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Inline styles
            HStack(spacing: Spacing.xs) {
                inlineToggle("B", font: NoteEditorDesign.inlineToggleBoldFont, active: fmt.bold, action: viewModel.editorToggleBold)
                inlineToggle("I", font: NoteEditorDesign.inlineToggleItalicFont, active: fmt.italic, action: viewModel.editorToggleItalic)
                inlineToggle("U", font: NoteEditorDesign.inlineToggleMediumFont, active: fmt.underline, action: viewModel.editorToggleUnderline, underlined: true)
                inlineToggle("S", font: NoteEditorDesign.inlineToggleMediumFont, active: fmt.strike, action: viewModel.editorToggleStrike, strikethrough: true)
                inlineToggleIcon("chevron.left.forwardslash.chevron.right", active: fmt.code, action: viewModel.editorToggleCode)
                highlightMenuButton
                inlineToggleIcon("eraser", active: false, action: viewModel.editorClearFormatting)
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
                paragraphRow("Code Block", active: fmt.codeBlock) { viewModel.editorToggleCodeBlock() }
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
        .frame(width: NoteEditorDesign.textStylePopoverWidth)
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
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
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
                .font(CiderFont.labelMedium)
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(active ? CiderColors.accentSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlight color menu

    private static let highlightColors: [(name: String, css: String, swatch: Color)] = [
        ("Yellow", "rgba(234, 179, 8, 0.35)", CiderColors.highlightYellow),
        ("Green", "rgba(34, 197, 94, 0.3)", CiderColors.highlightGreen),
        ("Blue", "rgba(59, 130, 246, 0.35)", CiderColors.highlightBlue),
        ("Pink", "rgba(236, 72, 153, 0.3)", CiderColors.highlightPink),
        ("Orange", "rgba(249, 115, 22, 0.3)", CiderColors.highlightOrange),
        ("Purple", "rgba(168, 85, 247, 0.3)", CiderColors.highlightPurple),
    ]

    private var lastHighlightSwatch: Color {
        Self.highlightColors.first(where: { $0.css == lastHighlightColor })?.swatch ?? .yellow
    }

    @ViewBuilder
    private var highlightMenuButton: some View {
        Menu {
            ForEach(Self.highlightColors, id: \.css) { color in
                Button {
                    lastHighlightColor = color.css
                    viewModel.editorToggleHighlight(color: color.css)
                } label: {
                    HStack {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: NoteEditorDesign.highlightColorDotSize, height: NoteEditorDesign.highlightColorDotSize)
                        Text(color.name)
                    }
                }
            }
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: "highlighter")
                    .font(CiderFont.labelMedium)
                    .foregroundColor(fmt.highlight ? CiderColors.controlAccent : CiderColors.secondary)
                RoundedRectangle(cornerRadius: NoteEditorDesign.highlightSwatchRadius, style: .continuous)
                    .fill(lastHighlightSwatch)
                    .frame(width: NoteEditorDesign.highlightSwatchWidth, height: NoteEditorDesign.highlightSwatchHeight)
                    .offset(y: NoteEditorDesign.highlightSwatchYOffset)
            }
            .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(fmt.highlight ? CiderColors.accentSubtle : Color.clear)
            )
        } primaryAction: {
            viewModel.editorToggleHighlight(color: lastHighlightColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
                .font(CiderFont.labelMedium)
                .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
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
                    .font(CiderFont.captionBold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: NoteEditorDesign.popoverRowIconWidth)
                    .opacity(active ? 1 : 0)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, NoteEditorDesign.popoverRowVerticalPadding)
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
                    .font(CiderFont.captionBold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: NoteEditorDesign.popoverRowIconWidth)
                    .opacity(active ? 1 : 0)

                Image(systemName: symbol)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(active ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: NoteEditorDesign.popoverRowIconWidth)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, NoteEditorDesign.popoverRowVerticalPadding)
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
    private let cellSize: CGFloat = NoteEditorDesign.tableCellSize
    private let cellSpacing: CGFloat = NoteEditorDesign.tableCellSpacing

    private var fmt: EditorFormatState { viewModel.editorFormatState }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grid picker
            VStack(spacing: cellSpacing) {
                ForEach(1...gridSize, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(1...gridSize, id: \.self) { col in
                            let highlighted = hoveredRow > 0 && hoveredCol > 0 && row <= hoveredRow && col <= hoveredCol
                            RoundedRectangle(cornerRadius: NoteEditorDesign.tableCellRadius, style: .continuous)
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
        .frame(width: NoteEditorDesign.tablePopoverWidth)
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
                    .font(CiderFont.labelMedium)
                    .foregroundColor(destructive ? CiderColors.destructive : CiderColors.secondary)
                    .frame(width: NoteEditorDesign.popoverRowIconWidth)

                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(destructive ? CiderColors.destructive : CiderColors.primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, NoteEditorDesign.popoverRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Toggle Button (Trailing Toolbar)

struct NotesInfoToggleButton: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                viewModel.isMetadataPanelVisible.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(viewModel.isMetadataPanelVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: viewModel.isMetadataPanelVisible ? "info.circle.fill" : "info.circle")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(viewModel.isMetadataPanelVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(viewModel.isMetadataPanelVisible ? "Hide Info" : "Show Info")
        .disabled(viewModel.selectedNote == nil)
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
                        .font(CiderFont.bodyMedium)
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
            .frame(width: Spacing.hairline, height: NotesDesign.toolbarDividerHeight)
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
        textField.font = NoteEditorDesign.findBarNSFont
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
                                    .font(CiderFont.bodyMedium)
                                    .foregroundColor(CiderColors.tertiary)
                                    .frame(width: NoteEditorDesign.popoverRowIconWidth)

                                VStack(alignment: .leading, spacing: Spacing.hairline) {
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
                            .padding(.vertical, NoteEditorDesign.popoverRowVerticalPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: NoteEditorDesign.snapshotScrollMaxHeight)
        }
        .frame(width: NoteEditorDesign.snapshotPopoverWidth)
        .padding(.bottom, Spacing.xs)
    }
}

// MARK: - Metadata Sidebar

struct NoteMetadataSidebar: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var isTitleExpanded = true
    @State private var isFolderExpanded = true
    @State private var isTagsExpanded = true
    @State private var isSourcesExpanded = true
    @State private var isHistoryExpanded = false
    @State private var showAllSnapshots = false
    @State private var isAIExpanded = true
    @State private var isInfoExpanded = true
    @State private var showNewTagForm = false
    @State private var editingTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleSection
                        .padding(.bottom, Spacing.md)

                    sectionDivider
                    folderSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    tagsSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    sourcesSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    historySection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    intelligenceSection
                        .padding(.vertical, Spacing.md)
                }
                .padding(Spacing.md)
                .background(
                    HideScrollIndicatorsHelper()
                        .frame(width: 0, height: 0)
                )
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            footerSection
        }
        .frame(width: BookmarksDesign.detailsSidebarFixedWidth)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
        .onAppear { editingTitle = note.title }
        .onChange(of: note.id) { _, _ in
            editingTitle = note.title
            showAllSnapshots = false
        }
        .onChange(of: note.title) { _, newTitle in
            if editingTitle != newTitle { editingTitle = newTitle }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Divider()
            .background(CiderColors.separator)
    }

    // MARK: - Title

    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Title", isExpanded: $isTitleExpanded)

            if isTitleExpanded {
                TextField("Title", text: $editingTitle, axis: .vertical)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onChange(of: editingTitle) { _, newTitle in
                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != note.title else { return }
                        viewModel.updateNoteTitle(trimmed)
                    }
            }
        }
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Folder", isExpanded: $isFolderExpanded)

            if isFolderExpanded {
                let folders = VaultFolderService.shared.legacyFolders
                Menu {
                    Button("No Folder") {
                        viewModel.updateNoteFolder(nil)
                    }
                    if !folders.isEmpty { Divider() }
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            viewModel.updateNoteFolder(folder.id)
                        }
                    }
                } label: {
                    HStack {
                        Label(currentFolderName, systemImage: "folder")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: BookmarksDesign.buttonTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var currentFolderName: String {
        guard let fid = note.folderID else { return "No Folder" }
        return VaultFolderService.shared.legacyFolders.first(where: { $0.id == fid })?.name ?? "No Folder"
    }

    // MARK: - Tags

    private var assignedLabels: [CardLabel] {
        note.labelIDs.compactMap { id in
            labelStorage.labels.first(where: { $0.id == id })
        }
    }

    private var unassignedLabels: [CardLabel] {
        let assigned = Set(note.labelIDs)
        return labelStorage.labels.filter { !assigned.contains($0.id) }
    }

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Tags", isExpanded: $isTagsExpanded)

            if isTagsExpanded {
                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(assignedLabels) { label in
                        TagPillView(
                            label: label,
                            onRemove: { viewModel.toggleNoteLabel(label.id) }
                        )
                    }

                    Menu {
                        if unassignedLabels.isEmpty && labelStorage.labels.isEmpty {
                            Button("New Tag...") {
                                showNewTagForm = true
                            }
                        } else {
                            ForEach(unassignedLabels) { label in
                                Button {
                                    viewModel.toggleNoteLabel(label.id)
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                                            .frame(width: BookmarksDesign.tagColorDotSize, height: BookmarksDesign.tagColorDotSize)
                                        Text(label.name)
                                    }
                                }
                            }

                            Divider()

                            Button("New Tag...") {
                                showNewTagForm = true
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "plus")
                                .font(CiderFont.badgeSemibold)
                            Text("Add Tag")
                                .font(CiderFont.caption)
                        }
                        .foregroundColor(CiderColors.controlAccent)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                .fill(CiderColors.accentSubtle)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .popover(isPresented: $showNewTagForm, arrowEdge: .bottom) {
                        InlineTagCreationForm { name, colorHex in
                            let newLabel = CardLabelStorage.shared.createLabel(name: name, colorHex: colorHex)
                            viewModel.toggleNoteLabel(newLabel.id)
                            showNewTagForm = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sources (extracted links)

    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Sources", isExpanded: $isSourcesExpanded)

            if isSourcesExpanded {
                let links = viewModel.extractedLinks
                if links.isEmpty {
                    Text("No links in this note")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(links, id: \.absoluteString) { url in
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "link")
                                        .font(CiderFont.captionMedium)
                                        .foregroundColor(CiderColors.tertiary)
                                        .frame(width: NoteEditorDesign.popoverRowIconWidth)

                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(url.host ?? url.absoluteString)
                                            .font(CiderFont.bodyMedium)
                                            .foregroundColor(CiderColors.controlAccent)
                                            .lineLimit(1)

                                        if url.path.count > 1 {
                                            Text(url.path)
                                                .font(CiderFont.caption)
                                                .foregroundColor(CiderColors.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, Spacing.xxs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - History (snapshots)

    private var snapshotChoices: [NotesRecoverySnapshotChoice] {
        showAllSnapshots ? viewModel.allRecoverySnapshotChoices : viewModel.recoverySnapshotChoices
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("History", isExpanded: $isHistoryExpanded)

            if isHistoryExpanded {
                let choices = snapshotChoices
                if choices.isEmpty {
                    Text("No snapshots yet")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(choices) { choice in
                            Button {
                                viewModel.restoreSnapshot(choice)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "clock")
                                        .font(CiderFont.bodyMedium)
                                        .foregroundColor(CiderColors.tertiary)
                                        .frame(width: NoteEditorDesign.popoverRowIconWidth)

                                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                                        Text(choice.title)
                                            .font(CiderFont.bodyMedium)
                                            .foregroundColor(CiderColors.primary)

                                        Text(choice.snapshotDate.formatted(date: .abbreviated, time: .shortened))
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.tertiary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, Spacing.xxs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.allRecoverySnapshotChoices.count > viewModel.recoverySnapshotChoices.count {
                        Button(showAllSnapshots ? "Show Less" : "Show All") {
                            showAllSnapshots.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .padding(.top, Spacing.xxs)
                    }
                }
            }
        }
    }

    // MARK: - Intelligence

    @ViewBuilder
    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Intelligence", isExpanded: $isAIExpanded)

            if isAIExpanded {
                Button {
                    // Future: AI summary
                } label: {
                    Label("Summarize", systemImage: "sparkles")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Coming soon")
            }
        }
    }

    // MARK: - Footer (pinned)

    @ViewBuilder
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)

            infoHeader

            if isInfoExpanded {
                infoGrid
                    .padding(.bottom, Spacing.xxs)
            }

            Divider()
                .background(CiderColors.separator)

            Button("Delete") {
                viewModel.deleteCurrentNote()
            }
            .buttonStyle(CiderDestructiveButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private var infoHeader: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isInfoExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Info")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .rotationEffect(.degrees(isInfoExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            propertyRow("Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
            propertyRow("Modified", value: note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            propertyRow("Type", value: "Note")
            propertyRow("Characters", value: "\(viewModel.charCount)")
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: NoteEditorDesign.infoGridLabelWidth, alignment: .leading)
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Hide Scroll Indicators (AppKit level)

/// SwiftUI's `showsIndicators: false` and `.scrollIndicators(.never)` are unreliable
/// on macOS — overlay scrollbars still appear. Place this inside a ScrollView's content
/// (via `.background()`) so walking up the superview chain finds the `NSScrollView`
/// and disables its scrollers at the AppKit level.
struct HideScrollIndicatorsHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            disableScrollers(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            disableScrollers(from: nsView)
        }
    }

    private func disableScrollers(from view: NSView) {
        var current: NSView? = view
        while let v = current {
            if let scrollView = v as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScroller = nil
                scrollView.horizontalScroller = nil
                return
            }
            current = v.superview
        }
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
                Label(viewModel.noteEditorMode.displayName, systemImage: viewModel.noteEditorMode.icon)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

                Text("•")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

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
        .frame(height: NoteEditorDesign.statusBarHeight)
    }
}
