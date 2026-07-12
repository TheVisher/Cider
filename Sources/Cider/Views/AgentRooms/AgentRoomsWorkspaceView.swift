import SwiftUI

struct AgentRoomsWorkspaceView: View {
    let loadWorkspace: @MainActor () async -> AgentRoomsWorkspaceState
    let onOpenLiveChat: () -> Void

    @State private var state: AgentRoomsWorkspaceState
    @State private var selectedRoomID: String?
    @FocusState private var focusedRegion: FocusRegion?

    private enum FocusRegion: Hashable {
        case roomList
        case transcript
    }

    init(
        loadWorkspace: @escaping @MainActor () async -> AgentRoomsWorkspaceState,
        onOpenLiveChat: @escaping () -> Void
    ) {
        self.loadWorkspace = loadWorkspace
        self.onOpenLiveChat = onOpenLiveChat
        _state = State(initialValue: .loading(authority: .canonicalIncomplete))
        _selectedRoomID = State(initialValue: nil)
    }

    /// Explicit state injection is reserved for previews and focused view tests.
    init(state: AgentRoomsWorkspaceState, onOpenLiveChat: @escaping () -> Void) {
        self.loadWorkspace = { state }
        self.onOpenLiveChat = onOpenLiveChat
        _state = State(initialValue: state)
        if case .loaded(_, _, let selectedRoomID) = state {
            _selectedRoomID = State(initialValue: selectedRoomID)
        } else {
            _selectedRoomID = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CiderColors.borderSubtle)
            workspaceBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CiderColors.surfaceHighlight)
        .task {
            await reload()
        }
        .onChange(of: state) { _, newState in
            if case .loaded(_, let rooms, let storedSelection) = newState {
                selectedRoomID = rooms.contains(where: { $0.id == storedSelection })
                    ? storedSelection
                    : rooms.first?.id
            } else {
                selectedRoomID = nil
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                headerTitle
                Spacer(minLength: Spacing.md)
                openLiveChatButton
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerTitle
                openLiveChatButton
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text("Rooms")
                    .font(CiderFont.displaySemibold)
                    .foregroundColor(CiderColors.primary)

                Text(authorityPresentation.badge)
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(CiderColors.surfaceInput))
                    .overlay(Capsule().stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
                    .accessibilityLabel(authorityPresentation.badgeAccessibility)
            }

            Text(authorityPresentation.subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        }
    }

