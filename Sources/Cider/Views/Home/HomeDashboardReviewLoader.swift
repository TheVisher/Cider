import Foundation

@MainActor
final class HomeDashboardReviewLoader: ObservableObject {
    @Published private(set) var model: CiderHomeDashboardReviewModel?
    @Published private(set) var lastLoadMilliseconds: Int?

    private var isLoading = false
    private var hasLoaded = false
    private let loadModel: @MainActor () -> CiderHomeDashboardReviewModel?

    init(
        loadModel: @escaping @MainActor () -> CiderHomeDashboardReviewModel? = {
            try? CiderReviewQueueService().homeDashboardReviewModel(
                itemLimit: 30,
                batchEnrichmentSampleLimit: 5
            )
        }
    ) {
        self.loadModel = loadModel
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        let startedAt = ContinuousClock.now

        // Let SwiftUI commit the Home route before the database-backed model is
        // constructed. The resulting snapshot stays alive across navigation so
        // ordinary returns to Home do not repeat this synchronous read path.
        await Task.yield()
        let result = loadModel()

        let elapsed = startedAt.duration(to: .now)
        lastLoadMilliseconds = Int(elapsed.components.seconds * 1_000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        model = result
        hasLoaded = true
        isLoading = false
    }

    func invalidate() {
        model = nil
        lastLoadMilliseconds = nil
        hasLoaded = false
    }
}
