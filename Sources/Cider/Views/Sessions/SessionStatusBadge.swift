import SwiftUI

/// Colored dot + label indicating a Claude session's current status.
struct SessionStatusBadge: View {
    let status: ClaudeSessionStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dotColor: Color {
        switch status {
        case .idle: CiderColors.tertiary
        case .working: CiderColors.success
        case .waitingForApproval: CiderColors.warning
        case .error: CiderColors.destructive
        case .stopped: CiderColors.tertiary
        }
    }

    private var label: String {
        switch status {
        case .idle: "Idle"
        case .working: "Working..."
        case .waitingForApproval: "Needs approval"
        case .error(let msg): msg
        case .stopped: "Stopped"
        }
    }

    private var isPulsing: Bool {
        if case .working = status { return true }
        return false
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: SessionsDesign.statusDotSize, height: SessionsDesign.statusDotSize)
                .opacity(isPulsing ? 0.6 : 1)
                .animation(
                    isPulsing && !reduceMotion
                        ? .spring(duration: 1).repeatForever(autoreverses: true)
                        : .none,
                    value: isPulsing
                )

            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
        }
    }
}
