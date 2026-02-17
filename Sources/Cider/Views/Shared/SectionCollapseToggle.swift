import SwiftUI

struct SectionCollapseToggle: View {
    let label: String
    @Binding var isCollapsed: Bool
    var collapsedHelp: String = "Show"
    var expandedHelp: String = "Hide"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(label)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Image(systemName: "chevron.right")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.quaternary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .snappy, value: isCollapsed)
        .help(isCollapsed ? collapsedHelp : expandedHelp)
    }
}
