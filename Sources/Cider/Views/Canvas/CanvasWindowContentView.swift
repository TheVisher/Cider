import SwiftUI

/// Root SwiftUI content for the canvas window.
/// For the POC: just the React Flow canvas, full bleed.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        CanvasView(viewModel: viewModel)
            .frame(minWidth: 600, minHeight: 400)
    }
}
