import Foundation

/// All CREATE TABLE and CREATE INDEX statements for the Cider SQLite database.
/// Tables are ordered by dependency: parent tables before children.
enum CiderSchema {

    // MARK: - Schema Version Tracking

    static let createSchemaVersion = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER NOT NULL
        );
        """

    // MARK: - Core Tables (no FK dependencies)

    static let createFolders = """
        CREATE TABLE IF NOT EXISTS folders (
            id                   TEXT PRIMARY KEY,
            relative_path        TEXT NOT NULL UNIQUE,
            created_at           REAL NOT NULL,
            updated_at           REAL NOT NULL,
            icon                 TEXT,
            cover_image_path     TEXT,
            cover_image_offset_y REAL
        );
        """

    static let createLabels = """
        CREATE TABLE IF NOT EXISTS labels (
            id         TEXT PRIMARY KEY,
            name       TEXT NOT NULL,
            color_hex  TEXT NOT NULL,
            kind       TEXT NOT NULL DEFAULT 'custom',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

    // MARK: - Items (references folders)

    static let createItems = """
        CREATE TABLE IF NOT EXISTS items (
            id            TEXT PRIMARY KEY,
            type          TEXT NOT NULL,
            title         TEXT NOT NULL,
            created_at    REAL NOT NULL,
            updated_at    REAL NOT NULL,
            folder_id     TEXT REFERENCES folders(id),
            relative_path TEXT
        );
        """

    // MARK: - Per-Type Detail Tables (reference items)

    static let createBookmarks = """
        CREATE TABLE IF NOT EXISTS bookmarks (
            item_id                 TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            url                     TEXT NOT NULL,
            notes                   TEXT NOT NULL DEFAULT '',
            notes_manually_set      INTEGER NOT NULL DEFAULT 0,
            title_manually_set      INTEGER NOT NULL DEFAULT 0,
            ai_summary              TEXT,
            enrichment_status       TEXT,
            last_enriched_at        REAL,
            ocr_text                TEXT,
            dominant_colors         TEXT,
            media_type              TEXT,
            thumbnail_relative_path TEXT,
            thumbnail_remote_url    TEXT,
            original_image_path     TEXT,
            carousel_image_paths    TEXT,
            reader_unavailable      INTEGER,
            preferred_hero_mode     TEXT
        );
        """

    static let createNotes = """
        CREATE TABLE IF NOT EXISTS notes (
            item_id   TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            content   TEXT NOT NULL DEFAULT '',
            is_pinned INTEGER NOT NULL DEFAULT 0
        );
        """

    static let createTodos = """
        CREATE TABLE IF NOT EXISTS todos (
            item_id      TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            details      TEXT NOT NULL DEFAULT '',
            due_date     REAL,
            priority     TEXT,
            is_completed INTEGER NOT NULL DEFAULT 0,
            completed_at REAL,
            notes        TEXT NOT NULL DEFAULT '',
            checklist    TEXT
        );
        """

    static let createEvents = """
        CREATE TABLE IF NOT EXISTS events (
            item_id         TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            details         TEXT NOT NULL DEFAULT '',
            start_at        REAL NOT NULL,
            end_at          REAL,
            all_day         INTEGER NOT NULL DEFAULT 0,
            location        TEXT NOT NULL DEFAULT '',
            amount          REAL,
            recurrence_rule TEXT,
            is_completed    INTEGER NOT NULL DEFAULT 0,
            completed_at    REAL,
            surfacing_rules TEXT
        );
        """

    static let createContacts = """
        CREATE TABLE IF NOT EXISTS contacts (
            item_id            TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            relationship_label TEXT NOT NULL DEFAULT '',
            birthday           REAL,
            notes              TEXT NOT NULL DEFAULT '',
            email              TEXT NOT NULL DEFAULT '',
            phone              TEXT NOT NULL DEFAULT '',
            address            TEXT NOT NULL DEFAULT '',
            has_avatar         INTEGER NOT NULL DEFAULT 0
        );
        """

    static let createVaultFiles = """
        CREATE TABLE IF NOT EXISTS vault_files (
            item_id         TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            filename        TEXT NOT NULL,
            file_type       TEXT NOT NULL,
            file_size       INTEGER NOT NULL,
            notes           TEXT NOT NULL DEFAULT '',
            ocr_text        TEXT,
            dominant_colors TEXT
        );
        """

    // MARK: - Sessions (standalone, not in items)

    static let createSessions = """
        CREATE TABLE IF NOT EXISTS sessions (
            id                  TEXT PRIMARY KEY,
            name                TEXT NOT NULL,
            source_browser_id   TEXT,
            source_browser_name TEXT,
            tabs                TEXT,
            folder_id           TEXT REFERENCES folders(id),
            label_ids           TEXT,
            created_at          REAL NOT NULL,
            updated_at          REAL NOT NULL
        );
        """

    // MARK: - Join / Relationship Tables

    static let createItemLabels = """
        CREATE TABLE IF NOT EXISTS item_labels (
            item_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
            PRIMARY KEY (item_id, label_id)
        );
        """

    static let createDismissedLabels = """
        CREATE TABLE IF NOT EXISTS dismissed_labels (
            item_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
            PRIMARY KEY (item_id, label_id)
        );
        """

    static let createTags = """
        CREATE TABLE IF NOT EXISTS tags (
            id   TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE
        );
        """

    static let createItemTags = """
        CREATE TABLE IF NOT EXISTS item_tags (
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (item_id, tag_id)
        );
        """

    static let createItemLinks = """
        CREATE TABLE IF NOT EXISTS item_links (
            source_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            target_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            link_type  TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (source_id, target_id, link_type)
        );
        """

    // MARK: - Trash

    static let createTrash = """
        CREATE TABLE IF NOT EXISTS trash (
            id                 TEXT PRIMARY KEY,
            item_id            TEXT NOT NULL,
            item_type          TEXT NOT NULL,
            title              TEXT NOT NULL,
            original_folder_id TEXT,
            deleted_at         REAL NOT NULL,
            payload            TEXT NOT NULL
        );
        """

    // MARK: - Indexes

    static let createIndexes: [String] = [
        "CREATE INDEX IF NOT EXISTS idx_items_type        ON items(type);",
        "CREATE INDEX IF NOT EXISTS idx_items_folder      ON items(folder_id);",
        "CREATE INDEX IF NOT EXISTS idx_items_created     ON items(created_at);",
        "CREATE INDEX IF NOT EXISTS idx_items_updated     ON items(updated_at);",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_items_path ON items(relative_path) WHERE relative_path IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_item_labels_label ON item_labels(label_id);",
        "CREATE INDEX IF NOT EXISTS idx_item_tags_tag     ON item_tags(tag_id);",
        "CREATE INDEX IF NOT EXISTS idx_item_links_target ON item_links(target_id);",
        "CREATE INDEX IF NOT EXISTS idx_bookmarks_url     ON bookmarks(url);",
        "CREATE INDEX IF NOT EXISTS idx_bookmarks_enrich  ON bookmarks(enrichment_status);",
        "CREATE INDEX IF NOT EXISTS idx_todos_completed   ON todos(is_completed);",
        "CREATE INDEX IF NOT EXISTS idx_events_start      ON events(start_at);",
    ]

    // MARK: - All Tables in Dependency Order

    /// All CREATE TABLE statements in dependency order (parents before children).
    static let allTables: [String] = [
        createFolders,
        createLabels,
        createItems,
        createBookmarks,
        createNotes,
        createTodos,
        createEvents,
        createContacts,
        createVaultFiles,
        createSessions,
        createItemLabels,
        createDismissedLabels,
        createTags,
        createItemTags,
        createItemLinks,
        createTrash,
    ]
}
