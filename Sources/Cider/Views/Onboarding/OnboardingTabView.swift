import SwiftUI

struct OnboardingTabView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let twoColumnThreshold: CGFloat = 560
    private static let maxGridWidth: CGFloat = 640

    private struct SectionData: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let lines: [String]
    }

    // 10 items total → 5 rows of 2 in grid mode
    private let allCards: [SectionData] = [
        SectionData(id: 0, icon: "option", title: "Open Cider Anytime", lines: [
            "Double-tap Option to recall your last floating Cider surface.",
            "If there is nothing to recall, Cider opens the main window."
        ]),
        SectionData(id: 1, icon: "plus.circle.fill", title: "Capture from Your Browser", lines: [
            "Click the capture button (top right) or press Opt+B.",
            "Cider grabs the URL, title, and a thumbnail automatically."
        ]),
        SectionData(id: 2, icon: "doc.on.clipboard", title: "Clipboard Capture", lines: [
            "Copy any URL and Cider detects it automatically.",
            "A toast appears letting you save or discard instantly.",
            "Works with copied images too \u{2014} save them as visual bookmarks."
        ]),
        SectionData(id: 3, icon: "note.text", title: "Write Notes", lines: [
            "Press Opt+N to create a note from anywhere.",
            "Rich text editor with markdown, images, and code blocks.",
            "Copy text from any app and paste it right into a note."
        ]),
        SectionData(id: 4, icon: "photo.on.rectangle.angled", title: "Drag & Drop Everything", lines: [
            "Drag images onto bookmarks to set their thumbnail.",
            "Drop images directly into the notes editor.",
            "Drag items to folders in the sidebar to organize them."
        ]),
        SectionData(id: 5, icon: "folder.fill", title: "Organize with Folders & Tags", lines: [
            "Create folders in the sidebar to group related items.",
            "Add tags for flexible cross-cutting categories.",
            "Nest folders for deeper organization."
        ]),
        SectionData(id: 6, icon: "calendar.badge.plus", title: "Track Events & Contacts", lines: [
            "Click +New to create date cards and contacts.",
            "Upcoming events surface automatically in your feed."
        ]),
        SectionData(id: 7, icon: "slider.horizontal.3", title: "Custom Tabs", lines: [
            "Each tab is a saved view with its own filters and layout.",
            "Use View Options to filter by type, sort, and switch layouts.",
            "Create as many tabs as you need \u{2014} list, grid, or masonry."
        ]),
        SectionData(id: 8, icon: "magnifyingglass", title: "Search Everything", lines: [
            "Press Cmd+K to open the search palette.",
            "Searches across bookmarks, notes, events, and contacts.",
            "Or use the sidebar search to filter the current view."
        ])
    ]

    var body: some View {
        GeometryReader { proxy in
            let useTwoColumns = proxy.size.width >= Self.twoColumnThreshold

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                        .frame(height: Spacing.xl)

                    // MARK: - Header

                    VStack(spacing: Spacing.md) {
                        Image(systemName: "sparkles")
                            .font(CiderFont.emptyStateIconLarge)
                            .foregroundColor(CiderColors.controlAccent)

                        Text("Welcome to Cider")
                            .font(CiderFont.displayBold)
                            .foregroundColor(CiderColors.primary)

                        Text("Your Mac workspace for saving\nand organizing anything you want back later.")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }

                    // MARK: - Sections

                    if useTwoColumns {
                        twoColumnLayout
                    } else {
                        singleColumnLayout
                    }

                    // MARK: - Footer

                    VStack(spacing: Spacing.md) {
                        Button("Get Started") {
                            onDismiss()
                        }
                        .buttonStyle(CiderAccentButtonStyle())

                        Text("You can always find this guide in Settings \u{2192} About.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                        .frame(height: Spacing.xxl)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layouts

    private var singleColumnLayout: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(allCards) { section in
                onboardingCard(section)
            }
            shortcutsCard
        }
        .frame(maxWidth: 360)
    }

    /// Pairs of cards in top-aligned rows: 9 sections + 1 shortcuts = 10 items → 5 rows
    private var twoColumnLayout: some View {
        // Build a flat array of card views, then chunk into rows of 2
        let paired: [(left: SectionData, right: SectionData?)] = stride(from: 0, to: allCards.count, by: 2).map { i in
            let left = allCards[i]
            let right = i + 1 < allCards.count ? allCards[i + 1] : nil
            return (left, right)
        }

        return VStack(spacing: Spacing.sm) {
            ForEach(paired, id: \.left.id) { pair in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    onboardingCard(pair.left)
                    if let right = pair.right {
                        onboardingCard(right)
                    } else {
                        shortcutsCard
                    }
                }
            }
            // If allCards.count is even, shortcuts needs its own row
            if allCards.count % 2 == 0 {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    shortcutsCard
                    Color.clear
                }
            }
        }
        .frame(maxWidth: Self.maxGridWidth)
    }

    // MARK: - Card Builders

    private func onboardingCard(_ section: SectionData) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: section.icon)
                .font(CiderFont.titleLarge)
                .foregroundColor(CiderColors.controlAccent)

            Text(section.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            VStack(spacing: Spacing.xs) {
                ForEach(section.lines, id: \.self) { line in
                    Text(line)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private var shortcutsCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "keyboard")
                .font(CiderFont.titleLarge)
                .foregroundColor(CiderColors.controlAccent)

            Text("Keyboard Shortcuts")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            VStack(spacing: Spacing.xs) {
                shortcutRow(keys: "Option \u{00D7} 2", action: "Recall last surface")
                shortcutRow(keys: "Opt + B", action: "Capture browser tab")
                shortcutRow(keys: "Opt + N", action: "New note")
                shortcutRow(keys: "Cmd + K", action: "Search palette")
                shortcutRow(keys: "Esc", action: "Dismiss window")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(action)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
