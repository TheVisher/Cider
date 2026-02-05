import SwiftUI

struct PaletteSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(CiderColors.secondary)
                .font(.system(size: 16 * textScale, weight: .medium))

            TextField("Search apps, windows, and more...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18 * textScale))
                .focused(isFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