    private var openLiveChatButton: some View {
        Button(action: onOpenLiveChat) {
            Label("Open Live Chat", systemImage: "rectangle.on.rectangle")
                .font(CiderFont.labelMedium)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Open current live Hermes chat in a separate panel")
        .help("Open current live Hermes chat in a separate panel")
    }

    @ViewBuilder
    private var workspaceBody: some View {
        switch state.projection(selectedRoomID: selectedRoomID) {
        case .loading:
            loadingState
        case .empty(let authority):
            emptyState(authority: authority)
        case .blocked(let authority, let message):
            blockedState(authority: authority, message: message)
        case .failed(_, let message):
            failedState(message: message)
        case .loaded(let authority, let rooms, let selectedRoom):
            GeometryReader { proxy in
                if proxy.size.width >= 660 {
                    HStack(spacing: 0) {
                        roomRail(rooms: rooms, selectedRoom: selectedRoom)
                            .frame(width: 252)
                        Divider().overlay(CiderColors.borderSubtle)
                        transcriptPane(room: selectedRoom, authority: authority)
                    }
                } else {
                    VStack(spacing: 0) {
                        roomRail(rooms: rooms, selectedRoom: selectedRoom)
                            .frame(maxHeight: 216)
                        Divider().overlay(CiderColors.borderSubtle)
                        transcriptPane(room: selectedRoom, authority: authority)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("Loading read-only Rooms")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading read-only Rooms")
    }

    private func emptyState(authority: AgentRoomsWorkspaceAuthority) -> some View {
        let presentation = authorityPresentation(for: authority)
        return VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)
            Text(presentation.emptyTitle)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)
            Text(presentation.emptyDetail)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
            openLiveChatButton
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func blockedState(authority: AgentRoomsWorkspaceAuthority, message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.secondary)
            Text("Legacy preview blocked")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
            Text(message)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await reload() }
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(authorityPresentation(for: authority).badgeAccessibility). Legacy preview blocked. \(message)")
    }

    private func failedState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.secondary)
            Text("Rooms unavailable")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
            Text(message)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await reload() }
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func roomRail(rooms: [AgentRoom], selectedRoom: AgentRoom) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("ROOMS")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.md)

                    ForEach(rooms) { room in
                        roomRow(room, isSelected: room.id == selectedRoom.id)
                            .id(room.id)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rooms")
            .focusable()
            .focused($focusedRegion, equals: .roomList)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs)
                    .stroke(
                        focusedRegion == .roomList ? CiderColors.controlAccent.opacity(0.8) : Color.clear,
                        lineWidth: Spacing.hairline
                    )
            )
            .onMoveCommand { direction in
                moveSelection(direction, rooms: rooms, selectedRoom: selectedRoom)
                if let selectedRoomID {
                    proxy.scrollTo(selectedRoomID, anchor: .center)
                }
            }
            .onKeyPress(.return) {
                focusedRegion = .transcript
                return .handled
            }
        }
        .background(CiderColors.surfaceSubtle)
    }

    private func roomRow(_ room: AgentRoom, isSelected: Bool) -> some View {
        Button {
            selectedRoomID = room.id
            focusedRegion = .roomList
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(room.title)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.xs)
                        Text(room.relativeTime)
                            .font(CiderFont.microMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Text(room.preview)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(2)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.controlAccent)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? CiderColors.controlAccent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isSelected ? CiderColors.borderHover : Color.clear, lineWidth: Spacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(room.title), \(room.preview), \(room.relativeTime)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func moveSelection(
        _ direction: MoveCommandDirection,
        rooms: [AgentRoom],
        selectedRoom: AgentRoom
    ) {
        guard let currentIndex = rooms.firstIndex(where: { $0.id == selectedRoom.id }) else { return }
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(rooms.startIndex, currentIndex - 1)
        case .down:
            nextIndex = min(rooms.index(before: rooms.endIndex), currentIndex + 1)
        default:
            return
        }
        selectedRoomID = rooms[nextIndex].id
    }

    private func transcriptPane(room: AgentRoom, authority: AgentRoomsWorkspaceAuthority) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    transcriptHeading(room, authority: authority)

                    ForEach(room.transcript.messages) { message in
                        messageView(message)
                    }

                    if let link = room.transcript.link {
                        projectLinkChip(link)
                    }

                    if let receipt = room.transcript.receipt {
                        receiptRow(receipt)
                    }

                    if let artifact = room.transcript.futureArtifact {
                        futureArtifactPlaceholder(artifact)
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .focusable()
            .focused($focusedRegion, equals: .transcript)
            .accessibilityLabel("\(authorityPresentation(for: authority).transcriptAccessibility) for \(room.title)")

            disabledComposer
        }
    }

    private func transcriptHeading(_ room: AgentRoom, authority: AgentRoomsWorkspaceAuthority) -> some View {
        let presentation = authorityPresentation(for: authority)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(room.title)
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.primary)
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(CiderColors.secondary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text("\(room.transcript.runtimeLabel) runtime · \(presentation.transcript)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(room.transcript.runtimeLabel) runtime, \(presentation.transcriptAccessibility)")
        }
    }

    private var authorityPresentation: AuthorityPresentation {
        authorityPresentation(for: state.authority)
    }

    private func authorityPresentation(for authority: AgentRoomsWorkspaceAuthority) -> AuthorityPresentation {
        switch authority {
        case .canonicalIncomplete:
            AuthorityPresentation(
                badge: "Read-only · Canonical incomplete",
                badgeAccessibility: "Read-only, incomplete canonical data",
                subtitle: "A secondary, incomplete view of durable agent threads.",
                transcript: "Read-only transcript",
                transcriptAccessibility: "read-only incomplete canonical transcript",
                emptyTitle: "No canonical rooms available yet",
                emptyDetail: "Existing live legacy chats remain in the Hermes panel."
            )
        case .legacyAuthoritativePreview:
            AuthorityPresentation(
                badge: "Read-only · Legacy authoritative",
                badgeAccessibility: "Read-only, legacy authoritative, noncanonical preview",
                subtitle: "Noncanonical preview of current legacy conversation history",
                transcript: "Legacy-authoritative preview · Not imported",
                transcriptAccessibility: "legacy-authoritative noncanonical preview, not imported",
                emptyTitle: "No legacy conversations available",
                emptyDetail: "No supported legacy conversation history was found for this read-only preview."
            )
        }
    }

    private struct AuthorityPresentation {
        let badge: String
        let badgeAccessibility: String
        let subtitle: String
        let transcript: String
        let transcriptAccessibility: String
        let emptyTitle: String
        let emptyDetail: String
    }

    private func messageView(_ message: AgentRoomMessage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(message.author)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(message.body)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(message.role == .human ? Spacing.md : 0)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(message.role == .human ? CiderColors.surfaceInput : Color.clear)
        )
        .frame(maxWidth: message.role == .human ? 520 : .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func projectLinkChip(_ link: AgentRoomLink) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(link.title).font(CiderFont.bodySemibold)
                Text(link.subtitle).font(CiderFont.microMedium)
            }
        } icon: {
            Image(systemName: "square.split.2x1")
                .foregroundColor(CiderColors.controlAccent)
        }
        .foregroundColor(CiderColors.secondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cider project link, \(link.title)")
    }

    private func receiptRow(_ receipt: AgentRoomReceipt) -> some View {
        let presentation = receiptPresentation(for: receipt.status)
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: presentation.symbol)
                .foregroundColor(presentation.color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(receipt.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text(receipt.detail)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.voiceOverWording), \(receipt.title), \(receipt.detail)")
    }

    private func receiptPresentation(
        for status: AgentRoomReceiptStatus
    ) -> (symbol: String, color: Color, voiceOverWording: String) {
        switch status {
        case .completed:
            ("checkmark.circle.fill", CiderColors.success, "Completed canonical turn receipt")
        case .failed:
            ("xmark.octagon.fill", CiderColors.destructive, "Failed canonical turn receipt")
        case .cancelled:
            ("slash.circle.fill", CiderColors.warning, "Cancelled canonical turn receipt")
        }
    }

    private func futureArtifactPlaceholder(_ artifact: AgentRoomFutureArtifact) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "doc.badge.ellipsis")
                .foregroundColor(CiderColors.tertiary)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(artifact.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.secondary)
                Text(artifact.detail)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(CiderColors.surfaceSubtle))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(CiderColors.borderSubtle, style: StrokeStyle(lineWidth: Spacing.hairline, dash: [4, 4]))
        )
        .accessibilityElement(children: .combine)
    }

    private var disabledComposer: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock")
                .foregroundColor(CiderColors.tertiary)
            Text("Live messaging remains in the Hermes panel.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 40)
        .background(CiderColors.surfaceSubtle)
        .overlay(alignment: .top) { Divider().overlay(CiderColors.borderSubtle) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Messaging disabled. Live messaging remains in the Hermes panel.")
    }

    @MainActor
    private func reload() async {
        state = .loading(authority: state.authority)
        state = await loadWorkspace()
    }
}
