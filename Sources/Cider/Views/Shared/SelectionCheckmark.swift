import SwiftUI

struct SelectionCheckmark: View {
    var body: some View {
        Circle()
            .fill(CiderColors.controlAccent)
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CiderColors.textOnColor)
            )
    }
}
