import AppKit
import SwiftUI

struct AgentRoomsWorkspaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let loadWorkspace: @MainActor (AgentRoomsWorkspaceRequest) async -> AgentRoomsWorkspaceState
    let roomActions: (any AgentRoomsActionServicing)?
    let onOpenLiveChat: () -> Void
    let onOpenCiderReference: (AgentRoomsCiderOpenRoute) -> Void
    let onExportRoom: ((UUID, String) -> Void)?

    @ObservedObject private var session: AgentRoomsSessionModel
    @ObservedObject private var liveChat: AgentRoomsLiveChatModel
    @State private var state: AgentRoomsWorkspaceState
    @State private var transcriptFollowPolicy = AgentRoomsTranscriptFollowPolicy()
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var request = AgentRoomsWorkspaceRequest()
    @State private var searchText = ""
    @State private var renameRoom: AgentRoom?
    @State private var renameText = ""
    @State private var actionError: String?
    @FocusState private var focusedRegion: FocusRegion?

    private enum FocusRegion: Hashable {
        case roomList
        case composer
        case search
    }

    init(
        loadWorkspace: @escaping @MainActor (AgentRoomsWorkspaceRequest) async -> AgentRoomsWorkspaceState,
        roomActions: any AgentRoomsActionServicing,
        session: AgentRoomsSessionModel,
        onOpenLiveChat: @escaping () -> Void,
        onOpenCiderReference: @escaping (AgentRoomsCiderOpenRoute) -> Void = { _ in },
        onExportRoom: ((UUID, String) -> Void)? = nil
    ) {
        self.loadWorkspace = loadWorkspace
        self.roomActions = roomActions
        self.onOpenLiveChat = onOpenLiveChat
        self.onOpenCiderReference = onOpenCiderReference
        self.onExportRoom = onExportRoom
        _session = ObservedObject(wrappedValue: session)
        _liveChat = ObservedObject(wrappedValue: session.liveChat)
        _state = State(initialValue: .loading(authority: .canonicalIncomplete))
    }

    /// Explicit state injection is reserved for previews and focused view tests.
    init(
        state: AgentRoomsWorkspaceState,
        session: AgentRoomsSessionModel,
        onOpenLiveChat: @escaping () -> Void,
        onOpenCiderReference: @escaping (AgentRoomsCiderOpenRoute) -> Void = { _ in },
        onExportRoom: ((UUID, String) -> Void)? = nil
    ) {
        self.loadWorkspace = { _ in state }
        self.roomActions = nil
        self.onOpenLiveChat = onOpenLiveChat
        self.onOpenCiderReference = onOpenCiderReference
        self.onExportRoom = onExportRoom
        _session = ObservedObject(wrappedValue: session)
        _liveChat = ObservedObject(wrappedValue: session.liveChat)
        _state = State(initialValue: state)
    }

    /// Explicit live-model injection is reserved for previews and focused view tests.
    init(
        state: AgentRoomsWorkspaceState,
        liveChat: AgentRoomsLiveChatModel = AgentRoomsLiveChatModel(transport: HermesRunTransport()),
        onOpenLiveChat: @escaping () -> Void,
        onOpenCiderReference: @escaping (AgentRoomsCiderOpenRoute) -> Void = { _ in },
        onExportRoom: ((UUID, String) -> Void)? = nil
    ) {
        let session = AgentRoomsSessionModel(liveChat: liveChat)
        if case .loaded(_, _, let selectedRoomID) = state {
            session.selectRoom(id: selectedRoomID, persistIfCanonical: false)
        } else if case .eligibleLoaded(_, _, let selectedRoomID, _) = state {
            session.selectRoom(id: selectedRoomID, persistIfCanonical: false)
        }
        self.init(
            state: state,
            session: session,
            onOpenLiveChat: onOpenLiveChat,
            onOpenCiderReference: onOpenCiderReference,
            onExportRoom: onExportRoom
        )
    }

    private var selectedRoomID: String? {
        session.selectedRoomID
    }

    private var composerText: String {
        get { session.composerText }
        nonmutating set { session.composerText = newValue }
    }

    private var composerTextBinding: Binding<String> {
        Binding(get: { session.composerText }, set: { session.composerText = $0 })
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
            if session.selectedRoomID == liveChat.activeRoom?.id {
                await liveChat.refreshTransportReadiness()
            }
            if session.restoreRecoveredDraftIfNeeded() {
                focusedRegion = .composer
            }
        }
        .onChange(of: state) { _, newState in
            if case .loading = newState { return }
            if let testRoomID = visibleLiveRoom?.id,
               liveChat.testRoom?.id == testRoomID,
               selectedRoomID == testRoomID {
                return
            }
            if case .loaded(_, let rooms, let storedSelection) = newState {
                let preferred = request.scope == .active ? session.preferredCanonicalRoomID : nil
                let resolvedSelection = rooms.first(where: { $0.id == selectedRoomID })?.id
                    ?? rooms.first(where: { $0.id == preferred })?.id
                    ?? rooms.first(where: { $0.id == storedSelection })?.id
                    ?? rooms.first?.id
                session.selectRoom(
                    id: resolvedSelection,
                    persistIfCanonical: request.scope == .active
                        && request.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            } else if case .eligibleLoaded(_, let rooms, let storedSelection, _) = newState {
                session.selectRoom(
                    id: rooms.first(where: { $0.id == selectedRoomID })?.id
                        ?? rooms.first(where: { $0.id == storedSelection })?.id
                        ?? rooms.first?.id,
                    persistIfCanonical: false
                )
            } else {
                session.selectRoom(id: nil, persistIfCanonical: false)
            }
        }
        .onChange(of: liveChat.turnState) { previousState, turnState in
            if turnState == .failed,
               session.restoreRecoveredDraftIfNeeded() { focusedRegion = .composer }
            let wasInFlight = previousState == .sending
                || previousState == .streaming
                || previousState == .cancelling
            if wasInFlight && (turnState == .completed || turnState == .failed) {
                Task { await reload() }
            }
        }
        .onChange(of: session.selectedRoomID) { _, selected in
            guard selected == liveChat.activeRoom?.id else { return }
            Task { await liveChat.refreshTransportReadiness() }
        }
        .onChange(of: liveChat.activeRoom?.id) { _, activeRoomID in
            guard activeRoomID == session.selectedRoomID else { return }
            Task { await liveChat.refreshTransportReadiness() }
        }
        .alert("Rename Conversation", isPresented: Binding(
            get: { renameRoom != nil },
            set: { if !$0 { renameRoom = nil } }
        )) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) { renameRoom = nil }
            Button("Rename") { renameSelectedConversation() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Choose a calm, searchable name. The Cider room identity and history will not change.")
        }
        .alert("Room action unavailable", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Try again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    headerTitle
                    Spacer(minLength: Spacing.md)
                    newConversationButton
                    newTestChatButton
                    openLiveChatButton
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    headerTitle
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.sm) {
                            newConversationButton
                            newTestChatButton
                            openLiveChatButton
                        }
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            newConversationButton
                            newTestChatButton
                            openLiveChatButton
                        }
                    }
                }
            }
            roomNavigationControls
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roomNavigationControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                conversationSearchField
                conversationScopePicker.frame(width: 250)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                conversationSearchField
                conversationScopePicker
            }
        }
    }

    private var conversationSearchField: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Search conversations", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedRegion, equals: .search)
                .onSubmit { applySearch() }
                .accessibilityLabel("Search conversations")
            Button {
                focusedRegion = .search
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Focus conversation search")
            .help("Search conversations (Command-F)")
        }
    }

    private var conversationScopePicker: some View {
        Picker("Conversation collection", selection: $request.scope) {
            Text("Active conversations").tag(AgentRoomsListScope.active)
            Text("Archived conversations").tag(AgentRoomsListScope.archived)
        }
        .pickerStyle(.segmented)
        .onChange(of: request.scope) { _, _ in
            Task { await reload() }
        }
        .accessibilityLabel("Show active or archived conversations")
    }

    private var newConversationButton: some View {
        Button {
            createConversation()
        } label: {
            Label("New Conversation", systemImage: "square.and.pencil")
                .font(CiderFont.labelMedium)
        }
        .buttonStyle(.borderedProminent)
        .disabled(roomActions == nil)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("New Conversation")
        .help("Create a durable Cider conversation")
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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
            request = .init(scope: .active)
            searchText = ""
            session.createTestChat()
            Task {
                await liveChat.refreshTransportReadiness()
                await Task.yield()
                focusedRegion = .composer
            }
        } label: {
            Label(
                liveChat.testRoom == nil ? "Start Cider Test Chat" : "Open Cider Test Chat",
                systemImage: "plus.bubble"
            )
            .font(CiderFont.labelMedium)
        }
        .buttonStyle(.bordered)
        .disabled(liveChat.transportState == .checking)
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .accessibilityLabel(liveChat.testRoom == nil ? "Start Cider Test Chat" : "Open Cider Test Chat")
        .help("Start or open Cider Test Chat (Command-Shift-N)")
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if let liveRoom = visibleLiveRoom {
            let legacy = legacyRoomsAndNotice
            let rooms = [liveRoom] + legacy.rooms.filter { $0.id != liveRoom.id }
            let selected = rooms.first(where: { $0.id == selectedRoomID }) ?? liveRoom
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

    private var visibleLiveRoom: AgentRoom? {
        guard request.scope == .active, let room = liveChat.activeRoom else { return nil }
        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return room }
        let matchesTitle = room.title.localizedCaseInsensitiveContains(query)
        let matchesTranscript = room.transcript.messages.contains {
            $0.body.localizedCaseInsensitiveContains(query)
        }
        return matchesTitle || matchesTranscript ? room : nil
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
                if AgentRoomsWorkspaceLayoutPolicy.mode(
                    width: proxy.size.width,
                    usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
                ) == .sideBySide {
                    HStack(spacing: 0) {
                        roomRail(rooms: rooms, selectedRoom: selectedRoom)
                            .frame(width: 252)
                        Divider().overlay(CiderColors.borderSubtle)
                        transcriptPane(room: selectedRoom, authority: authority)
                    }
                } else {
                    VStack(spacing: 0) {
                        roomRail(rooms: rooms, selectedRoom: selectedRoom)
                            .frame(minHeight: 112, maxHeight: 216)
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
        let isArchivedCanonicalCollection = authority == .canonicalIncomplete
            && request.scope == .archived
        let emptyTitle = isArchivedCanonicalCollection
            ? "No archived conversations"
            : presentation.emptyTitle
        let emptyDetail = isArchivedCanonicalCollection
            ? "Conversations you archive will appear here and can be restored."
            : presentation.emptyDetail
        return VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)
            Text(emptyTitle)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)
            Text(emptyDetail)
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
            session.selectRoom(
                id: room.id,
                persistIfCanonical: state.authority == .canonicalIncomplete
                    && room.lifecycleState == .active
            )
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
        .contextMenu {
            roomManagementMenu(room)
        }
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
        let room = rooms[nextIndex]
        session.selectRoom(
            id: room.id,
            persistIfCanonical: state.authority == .canonicalIncomplete
                && room.lifecycleState == .active
        )
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
                        if !receipt.objectReceipts.isEmpty {
                            ciderSourcesDisclosure(receipt.objectReceipts)
                        }
                        if let checkpoint = receipt.contextCheckpoint {
                            contextCheckpointDisclosure(checkpoint)
                        }
                        if let checkpoint = receipt.approvalCheckpoint {
                            approvalCheckpointDisclosure(checkpoint)
                        }
                        if let attachments = receipt.attachments {
                            assetDisclosure(attachments, kind: .attachment)
                        }
                        if let artifacts = receipt.generatedArtifacts {
                            assetDisclosure(artifacts, kind: .generatedArtifact)
                        }
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
                    var transaction = Transaction()
                    transaction.disablesAnimations = AgentRoomsTranscriptMotionPolicy.disablesScrollAnimations(
                        reduceMotion: reduceMotion
                    )
                    withTransaction(transaction) {
                        proxy.scrollTo("agent-rooms-transcript-bottom", anchor: .bottom)
                    }
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(liveChat.liveActivity) { activity in
                    receiptActivityRow(activity)
                }
            }
            .padding(.top, Spacing.xs)
        } label: {
            Label(
                "Hermes is working · \(liveChat.liveActivity.count) update\(liveChat.liveActivity.count == 1 ? "" : "s")",
                systemImage: "sparkles"
            )
            .font(CiderFont.captionMedium)
            .foregroundColor(CiderColors.secondary)
        }
        .tint(CiderColors.secondary)
        .accessibilityLabel("Hermes live activity, \(liveChat.liveActivity.count) updates, collapsed by default")
    }

    private func transcriptHeading(_ room: AgentRoom, authority: AgentRoomsWorkspaceAuthority) -> some View {
        let presentation = authorityPresentation(for: authority)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(room.title)
                    .font(CiderFont.titleMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                if let roomID = exportableRoomID(room) {
                    Button("Export") {
                        onExportRoom?(roomID, room.title)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .accessibilityLabel("Export Conversation \(room.title)")
                    .help("Export a local open-data copy of this conversation")
                }
                if canManage(room) {
                    Menu {
                        roomManagementMenu(room)
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("Manage \(room.title)")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Export or manage this conversation")
                }
            }
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
                badge: "Cider-owned",
                badgeAccessibility: "Cider-owned canonical conversations",
                subtitle: "Durable local conversations with calm room controls.",
                transcript: "Read-only transcript",
                transcriptAccessibility: "Cider-owned canonical transcript",
                emptyTitle: "No active conversations",
                emptyDetail: "Create a durable conversation or open Cider Test Chat."
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
                AgentRoomsMarkdownMessageView(
                    document: session.messagePresentationStore.document(for: message)
                )
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

    private func ciderObjectReceiptRow(_ receipt: AgentRoomsCiderObjectReceipt) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                ciderObjectReceiptThumbnail(receipt)
                ciderObjectReceiptIdentity(receipt)
                Spacer(minLength: Spacing.sm)
                ciderObjectOpenButton(receipt)
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                ciderObjectReceiptThumbnail(receipt)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ciderObjectReceiptIdentity(receipt)
                    ciderObjectOpenButton(receipt)
                }
            }
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceSubtle))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline))
        .accessibilityElement(children: .contain)
    }

    private func ciderSourcesDisclosure(_ receipts: [AgentRoomsCiderObjectReceipt]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(receipts) { receipt in
                    ciderObjectReceiptRow(receipt)
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "books.vertical")
                    .foregroundColor(CiderColors.controlAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(receipts.count == 1 ? "1 Cider source" : "\(receipts.count) Cider sources")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    Text("Validated objects · Expand for Open actions · Sources do not verify the assistant response")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                receipts.count == 1
                    ? "1 validated Cider source. Expand for Open actions. Sources do not verify the assistant response."
                    : "\(receipts.count) validated Cider sources. Expand for Open actions. Sources do not verify the assistant response."
            )
        }
        .tint(CiderColors.secondary)
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
    }

    private func contextCheckpointDisclosure(_ checkpoint: AgentRoomsContextCheckpoint) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if checkpoint.selectedContext.isEmpty {
                    Text(checkpoint.detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    contextReferenceGroup("Selected and sent", receipts: checkpoint.selectedContext)
                    if checkpoint.citations.isEmpty {
                        Text("No terminal citations were selected from this context.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    } else {
                        contextReferenceGroup("Citations", receipts: checkpoint.citations)
                    }
                }
                Text("\(checkpoint.provenance) · \(checkpoint.truthBoundary)")
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: checkpoint.state == .available ? "scope" : "eye.slash")
                    .foregroundColor(checkpoint.state == .rejected ? CiderColors.warning : CiderColors.controlAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(checkpoint.title)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(checkpoint.detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Context checkpoint. \(checkpoint.detail) \(checkpoint.truthBoundary).")
        }
        .tint(CiderColors.secondary)
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
    }

    private func contextReferenceGroup(
        _ title: String,
        receipts: [AgentRoomsCiderObjectReceipt]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)
            ForEach(receipts) { receipt in
                ciderObjectReceiptRow(receipt)
            }
        }
    }

    private func approvalCheckpointDisclosure(_ checkpoint: AgentRoomsApprovalCheckpoint) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if checkpoint.requests.isEmpty {
                    Text(checkpoint.detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    ForEach(checkpoint.requests) { request in
                        approvalRequestRow(request)
                    }
                }
                Text("Read-only. Cider did not execute or decide this request here.")
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: checkpoint.state == .available ? "hand.raised" : "eye.slash")
                    .foregroundColor(checkpoint.state == .available ? CiderColors.warning : CiderColors.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(checkpoint.requests.count == 1 ? "Approval request" : "Approval requests")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(checkpoint.detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Read-only approval presentation. \(checkpoint.detail). Nothing executed.")
        }
        .tint(CiderColors.secondary)
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
    }

    private func approvalRequestRow(_ request: AgentRoomsApprovalPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(request.action)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Spacer(minLength: Spacing.sm)
                Text(request.status.rawValue.capitalized)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(request.status == .requested ? CiderColors.warning : CiderColors.secondary)
            }
            approvalIdentityRow(label: "Target", value: request.target)
            approvalIdentityRow(label: "Scope", value: request.scope.rawValue.capitalized)
            approvalIdentityRow(label: "Risk", value: request.risk.rawValue.capitalized)
            Text(request.provenance)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceSubtle))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Approval request, \(request.action), target \(request.target), \(request.scope.rawValue) scope, \(request.risk.rawValue) risk, status \(request.status.rawValue), read-only, nothing executed."
        )
    }

    private func approvalIdentityRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(CiderFont.microMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(2)
        }
    }

    private func assetDisclosure(
        _ collection: AgentRoomsAssetCollection,
        kind: AgentRoomsAssetReceipt.Kind
    ) -> some View {
        let title: String = switch kind {
        case .attachment:
            collection.rows.count == 1 ? "Attachment" : "Attachments"
        case .generatedArtifact:
            collection.rows.count == 1 ? "Generated artifact" : "Generated artifacts"
        }
        let symbol = kind == .attachment ? "paperclip" : "doc.badge.gearshape"
        let disclosureDetail = AgentRoomsAssetDisclosurePresentation.detail(for: collection)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if collection.rows.isEmpty {
                    Text(collection.detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    ForEach(collection.rows) { row in
                        assetReceiptRow(row)
                    }
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: collection.state == .available ? symbol : "eye.slash")
                    .foregroundColor(collection.state == .available ? CiderColors.controlAccent : CiderColors.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(disclosureDetail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title). \(disclosureDetail). Cider-native open only when available.")
        }
        .tint(CiderColors.secondary)
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderDefault, lineWidth: Spacing.hairline))
    }

    private func assetReceiptRow(_ row: AgentRoomsAssetReceipt) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                assetReceiptIdentity(row)
                Spacer(minLength: Spacing.sm)
                assetOpenControl(row)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                assetReceiptIdentity(row)
                assetOpenControl(row)
            }
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceSubtle))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline))
        .accessibilityElement(children: .contain)
    }

    private func assetReceiptIdentity(_ row: AgentRoomsAssetReceipt) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: row.kind == .attachment ? "paperclip" : "doc.badge.gearshape")
                .foregroundColor(CiderColors.controlAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(row.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                Text("\(row.contentType) · \(row.sizeLabel)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                Text("\(row.provenance) · \(row.truthBoundary)")
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(row.contentType), \(row.sizeLabel), \(row.provenance), \(row.availability)")
    }

    @ViewBuilder
    private func assetOpenControl(_ row: AgentRoomsAssetReceipt) -> some View {
        if let route = row.openRoute {
            Button("Open") { onOpenCiderReference(route) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open \(row.title) in Cider")
                .help("Open this proven Cider-owned item")
        } else {
            Text("Unavailable")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .accessibilityLabel("Open unavailable for \(row.title)")
        }
    }

    @ViewBuilder
    private func ciderObjectReceiptThumbnail(_ receipt: AgentRoomsCiderObjectReceipt) -> some View {
        if case .bookmark(let bookmarkID) = receipt.openRoute,
           let reference = receipt.bookmarkThumbnail {
            AgentRoomsBookmarkReceiptThumbnailView(
                reference: reference,
                expectedBookmarkID: bookmarkID
            )
        }
    }

    private func ciderObjectReceiptIdentity(_ receipt: AgentRoomsCiderObjectReceipt) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: ciderObjectSymbol(receipt.kind))
                .foregroundColor(CiderColors.controlAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(receipt.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                Text(receipt.identifier)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                Text("\(receipt.provenance) · \(receipt.truthBoundary)")
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source-backed Cider \(ciderObjectKindLabel(receipt.kind)), \(receipt.title), \(receipt.identifier), \(receipt.truthBoundary)")
    }

    private func ciderObjectSymbol(_ kind: AgentRoomsCiderObjectReceipt.Kind) -> String {
        switch kind {
        case .bookmark: "bookmark"
        case .note: "note.text"
        case .task: "checklist"
        case .projectArtifact: "doc.text"
        }
    }

    private func ciderObjectKindLabel(_ kind: AgentRoomsCiderObjectReceipt.Kind) -> String {
        switch kind {
        case .bookmark: "saved bookmark"
        case .note: "note"
        case .task: "task"
        case .projectArtifact: "project artifact"
        }
    }

    private func ciderObjectOpenButton(_ receipt: AgentRoomsCiderObjectReceipt) -> some View {
        Button("Open") {
            onOpenCiderReference(receipt.openRoute)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Open \(receipt.title) in Cider")
        .help("Open this source-backed object in Cider")
    }

    private func receiptActivityRow(_ activity: AgentRoomsLiveActivity) -> some View {
        let calm = AgentRoomsActivityPresentation.project(activity)
        let symbol = switch activity.kind {
        case .reasoning: "brain.head.profile"
        case .toolStarted: "wrench.and.screwdriver"
        case .toolCompleted: "checkmark.circle"
        }
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(calm.label)
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                Text(calm.summary)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calm.accessibilityLabel)
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
        let status = liveChat.statusPresentation
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(status.title)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(status.state == .failed || status.state == .unavailable
                        ? CiderColors.destructive
                        : CiderColors.secondary)
                if status.allowsReconnect {
                    Button("Reconnect") {
                        Task { await liveChat.refreshTransportReadiness() }
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel("Reconnect to Hermes")
                }
            }
            if let detail = status.detail {
                Text(detail)
                    .font(CiderFont.microMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .accessibilityLabel(detail)
            }
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField(composerPlaceholder(roomID: roomID), text: composerTextBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($focusedRegion, equals: .composer)
                    .disabled(!enabled)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                editor.insertNewlineIgnoringFieldEditor(nil)
                            } else {
                                composerText += "\n"
                            }
                            return .handled
                        }
                        submitComposer(roomID: roomID)
                        return .handled
                    }
                    .accessibilityLabel(composerPlaceholder(roomID: roomID))
                    .background(AgentRoomsComposerDraftBridge { session.composerText = $0 })

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

    private func composerPlaceholder(roomID: String) -> String {
        if roomID == liveChat.testRoom?.id { return "Message Hermes in Cider Test Chat" }
        return "Message Hermes in \(liveChat.activeRoom?.title ?? "this conversation")"
    }

    private func submitComposer(roomID: String) {
        let text = composerText
        guard liveChat.startSubmission(text, selectedRoomID: roomID) == .accepted else { return }
        composerText = ""
    }

    @MainActor
    private func reload() async {
        state = .loading(authority: state.authority)
        state = await loadWorkspace(request)
    }

    @ViewBuilder
    private func roomManagementMenu(_ room: AgentRoom) -> some View {
        if let roomID = exportableRoomID(room) {
            Button("Export Conversation…") {
                onExportRoom?(roomID, room.title)
            }
            .accessibilityLabel("Export Conversation \(room.title)")

            if canManage(room) {
                Divider()
            }
        }

        if canManage(room) {
            Button("Rename Conversation") {
                renameText = room.title
                renameRoom = room
            }
            .accessibilityLabel("Rename Conversation \(room.title)")

            if room.lifecycleState == .active {
                Button("Archive Conversation") {
                    archiveConversation(room)
                }
                .accessibilityLabel("Archive Conversation \(room.title)")
            } else if room.lifecycleState == .archived {
                Button("Restore Conversation") {
                    restoreConversation(room)
                }
                .accessibilityLabel("Restore Conversation \(room.title)")
            }
        }
    }

    private func exportableRoomID(_ room: AgentRoom) -> UUID? {
        guard onExportRoom != nil,
              AgentRoomsRoomExportAvailability.allows(
                  room: room,
                  workspaceAuthority: state.authority,
                  activeLiveRoomID: liveChat.activeRoom?.id
              )
        else { return nil }
        return UUID(uuidString: room.id)
    }

    private func canManage(_ room: AgentRoom) -> Bool {
        roomActions != nil
            && state.authority == .canonicalIncomplete
            && UUID(uuidString: room.id) != nil
            && room.id != liveChat.testRoom?.id
    }

    private func applySearch() {
        request.searchText = searchText
        Task { await reload() }
    }

    private func createConversation() {
        guard let roomActions else { return }
        do {
            let room = try roomActions.createConversation()
            request = .init(scope: .active)
            searchText = ""
            session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
            Task {
                await liveChat.refreshTransportReadiness()
                await reload()
                focusedRegion = .composer
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func renameSelectedConversation() {
        guard let roomActions, let room = renameRoom, let roomID = UUID(uuidString: room.id) else { return }
        do {
            let renamed = try roomActions.renameConversation(id: roomID, title: renameText)
            renameRoom = nil
            session.selectRoom(
                id: renamed.id.uuidString,
                persistIfCanonical: renamed.lifecycleState == .active
            )
            Task { await reload() }
        } catch {
            renameRoom = nil
            actionError = error.localizedDescription
        }
    }

    private func archiveConversation(_ room: AgentRoom) {
        guard let roomActions, let roomID = UUID(uuidString: room.id) else { return }
        do {
            _ = try roomActions.archiveConversation(id: roomID)
            session.selectRoom(id: nil, persistIfCanonical: false)
            Task { await reload() }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func restoreConversation(_ room: AgentRoom) {
        guard let roomActions, let roomID = UUID(uuidString: room.id) else { return }
        do {
            let restored = try roomActions.restoreConversation(id: roomID)
            request = .init(scope: .active)
            searchText = ""
            session.selectRoom(id: restored.id.uuidString, persistIfCanonical: true)
            Task {
                await reload()
                focusedRegion = .composer
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct AgentRoomsBookmarkReceiptThumbnailView: View {
    let reference: AgentRoomsBookmarkThumbnailReference
    let expectedBookmarkID: UUID

    @StateObject private var loader = AgentRoomsBookmarkReceiptThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: BookmarksDesign.thumbnailWidthList,
                        height: BookmarksDesign.thumbnailHeightList
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline)
                    )
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .task(id: reference) {
            await loader.load(
                reference,
                expectedBookmarkID: expectedBookmarkID
            )
        }
    }
}

private struct AgentRoomsTranscriptBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AgentRoomsComposerDraftBridge: NSViewRepresentable {
    let persist: @MainActor (String) -> Void

    func makeNSView(context: Context) -> AgentRoomsComposerDraftBridgeView {
        AgentRoomsComposerDraftBridgeView(persist: persist)
    }

    func updateNSView(_ nsView: AgentRoomsComposerDraftBridgeView, context: Context) {
        nsView.persist = persist
        nsView.resolveComposerField()
    }

    static func dismantleNSView(_ nsView: AgentRoomsComposerDraftBridgeView, coordinator: Void) {
        nsView.persistVisibleDraft()
    }
}

private final class AgentRoomsComposerDraftBridgeView: NSView {
    var persist: @MainActor (String) -> Void
    private weak var composerField: NSTextField?

    init(persist: @escaping @MainActor (String) -> Void) {
        self.persist = persist
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            persistVisibleDraft()
        } else {
            resolveComposerField()
            DispatchQueue.main.async { [weak self] in self?.resolveComposerField() }
        }
    }

    func resolveComposerField() {
        guard composerField == nil, let contentView = window?.contentView else { return }
        composerField = Self.findComposerField(in: contentView)
    }

    func persistVisibleDraft() {
        resolveComposerField()
        guard let composerField else { return }
        persist(composerField.stringValue)
    }

    private static func findComposerField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField,
           field.placeholderString?.hasPrefix("Message Hermes in ") == true {
            return field
        }
        for subview in view.subviews {
            if let match = findComposerField(in: subview) { return match }
        }
        return nil
    }
}
