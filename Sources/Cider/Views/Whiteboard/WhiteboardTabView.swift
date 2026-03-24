import SwiftUI

struct WhiteboardTabView: View {
    let canvasID: UUID
    @ObservedObject var viewModel: WhiteboardViewModel

    @ObservedObject private var whiteboardStorage = WhiteboardStorage.shared

    private var canvas: WhiteboardCanvas? {
        whiteboardStorage.canvas(for: canvasID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if canvas != nil {
                ExcalidrawView(viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .onAppear {
            if let canvas {
                viewModel.loadCanvas(canvas)
            }
        }
        .onDisappear {
            viewModel.whiteboardWebView?.window?.makeFirstResponder(nil)
        }
        .onChange(of: canvasID) {
            if let canvas {
                viewModel.loadCanvas(canvas)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(CiderFont.fileIconLarge)
                .foregroundColor(CiderColors.tertiary)
            Text("Whiteboard not found")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
