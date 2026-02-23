import SwiftUI

@MainActor
final class UndoToastModel: ObservableObject {
    @Published var progress: CGFloat = 1
}

struct UndoToastView: View {
    @ObservedObject var model: UndoToastModel
    let message: String
    let showViewTrash: Bool
    let onUndo: () -> Void
    let onViewTrash: () -> Void
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: UndoToastDesign.cornerRadius)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trash")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.secondary)

                    Text(message)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: Spacing.xs)

                    if showViewTrash {
                        Button(action: onViewTrash) {
                            Text("Trash")
                                .font(CiderFont.bodyMedium)
                                .foregroundColor(CiderColors.secondary)
                                .padding(.horizontal, Spacing.sm)
                                .frame(minHeight: Spacing.xxl)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(CiderColors.surfaceInput)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onUndo) {
                        Text("Undo")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.controlAccent)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: Spacing.xxl)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.selectedFill)
                            )
                    }
                    .buttonStyle(.plain)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.borderSelected)

                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.accentSolid)
                            .frame(width: proxy.size.width * max(0, min(1, model.progress)))
                    }
                }
                .frame(height: BookmarksToastDesign.reviewProgressHeight)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: UndoToastDesign.width, height: UndoToastDesign.height)
        .padding(UndoToastDesign.shadowPadding)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }
}
