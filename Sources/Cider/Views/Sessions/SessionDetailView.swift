import SwiftUI

struct SessionDetailView: View {
    let session: BrowserSession
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var sessionStorage = BrowserSessionStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var restoreBrowserBundleID: String?
    @State private var isRestoring = false
    @State private var savedTabIDs: Set<UUID> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var liveSession: BrowserSession {
        sessionStorage.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        let current = liveSession
        VStack(alignment: .leading, spacing: Spacing.md) {
            // MARK: - Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if isEditingName {
                    HStack(spacing: Spacing.xs) {
                        TextField("Session name", text: $draftName, onCommit: commitRename)
                            .textFieldStyle(.plain)
                            .font(CiderFont.subheading)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )

                        Button("Save") { commitRename() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button("Cancel") {
                            isEditingName = false
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "rectangle.stack")
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.controlAccent)

                        Text(current.name)
                            .font(CiderFont.subheading)
                            .foregroundColor(CiderColors.primary)

                        Spacer(minLength: Spacing.sm)

                        Button {
                            draftName = current.name
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename session")
                    }
                }

                // Metadata row
                HStack(spacing: Spacing.sm) {
                    Text("\(current.tabCount) tab\(current.tabCount == 1 ? "" : "s")")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)

                    if let browserName = current.sourceBrowserName {
                        Text("\u{00B7}")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.quaternary)
                        Text(browserName)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Text("\u{00B7}")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                    Text(current.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }

                // Labels
                if !current.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: current.labelIDs,
                        labels: labelStorage.labels
                    )
                }
            }

            Divider().background(CiderColors.separator)

            // MARK: - Tab List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(current.tabs) { tab in
                        tabRow(tab)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Divider().background(CiderColors.separator)

            // MARK: - Actions
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    restoreButton(current)

                    browserPicker

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        if let trashItem = sessionStorage.delete(session.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .session, trashItem: trashItem))
                        }
                        onDismiss?()
                    } label: {
                        Image(systemName: "trash")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.destructive)
                    }
                    .buttonStyle(.plain)
                    .help("Delete session")
                }
            }
        }
    }

    // MARK: - Tab Row

    private func tabRow(_ tab: BrowserSessionTab) -> some View {
        let isSaved = savedTabIDs.contains(tab.id)
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "globe")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title ?? "Untitled")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text(tab.urlString)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            Button {
                if isSaved { return }
                _ = BookmarksStorage.shared.add(urlString: tab.urlString, title: tab.title)
                savedTabIDs.insert(tab.id)
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(CiderFont.body)
                    .foregroundColor(isSaved ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSaved ? "Saved as bookmark" : "Save as bookmark")

            if let url = tab.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in browser")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    // MARK: - Restore Button

    @ViewBuilder
    private func restoreButton(_ current: BrowserSession) -> some View {
        let urls = current.tabs.compactMap(\.url)
        Button {
            guard !urls.isEmpty else { return }
            isRestoring = true

            // Use explicitly chosen browser, or fall back to system default
            if let bundleID = restoreBrowserBundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
            } else {
                // Opens in system default browser
                for url in urls {
                    NSWorkspace.shared.open(url)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRestoring = false
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.uturn.backward")
                        .font(CiderFont.bodySemibold)
                }
                Text("Restore All Tabs")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.textOnColor)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(urls.isEmpty ? CiderColors.separatorMedium : CiderColors.controlAccent)
            )
        }
        .buttonStyle(.plain)
        .disabled(urls.isEmpty || isRestoring)
        .help(urls.isEmpty ? "No URLs to restore" : "Open all \(urls.count) tabs in browser")
    }

    // MARK: - Browser Picker

    private var browserPicker: some View {
        let browsers = BrowserTabCaptureService.runningBrowsers()
        return Menu {
            Button {
                restoreBrowserBundleID = nil
                var config = CiderConfig.load()
                config.sessionRestoreBrowserBundleID = nil
                config.save()
            } label: {
                HStack {
                    Text("Default Browser")
                    if restoreBrowserBundleID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !browsers.isEmpty {
                Divider()
                ForEach(browsers, id: \.bundleID) { browser in
                    Button {
                        restoreBrowserBundleID = browser.bundleID
                        var config = CiderConfig.load()
                        config.sessionRestoreBrowserBundleID = browser.bundleID
                        config.save()
                    } label: {
                        HStack {
                            Text(browser.appName)
                            if restoreBrowserBundleID == browser.bundleID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.tertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose browser for restore")
        .onAppear {
            restoreBrowserBundleID = CiderConfig.load().sessionRestoreBrowserBundleID
        }
    }

    // MARK: - Helpers

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }
        sessionStorage.rename(session.id, to: trimmed)
        isEditingName = false
    }
}
