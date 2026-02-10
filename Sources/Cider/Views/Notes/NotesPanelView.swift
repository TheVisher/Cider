import SwiftUI
import AppKit

struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PaletteBackgroundView(cornerRadius: NotesDesign.cornerRadius)

            VStack(spacing: 0) {
                NotesTitleBar(viewModel: viewModel)

                Divider()
                    .background(CiderColors.separator)

                if viewModel.selectedNote != nil {
                    TipTapEditorView(viewModel: viewModel)
                } else {
                    NotesEmptyState(onCreateNew: { viewModel.createNewNote() })
                }

                NotesStatusBar(viewModel: viewModel)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NotesResizeHandle()
        }
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
            // Close button
            Button(action: { viewModel.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close notes")

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
            if !viewModel.notes.isEmpty {
                Menu {
                    ForEach(viewModel.notes) { note in
                        Button(note.title) {
                            NotificationCenter.default.post(name: .openNoteInPanel, object: note)
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
            }

            // New note
            Button(action: { viewModel.createNewNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("New note")

            // Pin toggle
            Button(action: { viewModel.togglePin() }) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.isPinned ? CiderColors.controlAccent : CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "Unpin (allow behind windows)" : "Pin on top")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: NotesDesign.titleBarHeight)
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
