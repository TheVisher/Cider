import SwiftUI

struct InlineNoteEditorView: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        VStack(spacing: 0) {
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

            if viewModel.selectedNote != nil || viewModel.activeExternalFile != nil {
                TipTapEditorView(viewModel: viewModel)
            } else {
                NotesEditorEmptyState(onCreateNew: { viewModel.createNewNote() })
            }

            NotesStatusBar(viewModel: viewModel)
        }
    }
}

// MARK: - Formatting Toolbar

struct NotesFormattingToolbar: View {
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
                        symbol: "link",
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
