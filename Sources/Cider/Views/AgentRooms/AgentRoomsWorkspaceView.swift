import SwiftUI

struct AgentRoomsWorkspaceView: View {
    let loadWorkspace: @MainActor () async -> AgentRoomsWorkspaceState
    let onOpenLiveChat: () -> Void

    @StateObject private var liveChat: AgentRoomsLiveChatModel
    @State private var state: AgentRoomsWorkspaceState
    @State private var selectedRoomID: String?
    @State private var composerText = ""
    @State private var transcriptFollowPolicy = AgentRoomsTranscriptFollowPolicy()
    @State private var transcriptViewportHeight: CGFloat = 0
    @FocusState private var focusedRegion: FocusRegion?

    private enum FocusRegion: Hashable {
        case roomList
        case composer
    }

    init(
        loadWorkspace: @escaping @MainActor () async -> AgentRoomsWorkspaceState,
        liveChat: AgentRoomsLiveChatModel,
        onOpenLiveChat: @escaping () -> Void
    ) {
        self.loadWorkspace = loadWorkspace
        self.onOpenLiveChat = onOpenLiveChat
        _liveChat = StateObject(wrappedValue: liveChat)
        _state = State(initialValue: .loading(authority: .canonicalIncomplete))
        _selectedRoomID = State(initialValue: nil)
    }

