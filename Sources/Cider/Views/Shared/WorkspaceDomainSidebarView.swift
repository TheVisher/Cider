import SwiftUI

struct WorkspaceDomainSidebarView<DomainContent: View>: View {
    @Binding var selectedDomain: WorkspaceNavigationDomain?
    let domains: [WorkspaceNavigationDomain]
    let onSelectDomain: (WorkspaceNavigationDomain) -> Void
    @ViewBuilder let domainContent: () -> DomainContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let selectedDomain {
                domainSidebar(for: selectedDomain)
            } else {
                globalDomainList
            }
        }
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: selectedDomain)
    }

    private var globalDomainList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Cider")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text("Choose a workspace")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(domains) { domain in
                        domainButton(domain)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func domainSidebar(for domain: WorkspaceNavigationDomain) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            domainHeader(domain)
            domainContent()
        }
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func domainHeader(_ domain: WorkspaceNavigationDomain) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                selectedDomain = nil
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(CiderFont.captionBold)
                    Text("All Cider")
                        .font(CiderFont.captionSemibold)
                }
                .foregroundColor(CiderColors.controlAccent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to all Cider domains")

            HStack(spacing: Spacing.sm) {
                Image(systemName: domain.systemImage)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: Spacing.xl, height: Spacing.xl)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.controlAccent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(domain.title)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(domain.breadcrumbPath.joined(separator: " / "))
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    private func domainButton(_ domain: WorkspaceNavigationDomain) -> some View {
        Button {
            if domain == .aiAssistant {
                onSelectDomain(domain)
            } else {
                selectedDomain = domain
                onSelectDomain(domain)
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: domain.systemImage)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(domain.title)
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(domain.subtitle)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(domain.subtitle)
    }
}
