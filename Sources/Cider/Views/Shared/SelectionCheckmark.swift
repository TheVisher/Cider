import SwiftUI

struct SelectionCheckmark: View {
    var body: some View {
        Circle()
            .fill(CiderColors.controlAccent)
            .frame(width: SelectionCheckmarkDesign.circleSize, height: SelectionCheckmarkDesign.circleSize)
            .overlay(
                Image(systemName: "checkmark")
                    .font(CiderFont.captionBold)
                    .foregroundColor(CiderColors.textOnColor)
            )
    }
}
