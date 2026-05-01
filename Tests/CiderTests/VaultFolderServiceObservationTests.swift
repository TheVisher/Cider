import Combine
import Testing
@testable import Cider

@MainActor
struct VaultFolderServiceObservationTests {
    @Test("vault folder service is observable for metadata surfaces")
    func vaultFolderServiceIsObservable() {
        let _: any ObservableObject = VaultFolderService.shared
        #expect(VaultFolderService.shared.legacyFolders.count >= 0)
    }
}
