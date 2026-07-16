import AppKit
import ImageIO
import SwiftUI

struct JournalLibraryCardView: View {
    let container: JournalLibraryContainer
    let onOpen: () -> Void
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            let flags = NSEvent.modifierFlags
            if let onSelect, flags.contains(.command) {
                onSelect()
            } else if let onShiftSelect, flags.contains(.shift) {
                onShiftSelect()
            } else {
                onOpen()
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "book.closed")
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text(container.title)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                }

                Text("\(container.entryCount) daily entries")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)

                Text("Open the Journal Library viewer")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 132)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
    }
}

struct JournalDetailContentView: View {
    let projection: JournalLibraryReadModel
    @ObservedObject var notesViewModel: NotesViewModel
    @Binding var selectedEntryID: String?
    @ObservedObject var voiceCaptureSession: JournalVoiceCaptureSessionController
    let resolveCanonicalItem: (LibraryEntityType, String) -> LibraryEntityRef?
    let onOpenCanonicalItem: (LibraryEntityRef) -> Void
    @State private var isEditingSource = false
    @State private var intelligenceState: JournalIntelligenceDayReviewLoadState = .loading
    @State private var isIntelligenceExpanded = false
    @State private var intelligenceReloadToken = 0

    private var selectedDay: JournalLibraryDay? {
        if let selectedEntryID {
            return projection.days.first {
                $0.id == selectedEntryID || $0.sourceEntries.contains { $0.id == selectedEntryID }
            } ?? projection.defaultDay
        }
        return projection.defaultDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedDay {
                HStack(alignment: .center, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(selectedDay.displayTitle)
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(2)

                        Text(selectedDay.isAggregate ? "\(selectedDay.sourceEntries.count) preserved source notes" : selectedDay.displayTitle)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Spacer(minLength: Spacing.sm)

                    if let journalDate = selectedDay.sourceEntries.first?.dateLabel {
                        JournalVoiceCaptureControl(
                            session: voiceCaptureSession,
                            journalDate: journalDate,
                            dayTitle: selectedDay.displayTitle
                        )
                    }
                }
                .padding(Spacing.md)

                Divider()
                    .background(CiderColors.separator)

                if !selectedDay.captureCards.isEmpty, !isEditingSource {
                    JournalCaptureCardsView(
                        day: selectedDay,
                        intelligenceState: intelligenceState,
                        isIntelligenceExpanded: $isIntelligenceExpanded,
                        onReloadIntelligence: { intelligenceReloadToken += 1 },
                        resolveCanonicalItem: resolveCanonicalItem,
                        onOpenCanonicalItem: onOpenCanonicalItem,
                        onEditSource: selectedDay.editableEntry == nil ? nil : { isEditingSource = true }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if !isEditingSource {
                            JournalIntelligenceDayReviewView(
                                state: intelligenceState,
                                isExpanded: $isIntelligenceExpanded,
                                onReload: { intelligenceReloadToken += 1 },
                                onOpenSource: { _ in }
                            )
                            .padding(Spacing.md)
                        }
                        InlineNoteEditorView(viewModel: notesViewModel)
                    }
                }
            } else {
                EmptyStateView(icon: "book.closed", title: "No journal entries")
                    .padding(Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedEntryID = selectedDay?.id
            selectJournalNoteIfNeeded()
        }
        .onChange(of: selectedEntryID) { _, _ in
            voiceCaptureSession.cancel()
            isEditingSource = false
            isIntelligenceExpanded = false
            selectJournalNoteIfNeeded()
        }
        .onChange(of: projection.days) { _, _ in selectJournalNoteIfNeeded() }
        .task(id: intelligenceLoadID) {
            await loadJournalIntelligence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            voiceCaptureSession.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            voiceCaptureSession.cancel()
        }
        .onDisappear {
            voiceCaptureSession.cancel()
        }
    }

    private var intelligenceLoadID: String {
        guard let selectedDay else { return "journal-review-none-\(intelligenceReloadToken)" }
        let latestUpdate = selectedDay.sourceEntries.map(\.note.modifiedAt.timeIntervalSince1970).max() ?? 0
        return "\(selectedDay.id)-\(latestUpdate)-\(intelligenceReloadToken)"
    }

    @MainActor
    private func loadJournalIntelligence() async {
        intelligenceState = .loading
        await Task.yield()
        guard !Task.isCancelled, let day = selectedDay else {
            intelligenceState = .unavailable(JournalIntelligenceDayReviewHealth.unavailable.message)
            return
        }
        do {
            let review = try JournalIntelligenceDayReviewService().review(for: day)
            guard !Task.isCancelled, selectedDay?.id == day.id else { return }
            intelligenceState = .ready(review)
        } catch {
            guard !Task.isCancelled else { return }
            intelligenceState = .unavailable(JournalIntelligenceDayReviewHealth.unavailable.message)
        }
    }

    private func selectJournalNoteIfNeeded() {
        guard let day = selectedDay else {
            notesViewModel.setRichDisplayContentOverride(nil)
            notesViewModel.clearSelectedNote()
            return
        }
        guard let entry = day.editableEntry else {
            notesViewModel.setRichDisplayContentOverride(nil)
            notesViewModel.clearSelectedNote()
            return
        }
        let displayContent = entry.preparedDisplayContent(timestampFormat: CiderConfig.load().journalTimestampFormat)
        if notesViewModel.selectedNote?.id != entry.note.id {
            notesViewModel.selectNote(entry.note, richDisplayContentOverride: displayContent)
        } else {
            notesViewModel.setRichDisplayContentOverride(displayContent)
        }
    }
}

struct JournalVoiceCaptureControl: View {
    @ObservedObject var session: JournalVoiceCaptureSessionController
    let journalDate: String
    let dayTitle: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            switch session.state {
            case .idle:
                recordButton(accessibilityLabel: "Record a voice note for \(dayTitle)")
            case .requestingPermission:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Requesting Journal voice permissions")
                cancelButton(label: "Cancel Journal voice permission request")
            case .recording(let elapsed):
                Text(Self.elapsed(elapsed))
                    .font(CiderFont.microMedium.monospacedDigit())
                    .foregroundColor(CiderColors.secondary)
                    .accessibilityLabel("Recording elapsed \(Self.elapsed(elapsed))")
                Button {
                    Task { await session.stopRecording() }
                } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Stop and save Journal voice note")
                .help("Stop, transcribe, and save")
                cancelButton(label: "Cancel Journal voice note")
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Transcribing and saving Journal voice note")
                Text("Transcribing and saving")
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.secondary)
                cancelButton(label: "Cancel Journal voice transcription")
            case .succeeded(let receipt):
                statusLabel(
                    symbol: "checkmark.circle.fill",
                    text: receipt.wasReused ? "Voice note already saved" : "Voice note saved",
                    color: CiderColors.controlAccent
                )
                .help("Saved to Journal \(receipt.journalDate) at \(receipt.time). Receipt \(receipt.receiptID).")
                recordButton(accessibilityLabel: "Record another voice note for \(dayTitle)")
            case .cancelled:
                statusLabel(symbol: "xmark.circle", text: "Cancelled", color: CiderColors.tertiary)
                recordButton(accessibilityLabel: "Record a voice note for \(dayTitle)")
            case .failed(let failure):
                statusLabel(symbol: "exclamationmark.circle", text: failure.title, color: CiderColors.destructive)
                    .help(failure.detail)
                recordButton(accessibilityLabel: "Retry recording a voice note for \(dayTitle)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func recordButton(accessibilityLabel: String) -> some View {
        Button {
            if session.state != .idle { session.reset() }
            Task { await session.startRecording(journalDate: journalDate) }
        } label: {
            Image(systemName: "mic")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
        .help("Record Journal voice note")
    }

    private func cancelButton(label: String) -> some View {
        Button {
            session.cancel()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .help("Cancel and remove the temporary recording")
    }

    private func statusLabel(symbol: String, text: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(CiderFont.microMedium)
            .foregroundColor(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }

    private static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct JournalCaptureCardsView: View {
    let day: JournalLibraryDay
    let intelligenceState: JournalIntelligenceDayReviewLoadState
    @Binding var isIntelligenceExpanded: Bool
    let onReloadIntelligence: () -> Void
    let resolveCanonicalItem: (LibraryEntityType, String) -> LibraryEntityRef?
    let onOpenCanonicalItem: (LibraryEntityRef) -> Void
    let onEditSource: (() -> Void)?

    private var timestampFormat: JournalTimestampFormat {
        CiderConfig.load().journalTimestampFormat
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    JournalIntelligenceDayReviewView(
                        state: intelligenceState,
                        isExpanded: $isIntelligenceExpanded,
                        onReload: onReloadIntelligence,
                        onOpenSource: { navigation in
                            guard let captureCardID = navigation.captureCardID else { return }
                            withAnimation(.snappy) {
                                proxy.scrollTo(captureCardID, anchor: .center)
                            }
                        }
                    )

                    if let onEditSource {
                        HStack {
                            Text("Capture cards are a read-only view of one physical note.")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.tertiary)

                            Spacer(minLength: Spacing.sm)

                            Button("Edit source note", action: onEditSource)
                                .buttonStyle(.bordered)
                        }
                    }

                    ForEach(day.captureCards) { card in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text(card.displayTimestamp(format: timestampFormat))
                                    .font(CiderFont.bodySemibold)
                                    .foregroundColor(CiderColors.primary)

                                Text(JournalLibraryReadModel.friendlyCaptureSourceLabel(for: card.captureSource))
                                    .font(CiderFont.captionMedium)
                                    .foregroundColor(CiderColors.secondary)

                                Spacer(minLength: 0)
                            }

                            MarkdownContentView(
                                text: card.preparedMarkdown(
                                    timestampFormat: timestampFormat,
                                    resolveCanonicalItem: resolveCanonicalItem
                                )
                            )
                            .environment(\.openURL, OpenURLAction { destination in
                                switch JournalCaptureLink.target(
                                    for: destination,
                                    resolveCanonicalItem: resolveCanonicalItem
                                ) {
                                case .external(let url):
                                    CiderOpenPolicy.shared.openIfAllowed(.untrustedWeb(url))
                                    return .handled
                                case .item(let ref):
                                    onOpenCanonicalItem(ref)
                                    return .handled
                                case nil:
                                    return .discarded
                                }
                            })

                            if !card.mediaSources.isEmpty {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.sm)],
                                    alignment: .leading,
                                    spacing: Spacing.sm
                                ) {
                                    ForEach(card.mediaSources) { source in
                                        JournalMediaSourceCardView(source: source) {
                                            guard source.isOriginalAvailable else { return }
                                            onOpenCanonicalItem(source.canonicalItemRef)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CiderColors.surfaceInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .id(card.id)
                    }
                }
                .padding(Spacing.md)
            }
        }
    }
}

private struct JournalMediaSourceCardView: View {
    let source: JournalMediaSourceCard
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                thumbnail

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(source.displayTitle)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)

