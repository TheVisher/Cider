import SwiftUI

struct ScreenCaptureRoutingToastView: View {
    @ObservedObject var model: ScreenCaptureToastModel
    let route: CaptureRoute
    let onHoverChanged: (Bool) -> Void
    let onCreateNote: () -> Void
    let onCreateDateCard: () -> Void
    let onCreateContact: () -> Void

    @State private var selectedAction: CaptureRouteType

    init(
        model: ScreenCaptureToastModel,
        route: CaptureRoute,
        onHoverChanged: @escaping (Bool) -> Void,
        onCreateNote: @escaping () -> Void,
        onCreateDateCard: @escaping () -> Void,
        onCreateContact: @escaping () -> Void
    ) {
        self.model = model
        self.route = route
        self.onHoverChanged = onHoverChanged
        self.onCreateNote = onCreateNote
        self.onCreateDateCard = onCreateDateCard
        self.onCreateContact = onCreateContact
        _selectedAction = State(initialValue: route.type)
    }

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: ScreenCaptureToastDesign.cornerRadius)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Screen captured")
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)

                        if !route.suggestedTitle.isEmpty && route.suggestedTitle != "Screen Capture" {
                            Text(route.suggestedTitle)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Spacing.sm)
                }

                HStack(spacing: Spacing.xs) {
                    routeButton(
                        label: "Create Note",
                        systemImage: "note.text",
                        action: .note,
                        onTap: onCreateNote
                    )
                    routeButton(
                        label: "Date Card",
                        systemImage: "calendar",
                        action: .dateCard,
                        onTap: onCreateDateCard
                    )
                    routeButton(
                        label: "Contact",
                        systemImage: "person.crop.circle",
                        action: .contact,
                        onTap: onCreateContact
                    )
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
                .frame(height: 3)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: ScreenCaptureToastDesign.width, height: ScreenCaptureToastDesign.height)
        .padding(ScreenCaptureToastDesign.shadowPadding)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }

    @ViewBuilder
    private func routeButton(
        label: String,
        systemImage: String,
        action: CaptureRouteType,
        onTap: @escaping () -> Void
    ) -> some View {
        let isSelected = selectedAction == action
        Button {
            selectedAction = action
            onTap()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(CiderFont.caption)
                Text(label)
                    .font(CiderFont.captionMedium)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.selectedFill : CiderColors.surfaceInput)
            )
        }
        .buttonStyle(.plain)
    }
}
