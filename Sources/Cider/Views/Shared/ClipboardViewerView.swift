import SwiftUI
import ImageIO

// MARK: - Date Grouping

enum ClipboardDateGroup: Hashable, Comparable {
    case today
    case yesterday
    case weekday(Date)
    case lastWeek
    case twoWeeksAgo
    case threeWeeksAgo
    case month(year: Int, month: Int)

    static func group(for date: Date) -> ClipboardDateGroup {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }

        let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0

        if daysDiff < 7 { return .weekday(cal.startOfDay(for: date)) }
        if daysDiff < 14 { return .lastWeek }
        if daysDiff < 21 { return .twoWeeksAgo }
        if daysDiff < 28 { return .threeWeeksAgo }

        let comps = cal.dateComponents([.year, .month], from: date)
        return .month(year: comps.year ?? 2026, month: comps.month ?? 1)
    }

    var displayLabel: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .weekday(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        case .lastWeek: return "Last Week"
        case .twoWeeksAgo: return "2 Weeks Ago"
        case .threeWeeksAgo: return "3 Weeks Ago"
        case .month(let year, let month):
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            if let date = Calendar.current.date(from: comps) {
                return formatter.string(from: date)
            }
            return "\(month)/\(year)"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .weekday: return 2
        case .lastWeek: return 3
        case .twoWeeksAgo: return 4
        case .threeWeeksAgo: return 5
        case .month: return 6
        }
    }

    static func < (lhs: ClipboardDateGroup, rhs: ClipboardDateGroup) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        switch (lhs, rhs) {
        case (.weekday(let a), .weekday(let b)):
            return a > b // More recent weekday first
        case (.month(let yA, let mA), .month(let yB, let mB)):
            if yA != yB { return yA > yB }
            return mA > mB
        default:
            return false
        }
    }
}

// MARK: - Clipboard Viewer

struct ClipboardViewerView: View {
    @ObservedObject private var clipboardStorage = ClipboardStorage.shared
    @ObservedObject private var bookmarksStorage = BookmarksStorage.shared
    @ObservedObject private var notesStorage = NotesStorage.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cider.clipboardWideMode") private var isWideMode = false
    @State private var collapsedSections: Set<ClipboardDateGroup> = []
    @State private var copiedItemID: UUID?
    @State private var savedItemID: UUID?
    @State private var showClearConfirmation = false
    @State private var showPurgeConfirmation = false
    var isStandalone: Bool = false
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?

