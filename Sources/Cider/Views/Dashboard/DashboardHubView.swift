import SwiftUI

enum DashboardHubSelection: Hashable {
    case main
    case topic(String)
}

@MainActor
struct DashboardHubView<MainContent: View>: View {
    @ObservedObject private var storage: DashboardStorage
    @State private var selection: DashboardHubSelection = .main

    private let showsTopicSwitcher: Bool
    private let onOpenSourceURL: (URL) -> Void
    private let mainContent: () -> MainContent

    init(
        storage: DashboardStorage = .shared,
        showsTopicSwitcher: Bool = true,
        onOpenSourceURL: @escaping (URL) -> Void,
        @ViewBuilder mainContent: @escaping () -> MainContent
    ) {
        self.storage = storage
        self.showsTopicSwitcher = showsTopicSwitcher
        self.onOpenSourceURL = onOpenSourceURL
        self.mainContent = mainContent
    }

    var body: some View {
        let topics = activeTopics

        VStack(spacing: 0) {
            if showsTopicSwitcher {
                DashboardTopicTabsView(
                    topics: topics,
                    selection: $selection,
                    cardCounts: cardCounts
                )

                Divider()
                    .background(CiderColors.separator)
            }

            Group {
                if showsTopicSwitcher == false {
                    mainContent()
                } else {
                    switch selection {
                    case .main:
                        mainContent()
                    case .topic(let topicSyncId):
                        if let topic = topics.first(where: { $0.ciderSyncId == topicSyncId }) {
                            DashboardBoardView(
                                topic: topic,
                                storage: storage,
                                onOpenSourceURL: onOpenSourceURL
                            )
                        } else {
                            mainContent()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            normalizeSelection(topics: activeTopics)
        }
        .onChange(of: topics.map(\.ciderSyncId)) { _, _ in
            normalizeSelection(topics: activeTopics)
        }
    }

    private var activeTopics: [DashboardTopic] {
        let storedTopics = storage.topics
            .filter { $0.isArchived != true && $0.deleted != true }

        let storedTopicIds = Set(storedTopics.map(\.ciderSyncId))
        let defaultTopics = DashboardDefaultTopics.topics.filter { topic in
            storedTopicIds.contains(topic.ciderSyncId) == false
        }

        return (defaultTopics + storedTopics)
            .sorted { lhs, rhs in
                if lhs.position == rhs.position {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.position < rhs.position
            }
    }

    private var cardCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: activeTopics.map { topic in
            let count = storage.cards.filter { card in
                card.topicSyncIds.contains(topic.ciderSyncId)
                    && card.deleted != true
                    && card.status != .dismissed
                    && card.status != .archived
            }.count
            return (topic.ciderSyncId, count)
        })
    }

    private func normalizeSelection(topics: [DashboardTopic]) {
        guard case .topic(let topicSyncId) = selection else { return }
        if topics.contains(where: { $0.ciderSyncId == topicSyncId }) == false {
            selection = .main
        }
    }
}
