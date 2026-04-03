import SwiftUI

@MainActor
final class PlaceholderMode: PanelMode, ObservableObject {
    let id = "placeholder"
    let title = "Cider"
    let modeType: PanelModeType = .tool

    var contentView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(CiderColors.tertiary)
            Text("Open an item to get started")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
