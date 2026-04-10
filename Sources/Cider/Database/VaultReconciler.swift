import Foundation
import os

/// Reconciles the SQLite database against the vault filesystem on app launch.
///
/// Called after `CiderDatabase.shared` has been opened but before UI renders.
/// The reconciler is a thin coordinator — it delegates scanning to individual
/// services, which already implement orphan adoption, stale-row removal, and
/// moved-file detection via their existing scan/rescan methods.
///
/// Responsibilities:
/// 1. Trigger each service's existing scan/adopt logic so external filesystem
///    changes made while the app was closed are detected.
/// 2. Ensure the one-time JSON-to-SQLite migration paths embedded in each
///    service's init actually run (by touching `.shared` after DB is open).
/// 3. Keep startup fast: each service's rescan is idempotent and short-circuits
///    when no filesystem changes are detected.
///
/// Safe to call when `CiderDatabase.shared.isOpen` is false — in that case the
/// reconciler logs and returns, and services fall back to JSON persistence.
@MainActor
enum VaultReconciler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultReconciler"
    )

    /// Run reconciliation. Idempotent and safe to call multiple times.
    static func reconcile() {
        guard CiderDatabase.shared.isOpen else {
            logger.info("Skipping reconciliation — database is not open; services will use JSON fallback")
            return
        }

        logger.info("Starting vault reconciliation")
        let started = Date()

        // Touching each singleton triggers its lazy init, which runs the
        // one-time JSON-to-SQLite migration path (if applicable) and loads
        // state from SQLite. The order below reflects dependency ordering:
        // folders/labels first (referenced by content items), then content.

        // Folders and labels — derived state, DB-primary with JSON fallback.
        _ = VaultFolderService.shared
        _ = CardLabelStorage.shared

        // Content services — trigger rescan so external filesystem changes
        // made while the app was closed are detected and persisted to SQLite.

        // Bookmarks: adoptOrphanedVaultFiles() scans all vault folders + Inbox,
        // adopts new .webloc files, reassigns moved ones, and persists via the
        // SQLite-aware persist() path.
        VaultBookmarkService.shared.adoptOrphanedVaultFiles()

        // Notes: init already scans on first access. No public rescan needed —
        // touching the singleton is sufficient for startup reconciliation.
        _ = NotesStorage.shared

        // Todos / Events / Contacts: per-file .ics / .vcf stores with explicit
        // rescan() entry points that detect added/removed files.
        TodoCardStorage.shared.rescan()
        DateCardStorage.shared.rescan()
        ContactStorage.shared.rescan()

        // Vault files: scans the filesystem and reconciles with SQLite via
        // the stable id-map. Idempotent.
        VaultFileService.shared.scan()

        // Sessions (DB-only) and Trash (mirrored on writes) need no filesystem
        // reconciliation — they have no external source of truth.

        let elapsed = Date().timeIntervalSince(started)
        logger.info("Reconciliation finished in \(String(format: "%.3f", elapsed))s")
    }
}
