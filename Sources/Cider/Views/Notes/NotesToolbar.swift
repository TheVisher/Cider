import SwiftUI

struct NotesToolbar: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ToolbarButton(icon: "bold", help: "Bold") {
                viewModel.insertBold()
            }
            ToolbarButton(icon: "italic", help: "Italic") {
                viewModel.insertItalic()
            }
            ToolbarButton(icon: "number", help: "Heading") {
                viewModel.insertHeading()
            }
            ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", help: "Code") {
                viewModel.insertCode()
            }
            ToolbarButton(icon: "list.bullet", help: "List") {
                viewModel.insertList()
            }
            ToolbarButton(icon: "link", help: "Link") {
                viewModel.insertLink()
            }

            Spacer()

            // Preview toggle
            Button(action: { viewModel.isPreviewMode.toggle() }) {
                Image(systemName: viewModel.isPreviewMode ? "eye.fill" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.isPreviewMode ? CiderColors.controlAccent : CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.isPreviewMode ? "Edit mode" : "Preview")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: NotesDesign.toolbarHeight)
    }
}

private struct ToolbarButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