                    Text(source.isOriginalAvailable ? source.rawFilename : "Original unavailable")
                        .font(CiderFont.caption)
                        .foregroundColor(source.isOriginalAvailable ? CiderColors.tertiary : CiderColors.warning)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CiderColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!source.isOriginalAvailable)
        .accessibilityLabel(source.availabilityLabel)
        .help(source.isOriginalAvailable ? "Open in Cider" : "The retained original is missing")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if source.kind == .photo, source.isOriginalAvailable {
            JournalMediaPhotoThumbnailView(source: source)
        } else {
            Image(systemName: source.kind == .audio ? "waveform" : source.kind == .photo ? "photo" : "paperclip")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 48, height: 48)
                .background(CiderColors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
    }
}

private struct JournalMediaPhotoThumbnailView: View {
    let source: JournalMediaSourceCard
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CiderColors.surfaceInput)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .task(id: "\(source.id):\(source.relativePath):\(source.capturedAt.timeIntervalSince1970)") {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let cached = VaultFileThumbnailCache.shared.get(
            source.relativePath,
            modifiedAt: source.capturedAt
        ) {
            image = cached
            return
        }

        let url = StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(source.relativePath)
            .standardizedFileURL
        let loaded = await JournalMediaPhotoThumbnailLoader.load(at: url)
        guard !Task.isCancelled, let loaded else { return }
        VaultFileThumbnailCache.shared.set(
            loaded,
            for: source.relativePath,
            modifiedAt: source.capturedAt
        )
        image = loaded
    }
}

