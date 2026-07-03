import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Item Context Service Tests")
@MainActor
struct CiderItemContextServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-context-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func insertItem(
        _ ref: LibraryEntityRef,
        title: String,
        relativePath: String?,
        into db: CiderDatabase,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(createdAt), at: 4)
            .bind(DatabaseHelpers.encode(updatedAt), at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    private func tagItem(
        _ ref: LibraryEntityRef,
        tags: [String],
        in db: CiderDatabase
    ) throws {
        let findTag = try db.prepare("SELECT id FROM tags WHERE name = ?;")
        let createTag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
        let insertItemTag = try db.prepare("INSERT OR IGNORE INTO item_tags (item_id, tag_id) VALUES (?, ?);")

        for tag in tags {
            let tagName = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tagName.isEmpty else { continue }

            findTag.reset()
            findTag.bind(tagName, at: 1)
            let tagID: String
            if try findTag.step() {
                tagID = findTag.string(at: 0)
            } else {
                tagID = UUID().uuidString
                createTag.reset()
                createTag.bind(tagID, at: 1)
                    .bind(tagName, at: 2)
                try createTag.step()
            }

            insertItemTag.reset()
            insertItemTag.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
                .bind(tagID, at: 2)
            try insertItemTag.step()
        }
    }

    private func insertCaptureEvent(
        id: UUID,
        sourceKind: String,
        surface: String,
        channel: String,
        messageID: String,
        sourceText: String,
        createdAt: Date,
        into db: CiderDatabase
    ) throws {
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?, NULL, NULL, ?, 0, ?, ?);
            """)
        insertEvent.bind(id.uuidString, at: 1)
            .bind(sourceKind, at: 2)
            .bind(surface, at: 3)
            .bind(channel, at: 4)
            .bind(messageID, at: 5)
            .bind("codex", at: 6)
            .bind("Codex", at: 7)
            .bind(sourceText, at: 8)
            .bind(DatabaseHelpers.encodeJSON(["test": "library-hub"]) ?? "{}", at: 9)
            .bind(DatabaseHelpers.encode(createdAt), at: 10)
        try insertEvent.step()
    }

    @Test("context bundle includes item identity, sections, chunks, and related items")
    func contextBundleIncludesIdentitySectionsChunksAndRelatedItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and check insurance first.",
                source: "test",
                sortOrder: 0
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Dentist follow-up",
                body: "Call the dentist and check insurance first.",
                chunkIndex: 0
            )
        ])

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(database: db, linkService: linkService, secondBrainStore: store)

        let bundle = try service.context(for: note)

        #expect(bundle.item.id == note.entityID)
        #expect(bundle.item.type == .note)
        #expect(bundle.item.title == "Dentist follow-up")
        #expect(bundle.item.relativePath == "Inbox/Notes/Dentist follow-up.md")
        #expect(bundle.sections.map(\.sectionKey) == ["summary"])
        #expect(bundle.chunks.map(\.body) == ["Call the dentist and check insurance first."])
        #expect(bundle.related.map(\.title) == ["Dental insurance portal"])
    }

    @Test("captured item context exposes capture source context")
    func capturedItemContextExposesCaptureSourceContext() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Dogfood graph backend capture", relativePath: "Inbox/Notes/Dogfood graph backend capture.md", into: db)

        let eventID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_745_084_400)
        let metadata = DatabaseHelpers.encodeJSON(["workspace": "Cider"]) ?? "{}"
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        insertEvent.bind(eventID.uuidString, at: 1)
            .bind("text", at: 2)
            .bind("codex_dogfood", at: 3)
            .bind("cli", at: 4)
            .bind("local", at: 5)
            .bind("thread-42", at: 6)
            .bind("dogfood-2026-05-19", at: 7)
            .bind("codex", at: 8)
            .bind("Codex", at: 9)
            .bind(String?.none, at: 10)
            .bind(String?.none, at: 11)
            .bind("Original dogfood capture text", at: 12)
            .bind(0, at: 13)
            .bind(metadata, at: 14)
            .bind(DatabaseHelpers.encode(createdAt), at: 15)
        try insertEvent.step()

        let store = SecondBrainStore(database: db)
        let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: captureOwner,
            targetOwner: noteOwner,
            relationType: "produced_item",
            evidence: "Capture event produced note Dogfood graph backend capture.",
            source: "capture.add",
            actor: "system",
            confidence: 1,
            metadata: ["command": "capture.add"]
        ))

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let bundle = try service.context(for: note)

        #expect(bundle.captureProvenance.count == 1)
        #expect(bundle.captureProvenance[0].eventID == eventID.uuidString)
        #expect(bundle.captureProvenance[0].surface == "codex_dogfood")
        #expect(bundle.captureProvenance[0].channel == "cli")
        #expect(bundle.captureProvenance[0].messageID == "dogfood-2026-05-19")
        #expect(bundle.captureProvenance[0].senderID == "codex")
        #expect(bundle.captureProvenance[0].sourceText == "Original dogfood capture text")
        #expect(bundle.captureProvenance[0].metadata["workspace"] == "Cider")

        let dict = CiderCLI.itemContextBundleToDict(bundle)
        let provenance = try #require(dict["captureProvenance"] as? [[String: Any]])
        #expect(provenance.count == 1)
        #expect(provenance[0]["surface"] as? String == "codex_dogfood")
        #expect(provenance[0]["channel"] as? String == "cli")
        #expect(provenance[0]["messageID"] as? String == "dogfood-2026-05-19")

        let packet = try service.agentContext(for: note)
        #expect(packet.provenance.contains("capture:codex_dogfood/cli"))
        #expect(packet.captureProvenance.map(\.eventID) == [eventID.uuidString])
    }

    @Test("library hub groups related captures by source type relation and provenance without promoting candidates")
    func libraryHubGroupsRelatedCapturesBySourceTypeRelationAndProvenance() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let base = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let guide = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let buildNote = LibraryEntityRef(type: .note, entityID: UUID())
        let now = Date(timeIntervalSince1970: 1_767_000_000)
        try insertItem(base, title: "World of Warcraft Hub", relativePath: "Bookmarks/Games/World of Warcraft.webloc", into: db, createdAt: now, updatedAt: now)
        try insertItem(guide, title: "WoW Priest Guide", relativePath: "Bookmarks/Games/WoW Priest Guide.webloc", into: db, createdAt: now, updatedAt: now.addingTimeInterval(10))
        try insertItem(buildNote, title: "WoW mythic build notes", relativePath: "Notes/Games/WoW mythic build notes.md", into: db, createdAt: now, updatedAt: now.addingTimeInterval(20))

        let store = SecondBrainStore(database: db)
        let baseOwner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: base.entityID.uuidString)
        let guideOwner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: guide.entityID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: buildNote.entityID.uuidString)

        try store.recordRelation(SecondBrainRelation(
            sourceOwner: baseOwner,
            targetOwner: guideOwner,
            relationType: "source_for",
            evidence: "Base WoW bookmark is the source hub for the guide bookmark.",
            source: "test.accepted-link",
            actor: "Codex",
            confidence: 1
        ))
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: noteOwner,
            targetOwner: baseOwner,
            relationType: "related_to",
            evidence: "Build notes explicitly link back to the World of Warcraft hub.",
            source: "test.accepted-link",
            actor: "Codex",
            confidence: 1
        ))

        let guideCaptureID = UUID()
        let noteCaptureID = UUID()
        try insertCaptureEvent(
            id: guideCaptureID,
            sourceKind: "bookmark",
            surface: "cider-cli",
            channel: "cli",
            messageID: "wow-guide",
            sourceText: "Captured WoW priest guide URL.",
            createdAt: now.addingTimeInterval(30),
            into: db
        )
        try insertCaptureEvent(
            id: noteCaptureID,
            sourceKind: "journal",
            surface: "voice",
            channel: "driving",
            messageID: "wow-build-note",
            sourceText: "Remember WoW mythic build details.",
            createdAt: now.addingTimeInterval(40),
            into: db
        )
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: guideCaptureID.uuidString),
            targetOwner: guideOwner,
            relationType: "produced_item",
            evidence: "Capture produced guide bookmark.",
            source: "capture.add",
            actor: "system",
            confidence: 1
        ))
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: noteCaptureID.uuidString),
            targetOwner: noteOwner,
            relationType: "produced_item",
            evidence: "Capture produced build note.",
            source: "capture.add",
            actor: "system",
            confidence: 1
        ))

        try SecondBrainEnrichmentOutputService(database: db).record(SecondBrainEnrichmentOutput(
            owner: baseOwner,
            chunkID: nil,
            kind: SecondBrainGraphCandidateContract.outputKind,
            value: "WoW raid group",
            normalizedValue: "wow raid group",
            label: "Possible related object",
            evidence: "Maybe this belongs with the WoW raid group too.",
            source: "test.graph-candidate",
            confidence: 0.62,
            reviewState: "needs_review",
            metadata: [
                SecondBrainGraphCandidateContract.MetadataKey.candidateKind: "object_relation",
                SecondBrainGraphCandidateContract.MetadataKey.relationGuesses: "related_to",
            ]
        ))

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let hub = try service.libraryHub(for: base)

        #expect(hub.anchor.item.title == "World of Warcraft Hub")
        #expect(hub.relatedItems.map(\.item.title).contains("WoW Priest Guide"))
        #expect(hub.relatedItems.map(\.item.title).contains("WoW mythic build notes"))
        #expect(hub.domainFacets.contains {
            $0.kind == "domain" && $0.key == "games" && $0.confidenceLabel == "source_backed"
        })
        #expect(hub.domainFacets.contains {
            $0.kind == "entity_type" && $0.key == "game" && $0.confidenceLabel == "source_backed"
        })
        #expect(hub.domainFacets.contains {
            $0.kind == "alias" && $0.key == "wow" && $0.displayValue == "WoW"
        })
        #expect(hub.domainFacets.contains {
            $0.kind == "alias" && $0.key == "world_of_warcraft" && $0.displayValue == "World of Warcraft"
        })
        #expect(hub.relatedItems.flatMap(\.captureProvenance).map(\.sourceKind).contains("bookmark"))
        #expect(hub.relatedItems.flatMap(\.captureProvenance).map(\.sourceKind).contains("journal"))
        #expect(hub.groups.contains { $0.kind == "type" && $0.key == "bookmark" })
        #expect(hub.groups.contains { $0.kind == "type" && $0.key == "note" })
        #expect(hub.groups.contains { $0.kind == "relation" && $0.key == "source_for" })
        #expect(hub.groups.contains { $0.kind == "relation" && $0.key == "related_to" })
        #expect(hub.groups.contains { $0.kind == "provenance" && $0.key == "cider-cli" })
        #expect(hub.groups.contains { $0.kind == "provenance" && $0.key == "voice" })
        #expect(hub.reviewableCandidates.count == 1)
        #expect(hub.reviewableCandidates[0].reviewState == "needs_review")
        #expect(hub.safeNextCommands.contains("cider-cli item hub bookmark \(base.entityID.uuidString) --json"))

        let dict = CiderCLI.libraryHubReadModelToDict(hub)
        let hubDict = try #require(dict["hub"] as? [String: Any])
        let facets = try #require(hubDict["domainFacets"] as? [[String: Any]])
        #expect(facets.contains {
            $0["kind"] as? String == "alias"
                && $0["key"] as? String == "wow"
                && $0["truthBoundary"] as? String == "interpretive_metadata_not_accepted_truth"
        })
        #expect(facets.contains {
            $0["kind"] as? String == "domain"
                && $0["key"] as? String == "games"
                && $0["confidenceLabel"] as? String == "source_backed"
        })
        let boundary = try #require(hubDict["truthBoundary"] as? [String: Any])
        #expect(boundary["reviewableCandidatesAreTruth"] as? Bool == false)
        #expect(boundary["domainFacetsAreTruth"] as? Bool == false)
        #expect(boundary["autoMutatedUserFields"] as? Bool == false)
        let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item graph-candidates bookmark \(base.entityID.uuidString) --json"))
        #expect(safeNextCommands.contains("cider-cli item hub --query \"WoW\" --limit 5 --json"))
        #expect(safeNextCommands.contains("cider-cli item hub --query \"World of Warcraft\" --limit 5 --json"))
    }

    @Test("library hub exposes media and restaurant facets from source-backed metadata without promotion")
    func libraryHubExposesMediaAndRestaurantFacetsFromMetadataWithoutPromotion() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let movie = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let restaurant = LibraryEntityRef(type: .note, entityID: UUID())
        let now = Date(timeIntervalSince1970: 1_767_001_000)
        try insertItem(movie, title: "The Way Way Back movie", relativePath: "Bookmarks/Media/Movies/The Way Way Back.webloc", into: db, createdAt: now, updatedAt: now)
        try insertItem(restaurant, title: "Cactus Tacoma dinner notes", relativePath: "Notes/Restaurants/Tacoma/Cactus.md", into: db, createdAt: now, updatedAt: now.addingTimeInterval(10))

        let store = SecondBrainStore(database: db)
        let movieOwner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: movie.entityID.uuidString)
        let restaurantOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: restaurant.entityID.uuidString)

        try store.recordRelation(SecondBrainRelation(
            sourceOwner: movieOwner,
            targetOwner: restaurantOwner,
            relationType: "related_to",
            evidence: "Movie night note also mentioned Cactus in Tacoma.",
            source: "test.accepted-link",
            actor: "Codex",
            confidence: 1
        ))

        try SecondBrainEnrichmentOutputService(database: db).record(SecondBrainEnrichmentOutput(
            owner: movieOwner,
            chunkID: nil,
            kind: SecondBrainGraphCandidateContract.outputKind,
            value: "The Way Way Back",
            normalizedValue: "the way way back",
            label: "Possible movie",
            evidence: "I watched The Way Way Back last night.",
            source: "test.graph-candidate",
            confidence: 0.8,
            reviewState: "suggested",
            metadata: [
                SecondBrainGraphCandidateContract.MetadataKey.candidateKind: "object_relation",
                SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses: "movie, media",
                SecondBrainGraphCandidateContract.MetadataKey.relationGuesses: "watched",
            ]
        ))
        try SecondBrainEnrichmentOutputService(database: db).record(SecondBrainEnrichmentOutput(
            owner: restaurantOwner,
            chunkID: nil,
            kind: SecondBrainGraphCandidateContract.outputKind,
            value: "Cactus",
            normalizedValue: "cactus",
            label: "Possible restaurant",
            evidence: "We went to Cactus in Tacoma.",
            source: "test.graph-candidate",
            confidence: 0.72,
            reviewState: "needs_review",
            metadata: [
                SecondBrainGraphCandidateContract.MetadataKey.candidateKind: "object_candidate",
                SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses: "restaurant, place",
            ]
        ))

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let movieHub = try service.libraryHub(for: movie)
        #expect(movieHub.domainFacets.contains { $0.kind == "domain" && $0.key == "media" })
        #expect(movieHub.domainFacets.contains { $0.kind == "entity_type" && $0.key == "movie" && $0.confidenceLabel == "source_backed" })
        #expect(movieHub.domainFacets.contains { $0.kind == "entity_type" && $0.key == "restaurant" })
        #expect(movieHub.domainFacets.contains { $0.kind == "place" && $0.key == "tacoma" && $0.displayValue == "Tacoma" })

        let dict = CiderCLI.libraryHubReadModelToDict(movieHub)
        let hubDict = try #require(dict["hub"] as? [String: Any])
        let facets = try #require(hubDict["domainFacets"] as? [[String: Any]])
        #expect(facets.contains {
            $0["kind"] as? String == "entity_type"
                && $0["key"] as? String == "movie"
                && $0["truthBoundary"] as? String == "interpretive_metadata_not_accepted_truth"
        })
        let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item hub --query \"The Way Way Back movie\" --limit 5 --json"))
        #expect(safeNextCommands.contains("cider-cli item hub --query \"Cactus Tacoma dinner notes\" --limit 5 --json"))
    }

    @Test("item context and home overview share recent capture surfacing for unfiled bookmarks")
    func itemContextAndHomeOverviewShareRecentCaptureSurfacingForUnfiledBookmarks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmarkID = UUID()
        let ref = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        try insertItem(
            ref,
            title: "Saved Article",
            relativePath: "Inbox/Bookmarks/Saved Article.webloc",
            into: db
        )

        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Saved Article",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-60),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: nil,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark)],
            recentItems: [.bookmark(bookmark)],
            folders: [],
            surfacingDays: 7,
            now: now
        )

        let packet = try CiderItemContextService(database: db).agentContext(for: ref)
        let homeSurfacing = try #require(snapshot.recentCaptureItems.first?.surfacingExplanation)

        #expect(packet.surfacing.reviewState == homeSurfacing.reviewState)
        #expect(packet.surfacing.suggestedAction == homeSurfacing.suggestedAction)
        #expect(packet.surfacing.reviewState == "ok")
        #expect(packet.surfacing.suggestedAction == "Open")
    }

    @Test("search returns item title matches and chunk text matches through one surface")
    func searchReturnsItemTitleMatchesAndChunkTextMatchesThroughOneSurface() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteCreatedAt = Date(timeIntervalSince1970: 1_747_000_000)
        let noteUpdatedAt = Date(timeIntervalSince1970: 1_747_003_600)
        let dentist = LibraryEntityRef(type: .note, entityID: UUID())
        let renewal = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(
            dentist,
            title: "Dentist follow-up",
            relativePath: "Inbox/Notes/Dentist follow-up.md",
            into: db,
            createdAt: noteCreatedAt,
            updatedAt: noteUpdatedAt
        )
        try insertItem(renewal, title: "Review home insurance", relativePath: "Inbox/Todos/Review home insurance.md", into: db)

        let store = SecondBrainStore(database: db)
        let eventID = UUID()
        let captureCreatedAt = Date(timeIntervalSince1970: 1_746_999_000)
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        insertEvent.bind(eventID.uuidString, at: 1)
            .bind("text", at: 2)
            .bind("codex_dogfood", at: 3)
            .bind("cli", at: 4)
            .bind("local", at: 5)
            .bind("thread-42", at: 6)
            .bind("capture-2026-05-11", at: 7)
            .bind("codex", at: 8)
            .bind("Codex", at: 9)
            .bind(String?.none, at: 10)
            .bind(String?.none, at: 11)
            .bind("Dentist follow-up capture text", at: 12)
            .bind(0, at: 13)
            .bind("{}", at: 14)
            .bind(DatabaseHelpers.encode(captureCreatedAt), at: 15)
        try insertEvent.step()

        let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
        let dentistOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: dentist.entityID.uuidString)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: captureOwner,
            targetOwner: dentistOwner,
            relationType: "produced_item",
            evidence: "Capture event produced note Dentist follow-up.",
            source: "capture.add",
            actor: "system",
            confidence: 1,
            metadata: ["command": "capture.add"]
        ))

        let owner = SecondBrainOwnerRef(ownerType: "todo", ownerID: renewal.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: renewal.entityID.uuidString,
                source: "test",
                title: "Insurance renewal",
                body: "The renewal window opens in September.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let titleMatches = try service.search("dentist", limit: 10)
        #expect(titleMatches.contains {
            $0.kind == .item && $0.item?.id == dentist.entityID && $0.title == "Dentist follow-up"
        })
        let noteResult = try #require(titleMatches.first {
            $0.kind == .item && $0.item?.id == dentist.entityID
        })
        let noteResultDict = CiderCLI.itemSearchResultToDict(noteResult)
        #expect(noteResultDict["id"] as? String == "item-\(dentist.entityID.uuidString)")
        #expect(noteResultDict["kind"] as? String == "item")
        #expect(noteResultDict["title"] as? String == "Dentist follow-up")
        #expect(noteResultDict["snippet"] as? String == "Inbox/Notes/Dentist follow-up.md")
        #expect(noteResultDict["rank"] as? Double != nil)
        #expect(noteResultDict["createdAt"] as? String == ISO8601DateFormatter().string(from: noteCreatedAt))
        #expect(noteResultDict["updatedAt"] as? String == ISO8601DateFormatter().string(from: noteUpdatedAt))
        #expect(noteResultDict["sourceRef"] as? [String: String] == [
            "type": "note",
            "ref": dentist.entityID.uuidString,
        ])
        #expect(noteResultDict["owner"] as? [String: String] == [
            "ownerType": "note",
            "ownerID": dentist.entityID.uuidString,
            "ref": "note:\(dentist.entityID.uuidString)",
        ])
        #expect((noteResultDict["item"] as? [String: Any])?["type"] as? String == "note")
        let captureProvenance = try #require(noteResultDict["captureProvenance"] as? [[String: Any]])
        #expect(captureProvenance.count == 1)
        #expect(captureProvenance[0]["eventID"] as? String == eventID.uuidString)
        #expect(captureProvenance[0]["createdAt"] as? String == ISO8601DateFormatter().string(from: captureCreatedAt))
        let safeNextCommands = try #require(noteResultDict["safeNextCommands"] as? [String])
        #expect(safeNextCommands == [
            "cider-cli item context note \(dentist.entityID.uuidString) --json",
            "cider-cli item hub note \(dentist.entityID.uuidString) --json",
        ])
        #expect(!safeNextCommands.contains { command in
            command.contains(" delete ")
                || command.contains(" move ")
                || command.contains(" route ")
                || command.contains(" review ")
        })

        let chunkMatches = try service.search("renewal window", limit: 10)
        #expect(chunkMatches.contains {
            $0.kind == .chunk && $0.item?.id == renewal.entityID && $0.owner.ownerType == "todo"
        })
    }

    @Test("recent item read model returns bounded updated items with stable identity")
    func recentItemReadModelReturnsBoundedUpdatedItemsWithStableIdentity() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let recentNote = LibraryEntityRef(type: .note, entityID: UUID())
        let recentBookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let olderTodo = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(
            recentNote,
            title: "Main Brain recent note",
            relativePath: "Inbox/Notes/Main Brain recent note.md",
            into: db,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-30)
        )
        try insertItem(
            recentBookmark,
            title: "Shared context bookmark",
            relativePath: "Inbox/Bookmarks/Shared context bookmark.url",
            into: db,
            createdAt: now.addingTimeInterval(-180),
            updatedAt: now.addingTimeInterval(-60)
        )
        try insertItem(
            olderTodo,
            title: "Older isolated store task",
            relativePath: "Inbox/Todos/Older isolated store task.md",
            into: db,
            createdAt: now.addingTimeInterval(-90_000),
            updatedAt: now.addingTimeInterval(-90_000)
        )

        let service = CiderItemContextService(database: db, nowProvider: { now })
        let recent = try service.recentItems(since: now.addingTimeInterval(-3600), limit: 10)

        #expect(recent.map(\.id) == [recentNote.entityID, recentBookmark.entityID])
        #expect(recent.map(\.type) == [.note, .bookmark])
        #expect(recent.map(\.relativePath) == [
            "Inbox/Notes/Main Brain recent note.md",
            "Inbox/Bookmarks/Shared context bookmark.url",
        ])
    }

    @Test("search diagnostics explain FTS chunk hits with item routing and safe commands")
    func searchDiagnosticsExplainChunkHitsWithItemContext() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Saffron recall note", relativePath: "Inbox/Notes/Saffron recall note.md", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Saffron memory",
                body: "The saffron diagnostic token should be visible through FTS.",
                chunkIndex: 0
            )
        ])
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: note.entityID.uuidString,
                targetType: "folder",
                targetPath: "Projects/Cider/Recall",
                confidence: 0.82,
                reason: "Recall diagnostics work belongs with Cider.",
                status: "accepted",
                actor: "agent",
                source: "routing.test"
            )
        )

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let report = try service.searchDiagnostics("saffron diagnostic", limit: 10)

        #expect(report.query == "saffron diagnostic")
        #expect(report.exactMatches.contains { $0.item?.id == note.entityID })
        #expect(report.fallbackStages.contains { $0.name == "original_query" })
        #expect(report.matchedChunks.contains {
            $0.chunk.owner == owner
                && $0.item?.id == note.entityID
                && $0.routingDecisions.map(\.targetPath).contains("Projects/Cider/Recall")
                && $0.indexFreshness.status == "fresh"
        })
        #expect(report.semanticStatus.available == false)
        #expect(report.semanticStatus.status == "unavailable")
        #expect(report.safeNextCommands.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(report.safeNextCommands.contains("cider-cli item rebuild-chunks note \(note.entityID.uuidString) --json"))

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        #expect(dict["command"] as? String == "item.search-debug")
        #expect(dict["readOnly"] as? Bool == true)
        #expect(dict["changed"] as? Bool == false)
        #expect((dict["matchedChunks"] as? [[String: Any]])?.isEmpty == false)
        #expect((dict["semanticStatus"] as? [String: Any])?["status"] as? String == "unavailable")
        #expect((dict["safeNextCommands"] as? [String])?.contains("cider-cli item rebuild-chunks note \(note.entityID.uuidString) --json") == true)
        let receipt = try #require(dict["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.search-debug")
        #expect(receipt["commandFamily"] as? String == "item")
        #expect(receipt["subcommand"] as? String == "search-debug")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["status"] as? String == "succeeded")
        #expect(receipt["matchedCount"] as? Int == 1)
        #expect((receipt["matchedSourceRefs"] as? [String])?.contains("note:\(note.entityID.uuidString)") == true)
        #expect((receipt["provenanceRefs"] as? [String])?.contains("note:\(note.entityID.uuidString)") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item get note \(note.entityID.uuidString) --json") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item rebuild-chunks note \(note.entityID.uuidString) --json") == true)
        #expect(receipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
    }

    @Test("search diagnostics explain unavailable semantic recall surface")
    func searchDiagnosticsExplainUnavailableSemanticRecallSurface() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("paperwork I saved for executive function help", limit: 5)

        #expect(report.semanticStatus.available == false)
        #expect(report.semanticStatus.status == "unavailable")
        #expect(report.semanticStatus.mode == "supplemental")
        #expect(report.semanticStatus.candidateCount == 0)
        #expect(report.semanticStatus.candidates.isEmpty)
        #expect(report.semanticStatus.requiresRebuild == true)
        #expect(report.semanticStatus.safeNextCommands.contains("cider-cli item doctor --json"))
        #expect(report.warnings.contains {
            $0.kind == "semantic_recall_unavailable"
                && $0.message.contains("semantic/vector recall")
        })

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        let semantic = try #require(dict["semanticStatus"] as? [String: Any])
        #expect(semantic["mode"] as? String == "supplemental")
        #expect(semantic["candidateCount"] as? Int == 0)
        #expect(semantic["requiresRebuild"] as? Bool == true)
        #expect((semantic["candidates"] as? [[String: Any]])?.isEmpty == true)
        #expect((semantic["safeNextCommands"] as? [String])?.contains("cider-cli item doctor --json") == true)
    }

    @Test("search diagnostics return machine readable no match warnings")
    func searchDiagnosticsReturnNoMatchWarnings() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Ordinary recall note", relativePath: "Inbox/Notes/Ordinary recall note.md", into: db)

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("missing-zircon-token", limit: 10)

        #expect(report.exactMatches.isEmpty)
        #expect(report.matchedChunks.isEmpty)
        #expect(report.warnings.contains { $0.kind == "no_matches" })
        #expect(report.safeNextCommands.contains("cider-cli item search \"missing-zircon-token\" --limit 10 --json"))

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        let receipt = try #require(dict["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.search-debug")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["status"] as? String == "succeeded")
        #expect(receipt["matchedCount"] as? Int == 0)
        #expect((receipt["matchedSourceRefs"] as? [String])?.isEmpty == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item search \"missing-zircon-token\" --limit 10 --json") == true)
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
    }

    @Test("search diagnostics identify missing and stale item chunk indexes")
    func searchDiagnosticsIdentifyMissingAndStaleIndexes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let missing = LibraryEntityRef(type: .note, entityID: UUID())
        let stale = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(missing, title: "Nebula missing index", relativePath: "Inbox/Notes/Nebula missing index.md", into: db)
        try insertItem(stale, title: "Nebula stale index", relativePath: "Inbox/Notes/Nebula stale index.md", into: db)

        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let updateItem = try db.prepare("UPDATE items SET updated_at = ? WHERE id = ?;")
        updateItem.bind(DatabaseHelpers.encode(newDate), at: 1)
            .bind(DatabaseHelpers.encode(stale.entityID), at: 2)
        try updateItem.step()

        let chunkStmt = try db.prepare("""
            INSERT INTO content_chunks (
                id, item_id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, metadata, created_at, updated_at
            )
            VALUES (?, ?, 'note', ?, 'test', 'Nebula stale index', 'old nebula body',
                    0, 'stale-hash', '{}', ?, ?);
            """)
        chunkStmt.bind(UUID().uuidString, at: 1)
            .bind(stale.entityID.uuidString, at: 2)
            .bind(stale.entityID.uuidString, at: 3)
            .bind(DatabaseHelpers.encode(oldDate), at: 4)
            .bind(DatabaseHelpers.encode(oldDate), at: 5)
        try chunkStmt.step()

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("Nebula", limit: 10)

        #expect(report.indexWarnings.contains {
            $0.kind == "missing_chunks" && $0.item?.id == missing.entityID
        })
        #expect(report.indexWarnings.contains {
            $0.kind == "stale_chunks" && $0.item?.id == stale.entityID
        })
        #expect(report.indexWarnings.contains {
            $0.safeRepairCommand == "cider-cli item rebuild-chunks note \(missing.entityID.uuidString) --json"
        })
        #expect(report.indexWarnings.contains {
            $0.safeRepairCommand == "cider-cli item rebuild-chunks note \(stale.entityID.uuidString) --json"
        })
    }

    @Test("search handles common Kanban acceptance terms alongside item matches")
    func searchHandlesCommonKanbanAcceptanceTermsAlongsideItemMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            note,
            title: "Cutover acceptance text",
            relativePath: "Inbox/Notes/Cutover acceptance text.md",
            into: db
        )

        let store = SecondBrainStore(database: db)
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board/card")
        try store.replaceChunks(owner: cardOwner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: nil,
                source: "kanban_notes",
                title: "Acceptance Criteria",
                body: "Focused CLI acceptance checks pass or produce scoped follow-up cards.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let singleTermMatches = try service.search("acceptance", limit: 10)
        #expect(singleTermMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
        #expect(singleTermMatches.contains {
            $0.kind == .chunk && $0.owner == cardOwner
        })

        let phraseMatches = try service.search("Cutover acceptance", limit: 10)
        #expect(phraseMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
    }

    @Test("search dogfood paraphrases prefer saved items over Kanban audit chunks")
    func searchDogfoodParaphrasesPreferSavedItemsOverKanbanAuditChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let adhd = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let resume = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let imdb = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let tiktok = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let steam = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let tlHub = LibraryEntityRef(type: .note, entityID: UUID())

        try insertItem(adhd, title: "Neuropsych intake scan", relativePath: "Medical/Evaluations/ADHD evaluation.pdf", into: db)
        try insertItem(resume, title: "Vishal resume", relativePath: "Work/Resume/Vishal Resume.docx", into: db)
        try insertItem(imdb, title: "The Matrix - IMDb", relativePath: "Media/Movies/The Matrix.webloc", into: db)
        try insertItem(tiktok, title: "TikTok pasta recipe", relativePath: "Recipes/TikTok/Pasta.webloc", into: db)
        try insertItem(steam, title: "Hades on Steam", relativePath: "Media/Games/Hades.webloc", into: db)
        try insertItem(tlHub, title: "Work TL Hub", relativePath: "Work/TL/Hub.md", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: adhd.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: adhd.entityID.uuidString, source: "test", title: "ADHD evaluation body", body: "Symptoms notes mention Adderall and evaluation follow-up.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: tlHub.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: tlHub.entityID.uuidString, source: "test", title: "Team leader hub", body: "Team leader work hub notes for TL coaching and QA follow-up.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board/audit"), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: nil,
                source: "kanban_notes",
                title: "Recall audit findings",
                body: "Audit mentioned ADHD symptoms document Adderall, resume PDF DOCX, IMDb movie, TikTok captures, Steam game captures, and Work TL hub.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let cases: [(query: String, expected: LibraryEntityRef)] = [
            ("ADHD symptoms document Adderall", adhd),
            ("resume PDF DOCX", resume),
            ("IMDb movie", imdb),
            ("TikTok video recipe", tiktok),
            ("Steam game capture", steam),
            ("team leader work hub", tlHub),
        ]

        for dogfoodCase in cases {
            let results = try service.search(dogfoodCase.query, limit: 5)
            #expect(results.first?.kind == .item, "Expected saved item first for \(dogfoodCase.query), got \(String(describing: results.first))")
            #expect(results.first?.item?.id == dogfoodCase.expected.entityID, "Expected \(dogfoodCase.expected.id) first for \(dogfoodCase.query)")
            #expect(!results.prefix(3).contains { $0.owner.ownerType == "kanban_card" }, "Kanban audit chunk should not outrank saved item recall for \(dogfoodCase.query)")
        }
    }

    @Test("search diagnostics expose recall fallback stages")
    func searchDiagnosticsExposeRecallFallbackStages() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let resume = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        try insertItem(resume, title: "Vishal resume", relativePath: "Work/Resume/Vishal Resume.docx", into: db)

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("resume PDF DOCX", limit: 5)

        #expect(report.exactMatches.first?.item?.id == resume.entityID)
        #expect(report.fallbackStages.contains {
            $0.name == "human_query_expansion" && $0.query.contains("resume")
        })

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        let stages = try #require(dict["fallbackStages"] as? [[String: Any]])
        #expect(stages.contains {
            $0["name"] as? String == "human_query_expansion"
                && ($0["explanation"] as? String)?.contains("resume") == true
        })
    }

    @Test("life memory search scope suppresses QA artifacts while QA scope keeps them searchable")
    func searchScopesSeparateLifeMemoryFromQAArtifacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let event = LibraryEntityRef(type: .dateCard, entityID: UUID())
        let qaFile = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let qaNote = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(event, title: "Warhorse reveal event", relativePath: "Events/Warhorse reveal.event", into: db)
        try insertItem(qaFile, title: "Event search QA screenshot", relativePath: "Projects/Cider/QA/event-search.png", into: db)
        try insertItem(qaNote, title: "Event search audit", relativePath: "Projects/Cider/QA/Event search audit.md", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: qaFile.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: qaFile.entityID.uuidString, source: "file-ocr", title: "Event search QA screenshot", body: "event QA artifact screenshot", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: qaNote.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: qaNote.entityID.uuidString, source: "note", title: "Event search audit", body: "event QA artifact audit", chunkIndex: 0)
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let lifeResults = try service.search("event", limit: 10, scope: .personalMemory)
        let allResults = try service.search("event", limit: 10, scope: .all)
        let qaResults = try service.search("event", limit: 10, scope: .qaArtifacts)

        #expect(lifeResults.first?.item?.id == event.entityID)
        #expect(lifeResults.allSatisfy { $0.item?.relativePath?.contains("/QA/") != true })
        #expect(allResults.first?.item?.id == event.entityID)
        let allResultIDs = allResults.compactMap { $0.item?.id }
        let eventIndex = try #require(allResultIDs.firstIndex(of: event.entityID))
        let qaFileIndex = try #require(allResultIDs.firstIndex(of: qaFile.entityID))
        #expect(eventIndex < qaFileIndex)
        let qaResultIDs = qaResults.compactMap { $0.item?.id }
        #expect(qaResultIDs.contains(qaFile.entityID))
        #expect(qaResultIDs.contains(qaNote.entityID))
        #expect(qaResults.allSatisfy { $0.item?.relativePath?.contains("/QA/") == true })
    }

    @Test("project Kanban search recalls projected card display key title body and evidence")
    func projectKanbanSearchRecallsProjectedCardDisplayKeyTitleBodyAndEvidence() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let rebuildStorm = KanbanCard(
            id: "storm-card",
            title: "Bug: Library rebuild storm ghosts previous views and pegs CPU",
            notes: """
            ## Problem
            Previous Library views ghost behind the active note route during a rebuild storm.

            ## Test Evidence
            CID-447 verification captured CPU and RSS settling after the fix.
            """,
            displayKey: "CID-447"
        )
        let artifactScopes = KanbanCard(
            id: "artifact-scopes",
            title: "Add artifact-aware search scopes for life-memory recall",
            notes: """
            ## Problem
            Broad life memory recall should not be dominated by QA artifact evidence.
            """,
            displayKey: "CID-384"
        )
        let entityBlocks = KanbanCard(
            id: "entity-blocks",
            title: "Entity-linked memory blocks for people/contact profiles",
            notes: """
            ## Problem
            ADHD visual recall needs compact contact profile memory blocks instead of long walls of text.
            """,
            displayKey: "CID-385"
        )
        try projector.refreshCard(boardID: "2afee0", card: rebuildStorm)
        try projector.refreshCard(boardID: "2afee0", card: artifactScopes)
        try projector.refreshCard(boardID: "2afee0", card: entityBlocks)

        let qaNote = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            qaNote,
            title: "CID-447 ghost QA evidence",
            relativePath: "Projects/Cider/QA/CID-447 ghost evidence.md",
            into: db
        )
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: qaNote.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: qaNote.entityID.uuidString, source: "qa", title: "CID-447 ghost evidence", body: "CID-447 ghost rebuild storm QA screenshot evidence", chunkIndex: 0),
            SecondBrainChunkDraft(sectionID: nil, itemID: qaNote.entityID.uuidString, source: "qa", title: "Artifact recall evidence", body: "artifact aware search scopes life memory recall QA evidence", chunkIndex: 1),
            SecondBrainChunkDraft(sectionID: nil, itemID: qaNote.entityID.uuidString, source: "qa", title: "Entity visual evidence", body: "entity memory blocks contact profiles ADHD visual QA evidence", chunkIndex: 2),
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let cidResults = try service.search("CID-447 ghost rebuild storm", limit: 5, scope: .projectKanban)
        let artifactResults = try service.search("artifact aware search scopes life memory recall", limit: 5, scope: .projectKanban)
        let entityResults = try service.search("entity memory blocks contact profiles ADHD visual", limit: 5, scope: .projectKanban)
        let personalResults = try service.search("CID-447 ghost rebuild storm", limit: 5, scope: .personalMemory)

        #expect(cidResults.prefix(3).contains {
            $0.owner == SecondBrainKanbanProjectionService.owner(boardID: "2afee0", cardID: "storm-card")
                && $0.title.localizedCaseInsensitiveContains("Library rebuild storm")
        })
        #expect(artifactResults.prefix(3).contains {
            $0.owner == SecondBrainKanbanProjectionService.owner(boardID: "2afee0", cardID: "artifact-scopes")
                && $0.title == "Add artifact-aware search scopes for life-memory recall"
        })
        #expect(entityResults.prefix(3).contains {
            $0.owner == SecondBrainKanbanProjectionService.owner(boardID: "2afee0", cardID: "entity-blocks")
                && $0.title == "Entity-linked memory blocks for people/contact profiles"
        })
        #expect(personalResults.allSatisfy { $0.owner.ownerType != "kanban_card" })
    }

    @Test("natural file intent keeps personal memory search free of QA evidence artifacts")
    func naturalFileIntentKeepsPersonalMemorySearchFreeOfQAEvidenceArtifacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let file = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let qaEvidence = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        try insertItem(
            file,
            title: "ADHD evaluation file",
            relativePath: "Health/ADHD/Evaluation.pdf",
            into: db
        )
        try insertItem(
            note,
            title: "ADHD file reminder preference",
            relativePath: "Inbox/Notes/ADHD file reminder preference.md",
            into: db
        )
        try insertItem(
            qaEvidence,
            title: "ADHD file QA evidence",
            relativePath: "Projects/Cider/QA/ADHD file evidence.png",
            into: db
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: qaEvidence.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: qaEvidence.entityID.uuidString, source: "file-ocr", title: "ADHD file QA evidence", body: "ADHD file QA evidence screenshot", chunkIndex: 0)
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let personalResults = try service.search("ADHD file", limit: 10, scope: .personalMemory)
        let qaResults = try service.search("ADHD file", limit: 10, scope: .qaArtifacts)
        let personalResultIDs = Set(personalResults.compactMap { $0.item?.id })
        let qaResultIDs = Set(qaResults.compactMap { $0.item?.id })

        #expect(personalResultIDs.contains(file.entityID))
        #expect(personalResultIDs.contains(note.entityID))
        #expect(!personalResultIDs.contains(qaEvidence.entityID))
        #expect(qaResultIDs.contains(qaEvidence.entityID))
    }

    @Test("personal memory search suppresses parked project plans while project scope can recall them")
    func personalMemorySearchSuppressesParkedProjectPlans() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let personal = LibraryEntityRef(type: .note, entityID: UUID())
        let parkedPlan = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            personal,
            title: "Native AI assistant dinner thought",
            relativePath: "Inbox/Notes/Native AI assistant dinner thought.md",
            into: db
        )
        try insertItem(
            parkedPlan,
            title: "Parked Native AI Assistant idea plan",
            relativePath: "Projects/Cider/Plans/Parked Native AI Assistant idea plan.md",
            into: db
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: personal.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: personal.entityID.uuidString, source: "note", title: "Native AI assistant dinner thought", body: "native AI assistant came up during dinner", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: parkedPlan.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: parkedPlan.entityID.uuidString, source: "note", title: "Parked Native AI Assistant idea plan", body: "native AI assistant parked Cider project plan", chunkIndex: 0)
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let personalResults = try service.search("native AI assistant", limit: 10, scope: .personalMemory)
        let projectResults = try service.search("native AI assistant", limit: 10, scope: .projectKanban)
        let personalResultIDs = Set(personalResults.compactMap { $0.item?.id })
        let projectResultIDs = Set(projectResults.compactMap { $0.item?.id })

        #expect(personalResultIDs.contains(personal.entityID))
        #expect(!personalResultIDs.contains(parkedPlan.entityID))
        #expect(projectResultIDs.contains(parkedPlan.entityID))
    }

    @Test("item search result JSON can expose selected search scope")
    func itemSearchJSONExposesSelectedScope() throws {
        let result = CiderItemSearchResult(
            id: "item-\(UUID().uuidString)",
            kind: .item,
            owner: SecondBrainOwnerRef(ownerType: "dateCard", ownerID: UUID().uuidString),
            item: nil,
            title: "Family event",
            snippet: "event",
            rank: 100,
            searchScope: .personalMemory
        )

        let dict = CiderCLI.itemSearchResultToDict(result)

        #expect(dict["searchScope"] as? String == "personalMemory")
    }

    @Test("item search JSON exposes compact temporal provenance and safe replay commands for notes")
    func itemSearchJSONExposesTemporalProvenanceAndReplayCommandsForNotes() throws {
        let noteID = UUID()
        let created = Date(timeIntervalSince1970: 1_748_450_000)
        let updated = Date(timeIntervalSince1970: 1_748_520_000)
        let captureDate = Date(timeIntervalSince1970: 1_750_000_000)
        let result = CiderItemSearchResult(
            id: "item-\(noteID.uuidString)",
            kind: .item,
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString),
            item: CiderItemSummary(
                id: noteID,
                type: .note,
                title: "Daily Journal 2026-06-13",
                relativePath: "Journal/Daily Journal 2026-06-13.md",
                folderID: nil,
                createdAt: created,
                updatedAt: updated
            ),
            title: "Daily Journal 2026-06-13",
            snippet: "Dinner included Panda Express.",
            rank: 200,
            searchScope: .personalMemory,
            captureProvenance: [
                CiderItemCaptureProvenance(
                    eventID: UUID().uuidString,
                    owner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: UUID().uuidString),
                    sourceKind: "journal",
                    surface: "cli",
                    channel: "local",
                    channelID: nil,
                    threadID: nil,
                    messageID: "daily-2026-06-13",
                    senderID: "codex",
                    senderName: "Codex",
                    sourceURL: nil,
                    sourceFile: nil,
                    sourceText: "Panda Express journal capture",
                    attachmentCount: 0,
                    metadata: [:],
                    createdAt: captureDate,
                    relation: SecondBrainRelation(
                        sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: UUID().uuidString),
                        targetOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString),
                        relationType: "produced_item",
                        evidence: "Capture produced note.",
                        source: "capture.add",
                        actor: "system",
                        confidence: 1,
                        metadata: [:]
                    )
                )
            ]
        )

        let dict = CiderCLI.itemSearchResultToDict(result)

        let temporal = try #require(dict["temporal"] as? [String: Any])
        #expect(temporal["displayDate"] as? String == "2025-06-15T15:06:40Z")
        #expect(temporal["sortDate"] as? String == "2025-06-15T15:06:40Z")
        #expect(temporal["dateSource"] as? String == "captureProvenance.createdAt")
        #expect(temporal["dateConfidence"] as? String == "source_backed")

        let provenance = try #require(dict["provenance"] as? [String: Any])
        #expect(provenance["sourceType"] as? String == "note")
        #expect(provenance["sourceID"] as? String == noteID.uuidString)
        #expect(provenance["sourceTitle"] as? String == "Daily Journal 2026-06-13")
        #expect(provenance["sourceLocation"] as? String == "Journal/Daily Journal 2026-06-13.md")
        #expect(provenance["evidenceExcerpt"] as? String == "Dinner included Panda Express.")

        let contextCommands = try #require(dict["contextCommands"] as? [String])
        let verificationCommands = try #require(dict["verificationCommands"] as? [String])
        #expect(contextCommands == ["cider-cli item context note \(noteID.uuidString) --json"])
        #expect(verificationCommands == ["cider-cli item get note \(noteID.uuidString) --json"])
        #expect((dict["safeNextCommands"] as? [String])?.contains("cider-cli item context note \(noteID.uuidString) --json") == true)
    }

    @Test("scoped item search JSON wrapper includes read only action receipt")
    func scopedItemSearchJSONWrapperIncludesReadOnlyActionReceipt() throws {
        let noteID = UUID()
        let result = CiderItemSearchResult(
            id: "item-\(noteID.uuidString)",
            kind: .item,
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString),
            item: CiderItemSummary(
                id: noteID,
                type: .note,
                title: "Work coveralls size",
                relativePath: "Inbox/Notes/Work coveralls size.md",
                folderID: nil,
                createdAt: Date(timeIntervalSince1970: 1_782_701_200),
                updatedAt: Date(timeIntervalSince1970: 1_782_701_200)
            ),
            title: "Work coveralls size",
            snippet: "Red Kap size 60-RG coveralls fit.",
            rank: 250,
            searchScope: .personalMemory
        )

        let payload = CiderCLI.itemSearchResponseToDict(
            query: "coveralls",
            scope: .personalMemory,
            sort: .newest,
            space: nil,
            results: [result]
        )

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["query"] as? String == "coveralls")
        let actionReceipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["command"] as? String == "item.search")
        #expect(actionReceipt["commandFamily"] as? String == "item")
        #expect(actionReceipt["subcommand"] as? String == "search")
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["status"] as? String == "succeeded")
        #expect(actionReceipt["matchedCount"] as? Int == 1)
        #expect((actionReceipt["matchedSourceRefs"] as? [String]) == ["note:\(noteID.uuidString)"])
        #expect((actionReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context note \(noteID.uuidString) --json") == true)
        #expect(actionReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
    }

    @Test("default unscoped item search JSON compatibility remains array shaped")
    func defaultUnscopedItemSearchJSONCompatibilityRemainsArrayShaped() throws {
        let result = CiderItemSearchResult(
            id: "item-\(UUID().uuidString)",
            kind: .item,
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString),
            item: nil,
            title: "Array compatibility",
            snippet: "legacy array",
            rank: 10,
            searchScope: .all
        )

        let payload = CiderCLI.unscopedItemSearchArrayPayload(results: [result])

        #expect(payload.count == 1)
        #expect(payload.first?["title"] as? String == "Array compatibility")
        #expect(payload.first?["actionReceipt"] == nil)
    }

    @Test("item context JSON includes read only action receipt for same source ref")
    func itemContextJSONIncludesReadOnlyActionReceiptForSameSourceRef() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Coveralls source note", relativePath: "Inbox/Notes/Coveralls source note.md", into: db)
        let service = CiderItemContextService(database: db)
        let packet = try service.agentContext(for: note)

        let payload = CiderCLI.itemAgentContextResponseToDict(packet, requestedType: "note", requestedRef: note.entityID.uuidString)

        let actionReceipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["command"] as? String == "item.context")
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["matchedCount"] as? Int == 1)
        #expect((actionReceipt["matchedSourceRefs"] as? [String]) == ["note:\(note.entityID.uuidString)"])
        #expect((actionReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item get note \(note.entityID.uuidString) --json") == true)
    }

    @Test("item get JSON includes read only action receipt for resolved item")
    func itemGetJSONIncludesReadOnlyActionReceiptForResolvedItem() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Coveralls get note", relativePath: "Inbox/Notes/Coveralls get note.md", into: db)
        let service = CiderItemContextService(database: db)
        let bundle = try service.context(for: note)

        let payload = CiderCLI.itemGetResponseToDict(bundle, requestedType: "note", requestedRef: note.entityID.uuidString)

        let actionReceipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["command"] as? String == "item.get")
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["status"] as? String == "succeeded")
        #expect((actionReceipt["matchedSourceRefs"] as? [String]) == ["note:\(note.entityID.uuidString)"])
        #expect((actionReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context note \(note.entityID.uuidString) --json") == true)
    }

    @Test("search diagnostics filter low signal natural language expansions")
    func searchDiagnosticsFilterLowSignalNaturalLanguageExpansions() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let recipe = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            recipe,
            title: "Chickpea tahini dinner recipe",
            relativePath: "Recipes/Chickpea tahini dinner.webloc",
            into: db
        )

        let service = CiderItemContextService(database: db)
        let query = "recipe using chickpeas and tahini but I forgot the title"
        let report = try service.searchDiagnostics(query, limit: 5)
        let expansionQueries = report.fallbackStages
            .filter { $0.name == "human_query_expansion" }
            .map(\.query)

        #expect(expansionQueries.contains("recipe"))
        #expect(expansionQueries.contains("chickpeas"))
        #expect(expansionQueries.contains("tahini"))
        for lowSignal in ["using", "and", "but", "the", "title"] {
            #expect(!expansionQueries.contains(lowSignal), "\(lowSignal) should not become a fallback stage")
        }
        #expect(report.warnings.contains {
            $0.kind == "low_signal_terms_filtered"
                && $0.message.contains("using")
                && $0.message.contains("title")
        })

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        let warnings = try #require(dict["warnings"] as? [[String: Any]])
        #expect(warnings.contains {
            $0["kind"] as? String == "low_signal_terms_filtered"
        })
    }

    @Test("human recall ranks distinctive crowded provider matches above generic matches")
    func humanRecallRanksDistinctiveCrowdedProviderMatchesAboveGenericMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let olderGeneric = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let intended = LibraryEntityRef(type: .bookmark, entityID: UUID(uuidString: "7D3C21E6-0D38-489A-83C8-8B9AF8176213")!)
        let newerWeak = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let targetDate = Date(timeIntervalSince1970: 1_780_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_790_000_000)

        try insertItem(
            olderGeneric,
            title: "Anycubic TikTok 3D printing roundup",
            relativePath: "Media/TikTok/Anycubic 3D printing roundup.webloc",
            into: db,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try insertItem(
            intended,
            title: "My Completely 3D Printed And Modular Shelf System",
            relativePath: "Inbox/Bookmarks/TikTok/My Completely 3D Printed And Modular Shelf System.webloc",
            into: db,
            createdAt: targetDate,
            updatedAt: targetDate
        )
        try insertItem(
            newerWeak,
            title: "TikTok social video inbox save",
            relativePath: "Inbox/Bookmarks/TikTok/social video inbox save.webloc",
            into: db,
            createdAt: newerDate,
            updatedAt: newerDate
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: olderGeneric.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: olderGeneric.entityID.uuidString,
                source: "bookmark-provider",
                title: "TikTok Anycubic 3D printing",
                body: "Older TikTok social video about 3D printed Anycubic printer calibration and generic Kobra setup.",
                chunkIndex: 0
            )
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: intended.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: intended.entityID.uuidString,
                source: "bookmark-enrichment",
                title: "My Completely 3D Printed And Modular Shelf System",
                body: "TikTok social video showing a modular shelf system made from 3D printed parts on an Anycubic Kobra S1 Max.",
                chunkIndex: 0
            )
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: newerWeak.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: newerWeak.entityID.uuidString,
                source: "bookmark-provider",
                title: "TikTok social video",
                body: "Fresh provider-only TikTok social video capture with no useful maker project detail.",
                chunkIndex: 0
            )
        ])
        let spaceStore = CiderSpaceMembershipStore(database: db)
        try spaceStore.assign(
            item: intended,
            toSpaceID: "space-media",
            spaceName: "Media",
            reason: "TikTok 3D printed shelf system belongs in Media.",
            confidence: 0.91,
            source: "space.fixture",
            actor: "agent"
        )

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            spaceMembershipStore: spaceStore,
            nowProvider: { newerDate }
        )

        let query = "TikTok social video 3d printed modular shelf Anycubic Kobra"
        let results = try service.search(query, limit: 5)
        #expect(results.first?.item?.id == intended.entityID)
        #expect(results.first?.rankFactors.contains { $0 == "matched_field:chunk_title" || $0 == "matched_field:chunk_body" } == true)
        #expect(results.first?.rankFactors.contains { $0.hasPrefix("distinctive_terms:") && $0.contains("modular") && $0.contains("shelf") } == true)
        #expect(results.first?.rankFactors.contains("provider_signal:tiktok") == true)
        #expect(results.first?.rankFactors.contains("space_intent:Media") == true)
        #expect(results.first?.rankFactors.contains { $0.hasPrefix("recency_contribution:") } == true)
        #expect(results.first?.rankFactors.contains("stage:original_query") == true)
        #expect(results.first?.rankFactors.contains { $0.hasPrefix("matched_query:") } == true)

        let report = try service.searchDiagnostics(query, limit: 5)
        let first = try #require(report.exactMatches.first)
        #expect(first.item?.id == intended.entityID)
        #expect(first.rankFactors.contains("provider_signal:tiktok"))
        #expect(first.rankFactors.contains("space_intent:Media"))
        #expect(first.rankFactors.contains { $0.hasPrefix("distinctive_terms:") })
        #expect(first.rankFactors.contains("stage:original_query"))
        #expect(report.fallbackStages.contains {
            $0.name == "original_query"
                && $0.query == query
                && $0.resultCount > 0
        })

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        let rankedResults = try #require(dict["rankedResults"] as? [[String: Any]])
        #expect(rankedResults.first?["title"] as? String == "My Completely 3D Printed And Modular Shelf System")
        let exactMatches = try #require(dict["exactMatches"] as? [[String: Any]])
        let firstFactors = try #require(exactMatches.first?["rankFactors"] as? [String])
        #expect(firstFactors.contains("provider_signal:tiktok"))
        #expect(firstFactors.contains("space_intent:Media"))
        #expect(firstFactors.contains { $0.hasPrefix("recency_contribution:") })
    }

    @Test("human recall ranking covers media game and document providers without overfitting TikTok")
    func humanRecallRankingCoversMediaGameAndDocumentProvidersWithoutOverfittingTikTok() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let targetDate = Date(timeIntervalSince1970: 1_760_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_790_000_000)
        let imdb = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let imdbWeak = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let steam = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let steamWeak = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let docx = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let docxWeak = LibraryEntityRef(type: .vaultFile, entityID: UUID())

        try insertItem(imdb, title: "Sinners - IMDb", relativePath: "Media/Movies/Sinners IMDb.webloc", into: db, createdAt: targetDate, updatedAt: targetDate)
        try insertItem(imdbWeak, title: "Rotten Tomatoes media links", relativePath: "Media/Movies/Rotten Tomatoes links.webloc", into: db, createdAt: newerDate, updatedAt: newerDate)
        try insertItem(steam, title: "Blue Prince on Steam", relativePath: "Media/Games/Blue Prince Steam.webloc", into: db, createdAt: targetDate, updatedAt: targetDate)
        try insertItem(steamWeak, title: "Steam game sale roundup", relativePath: "Media/Games/Steam sale roundup.webloc", into: db, createdAt: newerDate, updatedAt: newerDate)
        try insertItem(docx, title: "Insurance appeal packet", relativePath: "Files/Health/Insurance Appeal Packet.docx", into: db, createdAt: targetDate, updatedAt: targetDate)
        try insertItem(docxWeak, title: "Recent DOCX file", relativePath: "Files/Recent/Recent Document.docx", into: db, createdAt: newerDate, updatedAt: newerDate)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: imdb.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: imdb.entityID.uuidString, source: "bookmark-enrichment", title: "Sinners IMDb Rotten Tomatoes", body: "Media recall for Sinners ratings across IMDb and Rotten Tomatoes.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: imdbWeak.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: imdbWeak.entityID.uuidString, source: "bookmark-provider", title: "Rotten Tomatoes media", body: "Newer generic Rotten Tomatoes and IMDb media bookmark.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: steam.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: steam.entityID.uuidString, source: "bookmark-enrichment", title: "Blue Prince Steam", body: "Steam game recall for Blue Prince puzzle roguelite mansion notes.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: steamWeak.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: steamWeak.entityID.uuidString, source: "bookmark-provider", title: "Steam game sale", body: "Newer generic Steam game sale capture.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: docx.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: docx.entityID.uuidString, source: "file-text", title: "Insurance appeal packet DOCX", body: "DOCX file recall for insurance appeal packet with denial letter and supporting evidence.", chunkIndex: 0)
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: docxWeak.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: docxWeak.entityID.uuidString, source: "file-metadata", title: "Recent DOCX file", body: "Newer generic document file without insurance appeal details.", chunkIndex: 0)
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { newerDate }
        )

        let cases: [(query: String, expected: LibraryEntityRef, provider: String)] = [
            ("IMDb Rotten Tomatoes media Sinners", imdb, "imdb"),
            ("Steam game Blue Prince puzzle", steam, "steam"),
            ("DOCX file insurance appeal packet", docx, "docx"),
        ]

        for recallCase in cases {
            let results = try service.search(recallCase.query, limit: 5)
            #expect(results.first?.item?.id == recallCase.expected.entityID, "Expected \(recallCase.expected.id) first for \(recallCase.query)")
            #expect(results.first?.rankFactors.contains { $0.hasPrefix("distinctive_terms:") } == true)
            #expect(results.first?.rankFactors.contains { $0 == "provider_signal:\(recallCase.provider)" || $0 == "type_signal:vaultFile" } == true)
        }
    }

    @Test("file lookup phrases rank exact ADHD Evaluation vault file above noisy recent journal chunks")
    func fileLookupPhrasesRankExactAdhdEvaluationVaultFileFirst() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let oldDate = Date(timeIntervalSince1970: 1_760_000_000)
        let recentDate = Date(timeIntervalSince1970: 1_790_000_000)
        let target = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let noisyJournal = LibraryEntityRef(type: .note, entityID: UUID())

        try insertItem(
            target,
            title: "ADHD Evaluation",
            relativePath: "Files/Health/ADHD Evaluation.pdf",
            into: db,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try insertItem(
            noisyJournal,
            title: "Daily Journal 2026-07-03",
            relativePath: "Journal/Daily Journal 2026-07-03.md",
            into: db,
            createdAt: recentDate,
            updatedAt: recentDate
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noisyJournal.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: noisyJournal.entityID.uuidString,
                source: "journal",
                title: "Recent recall scratchpad",
                body: "Dogfood note: find my ADHD evaluation document was a failed lookup phrase, but this journal is not the file.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { recentDate }
        )

        for query in ["ADHD evaluation", "ADHD evaluation form", "find my ADHD evaluation document"] {
            let results = try service.search(query, limit: 5)
            let first = try #require(results.first, "Expected a result for \(query)")
            #expect(first.item?.id == target.entityID, "Expected ADHD Evaluation file first for \(query), got \(first.title)")
            #expect(first.item?.type == .vaultFile)
            #expect(first.rankFactors.contains("file_lookup_title_or_filename_match"))
            #expect(results.firstIndex { $0.item?.id == noisyJournal.entityID }.map { $0 > 0 } ?? true)
        }
    }

    @Test("item search recency sort preserves relevance default and orders by capture provenance then item timestamps")
    func itemSearchRecencySortPreservesRelevanceDefaultAndOrdersByTemporalMetadata() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let olderExact = LibraryEntityRef(type: .note, entityID: UUID())
        let newerSourceBacked = LibraryEntityRef(type: .note, entityID: UUID())
        let oldest = LibraryEntityRef(type: .note, entityID: UUID())
        let olderDate = Date(timeIntervalSince1970: 1_748_450_000)
        let newerItemDate = Date(timeIntervalSince1970: 1_748_520_000)
        let newerCaptureDate = Date(timeIntervalSince1970: 1_750_000_000)
        let oldestDate = Date(timeIntervalSince1970: 1_740_000_000)

        try insertItem(
            olderExact,
            title: "Panda Express lunch",
            relativePath: "Inbox/Notes/Panda Express lunch.md",
            into: db,
            createdAt: olderDate,
            updatedAt: olderDate
        )
        try insertItem(
            newerSourceBacked,
            title: "Daily Journal 2026-06-13",
            relativePath: "Journal/Daily Journal 2026-06-13.md",
            into: db,
            createdAt: newerItemDate,
            updatedAt: newerItemDate
        )
        try insertItem(
            oldest,
            title: "Panda Express archive",
            relativePath: "Inbox/Notes/Panda Express archive.md",
            into: db,
            createdAt: oldestDate,
            updatedAt: oldestDate
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: newerSourceBacked.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(sectionID: nil, itemID: newerSourceBacked.entityID.uuidString, source: "journal-enrichment", title: "Panda Express journal mention", body: "Dinner included Panda Express.", chunkIndex: 0)
        ])

        let eventID = UUID()
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        insertEvent.bind(eventID.uuidString, at: 1)
            .bind("journal", at: 2)
            .bind("cli", at: 3)
            .bind("local", at: 4)
            .bind(String?.none, at: 5)
            .bind(String?.none, at: 6)
            .bind("daily-2026-06-13", at: 7)
            .bind("codex", at: 8)
            .bind("Codex", at: 9)
            .bind(String?.none, at: 10)
            .bind(String?.none, at: 11)
            .bind("Panda Express journal capture", at: 12)
            .bind(0, at: 13)
            .bind("{}", at: 14)
            .bind(DatabaseHelpers.encode(newerCaptureDate), at: 15)
        try insertEvent.step()

        try store.recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: newerSourceBacked.entityID.uuidString),
            relationType: "produced_item",
            evidence: "Capture produced newer Panda Express journal item.",
            source: "capture.add",
            actor: "system",
            confidence: 1,
            metadata: [:]
        ))

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let defaultResults = try service.search("Panda Express", limit: 10)
        let explicitRelevanceResults = try service.search("Panda Express", limit: 10, sort: .relevance)
        #expect(defaultResults.map(\.id) == explicitRelevanceResults.map(\.id))

        let newestResults = try service.search("Panda Express", limit: 10, sort: .newest)
        #expect(newestResults.map(\.item?.id).prefix(3) == [
            newerSourceBacked.entityID,
            olderExact.entityID,
            oldest.entityID,
        ])
        #expect(newestResults.first?.captureProvenance.first?.createdAt == newerCaptureDate)
        let newestResult = try #require(newestResults.first)
        let newestDict = CiderCLI.itemSearchResultToDict(newestResult)
        let newestTemporal = try #require(newestDict["temporal"] as? [String: Any])
        #expect(newestTemporal["sortDate"] as? String == "2025-06-15T15:06:40Z")
        #expect(newestTemporal["dateSource"] as? String == "captureProvenance.createdAt")

        let oldestResults = try service.search("Panda Express", limit: 10, sort: .oldest)
        #expect(oldestResults.map(\.item?.id).prefix(3) == [
            oldest.entityID,
            olderExact.entityID,
            newerSourceBacked.entityID,
        ])
    }

    @Test("tag facet recall intersects broad type and focused topic tags")
    func tagFacetRecallIntersectsBroadTypeAndFocusedTopicTags() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let target = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let noteCompetitor = LibraryEntityRef(type: .note, entityID: UUID())
        let fileCompetitor = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        try insertItem(
            target,
            title: "Evaluation paperwork",
            relativePath: "Files/Health/Evaluation paperwork.pdf",
            into: db,
            createdAt: now,
            updatedAt: now
        )
        try insertItem(
            noteCompetitor,
            title: "ADHD evaluation notes",
            relativePath: "Inbox/Notes/ADHD evaluation notes.md",
            into: db,
            createdAt: now,
            updatedAt: now
        )
        try insertItem(
            fileCompetitor,
            title: "Trip packing file",
            relativePath: "Files/Travel/Trip packing file.pdf",
            into: db,
            createdAt: now,
            updatedAt: now
        )

        try tagItem(target, tags: ["type/file", "topic/ADHD"], in: db)
        try tagItem(noteCompetitor, tags: ["type/note", "topic/ADHD"], in: db)
        try tagItem(fileCompetitor, tags: ["type/file", "topic/trip"], in: db)

        let service = CiderItemContextService(database: db, nowProvider: { now })
        let results = try service.search("type:file tag:ADHD", limit: 5)

        #expect(results.map(\.item?.id) == [target.entityID])
        let first = try #require(results.first)
        #expect(first.rankFactors.contains("tag_filter:type/file"))
        #expect(first.rankFactors.contains("tag_filter:topic/ADHD"))
        #expect(first.rankFactors.contains("tag_facet:type"))
        #expect(first.rankFactors.contains("tag_facet:topic"))

        let report = try service.searchDiagnostics("type:file tag:ADHD", limit: 5)
        #expect(report.exactMatches.map(\.item?.id) == [target.entityID])
        #expect(report.fallbackStages.contains {
            $0.name == "tag_facet_filter"
                && $0.query == "type:file tag:ADHD"
                && $0.resultCount == 1
        })
    }

    @Test("natural file lookup derives tag facet fallback for ADHD documents")
    func naturalFileLookupDerivesTagFacetFallbackForAdhdDocuments() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let target = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let noisyJournal = LibraryEntityRef(type: .note, entityID: UUID())
        let noisyNote = LibraryEntityRef(type: .note, entityID: UUID())
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        try insertItem(
            target,
            title: "Assessment paperwork",
            relativePath: "Files/Health/Assessment paperwork.pdf",
            into: db,
            createdAt: now.addingTimeInterval(-20_000),
            updatedAt: now.addingTimeInterval(-20_000)
        )
        try insertItem(
            noisyJournal,
            title: "Daily Journal 2026-07-03",
            relativePath: "Journal/Daily Journal 2026-07-03.md",
            into: db,
            createdAt: now,
            updatedAt: now
        )
        try insertItem(
            noisyNote,
            title: "ADHD admin note",
            relativePath: "Inbox/Notes/ADHD admin note.md",
            into: db,
            createdAt: now,
            updatedAt: now
        )

        try tagItem(target, tags: ["type/file", "topic/ADHD"], in: db)
        try tagItem(noisyJournal, tags: ["type/note", "topic/ADHD"], in: db)
        try tagItem(noisyNote, tags: ["type/note", "topic/ADHD"], in: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noisyJournal.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: noisyJournal.entityID.uuidString,
                source: "journal",
                title: "ADHD document lookup scratchpad",
                body: "Find my ADHD document came up during a noisy journal reflection, but this is not the file.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { now }
        )

        for query in ["find my ADHD document", "ADHD files", "show ADHD PDF"] {
            let results = try service.search(query, limit: 5)
            let first = try #require(results.first, "Expected a result for \(query)")
            #expect(first.item?.id == target.entityID, "Expected tagged ADHD file first for \(query), got \(first.title)")
            #expect(first.item?.type == .vaultFile)
            #expect(first.stage == "tag_facet_filter")
            #expect(first.rankFactors.contains("tag_filter:type/file"))
            #expect(first.rankFactors.contains("tag_filter:topic/ADHD"))
            #expect(first.rankFactors.contains("tag_facet:type"))
            #expect(first.rankFactors.contains("tag_facet:topic"))

            let firstDict = CiderCLI.itemSearchResultToDict(first)
            let rankFactors = try #require(firstDict["rankFactors"] as? [String])
            #expect(rankFactors.contains("tag_filter:topic/ADHD"))
            #expect((firstDict["safeNextCommands"] as? [String])?.contains("cider-cli item context vaultFile \(target.entityID.uuidString) --json") == true)
        }

        let report = try service.searchDiagnostics("find my ADHD document", limit: 5)
        #expect(report.exactMatches.first?.item?.id == target.entityID)
        #expect(report.fallbackStages.contains {
            $0.name == "tag_facet_filter"
                && $0.query == "find my ADHD document"
                && $0.resultCount == 1
        })
    }

    @Test("natural file lookup can use source backed projected topic facets")
    func naturalFileLookupCanUseSourceBackedProjectedTopicFacets() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let target = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let noisyJournal = LibraryEntityRef(type: .note, entityID: UUID())
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        try insertItem(
            target,
            title: "Assessment paperwork",
            relativePath: "Inbox/Files/adhd-intake-source.pdf",
            into: db,
            createdAt: now.addingTimeInterval(-20_000),
            updatedAt: now.addingTimeInterval(-20_000)
        )
        try insertItem(
            noisyJournal,
            title: "Daily Journal 2026-07-03",
            relativePath: "Journal/Daily Journal 2026-07-03.md",
            into: db,
            createdAt: now,
            updatedAt: now
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noisyJournal.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: noisyJournal.entityID.uuidString,
                source: "journal",
                title: "ADHD document lookup scratchpad",
                body: "Find my ADHD document came up during a noisy journal reflection, but this is not the file.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { now }
        )

        let results = try service.search("find my ADHD document", limit: 5)
        let first = try #require(results.first)
        #expect(first.item?.id == target.entityID)
        #expect(first.rankFactors.contains("source_backed_topic_facet:ADHD"))
        #expect(first.rankFactors.contains("tag_facet:source"))

        let dict = CiderCLI.itemSearchResultToDict(first)
        let rankFactors = try #require(dict["rankFactors"] as? [String])
        #expect(rankFactors.contains("source_backed_topic_facet:ADHD"))
    }

    @Test("journal phrase recall ranks recent daily journal body matches above generic voice titles")
    func journalPhraseRecallRanksRecentDailyJournalBodyMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let oldDate = Date(timeIntervalSince1970: 1_760_000_000)
        let recentDate = Date(timeIntervalSince1970: 1_790_000_000)
        let journal = LibraryEntityRef(type: .note, entityID: UUID())
        let genericVoice = LibraryEntityRef(type: .note, entityID: UUID())
        let voiceTitleCompetitor = LibraryEntityRef(type: .note, entityID: UUID())

        try insertItem(
            journal,
            title: "Daily Journal 2026-06-05",
            relativePath: "Inbox/Notes/Daily Journal 2026-06-05.md",
            into: db,
            createdAt: recentDate,
            updatedAt: recentDate
        )
        try insertItem(
            genericVoice,
            title: "Voice memo archive",
            relativePath: "Inbox/Notes/Voice memo archive.md",
            into: db,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try insertItem(
            voiceTitleCompetitor,
            title: "Voice-derived reflection archive",
            relativePath: "Inbox/Notes/Voice-derived reflection archive.md",
            into: db,
            createdAt: recentDate,
            updatedAt: recentDate
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: journal.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: journal.entityID.uuidString,
                source: "item_index.note",
                title: "Daily Journal 2026-06-05",
                body: "Dogfood QA 2026-06-05: Driving reflection. Voice-derived reflection phrase brake-light-moon-118.",
                chunkIndex: 0
            )
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: genericVoice.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: genericVoice.entityID.uuidString,
                source: "item_index.note",
                title: "Voice memo archive",
                body: "Older generic voice notes without the daily journal reflection phrase.",
                chunkIndex: 0
            )
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: voiceTitleCompetitor.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: voiceTitleCompetitor.entityID.uuidString,
                source: "item_index.note",
                title: "Voice-derived reflection archive",
                body: "Recent standalone voice note title competitor without daily journal append semantics.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { recentDate }
        )

        let results = try service.search("voice-derived reflection", limit: 8)
        #expect(results.first?.item?.id == journal.entityID)
        #expect(results.first?.rankFactors.contains("journal_intent_match") == true)
        #expect(results.first?.rankFactors.contains("matched_field:chunk_body") == true)

        let report = try service.searchDiagnostics("voice-derived reflection", limit: 8)
        let first = try #require(report.exactMatches.first)
        #expect(first.item?.id == journal.entityID)
        #expect(first.rankFactors.contains("journal_intent_match"))
        #expect(first.rankFactors.contains("matched_field:chunk_body"))
    }

    @Test("broad new contact recall boosts recent contacts above unrelated new items")
    func broadNewContactRecallBoostsRecentContacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let oldDate = Date(timeIntervalSince1970: 1_760_000_000)
        let recentDate = Date(timeIntervalSince1970: 1_790_000_000)
        let contact = LibraryEntityRef(type: .contact, entityID: UUID())
        let unrelatedNew = LibraryEntityRef(type: .bookmark, entityID: UUID())

        try insertItem(
            contact,
            title: "Avery Tester",
            relativePath: "Inbox/Contacts/Avery Tester.vcf",
            into: db,
            createdAt: recentDate,
            updatedAt: recentDate
        )
        try insertItem(
            unrelatedNew,
            title: "New controller bookmark",
            relativePath: "Inbox/Bookmarks/New controller bookmark.webloc",
            into: db,
            createdAt: oldDate,
            updatedAt: oldDate
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "contact", ownerID: contact.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: contact.entityID.uuidString,
                source: "item_index.contact",
                title: "Avery Tester",
                body: "Recently captured contact vCard for Avery Tester.",
                chunkIndex: 0
            )
        ])
        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: unrelatedNew.entityID.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: unrelatedNew.entityID.uuidString,
                source: "item_index.bookmark",
                title: "New controller bookmark",
                body: "New product bookmark with no person or vCard context.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(
            database: db,
            secondBrainStore: store,
            nowProvider: { recentDate }
        )

        let results = try service.search("new contact", limit: 12)
        #expect(results.first?.item?.id == contact.entityID)
        #expect(results.first?.rankFactors.contains("contact_intent_match") == true)
        #expect(results.first?.rankFactors.contains { $0.hasPrefix("recency_contribution:") } == true)

        let report = try service.searchDiagnostics("new contact", limit: 12)
        let first = try #require(report.exactMatches.first)
        #expect(first.item?.id == contact.entityID)
        #expect(first.rankFactors.contains("contact_intent_match"))
        #expect(first.rankFactors.contains { $0.hasPrefix("recency_contribution:") })
    }

    @Test("provider rank factors distinguish query intent from candidate evidence")
    func providerRankFactorsDistinguishQueryIntentFromCandidateEvidence() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let cases: [(query: String, title: String, provider: String)] = [
            ("IMDb movie Sinners cast notes", "Sinners cast notes", "imdb"),
            ("Steam game Blue Prince capture notes", "Blue Prince capture notes", "steam"),
            ("TikTok social video modular shelf notes", "Modular shelf notes", "tiktok"),
            ("Rotten Tomatoes movie rating watchlist", "Movie rating watchlist", "rottentomatoes"),
        ]

        for recallCase in cases {
            let item = LibraryEntityRef(type: .bookmark, entityID: UUID())
            try insertItem(
                item,
                title: recallCase.title,
                relativePath: "Inbox/\(recallCase.title).webloc",
                into: db
            )

            let service = CiderItemContextService(database: db)
            let results = try service.search(recallCase.query, limit: 5)
            let first = try #require(results.first)
            #expect(first.item?.id == item.entityID)
            #expect(first.rankFactors.contains("query_provider_intent:\(recallCase.provider)"))
            #expect(!first.rankFactors.contains("provider_signal:\(recallCase.provider)"))
        }
    }

    @Test("space listing and search use native membership rather than folder paths")
    func spaceListingAndSearchUseNativeMembership() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let inSpace = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let outside = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            inSpace,
            title: "Steam Deck review",
            relativePath: "Inbox/Bookmarks/Steam Deck review.webloc",
            into: db
        )
        try insertItem(
            outside,
            title: "Steam invoice",
            relativePath: "Inbox/Bookmarks/Steam invoice.webloc",
            into: db
        )

        let spaceStore = CiderSpaceMembershipStore(database: db)
        try spaceStore.assign(
            item: inSpace,
            toSpaceID: "space-media",
            spaceName: "Media",
            reason: "Games and hardware belong in Media even while staged in Inbox.",
            confidence: 0.9,
            source: "space.test",
            actor: "agent"
        )
        let service = CiderItemContextService(database: db, spaceMembershipStore: spaceStore)

        let listed = try service.items(inSpaceID: "space-media")
        #expect(listed.map(\.id) == [inSpace.entityID])
        #expect(listed.first?.relativePath == "Inbox/Bookmarks/Steam Deck review.webloc")

        let filtered = try service.search("Steam", limit: 10, inSpaceID: "space-media")
        #expect(filtered.map(\.item?.id) == [inSpace.entityID])
        #expect(!filtered.contains { $0.item?.id == outside.entityID })

        let context = try service.context(for: inSpace)
        #expect(context.ownerRelations.contains { relation in
            relation.targetOwner == SecondBrainOwnerRef(ownerType: "space", ownerID: "space-media")
                && relation.relationType == "belongs_to_space"
                && relation.source == "space_memberships"
        })
    }

    @Test("agent context bundle is bounded and includes provenance review history and safe commands")
    func agentContextBundleIsBoundedAndActionable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and confirm insurance before booking the follow-up appointment.",
                source: "projection",
                sortOrder: 0
            )
        )
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "details",
                title: "Details",
                body: "This longer section should not be included when the section limit is one.",
                source: "projection",
                sortOrder: 1
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Dentist follow-up chunk",
                body: "Call the dentist, verify the insurance portal, and ask whether the claim requires prior authorization.",
                chunkIndex: 0
            ),
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Extra chunk",
                body: "This chunk should be omitted by the max chunk limit.",
                chunkIndex: 1
            ),
        ])
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: note.entityID.uuidString,
                targetType: "folder",
                targetPath: "Health/Dental",
                confidence: 0.64,
                reason: "Health admin item, but target needs review.",
                status: "needs_review",
                actor: "agent",
                source: "routing.test"
            )
        )
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: note.entityID.uuidString,
                toolName: "cider-cli",
                actionType: "route",
                source: "agent.test",
                status: "suggested",
                summary: "Suggested routing to Health/Dental.",
                argumentsJSON: nil,
                resultJSON: nil
            )
        )
        let spaceStore = CiderSpaceMembershipStore(database: db)
        try spaceStore.assign(
            item: note,
            toSpaceID: "space-health",
            spaceName: "Health",
            reason: "Dental follow-up belongs in the Health meaning layer.",
            confidence: 0.88,
            source: "space.test",
            actor: "agent"
        )

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(
            database: db,
            linkService: linkService,
            secondBrainStore: store,
            spaceMembershipStore: spaceStore
        )

        let packet = try service.agentContext(
            for: note,
            limits: CiderItemAgentContextLimits(
                maxSections: 1,
                maxChunks: 1,
                maxRelated: 1,
                maxHistory: 2,
                maxBodyCharacters: 48
            )
        )

        #expect(packet.item.id == note.entityID)
        #expect(packet.summary == "Call the dentist and confirm insurance before bo")
        #expect(packet.summary.count <= 48)
        #expect(packet.provenance.contains("item:note"))
        #expect(packet.provenance.contains("path:Inbox/Notes/Dentist follow-up.md"))
        #expect(packet.provenance.contains("space:Health"))
        #expect(packet.spaceMemberships.map(\.spaceName) == ["Health"])
        #expect(packet.spaceMemberships.first?.reason == "Dental follow-up belongs in the Health meaning layer.")
        #expect(packet.contentBlocks.map(\.title) == ["Summary", "Dentist follow-up chunk"])
        #expect(packet.contentBlocks.allSatisfy { $0.body.count <= 48 })
        #expect(packet.related.map(\.title) == ["Dental insurance portal"])
        #expect(packet.review?.status == "needs_review")
        #expect(packet.review?.targetPath == "Health/Dental")
        #expect(packet.surfacing.reason == "Health admin item, but target needs review.")
        #expect(packet.surfacing.urgency == "review")
        #expect(packet.surfacing.sourceSignal == "item_context")
        #expect(packet.surfacing.reviewState == "needs_review")
        #expect(packet.recentHistory.map(\.summary).contains("Suggested routing to Health/Dental."))
        #expect(packet.safeCommands.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli item related note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli routing explain \(note.entityID.uuidString) --json"))
    }

    @Test("agent context uses shared reminder relevance for todo surfacing")
    func agentContextUsesReminderRelevanceForTodoSurfacing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let todoID = UUID()
        let todoRef = LibraryEntityRef(type: .todo, entityID: todoID)
        let todo = TodoCard(
            id: todoID,
            title: "Pay rent",
            dueDate: now,
            priority: .high,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )
        try insertItem(todoRef, title: "Pay rent", relativePath: "Inbox/Todos/Pay rent.md", into: db)

        let service = CiderItemContextService(
            database: db,
            todoProvider: { [todo] },
            dateCardProvider: { [] },
            nowProvider: { now }
        )

        let packet = try service.agentContext(for: todoRef)

        #expect(packet.surfacing.reason == "due today")
        #expect(packet.surfacing.urgency == "today")
        #expect(packet.surfacing.sourceSignal == "reminder_relevance")
        #expect(packet.surfacing.reviewState == "ok")
        #expect(packet.surfacing.suggestedAction == "open action URL")
        #expect(packet.surfacing.actionURLString == "https://rent.example.com")
    }
}