    /// Explicit state injection is reserved for previews and focused view tests.
    init(
        state: AgentRoomsWorkspaceState,
        liveChat: AgentRoomsLiveChatModel = AgentRoomsLiveChatModel(transport: HermesRunTransport()),
        onOpenLiveChat: @escaping () -> Void
    ) {
        self.loadWorkspace = { state }
        self.onOpenLiveChat = onOpenLiveChat
        _liveChat = StateObject(wrappedValue: liveChat)
        _state = State(initialValue: state)
        if case .loaded(_, _, let selectedRoomID) = state {
            _selectedRoomID = State(initialValue: selectedRoomID)
        } else if case .eligibleLoaded(_, _, let selectedRoomID, _) = state {
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
            if let testRoomID = liveChat.testRoom?.id, selectedRoomID == testRoomID {
                return
            }
            if case .loaded(_, let rooms, let storedSelection) = newState {
                selectedRoomID = rooms.contains(where: { $0.id == storedSelection })
                    ? storedSelection
                    : rooms.first?.id
            } else if case .eligibleLoaded(_, let rooms, let storedSelection, _) = newState {
                selectedRoomID = rooms.contains(where: { $0.id == storedSelection })
                    ? storedSelection
                    : rooms.first?.id
            } else {
                selectedRoomID = nil
            }
        }
        .onChange(of: liveChat.turnState) { _, turnState in
            guard turnState == .failed, composerText.isEmpty,
                  let recovered = liveChat.takeRecoveredDraft() else { return }
            composerText = recovered
            focusedRegion = .composer
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                headerTitle
                Spacer(minLength: Spacing.md)
                newTestChatButton
                openLiveChatButton
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerTitle
                HStack(spacing: Spacing.sm) {
                    newTestChatButton
                    openLiveChatButton
                }
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

    private var newTestChatButton: some View {
        Button {
            liveChat.createTestChat()
            selectedRoomID = liveChat.testRoom?.id
            Task {
                await liveChat.refreshTransportReadiness()
            }
        } label: {
            Label(
                liveChat.testRoom == nil ? "Start Cider Test Chat" : "Open Cider Test Chat",
                systemImage: "plus.bubble"
            )
            .font(CiderFont.labelMedium)
        }
        .buttonStyle(.borderedProminent)
        .disabled(liveChat.transportState == .checking)
        .accessibilityLabel(liveChat.testRoom == nil ? "Start Cider Test Chat" : "Open Cider Test Chat")
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if let testRoom = liveChat.testRoom {
            let legacy = legacyRoomsAndNotice
            let rooms = [testRoom] + legacy.rooms.filter { $0.id != testRoom.id }
            let selected = rooms.first(where: { $0.id == selectedRoomID }) ?? testRoom
            VStack(spacing: 0) {
                if let blocked = legacyBlockedSummary {
                    legacyBlockedBanner(title: blocked.title, detail: blocked.detail)
                }
                loadedWorkspace(
                    authority: state.authority,
                    rooms: rooms,
                    selectedRoom: selected,
                    notice: legacy.notice
                )
            }
        } else {
            workspaceBodyWithoutTestRoom
        }
    }

    @ViewBuilder
    private var workspaceBodyWithoutTestRoom: some View {
        switch state.projection(selectedRoomID: selectedRoomID) {
        case .loading:
            loadingState
        case .empty(let authority):
            emptyState(authority: authority)
        case .eligibleEmpty(_, let notice):
            eligibleEmptyState(notice: notice)
        case .blocked(let authority, let message):
            genericBlockedState(authority: authority, title: "Legacy preview blocked", message: message)
        case .eligiblePreviewBlocked(let authority):
            genericBlockedState(
                authority: authority,
                title: "Eligible legacy preview unavailable",
                message: EligibleLegacyAgentRoomsPreviewService.blockedMessage
            )
        case .legacyIdentityConflict(let authority, let notice):
            identityConflictState(authority: authority, notice: notice)
        case .legacyRegistryMappingConflict(let authority, let notice):
            registryMappingConflictState(authority: authority, notice: notice)
        case .failed(let authority, let message):
            failedState(authority: authority, message: message)
        case .loaded(let authority, let rooms, let selectedRoom):
            loadedWorkspace(authority: authority, rooms: rooms, selectedRoom: selectedRoom, notice: nil)
        case .eligibleLoaded(let authority, let rooms, let selectedRoom, let notice):
            loadedWorkspace(authority: authority, rooms: rooms, selectedRoom: selectedRoom, notice: notice)
        }
    }

    private var legacyRoomsAndNotice: (rooms: [AgentRoom], notice: AgentRoomsEligibleNotice?) {
        switch state.projection(selectedRoomID: selectedRoomID) {
        case .loaded(_, let rooms, _):
            return (rooms, nil)
        case .eligibleLoaded(_, let rooms, _, let notice):
            return (rooms, notice)
        default:
            return ([], nil)
        }
    }

    private var legacyBlockedSummary: (title: String, detail: String)? {
        switch state.projection(selectedRoomID: selectedRoomID) {
        case .blocked(_, let message):
            return ("Legacy preview remains blocked", message)
        case .eligiblePreviewBlocked:
            return ("Eligible legacy preview remains blocked", EligibleLegacyAgentRoomsPreviewService.blockedMessage)
        case .legacyIdentityConflict(_, let notice):
            return (notice.title, notice.detail)
        case .legacyRegistryMappingConflict(_, let notice):
            return (notice.title, notice.detail)
        default:
            return nil
        }
    }

    private func legacyBlockedBanner(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
            Text("\(detail) Legacy messaging stays disabled; Cider Test Chat remains separate.")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiderColors.surfaceSubtle)
        .accessibilityElement(children: .combine)
    }

    private func loadedWorkspace(
        authority: AgentRoomsWorkspaceAuthority,
        rooms: [AgentRoom],
        selectedRoom: AgentRoom,
        notice: AgentRoomsEligibleNotice?
    ) -> some View {
        VStack(spacing: 0) {
            if let notice { eligibleNotice(notice) }
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

    private func eligibleNotice(_ notice: AgentRoomsEligibleNotice) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(notice.title).font(CiderFont.bodySemibold).foregroundColor(CiderColors.primary)
            Text(notice.detail).font(CiderFont.caption).foregroundColor(CiderColors.secondary)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiderColors.surfaceSubtle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityLabel)
    }

    private func eligibleEmptyState(notice: AgentRoomsEligibleNotice) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)
            Text(notice.title).font(CiderFont.subheadingMedium).foregroundColor(CiderColors.primary)
            Text(notice.detail).font(CiderFont.body).foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
            openLiveChatButton
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityLabel)
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

    private func genericBlockedState(
        authority: AgentRoomsWorkspaceAuthority,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.secondary)
            Text(title)
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
        .accessibilityLabel("\(authorityPresentation(for: authority).badgeAccessibility). \(title). \(message) Read-only, legacy authoritative, noncanonical preview, not imported. Messaging disabled.")
    }

    private func identityConflictState(
        authority: AgentRoomsWorkspaceAuthority,
        notice: AgentRoomsIdentityConflictNotice
    ) -> some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(CiderFont.emptyStateIcon)
                    .foregroundColor(CiderColors.secondary)
                Text(notice.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                Text(notice.detail)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(notice.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Spacing.lg) {
                            Text(row.label)
                            Spacer(minLength: Spacing.lg)
                            Text(row.count)
                        }
                    }
                    HStack(spacing: Spacing.lg) {
                        Text("Affected registered rooms")
                        Spacer(minLength: Spacing.lg)
                        Text(notice.affectedCandidateCount)
                    }
                }
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: 440)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(authorityPresentation(for: authority).badgeAccessibility). \(notice.accessibilityLabel)")

            Button("Retry") {
                Task { await reload() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Retry read-only legacy Rooms diagnosis")
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func registryMappingConflictState(
        authority: AgentRoomsWorkspaceAuthority,
        notice: AgentRoomsRegistryMappingNotice
    ) -> some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(CiderFont.emptyStateIcon)
                    .foregroundColor(CiderColors.secondary)
                Text(notice.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                Text(notice.detail)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(notice.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Spacing.lg) {
                            Text(row.label)
                            Spacer(minLength: Spacing.lg)
                            Text(row.count)
                        }
                    }
                    HStack(spacing: Spacing.lg) {
                        Text("Affected registered rooms")
                        Spacer(minLength: Spacing.lg)
                        Text(notice.affectedRegistryRecordCount)
                    }
                }
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: 440)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(authorityPresentation(for: authority).badgeAccessibility). \(notice.accessibilityLabel)")

            Button("Retry") {
                Task { await reload() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Retry read-only legacy Rooms diagnosis")
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedState(authority: AgentRoomsWorkspaceAuthority, message: String) -> some View {
        let title = authority == .legacyAuthoritativePreview
            ? "Legacy Rooms preview is temporarily unavailable"
            : "Rooms unavailable"
        return VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.secondary)
            Text(title)
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
        .accessibilityLabel("\(title). \(message) Read-only, legacy authoritative, noncanonical preview, not imported. Messaging disabled.")
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
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    transcriptHeading(room, authority: authority)

                    if let notice = room.messageLimitNotice {
                        Text(notice)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.secondary)
                            .accessibilityLabel(notice)
                    }

                    ForEach(room.transcript.messages) { message in
                        messageView(message, showsDelivery: room.continuity == .liveContinuation)
                    }

                    if room.continuity == .liveContinuation,
                       room.transcript.receipt == nil,
                       !liveChat.liveActivity.isEmpty {
                        liveActivityView
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

                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: AgentRoomsTranscriptBottomPreferenceKey.self,
                            value: geometry.frame(in: .named("agent-rooms-transcript")).maxY
                        )
                    }
                    .frame(height: 1)
                    .id("agent-rooms-transcript-bottom")
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.xl)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "agent-rooms-transcript")
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { transcriptViewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in transcriptViewportHeight = height }
                })
                .scrollIndicators(.hidden)
                .onPreferenceChange(AgentRoomsTranscriptBottomPreferenceKey.self) { bottom in
                    _ = transcriptFollowPolicy.shouldFollow(
                        distanceFromBottom: max(0, bottom - transcriptViewportHeight)
                    )
                }
                .onChange(of: room.transcript.messages.last?.body) { _, _ in
                    guard transcriptFollowPolicy.shouldAutoScrollForNewContent else { return }
                    proxy.scrollTo("agent-rooms-transcript-bottom", anchor: .bottom)
                }
                .accessibilityLabel(room.continuity == .liveContinuation
                    ? "Live continuation transcript for \(room.title)"
                    : "\(authorityPresentation(for: authority).transcriptAccessibility) for \(room.title)")
            }

            if room.continuity == .liveContinuation {
                liveComposer(roomID: room.id)
            } else {
                disabledComposer
            }
        }
    }

    private var liveActivityView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(liveChat.liveActivity) { activity in
                Text(activity.detail)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes live activity")
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
                Text(room.continuity == .liveContinuation
                     ? "\(room.transcript.runtimeLabel) runtime · Live continuation"
                     : "\(room.transcript.runtimeLabel) runtime · \(presentation.transcript)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(room.continuity == .liveContinuation
                ? "\(room.transcript.runtimeLabel) runtime, live continuation"
                : "\(room.transcript.runtimeLabel) runtime, \(presentation.transcriptAccessibility)")
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

    private func messageView(_ message: AgentRoomMessage, showsDelivery: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message.author)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Text(message.body)
                    .font(CiderFont.label)
                    .foregroundColor(CiderColors.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if showsDelivery, message.role == .human {
                HStack(spacing: Spacing.sm) {
                    Text(deliveryLabel(message.deliveryState))
                        .font(CiderFont.microMedium)
                        .foregroundColor(message.deliveryState == .failed ? CiderColors.destructive : CiderColors.tertiary)
                    if message.deliveryState == .failed, message.canRetry {
                        Button("Retry") {
                            if composerText == message.body { composerText = "" }
                            Task {
                                await liveChat.retry(clientMessageID: message.id, selectedRoomID: selectedRoomID)
                            }
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("Retry failed message")
                    }
                }
            }
        }
        .padding(message.role == .human ? Spacing.md : 0)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(message.role == .human ? CiderColors.surfaceInput : Color.clear)
        )
        .frame(maxWidth: message.role == .human ? 520 : .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func deliveryLabel(_ state: AgentRoomMessageDeliveryState) -> String {
        switch state {
        case .pending: "Sending…"
        case .sent: "Sent"
        case .failed: "Failed"
        }
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
        let voiceOverWording = receipt.continuity == .liveContinuation
            ? presentation.voiceOverWording.replacingOccurrences(
                of: "canonical",
                with: receipt.sourceBackedTransport ? "source-backed live continuation" : "live continuation"
            )
            : presentation.voiceOverWording
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let sourceIdentity = receipt.sourceIdentity {
                    receiptIdentityRow(label: "Source", value: sourceIdentity)
                    receiptIdentityRow(label: "Run", value: receipt.runIdentity ?? "Not accepted")
                    Text(receipt.runIdentity == nil
                         ? "Session-only activity observed during this attempt."
                         : "Session-only activity reported by this run.")
                        .font(CiderFont.microMedium)
                        .foregroundColor(CiderColors.tertiary)
                }

                if receipt.activity.isEmpty {
                    Text("No bounded tool or reasoning activity reported.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(receipt.activity) { activity in
                            receiptActivityRow(activity)
                        }
                    }
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: presentation.symbol)
                    .foregroundColor(presentation.color)
                    .accessibilityHidden(true)
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
            .accessibilityLabel("Turn activity receipt, \(voiceOverWording), \(receipt.title), \(receipt.detail)")
        }
        .tint(CiderColors.secondary)
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
    }

    private func receiptIdentityRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func receiptActivityRow(_ activity: AgentRoomsLiveActivity) -> some View {
        let presentation: (label: String, symbol: String) = switch activity.kind {
        case .reasoning: ("Reasoning", "brain.head.profile")
        case .toolStarted: ("Tool started", "wrench.and.screwdriver")
        case .toolCompleted: ("Tool completed", "checkmark.circle")
        }
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: presentation.symbol)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(presentation.label)
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                Text(activity.detail)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.label), \(activity.detail)")
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

    private func liveComposer(roomID: String) -> some View {
        let enabled = liveChat.isComposerEnabled(selectedRoomID: selectedRoomID)
        let validDraft = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && composerText.count <= AgentRoomsLiveChatModel.maximumMessageLength
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if let message = liveChat.composerMessage {
                Text(message)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .accessibilityLabel(message)
            }
            Text(liveTurnStatusLabel)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
                .accessibilityLabel("Hermes turn \(liveTurnStatusLabel)")
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("Message Hermes in Cider Test Chat", text: $composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($focusedRegion, equals: .composer)
                    .disabled(!enabled)
                    .onSubmit { submitComposer(roomID: roomID) }
                    .accessibilityLabel("Message Hermes in Cider Test Chat")

                if liveChat.activeRunCanBeCancelled {
                    Button("Cancel") {
                        Task { await liveChat.cancelActiveSend() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Cancel Hermes response")
                }

                Button("Send") { submitComposer(roomID: roomID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!enabled || !validDraft)
                    .accessibilityLabel("Send message to Hermes")
            }
            Text("Return sends · Shift-Return adds a line · \(composerText.count)/\(AgentRoomsLiveChatModel.maximumMessageLength)")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(CiderColors.surfaceSubtle)
        .background(CiderWindowDragExclusionReporter(id: "agent-rooms-live-composer"))
        .overlay(alignment: .top) { Divider().overlay(CiderColors.borderSubtle) }
    }

    private var liveTurnStatusLabel: String {
        switch liveChat.turnState {
        case .idle: "Ready"
        case .sending: "Sending…"
        case .streaming: "Streaming…"
        case .cancelling: "Cancelling…"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }

    private func submitComposer(roomID: String) {
        let text = composerText
        guard liveChat.isComposerEnabled(selectedRoomID: selectedRoomID) else { return }
        composerText = ""
        Task { await liveChat.send(text, selectedRoomID: roomID) }
    }

    @MainActor
    private func reload() async {
        state = .loading(authority: state.authority)
        state = await loadWorkspace()
    }
}

private struct AgentRoomsTranscriptBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
