import SwiftUI

extension CiderPanelView {

    // MARK: - Title Bar Content

    @ViewBuilder
    var titleBarContent: some View {
        if isAnyDetailPageMode {
            detailPageTitleBar
        } else if !selectedItemIDs.isEmpty {
            selectionTitleBar
        } else {
            normalTitleBar
        }
    }

    @ViewBuilder
    private var normalTitleBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: currentLocationSystemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(currentLocationTitle)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if let subtitle = currentLocationSubtitle {
                    Text(subtitle)
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.md)
        }
        .frame(maxWidth: .infinity)

        Image(systemName: "safari")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
            }
            .help("Capture active browser tab")

        Image(systemName: "camera.viewfinder")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .requestScreenCapture, object: nil)
            }
            .help("Capture screen region (\u{2318}\u{2325}2)")

        Image(systemName: "clipboard")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .toggleClipboardViewer, object: nil)
            }
            .help("Clipboard history (\u{2325}V)")

    }

    private var currentLocationTitle: String {
        if let folderID = selectedFolderID,
           let folder = bookmarksViewModel.folders.first(where: { $0.id == folderID }) {
            return folder.name
        }
        if selectedDomainRouteKind == .folders, selectedNavigationDomain != nil {
            return "Folders"
        }
        if !selectedTagIDs.isEmpty {
            return selectedTagIDs.count == 1 ? "Tag" : "Tags"
        }
        if let route = currentDomainRoute, selectedNavigationDomain == .browse {
            return route.title
        }
        if selectedNavigationDomain == nil {
            return "Home"
        }
        if selectedNavigationDomain == .projects, let workspace = selectedProjectWorkspace {
            return workspace.title
        }
        return selectedNavigationDomain?.title ?? selectedTab?.displayName ?? "Cider"
    }

    private var currentLocationSubtitle: String? {
        if let folderID = selectedFolderID {
            let domainTitle = selectedNavigationDomain?.title ?? "Library"
            return "\(domainTitle) / \(bookmarksViewModel.folderPath(to: folderID).map(\.name).joined(separator: " / "))"
        }
        if selectedDomainRouteKind == .folders, let domain = selectedNavigationDomain {
            return "\(domain.title) / Folder browser"
        }
        if let route = currentDomainRoute, selectedNavigationDomain == .browse {
            return "Library / \(route.title)"
        }
        if selectedNavigationDomain == .projects,
           selectedTab != .domainDashboard(.projects),
           let selectedTab {
            return "Projects / \(selectedTab.displayName)"
        }
        if let domain = selectedNavigationDomain {
            return domain.subtitle
        }
        return "Command center and active work"
    }

    private var currentLocationSystemImage: String {
        if selectedFolderID != nil { return "folder" }
        if selectedDomainRouteKind == .folders, selectedNavigationDomain != nil { return "folder" }
        if !selectedTagIDs.isEmpty { return "tag" }
        if let route = currentDomainRoute, selectedNavigationDomain == .browse {
            return route.systemImage
        }
        if selectedNavigationDomain == .projects,
           selectedTab != .domainDashboard(.projects),
           let selectedTab {
            return selectedTab.systemImage
        }
        return selectedNavigationDomain?.systemImage ?? WorkspaceNavigationDomain.mainDashboard.systemImage
    }

    private var currentDomainRoute: WorkspaceDomainRoute? {
        guard let domain = selectedNavigationDomain else { return nil }
        return WorkspaceDomainRoutePolicy.routes(for: domain).first { $0.kind == selectedDomainRouteKind }
    }

    @ViewBuilder
    private var selectionTitleBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                selectedItemIDs.removeAll()
            }
        } label: {
            Image(systemName: "xmark")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear selection")

        Text("\(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s") selected")
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

        Spacer(minLength: Spacing.sm)

        Menu {
            ForEach(bookmarksViewModel.folders) { folder in
                Button(folder.name) {
                    moveSelectedToFolder(folder.id)
                }
            }
            if !bookmarksViewModel.folders.isEmpty {
                Divider()
            }
            Button("Remove from Folder") {
                moveSelectedToFolder(nil)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionSemibold)
                Text("Move")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move selected items to folder")

        Menu {
            ForEach(CardLabelStorage.shared.labels) { label in
                Button {
                    toggleTagOnSelected(label.id)
                } label: {
                    HStack {
                        if selectedItemsAllHaveLabel(label.id) {
                            Image(systemName: "checkmark")
                        }
                        Circle()
                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                            .frame(width: 8, height: 8)
                        Text(label.name)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tag")
                    .font(CiderFont.captionSemibold)
                Text("Tag")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tag selected items")

        Button {
            deleteSelectedItems()
        } label: {
            Image(systemName: "trash")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.destructive)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete selected items")
    }
}
