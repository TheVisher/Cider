import Foundation
import Testing
@testable import Cider

/// Tests for `VaultReconciler`, the startup coordinator that reconciles the
/// SQLite database with the vault filesystem.
///
/// The reconciler is a thin delegator — it mostly triggers each service's
/// existing rescan logic. These tests verify the entry point behaves correctly
/// in isolation; per-service scan semantics are covered by the individual
/// service test suites.
///
/// Note: The reconciler touches `CiderDatabase.shared` and service singletons.
/// To keep tests isolated from the shared state used by other tests (which
/// open their own `CiderDatabase` instances via `init(database:)`), these
/// tests only exercise the DB-closed fast path and verify idempotency.
/// Full integration of reconcile() against a temp vault is covered by the
/// manual test scenarios documented in the Task 12 commit message.
@Suite("VaultReconciler Tests")
@MainActor
struct VaultReconcilerTests {

    @Test("reconcile() is a no-op when CiderDatabase.shared is not open")
    func reconcileNoOpWhenClosed() {
        // The shared DB should not be open in the test process (tests use
        // injected CiderDatabase instances, not the shared singleton).
        #expect(CiderDatabase.shared.isOpen == false)

        // Should return without throwing and without side effects.
        VaultReconciler.reconcile()

        // Still closed afterwards.
        #expect(CiderDatabase.shared.isOpen == false)
    }

    @Test("reconcile() is idempotent — multiple calls produce no errors")
    func reconcileIdempotent() {
        #expect(CiderDatabase.shared.isOpen == false)

        // Calling reconcile() multiple times in the DB-closed state must be
        // safe and must not change shared state.
        VaultReconciler.reconcile()
        VaultReconciler.reconcile()
        VaultReconciler.reconcile()

        #expect(CiderDatabase.shared.isOpen == false)
    }

    /// Smoke test for the Task 12 bug fix: `NotesStorage.rescan()` must exist
    /// as a public entry point so VaultReconciler can force a filesystem
    /// rescan on startup (init alone short-circuits on any non-empty DB load).
    ///
    /// This test only verifies the method is callable and returns without
    /// crashing — full round-trip coverage lives in manual/integration tests
    /// because `NotesStorage.rescan()` scans the real vault directory.
    @Test("NotesStorage.rescan() is callable without crashing")
    func notesStorageRescanIsCallable() {
        // Touches the shared singleton (tests do not open CiderDatabase.shared
        // so the DB-less fallback path is exercised).
        #expect(CiderDatabase.shared.isOpen == false)
        NotesStorage.shared.rescan()
        NotesStorage.shared.rescan() // idempotent
    }
}
