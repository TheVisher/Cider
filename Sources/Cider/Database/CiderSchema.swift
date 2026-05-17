import Foundation

/// All CREATE TABLE and CREATE INDEX statements for the Cider SQLite database.
/// Tables are ordered by dependency: parent tables before children.
enum CiderSchema {

    // MARK: - Schema Version Tracking

    static let createSchemaVersion = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
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
            summary   TEXT,
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
            checklist    TEXT,
            surfacing_rules TEXT,
            action_url   TEXT,
            snoozed_until REAL
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
            surfacing_rules TEXT,
            action_url   TEXT,
            snoozed_until REAL
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
            has_avatar         INTEGER NOT NULL DEFAULT 0,
            custom_fields      TEXT NOT NULL DEFAULT '[]'
        );
        """

    static let createVaultFiles = """
        CREATE TABLE IF NOT EXISTS vault_files (
            item_id            TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            filename           TEXT NOT NULL,
            file_type          TEXT NOT NULL,
            file_size          INTEGER NOT NULL,
            notes              TEXT NOT NULL DEFAULT '',
            ocr_text           TEXT,
            dominant_colors    TEXT,
            title_manually_set INTEGER NOT NULL DEFAULT 0
        );
        """

    /// Named-migration ledger. Tracks one-off data migrations by name so they
    /// don't re-run even if sidecar files are lost (e.g. id-map.json deleted).
    static let createSchemaMigrations = """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            name       TEXT PRIMARY KEY,
            applied_at REAL NOT NULL
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

    // MARK: - Second Brain Foundation

    static let createItemSections = """
        CREATE TABLE IF NOT EXISTS item_sections (
            id          TEXT PRIMARY KEY,
            item_id     TEXT REFERENCES items(id) ON DELETE CASCADE,
            owner_type  TEXT NOT NULL,
            owner_id    TEXT NOT NULL,
            section_key TEXT NOT NULL,
            title       TEXT NOT NULL,
            body        TEXT NOT NULL DEFAULT '',
            source      TEXT NOT NULL,
            confidence  REAL,
            metadata    TEXT NOT NULL DEFAULT '{}',
            sort_order  INTEGER NOT NULL DEFAULT 0,
            created_at  REAL NOT NULL,
            updated_at  REAL NOT NULL,
            UNIQUE(owner_type, owner_id, section_key)
        );
        """

    static let createContentChunks = """
        CREATE TABLE IF NOT EXISTS content_chunks (
            id           TEXT PRIMARY KEY,
            section_id   TEXT REFERENCES item_sections(id) ON DELETE SET NULL,
            item_id      TEXT REFERENCES items(id) ON DELETE CASCADE,
            owner_type   TEXT NOT NULL,
            owner_id     TEXT NOT NULL,
            source       TEXT NOT NULL,
            title        TEXT NOT NULL DEFAULT '',
            body         TEXT NOT NULL,
            chunk_index  INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL,
            metadata     TEXT NOT NULL DEFAULT '{}',
            created_at   REAL NOT NULL,
            updated_at   REAL NOT NULL
        );
        """

    static let createContentChunksFTS = """
        CREATE VIRTUAL TABLE IF NOT EXISTS content_chunks_fts
        USING fts5(
            title,
            body,
            owner_type UNINDEXED,
            owner_id UNINDEXED,
            content='content_chunks',
            content_rowid='rowid'
        );
        """

    static let createContentChunksFTSInsertTrigger = """
        CREATE TRIGGER IF NOT EXISTS content_chunks_ai
        AFTER INSERT ON content_chunks BEGIN
            INSERT INTO content_chunks_fts(rowid, title, body, owner_type, owner_id)
            VALUES (new.rowid, new.title, new.body, new.owner_type, new.owner_id);
        END;
        """

    static let createContentChunksFTSDeleteTrigger = """
        CREATE TRIGGER IF NOT EXISTS content_chunks_ad
        AFTER DELETE ON content_chunks BEGIN
            INSERT INTO content_chunks_fts(content_chunks_fts, rowid, title, body, owner_type, owner_id)
            VALUES ('delete', old.rowid, old.title, old.body, old.owner_type, old.owner_id);
        END;
        """

    static let createContentChunksFTSUpdateTrigger = """
        CREATE TRIGGER IF NOT EXISTS content_chunks_au
        AFTER UPDATE ON content_chunks BEGIN
            INSERT INTO content_chunks_fts(content_chunks_fts, rowid, title, body, owner_type, owner_id)
            VALUES ('delete', old.rowid, old.title, old.body, old.owner_type, old.owner_id);
            INSERT INTO content_chunks_fts(rowid, title, body, owner_type, owner_id)
            VALUES (new.rowid, new.title, new.body, new.owner_type, new.owner_id);
        END;
        """

    static let createAgentActions = """
        CREATE TABLE IF NOT EXISTS agent_actions (
            id             TEXT PRIMARY KEY,
            item_id        TEXT REFERENCES items(id) ON DELETE SET NULL,
            owner_type     TEXT NOT NULL,
            owner_id       TEXT NOT NULL,
            tool_name      TEXT NOT NULL,
            action_type    TEXT NOT NULL,
            source         TEXT NOT NULL,
            status         TEXT NOT NULL,
            summary        TEXT NOT NULL,
            arguments_json TEXT,
            result_json    TEXT,
            created_at     REAL NOT NULL
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

    static let createMutationAudit = """
        CREATE TABLE IF NOT EXISTS mutation_audit (
            id           TEXT PRIMARY KEY,
            occurred_at  REAL NOT NULL,
            item_type    TEXT NOT NULL,
            item_id      TEXT NOT NULL,
            action       TEXT NOT NULL,
            source       TEXT NOT NULL,
            before_state TEXT,
            after_state  TEXT,
            metadata     TEXT
        );
        """

    static let createFolderSyncDecisions = """
        CREATE TABLE IF NOT EXISTS folder_sync_decisions (
            remote_folder_id TEXT PRIMARY KEY,
            local_folder_id  TEXT REFERENCES folders(id) ON DELETE SET NULL,
            decision         TEXT NOT NULL,
            reason           TEXT NOT NULL,
            requested_path   TEXT NOT NULL DEFAULT '',
            source           TEXT NOT NULL,
            metadata         TEXT,
            created_at       REAL NOT NULL,
            updated_at       REAL NOT NULL
        );
        """

    static let createRoutingDecisions = """
        CREATE TABLE IF NOT EXISTS routing_decisions (
            id                    TEXT PRIMARY KEY,
            item_id               TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            item_type             TEXT NOT NULL,
            target_kind           TEXT NOT NULL,
            target_name           TEXT NOT NULL,
            target_relative_path  TEXT NOT NULL,
            target_folder_id      TEXT REFERENCES folders(id),
            confidence            REAL NOT NULL,
            reason                TEXT NOT NULL,
            actor                 TEXT NOT NULL,
            source                TEXT NOT NULL,
            review_state          TEXT NOT NULL,
            created_at            REAL NOT NULL,
            supersedes_decision_id TEXT REFERENCES routing_decisions(id)
        );
        """

    static let createSecondBrainRoutingDecisions = """
        CREATE TABLE IF NOT EXISTS second_brain_routing_decisions (
            id              TEXT PRIMARY KEY,
            item_id         TEXT REFERENCES items(id) ON DELETE SET NULL,
            owner_type      TEXT NOT NULL,
            owner_id        TEXT NOT NULL,
            target_type     TEXT NOT NULL,
            target_id       TEXT,
            target_path     TEXT,
            confidence      REAL NOT NULL,
            reason          TEXT NOT NULL,
            status          TEXT NOT NULL,
            actor           TEXT NOT NULL,
            source          TEXT NOT NULL,
            candidates_json TEXT,
            created_at      REAL NOT NULL,
            reviewed_at     REAL
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
        "CREATE INDEX IF NOT EXISTS idx_item_sections_owner ON item_sections(owner_type, owner_id, sort_order);",
        "CREATE INDEX IF NOT EXISTS idx_item_sections_item ON item_sections(item_id) WHERE item_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_content_chunks_owner ON content_chunks(owner_type, owner_id, chunk_index);",
        "CREATE INDEX IF NOT EXISTS idx_content_chunks_section ON content_chunks(section_id) WHERE section_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_agent_actions_owner ON agent_actions(owner_type, owner_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_agent_actions_tool ON agent_actions(tool_name, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_owner ON second_brain_routing_decisions(owner_type, owner_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_status ON second_brain_routing_decisions(status, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_bookmarks_url     ON bookmarks(url);",
        "CREATE INDEX IF NOT EXISTS idx_bookmarks_enrich  ON bookmarks(enrichment_status);",
        "CREATE INDEX IF NOT EXISTS idx_todos_completed   ON todos(is_completed);",
        "CREATE INDEX IF NOT EXISTS idx_events_start      ON events(start_at);",
        "CREATE INDEX IF NOT EXISTS idx_mutation_audit_time ON mutation_audit(occurred_at);",
        "CREATE INDEX IF NOT EXISTS idx_mutation_audit_item ON mutation_audit(item_type, item_id, occurred_at);",
        "CREATE INDEX IF NOT EXISTS idx_folder_sync_decisions_local ON folder_sync_decisions(local_folder_id);",
        "CREATE INDEX IF NOT EXISTS idx_folder_sync_decisions_decision ON folder_sync_decisions(decision, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_routing_decisions_item ON routing_decisions(item_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_routing_decisions_review ON routing_decisions(review_state);",
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
        createItemSections,
        createContentChunks,
        createContentChunksFTS,
        createContentChunksFTSInsertTrigger,
        createContentChunksFTSDeleteTrigger,
        createContentChunksFTSUpdateTrigger,
        createRoutingDecisions,
        createSecondBrainRoutingDecisions,
        createAgentActions,
        createTrash,
        createMutationAudit,
        createFolderSyncDecisions,
        createSchemaMigrations,
    ]
}
