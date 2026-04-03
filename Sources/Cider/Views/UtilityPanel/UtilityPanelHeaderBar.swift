import SwiftUI

struct UtilityPanelHeaderBar: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    let onClose: () -> Void
    let onMaximize: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Traffic lights
            trafficLights

            // Nav buttons
            navButtons

            // Dot row
            UtilityPanelDotRow(buffer: coordinator.buffer) { index in
                coordinator.activateDot(at: index)
            }

            // Title
            Text(currentTitle)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            // Tool buttons
            toolButtons
        }
        .padding(.horizontal, UtilityPanelDesign.headerHorizontalPadding)
        .frame(height: UtilityPanelDesign.headerBarHeight)
        .contentShape(Rectangle())
    }

    // MARK: - Traffic Lights

    private var trafficLights: some View {
        HStack(spacing: CiderPanelDesign.trafficLightSpacing) {
            PanelTrafficLightButton(
                color: .systemRed,
                symbol: "xmark",
                help: "Close panel",
                action: onClose
            )
            PanelTrafficLightButton(
                color: .systemYellow,
                symbol: "minus",
                help: "Hide panel",
                action: onClose
            )
            PanelTrafficLightButton(
                color: .systemGreen,
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Maximize",
                action: onMaximize
            )
        }
    }

    // MARK: - Nav Buttons

    private var navButtons: some View {
        HStack(spacing: Spacing.xxs) {
            Button {
                coordinator.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(coordinator.history.canGoBack ? CiderColors.primary : CiderColors.quaternary)
                    .frame(
                        width: UtilityPanelDesign.navButtonSize,
                        height: UtilityPanelDesign.navButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.history.canGoBack)
            .help("Back")

            Button {
                coordinator.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(coordinator.history.canGoForward ? CiderColors.primary : CiderColors.quaternary)
                    .frame(
                        width: UtilityPanelDesign.navButtonSize,
                        height: UtilityPanelDesign.navButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.history.canGoForward)
            .help("Forward")
        }
    }

    // MARK: - Tool Buttons

    private var toolButtons: some View {
        HStack(spacing: Spacing.xxs) {
            Button {
                if coordinator.activeTool == .search {
                    coordinator.closeActive()
                } else if !coordinator.searchResults.isEmpty {
                    coordinator.openTool(.search)
                }
            } label: {
                let hasResults = !coordinator.searchResults.isEmpty
                let isActive = coordinator.activeTool == .search
                Image(systemName: "magnifyingglass")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(isActive ? CiderColors.controlAccent : hasResults ? CiderColors.secondary : CiderColors.quaternary)
                    .frame(
                        width: UtilityPanelDesign.toolButtonSize,
                        height: UtilityPanelDesign.toolButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.searchResults.isEmpty && coordinator.activeTool != .search)
            .help(coordinator.searchResults.isEmpty ? "No search results" : "Search")

            Button {
                if coordinator.activeTool == .clipboard {
                    coordinator.closeActive()
                } else {
                    coordinator.openTool(.clipboard)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(coordinator.activeTool == .clipboard ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(
                        width: UtilityPanelDesign.toolButtonSize,
                        height: UtilityPanelDesign.toolButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clipboard")

            Button {
                if coordinator.activeTool == .aiChat {
                    coordinator.closeActive()
                } else {
                    coordinator.openTool(.aiChat)
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(coordinator.activeTool == .aiChat ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(
                        width: UtilityPanelDesign.toolButtonSize,
                        height: UtilityPanelDesign.toolButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("AI Chat")
        }
    }

    // MARK: - Computed

    private var currentTitle: String {
        if let tool = coordinator.activeTool {
            return switch tool {
            case .search: "Search"
            case .clipboard: "Clipboard"
            case .aiChat: "AI Chat"
            case .capture: "Capture"
            }
        }
        if let activeIndex = coordinator.buffer.activeIndex,
           let slot = coordinator.buffer.slots[activeIndex] {
            return slot.title
        }
        return "Cider"
    }
}