    private static let wideColumns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
    ]

    /// Grouped items for the history sections, excluding the current (first) item.
    private var groupedItems: [(group: ClipboardDateGroup, items: [ClipboardItem])] {
        let currentID = clipboardStorage.items.first?.id
        let historyItems = clipboardStorage.items.filter { $0.id != currentID }
        let grouped = Dictionary(grouping: historyItems) { ClipboardDateGroup.group(for: $0.timestamp) }
        return grouped.sorted { $0.key < $1.key }.map { (group: $0.key, items: $0.value) }
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 500

            VStack(spacing: 0) {
                viewerHeader
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                Divider()
                    .opacity(CiderColors.dividerSecondaryOpacity)

                if clipboardStorage.items.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Current clipboard item (first item = most recent copy)
                            if let current = clipboardStorage.items.first {
                                Section {
                                    if isWide {
                                        LazyVGrid(columns: Self.wideColumns, spacing: Spacing.sm) {
                                            clipboardItemCard(for: current)
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.top, Spacing.sm)
                                        .padding(.bottom, Spacing.xs)
                                    } else {
                                        clipboardItemCard(for: current)
                                            .padding(.horizontal, Spacing.md)
                                            .padding(.top, Spacing.sm)
                                            .padding(.bottom, Spacing.xs)
                                    }
                                } header: {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: "arrow.right.doc.on.clipboard")
                                            .font(CiderFont.micro)
                                            .foregroundColor(CiderColors.controlAccent)
                                        Text("Current")
                                            .font(CiderFont.captionMedium)
                                            .foregroundColor(CiderColors.controlAccent)
                                        Spacer()
                                    }
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.xs)
                                    .background(CiderColors.accentSubtle)
                                }
                            }

                            ForEach(groupedItems, id: \.group) { group, items in
                                Section {
                                    if !collapsedSections.contains(group) {
                                        if isWide {
                                            LazyVGrid(columns: Self.wideColumns, spacing: Spacing.sm) {
                                                ForEach(items) { item in
                                                    clipboardItemCard(for: item)
                                                }
                                            }
                                            .padding(.horizontal, Spacing.md)
                                            .padding(.top, Spacing.sm)
                                            .padding(.bottom, Spacing.xs)
                                        } else {
                                            ForEach(items) { item in
                                                clipboardItemCard(for: item)
                                                    .padding(.horizontal, Spacing.md)
                                                    .padding(.vertical, Spacing.xs)
                                            }
                                        }
                                    }
                                } header: {
                                    ClipboardSectionHeader(
                                        group: group,
                                        itemCount: items.count,
                                        isCollapsed: collapsedSections.contains(group),
                                        onToggle: {
                                            withAnimation(reduceMotion ? .none : .snappy) {
                                                if collapsedSections.contains(group) {
                                                    collapsedSections.remove(group)
                                                } else {
                                                    collapsedSections.insert(group)
                                                }
                                            }
                                        },
                                        onDeleteSection: {
                                            withAnimation(reduceMotion ? .none : .snappy) {
                                                let ids = Set(items.map(\.id))
                                                clipboardStorage.dismissAll(ids: ids)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: bookmarksStorage.bookmarks.map(\.id)) { _, _ in
            reconcileSavedState()
        }
        .onChange(of: notesStorage.notes.map(\.id)) { _, _ in
            reconcileSavedState()
        }
        .alert("Clear Clipboard History", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                withAnimation(reduceMotion ? .none : .snappy) {
                    clipboardStorage.clearAll()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all clipboard history items. This cannot be undone.")
        }
        .alert("Purge Saved Items", isPresented: $showPurgeConfirmation) {
            Button("Purge", role: .destructive) {
                withAnimation(reduceMotion ? .none : .snappy) {
                    clipboardStorage.purgeSavedItems()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all items that have been saved as bookmarks or notes from clipboard history.")
        }
    }

    // MARK: - Item Card

    private func clipboardItemCard(for item: ClipboardItem) -> some View {
        ClipboardItemRow(
            item: item,
            isCopied: copiedItemID == item.id,
            isSavedFlash: savedItemID == item.id,
            onCopy: { copyItem(item) },
            onSave: { saveItem(item) },
            onDismiss: {
                withAnimation(reduceMotion ? .none : .snappy) {
                    clipboardStorage.dismiss(item)
                }
            }
        )
    }

    // MARK: - Header

    private var viewerHeader: some View {
        HStack(spacing: Spacing.sm) {
            if isStandalone, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close clipboard")
            }

            Text("Clipboard")
                .font(CiderFont.navTitle)
                .foregroundColor(CiderColors.primary)

            Spacer()

            if clipboardStorage.items.contains(where: { $0.isSaved }) {
                Button { showPurgeConfirmation = true } label: {
                    Text("Purge saved")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove all saved items from clipboard history")
            }

            if !clipboardStorage.items.isEmpty {
                Button { showClearConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all clipboard history")
            }

            if isStandalone {
                Button {
                    isWideMode.toggle()
                    NotificationCenter.default.post(name: .toggleClipboardPanelWidth, object: nil)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help(isWideMode ? "Narrow view" : "Wide view")
            }

            if isStandalone, let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Expand panel")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clipboard")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)
            Text("No clipboard history")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
            Text("Items you copy will appear here")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Copy

    private func copyItem(_ item: ClipboardItem) {
        // Move item to top of history (becomes "Current")
        clipboardStorage.moveToTop(item.id)

        switch item.type {
        case .url, .text, .richText:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
            suspendAllClipboardMonitors()
            flashCopied(item.id)
        case .image:
            guard let url = clipboardStorage.imageURL(for: item) else { return }
            flashCopied(item.id)
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: url)
                }.value
                guard let data else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(data, forType: .png)
                suspendAllClipboardMonitors()
            }
        }
    }

    private func suspendAllClipboardMonitors() {
        ClipboardHistoryService.shared.suspendFor(seconds: 2)
        BookmarksClipboardMonitor.shared.suspendFor(seconds: 2)
    }

    private func flashCopied(_ id: UUID) {
        withAnimation(reduceMotion ? .none : .snappy) {
            copiedItemID = id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if copiedItemID == id {
                withAnimation(reduceMotion ? .none : .smooth) {
                    copiedItemID = nil
                }
            }
        }
    }

    private func flashSaved(_ id: UUID) {
        withAnimation(reduceMotion ? .none : .snappy) {
            savedItemID = id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if savedItemID == id {
                withAnimation(reduceMotion ? .none : .smooth) {
                    savedItemID = nil
                }
            }
        }
    }

    private func reconcileSavedState() {
        let bookmarkIDs = Set(bookmarksStorage.bookmarks.map(\.id))
        let noteIDs = Set(notesStorage.notes.map(\.id))
        clipboardStorage.reconcileSavedState(bookmarkIDs: bookmarkIDs, noteIDs: noteIDs)
    }

    // MARK: - Save

    private func saveItem(_ item: ClipboardItem) {
        // Prevent duplicate saves
        guard !item.isSaved else { return }

        var resultID: UUID?

        switch item.type {
        case .url:
            if let urlString = item.textContent {
                if let bookmark = BookmarksStorage.shared.add(urlString: urlString, title: nil) {
                    resultID = bookmark.id
                    NotificationCenter.default.post(
                        name: .showBookmarkCaptureToast,
                        object: nil,
                        userInfo: ["message": "Saved as bookmark", "isSuccess": true]
                    )
                }
            }
        case .image:
            guard let url = clipboardStorage.imageURL(for: item) else { break }
            let ext = item.imageFileExtension ?? "png"
            let itemID = item.id
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: url)
                }.value
                guard let data else { return }
                let bookmark = BookmarksStorage.shared.addImageBookmark(title: "Clipboard Image")
                _ = BookmarksStorage.shared.assignThumbnail(
                    for: bookmark.id,
                    imageData: data,
                    preferredFileExtension: ext
                )
                clipboardStorage.markSaved(itemID, savedItemID: bookmark.id)
                flashSaved(itemID)
                NotificationCenter.default.post(
                    name: .showBookmarkCaptureToast,
                    object: nil,
                    userInfo: ["message": "Saved as image bookmark", "isSuccess": true]
                )
            }
            return  // async path handles markSaved + flash itself
        case .text, .richText:
            if let text = item.textContent {
                resultID = saveAsNote(text: text)
            }
        }

        clipboardStorage.markSaved(item.id, savedItemID: resultID)
        flashSaved(item.id)
    }

    @discardableResult
    private func saveAsNote(text: String) -> UUID {
        let storage = NotesStorage.shared
        var note = storage.createNew()
        note.content = text
        storage.save(note: note, createSnapshot: false)
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: ["message": "Saved as note", "isSuccess": true]
        )
        return note.id
    }
}