enum JournalMediaPhotoThumbnailLoader {
    static func load(at url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                options as CFDictionary
            ) else {
                return nil
            }
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }.value
    }
}

struct JournalNavigationPanelView: View {
    let projection: JournalLibraryReadModel
    @Binding var selectedEntryID: String?

    @State private var expandedNodeIDs: Set<String> = []

    var body: some View {
        ItemMetadataPanel {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Journal Navigation")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                if projection.navigation.isEmpty {
                    ItemMetadataEmptyText(text: "No daily journal entries yet.")
                } else {
                    ForEach(projection.navigation) { node in
                        nodeView(node, depth: 0)
                    }
                }
            }
        }
    }

    private func nodeView(_ node: JournalNavigationNode, depth: Int) -> AnyView {
        let isExpanded = expandedNodeIDs.contains(node.id)
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if let entryID = node.entryID {
                        selectedEntryID = entryID
                    } else if isExpanded {
                        expandedNodeIDs.remove(node.id)
                    } else {
                        expandedNodeIDs.insert(node.id)
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if node.children.isEmpty {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(CiderColors.quaternary)
                                .frame(width: 12)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.tertiary)
                                .frame(width: 12)
                        }

                        Text(node.title)
                            .font(node.entryID == nil ? CiderFont.bodyMedium : CiderFont.body)
                            .foregroundColor(node.entryID == selectedEntryID ? CiderColors.controlAccent : CiderColors.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(depth) * Spacing.md)
                    .padding(.vertical, Spacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(node.children) { child in
                        nodeView(child, depth: depth + 1)
                    }
                }
            }
        )
    }
}

struct JournalMetadataPanelView: View {
    let projection: JournalLibraryReadModel

    var body: some View {
        ItemMetadataPanel {
            ItemMetadataSectionView(title: "Details", isExpanded: .constant(true)) {
                ItemMetadataRowsView(rows: [
                    ItemMetadataRow(id: "type", symbol: "book.closed", title: "Type", value: "Journal"),
                    ItemMetadataRow(id: "entries", symbol: "doc.text", title: "Entries", value: "\(projection.entries.count)")
                ])
            }
        }
    }
}

struct JournalNavigationToggleButton: View {
    @Binding var isVisible: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: isVisible ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                        .font(CiderFont.toolbarIcon)
                        .foregroundColor(isVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide journal navigation" : "Show journal navigation")
    }
}
