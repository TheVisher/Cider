import SwiftUI

struct ClipboardPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
                cornerRadius: ClipboardPanelDesign.cornerRadius
            )

            ClipboardViewerView(
                isStandalone: true,
                onClose: {
                    NotificationCenter.default.post(name: .dismissClipboardPanel, object: nil)
                },
                onExpand: {
                    NotificationCenter.default.post(name: .dismissClipboardPanel, object: nil)
                    NotificationCenter.default.post(name: .openCiderMainWindow, object: nil)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: ClipboardPanelDesign.cornerRadius, style: .continuous))
        }
        .overlay {
            PanelEdgeResizeView(horizontalResizeEnabled: false)
        }
        .background {
            Button("") {
                NotificationCenter.default.post(name: .dismissClipboardPanel, object: nil)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
    }
}