// MARK: - Section Header

private struct ClipboardSectionHeader: View {
    let group: ClipboardDateGroup
    let itemCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onDeleteSection: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 12)

                    Text(group.displayLabel)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                }
            }
            .buttonStyle(.plain)

            Text("\(itemCount)")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.surfaceSubtle)
                )

            Spacer()

            if isHovered {
                Button(action: onDeleteSection) {
                    Image(systemName: "trash")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.destructive)
                }
                .buttonStyle(.plain)
                .help("Delete all items in this section")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(CiderColors.surfaceSubtle)
        .padding(.top, Spacing.sm)
        .hoverState($isHovered, animation: .snappy)
    }
}

// MARK: - Clipboard Item Row

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isCopied: Bool
    var isSavedFlash: Bool = false
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: type icon + source + timestamp
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.typeIcon)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.controlAccent)

                if let appName = item.sourceAppName {
                    Text(appName)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                }

                Spacer()

                if item.isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.success)
                }

                Text(item.timestamp, style: .relative)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            // Content preview
            contentPreview

            // Actions on hover
            if isHovered {
                HStack(spacing: Spacing.sm) {
                    copyButton
                    saveButton
                    dismissButton
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(Spacing.md)
        .cardContainer(isHovered: isHovered)
        .overlay {
            if isCopied {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(CiderFont.bodySemibold)
                            Text("Copied")
                                .font(CiderFont.bodySemibold)
                        }
                        .foregroundColor(CiderColors.controlAccent)
                    }
                    .transition(.opacity)
            } else if isSavedFlash {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(CiderFont.bodySemibold)
                            Text("Saved")
                                .font(CiderFont.bodySemibold)
                        }
                        .foregroundColor(CiderColors.success)
                    }
                    .transition(.opacity)
            }
        }
        .hoverState($isHovered, animation: .snappy)
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .url:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    AsyncFavicon(item: item)
                        .frame(width: 16, height: 16)
                    if let domain = Self.domain(from: item.textContent) {
                        Text(domain)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                    }
                }
                if let url = item.textContent {
                    Text(url)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .lineLimit(2)
                }
            }
        case .image:
            clipboardImagePreview
        case .text, .richText:
            if let text = item.textContent {
                Text(text)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private var clipboardImagePreview: some View {
        if let url = ClipboardStorage.shared.imageURL(for: item) {
            AsyncClipboardImage(url: url)
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.on.doc")
                    .font(CiderFont.caption)
                Text("Copy")
                    .font(CiderFont.captionMedium)
            }
            .foregroundColor(CiderColors.controlAccent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.accentSubtle)
            )
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: saveButtonIcon)
                    .font(CiderFont.caption)
                Text(saveButtonLabel)
                    .font(CiderFont.captionMedium)
            }
            .foregroundColor(item.isSaved ? CiderColors.success : CiderColors.controlAccent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(item.isSaved ? CiderColors.success.opacity(0.08) : CiderColors.accentSubtle)
            )
        }
        .buttonStyle(.plain)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "trash")
                    .font(CiderFont.caption)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
        }
        .buttonStyle(.plain)
    }

    private var saveButtonIcon: String {
        if item.isSaved { return "checkmark" }
        switch item.type {
        case .url, .image: return "bookmark"
        case .text, .richText: return "note.text"
        }
    }

    private var saveButtonLabel: String {
        if item.isSaved { return "Saved" }
        switch item.type {
        case .url: return "Bookmark"
        case .image: return "Bookmark"
        case .text, .richText: return "Note"
        }
    }

    nonisolated static func domain(from urlString: String?) -> String? {
        guard let urlString, let host = URL(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Async Favicon

private struct AsyncFavicon: View {
    let item: ClipboardItem
    @ObservedObject private var storage = ClipboardStorage.shared

    var body: some View {
        Group {
            if let url = storage.cachedFaviconURL(for: item),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .task(id: item.id) {
            // Trigger on-demand fetch for items without cached favicons
            if storage.cachedFaviconURL(for: item) == nil {
                await storage.fetchFavicon(for: item)
            }
        }
    }
}

// MARK: - Async Clipboard Image

private struct AsyncClipboardImage: View {
    let url: URL
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
                    .frame(height: 60)
            }
        }
        .task(id: url) {
            nsImage = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
