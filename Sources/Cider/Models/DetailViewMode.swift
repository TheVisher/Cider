import Foundation
import SwiftUI

enum DetailViewMode: String, Codable, CaseIterable {
    case slideOut
    case fullPanel
    case page

    var displayName: String {
        switch self {
        case .slideOut: return "Slide-out"
        case .fullPanel: return "Full panel"
        case .page: return "Page"
        }
    }

    var iconName: String {
        switch self {
        case .slideOut: return "sidebar.trailing"
        case .fullPanel: return "rectangle"
        case .page: return "rectangle.fill"
        }
    }
}

// MARK: - View Mode Picker (single button → popover)

struct DetailViewModePicker: View {
    var currentMode: DetailViewMode
    var onChange: (DetailViewMode) -> Void

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: currentMode.iconName)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("View mode")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(DetailViewMode.allCases, id: \.self) { mode in
                    Button {
                        onChange(mode)
                        showPopover = false
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(CiderColors.controlAccent)
                                .frame(width: 16)
                                .opacity(mode == currentMode ? 1 : 0)

                            Image(systemName: mode.iconName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(mode == currentMode ? CiderColors.controlAccent : CiderColors.secondary)
                                .frame(width: 16)

                            Text(mode.displayName)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Spacer()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs + 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.xs)
            .frame(width: 160)
        }
    }
}
