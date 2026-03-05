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
                    // Use toggleCiderPanel which shows if hidden; if already visible, it's a no-op
                    // because the clipboard panel is separate and doesn't affect Cider panel visibility
                    if !NSApp.windows.contains(where: { $0 is CiderPanel && $0.isVisible }) {
                        NotificationCenter.default.post(name: .toggleCiderPanel, object: nil)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: ClipboardPanelDesign.cornerRadius, style: .continuous))
        }
        .overlay {
            PanelEdgeResizeView()
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
