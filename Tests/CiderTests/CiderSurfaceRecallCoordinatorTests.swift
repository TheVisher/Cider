import Foundation
import Testing
@testable import Cider

struct CiderSurfaceRecallCoordinatorTests {
    @Test("item and AI surfaces are recallable and utility surfaces are ignored")
    func recallabilityFiltersUtilitySurfaces() {
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.note(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.bookmark(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.bookmarkMetadata(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.contact(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.dateCard(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.todo(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.aiAssistant))
        #expect(!CiderSurfaceRecallCoordinator.isRecallable(.dropZone))
        #expect(!CiderSurfaceRecallCoordinator.isRecallable(.clipboard))
    }

    @Test("activation opens main window when no recallable surface exists")
    func activationFallsBackToMainWindow() {
        let coordinator = CiderSurfaceRecallCoordinator()

        #expect(coordinator.activationAction(isVisible: { _ in false }) == .openMainWindow)
    }

    @Test("activation restores the last recallable surface")
    func activationRestoresLastSurface() {
        let noteID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()

        coordinator.record(.note(noteID))

        #expect(coordinator.activationAction(isVisible: { _ in false }) == .show(.note(noteID)))
    }

    @Test("activation hides the visible recalled surface")
    func activationHidesVisibleSurface() {
        let todoID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()

        coordinator.record(.todo(todoID))

        #expect(coordinator.activationAction(isVisible: { $0 == .todo(todoID) }) == .hide(.todo(todoID)))
    }

    @Test("closing a recallable surface keeps it available for recall")
    func closedSurfaceRemainsRecallable() {
        let bookmarkID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()

        coordinator.record(.bookmarkMetadata(bookmarkID))
        coordinator.recordClosed(.bookmarkMetadata(bookmarkID))

        #expect(coordinator.activationAction(isVisible: { _ in false }) == .show(.bookmarkMetadata(bookmarkID)))
    }
}
