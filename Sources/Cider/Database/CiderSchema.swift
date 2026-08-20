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

    static let createOwnerRelations = """
        CREATE TABLE IF NOT EXISTS owner_relations (
            id                TEXT PRIMARY KEY,
            source_owner_type TEXT NOT NULL,
            source_owner_id   TEXT NOT NULL,
            target_owner_type TEXT NOT NULL,
            target_owner_id   TEXT NOT NULL,
            relation_type     TEXT NOT NULL,
            evidence          TEXT NOT NULL DEFAULT '',
            source            TEXT NOT NULL,
            actor             TEXT NOT NULL,
            confidence        REAL,
            metadata          TEXT NOT NULL DEFAULT '{}',
            created_at        REAL NOT NULL,
            updated_at        REAL NOT NULL,
            UNIQUE(source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, source)
        );
        """

    static let createProjects = """
        CREATE TABLE IF NOT EXISTS projects (
            id         TEXT PRIMARY KEY,
            title      TEXT NOT NULL,
            subtitle   TEXT NOT NULL DEFAULT '',
            status     TEXT NOT NULL DEFAULT 'active',
            metadata   TEXT NOT NULL DEFAULT '{}',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

    static let createProjectGraphStates = """
        CREATE TABLE IF NOT EXISTS project_graph_states (
            project_id                 TEXT PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
            graph_revision             INTEGER NOT NULL DEFAULT 0 CHECK (graph_revision >= 0),
            primary_path_revision      INTEGER NOT NULL DEFAULT 0 CHECK (primary_path_revision >= 0),
            canonical_summary_revision INTEGER NOT NULL DEFAULT 0 CHECK (canonical_summary_revision >= 0),
            intake_summary             TEXT NOT NULL DEFAULT '',
            active_intake_count         INTEGER NOT NULL DEFAULT 0 CHECK (active_intake_count >= 0),
            updated_at                  REAL NOT NULL
        );
        """

    static let createProjectNodes = """
        CREATE TABLE IF NOT EXISTS project_nodes (
            id                TEXT PRIMARY KEY,
            project_id        TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            node_kind         TEXT NOT NULL DEFAULT 'idea'
                                CHECK (node_kind IN ('idea', 'feature', 'milestone')),
            title             TEXT NOT NULL,
            concise_summary   TEXT NOT NULL,
            lifecycle_state   TEXT NOT NULL
                                CHECK (lifecycle_state IN ('captured', 'reviewed', 'integrated', 'deferred', 'rejected')),
            placement_kind    TEXT NOT NULL
                                CHECK (placement_kind IN ('intake', 'primary')),
            intake_visibility TEXT NOT NULL DEFAULT 'active'
                                CHECK (intake_visibility IN ('active', 'deferred', 'archived')),
            request_id        TEXT NOT NULL UNIQUE,
            capture_key       TEXT NOT NULL UNIQUE,
            schema_version    INTEGER NOT NULL DEFAULT 1,
            node_revision     INTEGER NOT NULL DEFAULT 1 CHECK (node_revision >= 1),
            created_at        REAL NOT NULL,
            updated_at        REAL NOT NULL,
            integrated_at     REAL,
            CHECK (
                (lifecycle_state = 'integrated' AND placement_kind = 'primary' AND integrated_at IS NOT NULL)
                OR
                (lifecycle_state <> 'integrated' AND placement_kind = 'intake' AND integrated_at IS NULL)
            )
        );
        """

    static let createProjectPrimaryPathMemberships = """
        CREATE TABLE IF NOT EXISTS project_primary_path_memberships (
            project_id        TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            node_id           TEXT NOT NULL UNIQUE REFERENCES project_nodes(id) ON DELETE CASCADE,
            ordinal           INTEGER NOT NULL CHECK (ordinal >= 0),
            approval_event_id TEXT NOT NULL,
            integrated_at     REAL NOT NULL,
            PRIMARY KEY (project_id, node_id),
            UNIQUE (project_id, ordinal)
        );
        """

    static let createProjectNodeEvents = """
        CREATE TABLE IF NOT EXISTS project_node_events (
            id                    TEXT PRIMARY KEY,
            node_id               TEXT NOT NULL REFERENCES project_nodes(id) ON DELETE CASCADE,
            operation_id          TEXT NOT NULL,
            event_kind            TEXT NOT NULL,
            from_state            TEXT,
            to_state              TEXT,
            actor_type            TEXT NOT NULL,
            actor_id              TEXT,
            authority_revision    INTEGER,
            primary_path_revision INTEGER,
            payload_json          TEXT NOT NULL DEFAULT '{}',
            created_at            REAL NOT NULL,
            UNIQUE (node_id, operation_id)
        );
        """

    static let createOwnerLabelIndex = """
        CREATE TABLE IF NOT EXISTS owner_label_index (
            owner_type              TEXT NOT NULL,
            owner_id                TEXT NOT NULL,
            owner_kind              TEXT NOT NULL,
            canonical_label         TEXT NOT NULL,
            normalized_label        TEXT NOT NULL,
            aliases_json            TEXT NOT NULL DEFAULT '[]',
            normalized_aliases_json TEXT NOT NULL DEFAULT '[]',
            external_ids_json       TEXT NOT NULL DEFAULT '{}',
            provenance_refs_json    TEXT NOT NULL DEFAULT '[]',
            source_refs_json        TEXT NOT NULL DEFAULT '[]',
            label_source            TEXT NOT NULL DEFAULT '',
            confidence              REAL,
            is_deleted              INTEGER NOT NULL DEFAULT 0,
            created_at              REAL NOT NULL,
            updated_at              REAL NOT NULL,
            PRIMARY KEY (owner_type, owner_id)
        );
        """

    static let createCaptureEvents = """
        CREATE TABLE IF NOT EXISTS capture_events (
            id               TEXT PRIMARY KEY,
            source_kind      TEXT NOT NULL,
            surface          TEXT,
            channel          TEXT,
            channel_id       TEXT,
            thread_id        TEXT,
            message_id       TEXT,
            sender_id        TEXT,
            sender_name      TEXT,
            source_url       TEXT,
            source_file      TEXT,
            source_text      TEXT,
            attachment_count INTEGER NOT NULL DEFAULT 0,
            metadata         TEXT NOT NULL DEFAULT '{}',
            created_at       REAL NOT NULL
        );
        """

    static let createCaptureAttachments = """
        CREATE TABLE IF NOT EXISTS capture_attachments (
            id                   TEXT PRIMARY KEY,
            capture_event_id     TEXT NOT NULL,
            attachment_index     INTEGER NOT NULL,
            source_attachment_id TEXT,
            filename             TEXT,
            mime_type            TEXT,
            local_path           TEXT,
            remote_url           TEXT,
            byte_size            INTEGER,
            metadata             TEXT NOT NULL DEFAULT '{}',
            created_at           REAL NOT NULL,
            UNIQUE(capture_event_id, attachment_index),
            FOREIGN KEY(capture_event_id) REFERENCES capture_events(id) ON DELETE CASCADE
        );
        """

    static let createEnrichmentOutputs = """
        CREATE TABLE IF NOT EXISTS enrichment_outputs (
            id               TEXT PRIMARY KEY,
            owner_type       TEXT NOT NULL,
            owner_id         TEXT NOT NULL,
            chunk_id         TEXT,
            kind             TEXT NOT NULL,
            value            TEXT NOT NULL,
            normalized_value TEXT NOT NULL,
            label            TEXT NOT NULL DEFAULT '',
            evidence         TEXT NOT NULL DEFAULT '',
            source           TEXT NOT NULL,
            occurrence_key   TEXT NOT NULL DEFAULT '',
            confidence       REAL,
            review_state     TEXT NOT NULL DEFAULT 'suggested',
            metadata         TEXT NOT NULL DEFAULT '{}',
            created_at       REAL NOT NULL,
            updated_at       REAL NOT NULL,
            UNIQUE(owner_type, owner_id, kind, normalized_value, source, occurrence_key)
        );
        """

    static let createSourceEvidence = """
        CREATE TABLE IF NOT EXISTS source_evidence (
            id                  TEXT PRIMARY KEY,
            evidence_kind       TEXT NOT NULL DEFAULT 'source_span',
            source_owner_type   TEXT NOT NULL,
            source_owner_id     TEXT NOT NULL,
            source_kind         TEXT,
            source_quote        TEXT NOT NULL DEFAULT '',
            span_start          INTEGER,
            span_end            INTEGER,
            observed_at         REAL,
            captured_at         REAL,
            extracted_at        REAL,
            extraction_source   TEXT NOT NULL,
            extraction_run_id   TEXT,
            extraction_provider TEXT,
            extraction_model    TEXT,
            derived_owner_type  TEXT NOT NULL,
            derived_owner_id    TEXT NOT NULL,
            derived_kind        TEXT NOT NULL,
            candidate_ref       TEXT,
            metadata            TEXT NOT NULL DEFAULT '{}',
            created_at          REAL NOT NULL,
            updated_at          REAL NOT NULL,
            UNIQUE(derived_owner_type, derived_owner_id, evidence_kind)
        );
        """

    static let createReviewLifecycleEvents = """
        CREATE TABLE IF NOT EXISTS review_lifecycle_events (
            id                  TEXT PRIMARY KEY,
            owner_type          TEXT NOT NULL,
            owner_id            TEXT NOT NULL,
            candidate_ref       TEXT,
            lifecycle_state     TEXT NOT NULL,
            event_kind          TEXT NOT NULL,
            actor               TEXT NOT NULL,
            source              TEXT NOT NULL,
            tool_name           TEXT,
            reason              TEXT,
            decision_note       TEXT,
            source_evidence_id  TEXT,
            source_evidence_ref TEXT,
            supersedes_ref      TEXT,
            invalidates_ref     TEXT,
            corrects_ref        TEXT,
            metadata            TEXT,
            created_at          REAL NOT NULL,
            FOREIGN KEY (source_evidence_id) REFERENCES source_evidence(id) ON DELETE SET NULL
        );
        """

    static let createRecallAccessEvents = """
        CREATE TABLE IF NOT EXISTS recall_access_events (
            id                TEXT PRIMARY KEY,
            surface           TEXT NOT NULL,
            selector_kind     TEXT NOT NULL,
            query_hash        TEXT,
            query_length      INTEGER,
            query_token_count INTEGER,
            anchor_refs       TEXT NOT NULL DEFAULT '[]',
            surfaced_refs     TEXT NOT NULL DEFAULT '[]',
            reason_kinds      TEXT NOT NULL DEFAULT '[]',
            metadata          TEXT NOT NULL DEFAULT '{}',
            created_at        REAL NOT NULL
        );
        """

    static let createFactValidityCandidates = """
        CREATE TABLE IF NOT EXISTS fact_validity_candidates (
            id                  TEXT PRIMARY KEY,
            target_ref          TEXT NOT NULL,
            proposed_state      TEXT NOT NULL,
            valid_at            REAL,
            invalid_at          REAL,
            expired_at          REAL,
            supersedes_ref      TEXT,
            superseded_by_ref   TEXT,
            source_owner_type   TEXT NOT NULL,
            source_owner_id     TEXT NOT NULL,
            source_quote        TEXT NOT NULL DEFAULT '',
            reason              TEXT NOT NULL DEFAULT '',
            review_state        TEXT NOT NULL DEFAULT 'suggested',
            source              TEXT NOT NULL,
            actor               TEXT NOT NULL,
            source_evidence_id  TEXT,
            source_evidence_ref TEXT,
            decision_note       TEXT,
            metadata            TEXT NOT NULL DEFAULT '{}',
            created_at          REAL NOT NULL,
            updated_at          REAL NOT NULL,
            reviewed_at         REAL,
            FOREIGN KEY (source_evidence_id) REFERENCES source_evidence(id) ON DELETE SET NULL
        );
        """

    static let createEntityResolutionCandidates = """
        CREATE TABLE IF NOT EXISTS entity_resolution_candidates (
            id                       TEXT PRIMARY KEY,
            candidate_type           TEXT NOT NULL,
            source_entity_type       TEXT NOT NULL,
            source_entity_id         TEXT NOT NULL,
            source_label             TEXT NOT NULL,
            input_mention            TEXT NOT NULL,
            target_entity_type       TEXT NOT NULL,
            target_entity_id         TEXT NOT NULL,
            target_label             TEXT NOT NULL,
            source_owner_type        TEXT NOT NULL,
            source_owner_id          TEXT NOT NULL,
            source_quote             TEXT NOT NULL DEFAULT '',
            confidence               REAL,
            confidence_reasons       TEXT NOT NULL DEFAULT '[]',
            conflicts_json           TEXT NOT NULL DEFAULT '[]',
            review_state             TEXT NOT NULL DEFAULT 'suggested',
            source                   TEXT NOT NULL,
            actor                    TEXT NOT NULL,
            source_evidence_id       TEXT,
            source_evidence_ref      TEXT,
            accepted_relation_id     TEXT,
            decision_note            TEXT,
            metadata                 TEXT NOT NULL DEFAULT '{}',
            created_at               REAL NOT NULL,
            updated_at               REAL NOT NULL,
            reviewed_at              REAL,
            UNIQUE(candidate_type, source_entity_type, source_entity_id, target_entity_type, target_entity_id, source)
        );
        """

    static let createSimilarityCandidates = """
        CREATE TABLE IF NOT EXISTS similarity_candidates (
            id                 TEXT PRIMARY KEY,
            source_owner_type  TEXT NOT NULL,
            source_owner_id    TEXT NOT NULL,
            target_owner_type  TEXT NOT NULL,
            target_owner_id    TEXT NOT NULL,
            candidate_type     TEXT NOT NULL,
            signal             TEXT NOT NULL,
            score              REAL NOT NULL,
            reason             TEXT NOT NULL DEFAULT '',
            evidence           TEXT NOT NULL DEFAULT '',
            source             TEXT NOT NULL,
            review_state       TEXT NOT NULL DEFAULT 'suggested',
            metadata           TEXT NOT NULL DEFAULT '{}',
            created_at         REAL NOT NULL,
            updated_at         REAL NOT NULL,
            reviewed_at        REAL,
            UNIQUE(source_owner_type, source_owner_id, target_owner_type, target_owner_id, candidate_type, signal, source)
        );
        """

    static let createSimilarityReconciliationRuns = """
        CREATE TABLE IF NOT EXISTS similarity_reconciliation_runs (
            id                 TEXT PRIMARY KEY,
            owner_type         TEXT,
            owner_id           TEXT,
            trigger            TEXT NOT NULL,
            scope              TEXT NOT NULL,
            threshold          REAL NOT NULL,
            candidate_limit    INTEGER NOT NULL,
            selected_count     INTEGER NOT NULL,
            created_count      INTEGER NOT NULL,
            updated_count      INTEGER NOT NULL,
            unchanged_count    INTEGER NOT NULL,
            stale_count        INTEGER NOT NULL,
            unseeded_count     INTEGER NOT NULL,
            candidate_families TEXT NOT NULL DEFAULT '{}',
            metadata           TEXT NOT NULL DEFAULT '{}',
            started_at         REAL NOT NULL,
            finished_at        REAL NOT NULL
        );
        """

    static let createSpaceMemberships = """
        CREATE TABLE IF NOT EXISTS space_memberships (
            space_id   TEXT NOT NULL,
            item_id    TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            item_type  TEXT NOT NULL,
            space_name TEXT NOT NULL,
            reason     TEXT NOT NULL DEFAULT '',
            confidence REAL,
            source     TEXT NOT NULL,
            actor      TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (space_id, item_id, item_type)
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

    static let createActionReceipts = """
        CREATE TABLE IF NOT EXISTS action_receipts (
            id                         TEXT PRIMARY KEY,
            command                    TEXT NOT NULL,
            action                     TEXT NOT NULL,
            actor                      TEXT NOT NULL,
            status                     TEXT NOT NULL,
            owner_type                 TEXT,
            owner_id                   TEXT,
            source_refs_json           TEXT NOT NULL DEFAULT '[]',
            evidence_refs_json         TEXT NOT NULL DEFAULT '[]',
            read_only                  INTEGER NOT NULL,
            changed                    INTEGER NOT NULL,
            before_json                TEXT,
            after_json                 TEXT,
            error_code                 TEXT,
            safe_verification_commands TEXT NOT NULL DEFAULT '[]',
            safe_next_commands         TEXT NOT NULL DEFAULT '[]',
            correlation_id             TEXT,
            receipt_json               TEXT NOT NULL DEFAULT '{}',
            created_at                 REAL NOT NULL
        );
        """

    // MARK: - Conversation Core

    static let createConversationRooms = """
        CREATE TABLE IF NOT EXISTS conversation_rooms (
            id                    TEXT PRIMARY KEY,
            stable_key            TEXT UNIQUE,
            title                 TEXT NOT NULL,
            kind                  TEXT NOT NULL DEFAULT 'chat',
            lifecycle_state       TEXT NOT NULL DEFAULT 'active',
            next_turn_sequence    INTEGER NOT NULL DEFAULT 1,
            next_message_sequence INTEGER NOT NULL DEFAULT 1,
            metadata_json         TEXT NOT NULL DEFAULT '{}',
            created_at            REAL NOT NULL,
            updated_at            REAL NOT NULL,
            archived_at           REAL,
            trashed_at            REAL
        );
        """

    static let createConversationRuntimeBindings = """
        CREATE TABLE IF NOT EXISTS conversation_runtime_bindings (
            id                  TEXT PRIMARY KEY,
            room_id             TEXT NOT NULL REFERENCES conversation_rooms(id) ON DELETE CASCADE,
            parent_binding_id   TEXT,
            runtime_id          TEXT NOT NULL,
            transport_id        TEXT NOT NULL,
            source_namespace    TEXT NOT NULL,
            external_session_id TEXT,
            binding_state       TEXT NOT NULL DEFAULT 'active',
            cursor_message_id   TEXT,
            cursor_timestamp    REAL,
            metadata_json       TEXT NOT NULL DEFAULT '{}',
            created_at          REAL NOT NULL,
            updated_at          REAL NOT NULL,
            UNIQUE(room_id, id),
            FOREIGN KEY(room_id, parent_binding_id)
                REFERENCES conversation_runtime_bindings(room_id, id)
                DEFERRABLE INITIALLY DEFERRED
        );
        """

    static let createConversationTurns = """
        CREATE TABLE IF NOT EXISTS conversation_turns (
            id                 TEXT PRIMARY KEY,
            room_id            TEXT NOT NULL REFERENCES conversation_rooms(id) ON DELETE CASCADE,
            sequence           INTEGER NOT NULL,
            runtime_binding_id TEXT,
            source_namespace   TEXT,
            source_turn_id     TEXT,
            status             TEXT NOT NULL,
            error_code         TEXT,
            error_detail       TEXT,
            metadata_json      TEXT NOT NULL DEFAULT '{}',
            created_at         REAL NOT NULL,
            started_at         REAL,
            completed_at       REAL,
            updated_at         REAL NOT NULL,
            UNIQUE(room_id, id),
            UNIQUE(room_id, sequence),
            CHECK (
                (source_namespace IS NULL AND source_turn_id IS NULL) OR
                (source_namespace IS NOT NULL AND source_turn_id IS NOT NULL)
            ),
            FOREIGN KEY(room_id, runtime_binding_id)
                REFERENCES conversation_runtime_bindings(room_id, id)
        );
        """

    static let createConversationMessages = """
        CREATE TABLE IF NOT EXISTS conversation_messages (
            id                 TEXT PRIMARY KEY,
            room_id            TEXT NOT NULL REFERENCES conversation_rooms(id) ON DELETE CASCADE,
            turn_id            TEXT,
            runtime_binding_id TEXT,
            parent_message_id  TEXT,
            sequence           INTEGER NOT NULL,
            role               TEXT NOT NULL,
            content_text       TEXT NOT NULL DEFAULT '',
            status             TEXT NOT NULL,
            finish_reason      TEXT,
            source_namespace   TEXT,
            source_message_id  TEXT,
            source_created_at  REAL,
            metadata_json      TEXT NOT NULL DEFAULT '{}',
            created_at         REAL NOT NULL,
            updated_at         REAL NOT NULL,
            UNIQUE(room_id, id),
            UNIQUE(room_id, sequence),
            CHECK (
                (source_namespace IS NULL AND source_message_id IS NULL) OR
                (source_namespace IS NOT NULL AND source_message_id IS NOT NULL)
            ),
            FOREIGN KEY(room_id, turn_id)
                REFERENCES conversation_turns(room_id, id),
            FOREIGN KEY(room_id, runtime_binding_id)
                REFERENCES conversation_runtime_bindings(room_id, id),
            FOREIGN KEY(room_id, parent_message_id)
                REFERENCES conversation_messages(room_id, id)
                DEFERRABLE INITIALLY DEFERRED
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
            target_space_id       TEXT,
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
        "CREATE INDEX IF NOT EXISTS idx_owner_relations_source ON owner_relations(source_owner_type, source_owner_id, relation_type, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_owner_relations_target ON owner_relations(target_owner_type, target_owner_id, relation_type, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_owner_relations_type ON owner_relations(relation_type, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_project_nodes_project ON project_nodes(project_id, lifecycle_state, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_project_node_events_node ON project_node_events(node_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_project_primary_path_order ON project_primary_path_memberships(project_id, ordinal);",
        "CREATE INDEX IF NOT EXISTS idx_owner_label_index_lookup ON owner_label_index(owner_kind, normalized_label, updated_at) WHERE is_deleted = 0;",
        "CREATE INDEX IF NOT EXISTS idx_owner_label_index_owner ON owner_label_index(owner_type, owner_id) WHERE is_deleted = 0;",
        "CREATE INDEX IF NOT EXISTS idx_capture_events_source ON capture_events(source_kind, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_capture_events_channel ON capture_events(channel, channel_id, message_id);",
        "CREATE INDEX IF NOT EXISTS idx_capture_attachments_event ON capture_attachments(capture_event_id, attachment_index);",
        "CREATE INDEX IF NOT EXISTS idx_capture_attachments_source ON capture_attachments(source_attachment_id) WHERE source_attachment_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_enrichment_outputs_owner ON enrichment_outputs(owner_type, owner_id, kind, review_state);",
        "CREATE INDEX IF NOT EXISTS idx_enrichment_outputs_kind ON enrichment_outputs(kind, normalized_value);",
        "CREATE INDEX IF NOT EXISTS idx_source_evidence_source ON source_evidence(source_owner_type, source_owner_id, evidence_kind, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_source_evidence_derived ON source_evidence(derived_owner_type, derived_owner_id, evidence_kind);",
        "CREATE INDEX IF NOT EXISTS idx_source_evidence_candidate ON source_evidence(candidate_ref) WHERE candidate_ref IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_review_lifecycle_owner ON review_lifecycle_events(owner_type, owner_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_review_lifecycle_candidate ON review_lifecycle_events(candidate_ref, created_at) WHERE candidate_ref IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_review_lifecycle_evidence ON review_lifecycle_events(source_evidence_id, created_at) WHERE source_evidence_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_review_lifecycle_state ON review_lifecycle_events(lifecycle_state, event_kind, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_recall_access_created ON recall_access_events(created_at);",
        "CREATE INDEX IF NOT EXISTS idx_recall_access_surface ON recall_access_events(surface, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_recall_access_query ON recall_access_events(query_hash, created_at) WHERE query_hash IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_fact_validity_target ON fact_validity_candidates(target_ref, review_state, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_fact_validity_review ON fact_validity_candidates(review_state, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_fact_validity_evidence ON fact_validity_candidates(source_evidence_id) WHERE source_evidence_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_entity_resolution_review ON entity_resolution_candidates(review_state, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_entity_resolution_source ON entity_resolution_candidates(source_entity_type, source_entity_id, review_state);",
        "CREATE INDEX IF NOT EXISTS idx_entity_resolution_target ON entity_resolution_candidates(target_entity_type, target_entity_id, review_state);",
        "CREATE INDEX IF NOT EXISTS idx_entity_resolution_evidence ON entity_resolution_candidates(source_evidence_id) WHERE source_evidence_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_source ON similarity_candidates(source_owner_type, source_owner_id, review_state, score);",
        "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_target ON similarity_candidates(target_owner_type, target_owner_id, review_state, score);",
        "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_review ON similarity_candidates(review_state, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_similarity_reconciliation_owner ON similarity_reconciliation_runs(owner_type, owner_id, started_at);",
        "CREATE INDEX IF NOT EXISTS idx_similarity_reconciliation_trigger ON similarity_reconciliation_runs(trigger, started_at);",
        "CREATE INDEX IF NOT EXISTS idx_space_memberships_item ON space_memberships(item_id, item_type);",
        "CREATE INDEX IF NOT EXISTS idx_space_memberships_space ON space_memberships(space_id, updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_item_sections_owner ON item_sections(owner_type, owner_id, sort_order);",
        "CREATE INDEX IF NOT EXISTS idx_item_sections_item ON item_sections(item_id) WHERE item_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_content_chunks_owner ON content_chunks(owner_type, owner_id, chunk_index);",
        "CREATE INDEX IF NOT EXISTS idx_content_chunks_section ON content_chunks(section_id) WHERE section_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS idx_agent_actions_owner ON agent_actions(owner_type, owner_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_agent_actions_tool ON agent_actions(tool_name, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_action_receipts_created ON action_receipts(created_at);",
        "CREATE INDEX IF NOT EXISTS idx_action_receipts_owner ON action_receipts(owner_type, owner_id, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_action_receipts_action ON action_receipts(action, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_action_receipts_actor ON action_receipts(actor, created_at);",
        "CREATE INDEX IF NOT EXISTS idx_action_receipts_status ON action_receipts(status, created_at);",
        "CREATE UNIQUE INDEX IF NOT EXISTS conversation_binding_external_identity ON conversation_runtime_bindings(source_namespace, external_session_id) WHERE external_session_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS conversation_bindings_room ON conversation_runtime_bindings(room_id, binding_state, created_at);",
        "CREATE UNIQUE INDEX IF NOT EXISTS conversation_turn_source_identity ON conversation_turns(source_namespace, source_turn_id) WHERE source_namespace IS NOT NULL AND source_turn_id IS NOT NULL;",
        "CREATE UNIQUE INDEX IF NOT EXISTS conversation_message_source_identity ON conversation_messages(source_namespace, source_message_id) WHERE source_namespace IS NOT NULL AND source_message_id IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS conversation_messages_room_order ON conversation_messages(room_id, sequence);",
        "CREATE INDEX IF NOT EXISTS conversation_messages_parent ON conversation_messages(room_id, parent_message_id, sequence);",
        "CREATE INDEX IF NOT EXISTS conversation_messages_turn ON conversation_messages(room_id, turn_id, sequence);",
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
        createOwnerRelations,
        createProjects,
        createProjectGraphStates,
        createProjectNodes,
        createProjectPrimaryPathMemberships,
        createProjectNodeEvents,
        createOwnerLabelIndex,
        createCaptureEvents,
        createCaptureAttachments,
        createEnrichmentOutputs,
        createSourceEvidence,
        createReviewLifecycleEvents,
        createRecallAccessEvents,
        createFactValidityCandidates,
        createEntityResolutionCandidates,
        createSimilarityCandidates,
        createSimilarityReconciliationRuns,
        createSpaceMemberships,
        createItemSections,
        createContentChunks,
        createContentChunksFTS,
        createContentChunksFTSInsertTrigger,
        createContentChunksFTSDeleteTrigger,
        createContentChunksFTSUpdateTrigger,
        createRoutingDecisions,
        createSecondBrainRoutingDecisions,
        createAgentActions,
        createActionReceipts,
        createConversationRooms,
        createConversationRuntimeBindings,
        createConversationTurns,
        createConversationMessages,
        createTrash,
        createMutationAudit,
        createFolderSyncDecisions,
        createSchemaMigrations,
    ]
}
