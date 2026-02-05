import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    @ObservedObject var pinnedAppsViewModel: PinnedAppsViewModel
    @ObservedObject var windowListViewModel: WindowListViewModel
    @State private var sectionFrames: [SidebarViewModel.Section: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Raycast-style Acrylic background
            SidebarBackgroundView(cornerRadius: CiderDesign.cornerRadius)

            // Content - clipped separately so it doesn't overflow the rounded corners
            ScrollView {
                contentStack
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: CiderDesign.cornerRadius, style: .continuous))
        }
        // Inset content within the larger window to leave room for shadow
        .padding(.horizontal, CiderDesign.shadowPaddingHorizontal)
        .padding(.top, CiderDesign.shadowPaddingTop)
        .padding(.bottom, CiderDesign.shadowPaddingBottom)
        .coordinateSpace(name: "SidebarSpace")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            MouseTrackingView(
                onMove: { point in
                    updateHoveredSection(at: point)
                },
                onEnter: {
                    viewModel.isExpanded = true
                },
                onExit: {
                    withAnimation(hoverAnimation) {
                        viewModel.isExpanded = false
                        viewModel.hoveredSection = nil
                    }
                }
            )
        )
        .onPreferenceChange(SectionFrameKey.self) { frames in
            sectionFrames = frames
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        VStack(alignment: .leading, spacing: CiderDesign.componentSpacing) {
            PinnedAppsView(viewModel: pinnedAppsViewModel, isCompact: !viewModel.isExpanded)
                .background(
                    GeometryReader { sectionGeo in
                        Color.clear.preference(
                            key: SectionFrameKey.self,
                            value: [.pinnedApps: sectionGeo.frame(in: .named("SidebarSpace"))]
                        )
                    }
                )

            WindowListView(viewModel: windowListViewModel, isCompact: !viewModel.isExpanded)
                .background(
                    GeometryReader { sectionGeo in
                        Color.clear.preference(
                            key: SectionFrameKey.self,
                            value: [.windows: sectionGeo.frame(in: .named("SidebarSpace"))]
                        )
                    }
                )
        }
        .padding(Spacing.sm)
    }

    private func updateHoveredSection(at point: CGPoint) {
        let newSection: SidebarViewModel.Section?
        if let frame = sectionFrames[.pinnedApps], frame.contains(point) {
            newSection = .pinnedApps
        } else if let frame = sectionFrames[.windows], frame.contains(point) {
            newSection = .windows
        } else {
            newSection = viewModel.hoveredSection
        }

        guard newSection != viewModel.hoveredSection else { return }
        withAnimation(hoverAnimation) {
            viewModel.hoveredSection = newSection
        }
    }

    private var hoverAnimation: Animation {
        reduceMotion ? CiderAnimation.reduceMotion : CiderAnimation.snappy
    }
}
