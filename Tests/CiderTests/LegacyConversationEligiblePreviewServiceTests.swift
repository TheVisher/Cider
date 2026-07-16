import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Eligible Legacy Conversation Preview Tests")
@MainActor
struct LegacyConversationEligiblePreviewServiceTests {
    @Test("Eligible preview is independently versioned, immutable, and never authorizes writes")
    func eligiblePreviewSafetyContract() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let before = try fixture.inputSnapshot()
            let first = fixture.service.preview()
            let second = fixture.service.preview()

            #expect(first == second)
            #expect(first.formatVersion == "cider.legacy-conversation-eligible-preview.v1")
            #expect(first.state == .ready)
            #expect(first.readOnly)
            #expect(!first.changed)
            #expect(!first.safeForBackfill)
            #expect(!first.safeForShadowWrites)
            #expect(first.counts.registeredActiveTotal == 1)
            #expect(first.counts.eligibleTotal == 1)
            #expect(first.counts.roomLocalOmitted == 0)
            #expect(first.counts.displayedTotal == 1)
            #expect(try fixture.inputSnapshot() == before)
        }
    }

    @Test("Cross-candidate UUID collision blocks every room without exposing private values")
    func crossCandidateCollisionBlocks() throws {
        try withEligibleFixture { fixture in
            let collision = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
            try fixture.writeRoom(index: 1, messageID: collision, privateText: "sentinel-private-one")
            try fixture.writeRoom(index: 2, messageID: collision, privateText: "sentinel-private-two")

            let result = fixture.service.preview()
            #expect(result.state == .blocked)
            #expect(result.rooms.isEmpty)
            #expect(result.counts == .zero)
            #expect(result.conflictDiagnosis?.affectedCandidateCount == .exact(2))
            #expect(result.conflictDiagnosis?.counts == [
                .init(kind: .messageRecordIdentity, conflictingIdentityGroups: .exact(1)),
                .init(kind: .messageProvenanceIdentity, conflictingIdentityGroups: .exact(0)),
                .init(kind: .runtimeBindingIdentity, conflictingIdentityGroups: .exact(0)),
                .init(kind: .historicalTurnProvenanceIdentity, conflictingIdentityGroups: .exact(0)),
            ])
            #expect(!String(describing: result).contains("sentinel-private"))
        }
    }

    @Test("Exact cross-candidate provenance, runtime, and historical-turn taxonomy")
    func exactCrossCandidateTaxonomy() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, messageID: UUID(), privateText: "different-one", sourceIDOverride: "hermes:shared-provenance")
            try fixture.writeRoom(index: 2, messageID: UUID(), privateText: "different-two", sourceIDOverride: "hermes:shared-provenance")
            assertDiagnosis(fixture.service.preview(), affected: .exact(2), provenance: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, sessionOverride: "shared-session")
            try fixture.writeRoom(index: 2, sessionOverride: "shared-session")
            assertDiagnosis(fixture.service.preview(), affected: .exact(2), runtime: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, sourceIDOverride: "hermes-run:shared-run:user", roleOverride: .user)
            try fixture.writeRoom(index: 2, sourceIDOverride: "hermes-run:shared-run:assistant", roleOverride: .assistant)
            assertDiagnosis(fixture.service.preview(), affected: .exact(2), turn: .exact(1))
        }
    }

    @Test("Equivalent messages still collide on complete provenance identity")
    func equivalentMessagesStillCollideOnProvenance() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, messageID: UUID(), privateText: "equivalent", sourceIDOverride: "hermes:equivalent-source")
            try fixture.writeRoom(index: 2, messageID: UUID(), privateText: "equivalent", sourceIDOverride: "hermes:equivalent-source")
            assertDiagnosis(fixture.service.preview(), affected: .exact(2), provenance: .exact(1))
        }
    }

    @Test("Multiple categories and candidates count groups and affected union exactly once")
    func groupAndAffectedUnionSemantics() throws {
        try withEligibleFixture { fixture in
            let shared = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
            try fixture.writeRoom(
                index: 1, messageID: shared, sourceIDOverride: "hermes-run:shared:user",
                sessionOverride: "shared-session", roleOverride: .user
            )
            try fixture.writeRoom(
                index: 2, messageID: shared, sourceIDOverride: "hermes-run:shared:user",
                sessionOverride: "shared-session", roleOverride: .user
            )
            assertDiagnosis(
                fixture.service.preview(), affected: .exact(2), record: .exact(1),
                provenance: .exact(1), runtime: .exact(1), turn: .exact(1)
            )
        }
        try withEligibleFixture { fixture in
            let shared = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
            for index in 1...3 { try fixture.writeRoom(index: index, messageID: shared) }
            assertDiagnosis(fixture.service.preview(), affected: .exact(3), record: .exact(1))
        }
        try withEligibleFixture { fixture in
            let first = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
            let second = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
            try fixture.writeRoom(index: 1, messageID: first)
            try fixture.writeRoom(index: 2, messageID: first)
            try fixture.writeRoom(index: 3, messageID: second)
            try fixture.writeRoom(index: 4, messageID: second)
            assertDiagnosis(fixture.service.preview(), affected: .exact(4), record: .exact(2))
        }
    }

    @Test("Conflict counting saturates groups and affected candidates without overflow")
    func conflictCountingSaturates() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let baseline = fixture.service.preview()
            var template = try #require(baseline.rooms.first?.plan)
            template.bindings = []
            template.turns = []
            template.messages[0].source = nil
            let plans = (0..<200).map { index -> LegacyConversationImportPlan in
                var plan = template
                let group = index / 2 + 1
                plan.messages[0].id = UUID(
                    uuidString: String(format: "%08d-0000-4000-8000-%012d", group, group)
                )!
                return plan
            }
            let diagnosis = try #require(LegacyCandidateConflictDiagnoser.diagnose(plans))
            #expect(diagnosis.affectedCandidateCount == .atLeast100)
            #expect(diagnosis.counts[0].conflictingIdentityGroups == .atLeast100)
            #expect(diagnosis.counts.dropFirst().allSatisfy { $0.conflictingIdentityGroups == .exact(0) })
        }
    }

    @Test("Binding UUID and turn UUID alone are explicitly outside the taxonomy")
    func generatedUUIDsAloneAreNotClassified() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, sourceIDOverride: "hermes-run:first:user")
            try fixture.writeRoom(index: 2, sourceIDOverride: "hermes-run:second:user")
            let preview = fixture.service.preview()
            var plans = preview.rooms.map(\.plan)
            #expect(plans.count == 2)
            plans[1].bindings[0].id = plans[0].bindings[0].id
            plans[1].turns[0].id = plans[0].turns[0].id
            #expect(LegacyCandidateConflictDiagnoser.diagnose(plans) == nil)
        }
    }

    @Test("Duplicate within one candidate remains a local omission without diagnosis")
    func duplicateWithinCandidateIsLocalOmission() throws {
        try withEligibleFixture { fixture in
            var messages = fixture.messages(count: 2, roomIndex: 1)
            messages[1] = AIAssistantMessage(
                id: messages[0].id,
                role: messages[1].role,
                content: messages[1].content,
                timestamp: messages[1].timestamp,
                sourceID: messages[1].sourceID,
                sourceSessionID: messages[1].sourceSessionID,
                sourceName: messages[1].sourceName
            )
            try fixture.writeRoom(index: 1, messages: messages)
            let result = fixture.service.preview()
            #expect(result.state == .eligibleEmpty)
            #expect(result.counts.roomLocalOmitted == 1)
            #expect(result.conflictDiagnosis == nil)
        }
    }

    @Test("Orphan collisions omit only the affected whole candidate and orphan-only collisions remain local")
    func orphanCollisionPolicy() throws {
        try withEligibleFixture { fixture in
            let collision = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
            try fixture.writeRoom(index: 1, messageID: collision)
            try fixture.writeRoom(index: 2)
            try fixture.writeOrphan(index: 1, messageID: collision, sourceID: "hermes:orphan:shared")
            try fixture.writeOrphan(index: 2, messageID: collision, sourceID: "hermes:orphan:shared")

            let result = fixture.service.preview()
            #expect(result.state == .ready)
            #expect(result.counts.registeredActiveTotal == 2)
            #expect(result.counts.eligibleTotal == 1)
            #expect(result.counts.roomLocalOmitted == 1)
            #expect(result.counts.unregisteredFileTotal == 2)
            #expect(result.conflictDiagnosis == nil)
        }
    }

    @Test("Malformed orphan and registry inputs globally block with zero rooms")
    func incompleteEnumerationBlocks() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            try Data("not-json\nnot-json\n".utf8).write(
                to: fixture.conversationDirectory.appendingPathComponent("11111111-1111-4111-8111-111111111111.jsonl")
            )
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
        try withEligibleFixture { fixture in
            try Data("sentinel-private-registry".utf8).write(
                to: fixture.registryDirectory.appendingPathComponent("22222222-2222-4222-8222-222222222222.json")
            )
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
    }

    @Test("Earlier registry, filesystem, and limit blockers remain generic without diagnosis")
    func earlierGlobalBlockersRemainGeneric() throws {
        try withEligibleFixture { fixture in
            let symlink = fixture.conversationDirectory.appendingPathComponent("77777777-7777-4777-8777-777777777777.jsonl")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture.registryDirectory)
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
        try withEligibleFixture { fixture in
            let nonregular = fixture.conversationDirectory.appendingPathComponent("88888888-8888-4888-8888-888888888888.jsonl")
            try FileManager.default.createDirectory(at: nonregular, withIntermediateDirectories: false)
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let limited = fixture.makeService(limits: .init(maximumFiles: 1))
            #expect(limited.preview() == .sanitized(.blocked))
        }
    }

    @Test("Duplicate registry mappings report exact groups and affected-record unions")
    func duplicateRegistryMappingDiagnosis() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, conversationIDOverride: fixture.roomID(index: 7))
            try fixture.writeRoom(index: 2, conversationIDOverride: fixture.roomID(index: 7))
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(2), conversation: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 2, stableIDOverride: "temporary.shared")
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(2), stable: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, conversationIDOverride: fixture.roomID(index: 7), stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 2, conversationIDOverride: fixture.roomID(index: 7), stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 3, stableIDOverride: "temporary.shared")
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(3), conversation: .exact(1), stable: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, conversationIDOverride: fixture.roomID(index: 7))
            try fixture.writeRoom(index: 2, conversationIDOverride: fixture.roomID(index: 7))
            try fixture.writeRoom(index: 3, stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 4, stableIDOverride: "temporary.shared")
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(4), conversation: .exact(1), stable: .exact(1))
        }
        try withEligibleFixture { fixture in
            for index in 1...3 {
                try fixture.writeRoom(index: index, stableIDOverride: "temporary.shared")
            }
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(3), stable: .exact(1))
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, stableIDOverride: "temporary.first")
            try fixture.writeRoom(index: 2, stableIDOverride: "temporary.first")
            try fixture.writeRoom(index: 3, stableIDOverride: "temporary.second")
            try fixture.writeRoom(index: 4, stableIDOverride: "temporary.second")
            assertRegistryDiagnosis(fixture.service.preview(), affected: .exact(4), stable: .exact(2))
        }
    }

    @Test("Registry mapping counts saturate and unique registries retain the existing path")
    func registryMappingSaturationAndUniquePath() throws {
        try withEligibleFixture { fixture in
            for index in 1...101 { try fixture.writeRoom(index: index, stableIDOverride: "temporary.shared") }
            assertRegistryDiagnosis(fixture.service.preview(), affected: .atLeast100, stable: .exact(1))
        }
        try withEligibleFixture { fixture in
            for index in 1...200 { try fixture.writeRoom(index: index, stableIDOverride: "temporary.\((index - 1) / 2)") }
            assertRegistryDiagnosis(fixture.service.preview(), affected: .atLeast100, stable: .atLeast100)
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            #expect(fixture.service.preview().state == .ready)
            #expect(fixture.service.preview().registryMappingDiagnosis == nil)
        }
    }

    @Test("Registry diagnosis retry is immutable and concurrent replacement discards it")
    func registryMappingRetryAndSnapshotRevalidation() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 2, stableIDOverride: "temporary.shared")
            let inputs = try fixture.inputFingerprint()
            let canonical = try fixture.databaseSnapshot()
            #expect(fixture.service.preview() == fixture.service.preview())
            #expect(try fixture.inputFingerprint() == inputs)
            #expect(try fixture.databaseSnapshot() == canonical)
        }
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, stableIDOverride: "temporary.shared")
            try fixture.writeRoom(index: 2, stableIDOverride: "temporary.shared")
            let service = fixture.makeService(fileManager: RevalidationMutatingFileManager(
                targetURL: fixture.registryURL(index: 1)
            ))
            let result = service.preview()
            #expect(result == .sanitized(.failed))
            #expect(result.registryMappingDiagnosis == nil)
        }
    }

    @Test("Attachment or malformed data anywhere omits the whole room before message caps")
    func wholeRoomValidationBeforeCaps() throws {
        try withEligibleFixture { fixture in
            var messages = fixture.messages(count: 105, roomIndex: 1)
            messages[0].attachments = [.init(id: "sentinel-attachment", kind: .image)]
            try fixture.writeRoom(index: 1, messages: messages)
            let result = fixture.service.preview()
            #expect(result.state == .eligibleEmpty)
            #expect(result.counts.roomLocalOmitted == 1)
            #expect(result.rooms.isEmpty)
        }
    }

    @Test("Room and message caps use exact arithmetic and deterministic chronological output")
    func exactCaps() throws {
        try withEligibleFixture { fixture in
            for index in 1...22 {
                try fixture.writeRoom(index: index, messages: fixture.messages(count: index == 22 ? 105 : 1, roomIndex: index))
            }
            let result = fixture.service.preview()
            #expect(result.counts.registeredActiveTotal == 22)
            #expect(result.counts.eligibleTotal == 22)
            #expect(result.counts.displayedTotal == 20)
            #expect(result.counts.eligibleCapOmitted == 2)
            #expect(result.rooms.count == 20)
            #expect(result.rooms[0].totalMessages == 105)
            #expect(result.rooms[0].messageCapOmitted == 5)
            #expect(result.rooms[0].plan.messages.map(\.sequence) == Array(6...105).map(Int64.init))
        }
    }

    @Test("Concurrent input replacement is discarded as sanitized retryable failure")
    func concurrentChangeIsDiscarded() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let service = fixture.makeService(fileManager: RevalidationMutatingFileManager(
                targetURL: fixture.registryURL(index: 1)
            ))
            let result = service.preview()
            #expect(result == .sanitized(.failed))
            #expect(result.conflictDiagnosis == nil)
        }
    }

    @Test("Concurrent change discards a computed conflict diagnosis")
    func concurrentChangeDiscardsDiagnosis() throws {
        try withEligibleFixture { fixture in
            let shared = UUID(uuidString: "abababab-abab-4bab-8bab-abababababab")!
            try fixture.writeRoom(index: 1, messageID: shared)
            try fixture.writeRoom(index: 2, messageID: shared)
            let service = fixture.makeService(fileManager: RevalidationMutatingFileManager(
                targetURL: fixture.registryURL(index: 1)
            ))
            let result = service.preview()
            #expect(result == .sanitized(.failed))
            #expect(result.conflictDiagnosis == nil)
        }
    }

    @Test("Conflict retry is deterministic and leaves every fake input and canonical counter unchanged")
    func conflictRetryIsImmutable() throws {
        try withEligibleFixture { fixture in
            let shared = UUID(uuidString: "acacacac-acac-4cac-8cac-acacacacacac")!
            try fixture.writeRoom(index: 1, messageID: shared)
            try fixture.writeRoom(index: 2, messageID: shared)
            let inputsBefore = try fixture.inputFingerprint()
            let canonicalBefore = try fixture.databaseSnapshot()
            let first = fixture.service.preview()
            let second = fixture.service.preview()
            #expect(first == second)
            #expect(first.conflictDiagnosis != nil)
            #expect(try fixture.inputFingerprint() == inputsBefore)
            #expect(try fixture.databaseSnapshot() == canonicalBefore)
        }
    }

    @Test("Private raw fields never enter diagnosis, workspace, or accessibility description")
    func privateRawFieldsNeverEnterSafeDiagnosis() throws {
        try withEligibleFixture { fixture in
            let sentinel = "PRIVATE_AUTH_SOURCE_SESSION_TITLE_CONTENT_TIMESTAMP"
            let shared = UUID(uuidString: "adadadad-adad-4dad-8dad-adadadadadad")!
            try fixture.writeRoom(
                index: 1,
                messageID: shared,
                privateText: sentinel,
                titleOverride: sentinel,
                sourceIDOverride: "hermes:\(sentinel)-one",
                sessionOverride: "\(sentinel)-session-one"
            )
            try fixture.writeRoom(
                index: 2,
                messageID: shared,
                privateText: sentinel,
                titleOverride: sentinel,
                sourceIDOverride: "hermes:\(sentinel)-two",
                sessionOverride: "\(sentinel)-session-two"
            )
            let preview = fixture.service.preview()
            let workspace = EligibleLegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace()
            #expect(!String(describing: preview.conflictDiagnosis).contains(sentinel))
            #expect(!String(describing: workspace).contains(sentinel))
            guard case .legacyIdentityConflict(_, let notice) = workspace else {
                Issue.record("Expected safe identity conflict")
                return
            }
            #expect(!notice.accessibilityLabel.contains(sentinel))
        }
        try withEligibleFixture { fixture in
            let sentinel = "PRIVATE_REGISTRY_IDENTITY_TITLE_PATH_HASH_AUTH_SESSION_TIMESTAMP"
            try fixture.writeRoom(index: 1, titleOverride: sentinel, stableIDOverride: sentinel)
            try fixture.writeRoom(index: 2, titleOverride: sentinel, stableIDOverride: sentinel)
            let preview = fixture.service.preview()
            let workspace = EligibleLegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace()
            #expect(!String(describing: preview.registryMappingDiagnosis).contains(sentinel))
            #expect(!String(describing: workspace).contains(sentinel))
            guard case .legacyRegistryMappingConflict(_, let notice) = workspace else {
                Issue.record("Expected safe registry mapping conflict")
                return
            }
            #expect(!notice.accessibilityLabel.contains(sentinel))
        }
    }

    @Test("Canonical room and binding timestamp drift omits the whole candidate")
    func canonicalTimestampParityIsExact() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let baseline = fixture.service.preview()
            let eligible = try #require(baseline.rooms.first)
            let room = try #require(eligible.plan.rooms.first)
            let binding = try #require(eligible.plan.bindings.first)

            let exact = fixture.makeService(
                parityReader: PlannedParityReader(room: room, binding: binding)
            ).preview()
            #expect(exact.state == .ready)

            let roomDrift = fixture.makeService(
                parityReader: PlannedParityReader(
                    room: room,
                    binding: binding,
                    roomUpdatedAt: room.updatedAt.addingTimeInterval(1)
                )
            ).preview()
            #expect(roomDrift.state == .eligibleEmpty)
            #expect(roomDrift.counts.roomLocalOmitted == 1)

            let bindingDrift = fixture.makeService(
                parityReader: PlannedParityReader(
                    room: room,
                    binding: binding,
                    bindingUpdatedAt: binding.updatedAt.addingTimeInterval(1)
                )
            ).preview()
            #expect(bindingDrift.state == .eligibleEmpty)
            #expect(bindingDrift.counts.roomLocalOmitted == 1)
        }
    }

    @Test("Cross-room binding identity collision blocks even with distinct messages")
    func crossBindingCollisionBlocks() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, sessionOverride: "shared-session")
            try fixture.writeRoom(index: 2, sessionOverride: "shared-session")
            assertDiagnosis(fixture.service.preview(), affected: .exact(2), runtime: .exact(1))
        }
    }

    @Test("Production-style arbitration reads eligible fake history once without merging or mutation")
    func productionStyleArbitrationIsImmutable() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, privateText: "temporary eligible transcript")
            let inputsBefore = try fixture.inputFingerprint()
            let canonicalBefore = try fixture.databaseSnapshot()
            var legacyCalls = 0
            var canonicalChecks = 0
            let eligible = fixture.makeService(canonicalIsHonestlyEmpty: {
                canonicalChecks += 1
                return try fixture.repository.rooms(lifecycle: .active, limit: 1).isEmpty
            })
            let adapter = EligibleLegacyAgentRoomsPreviewService(loadPreview: eligible.preview, now: { fixture.timestamp })
            let loadLegacy = {
                legacyCalls += 1
                return adapter.loadWorkspace()
            }
            let canonicalRoom = AgentRoom(
                id: "canonical", title: "Canonical", preview: "Canonical", updatedAt: fixture.timestamp,
                relativeTime: "Now", transcript: .init(runtimeLabel: "Hermes", messages: [], link: nil, receipt: nil, futureArtifact: nil)
            )

            for canonical in [
                AgentRoomsWorkspaceState.loaded(authority: .canonicalIncomplete, rooms: [canonicalRoom], selectedRoomID: canonicalRoom.id),
                .failed(authority: .canonicalIncomplete, message: "sanitized"),
                .loading(authority: .canonicalIncomplete),
                .blocked(authority: .canonicalIncomplete, message: "sanitized"),
            ] {
                #expect(AgentRoomsWorkspaceLoader(loadCanonical: { canonical }, loadLegacy: loadLegacy).loadWorkspace() == canonical)
            }
            #expect(legacyCalls == 0)
            #expect(canonicalChecks == 0)

            for expectedCalls in 1...2 {
                let result = AgentRoomsWorkspaceLoader(
                    loadCanonical: { .empty(authority: .canonicalIncomplete) },
                    loadLegacy: loadLegacy
                ).loadWorkspace()
                guard case .eligibleLoaded(let authority, let rooms, _, let notice) = result else {
                    Issue.record("Expected eligible legacy workspace")
                    return
                }
                #expect(authority == .legacyAuthoritativePreview)
                #expect(rooms.map(\.title) == ["Temporary 1"])
                #expect(rooms.flatMap(\.transcript.messages).map(\.body) == ["temporary eligible transcript"])
                #expect(notice == .init(kind: .loaded, displayed: 1, omitted: 0, capOmitted: 0, unregistered: 0))
                #expect(legacyCalls == expectedCalls)
                #expect(canonicalChecks == expectedCalls)
                #expect(try fixture.inputFingerprint() == inputsBefore)
                #expect(try fixture.databaseSnapshot() == canonicalBefore)
            }
        }
    }

    @Test("Bounded canonical defense blocks publication when a room appears after arbitration")
    func boundedCanonicalDefenseBlocksPublication() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, privateText: "must not publish")
            let inputsBefore = try fixture.inputFingerprint()
            var canonicalChecks = 0
            let eligible = fixture.makeService(canonicalIsHonestlyEmpty: {
                canonicalChecks += 1
                return try fixture.repository.rooms(lifecycle: .active, limit: 1).isEmpty
            })
            let adapter = EligibleLegacyAgentRoomsPreviewService(loadPreview: eligible.preview)
            var canonicalAfterInsertion: [Int64]?

            let result = AgentRoomsWorkspaceLoader(
                loadCanonical: {
                    _ = try? fixture.repository.createRoom(.init(stableKey: "temporary.canonical", title: "Canonical appeared"))
                    canonicalAfterInsertion = try? fixture.databaseSnapshot()
                    return .empty(authority: .canonicalIncomplete)
                },
                loadLegacy: adapter.loadWorkspace
            ).loadWorkspace()

            #expect(result == .eligiblePreviewBlocked(authority: .legacyAuthoritativePreview))
            #expect(canonicalChecks == 1)
            #expect(try fixture.repository.rooms(lifecycle: .active, limit: 1).count == 1)
            #expect(try fixture.inputFingerprint() == inputsBefore)
            #expect(try fixture.databaseSnapshot() == canonicalAfterInsertion)
            #expect(!String(describing: result).contains("must not publish"))
        }
    }
}

@MainActor
private func assertDiagnosis(
    _ preview: LegacyConversationEligiblePreview,
    affected: LegacyBoundedCount,
    record: LegacyBoundedCount = .exact(0),
    provenance: LegacyBoundedCount = .exact(0),
    runtime: LegacyBoundedCount = .exact(0),
    turn: LegacyBoundedCount = .exact(0)
) {
    #expect(preview.state == .blocked)
    #expect(preview.rooms.isEmpty)
    #expect(preview.counts == .zero)
    #expect(preview.readOnly && !preview.changed && !preview.safeForBackfill && !preview.safeForShadowWrites)
    #expect(preview.conflictDiagnosis == .init(affectedCandidateCount: affected, counts: [
        .init(kind: .messageRecordIdentity, conflictingIdentityGroups: record),
        .init(kind: .messageProvenanceIdentity, conflictingIdentityGroups: provenance),
        .init(kind: .runtimeBindingIdentity, conflictingIdentityGroups: runtime),
        .init(kind: .historicalTurnProvenanceIdentity, conflictingIdentityGroups: turn),
    ]))
}

@MainActor
private func assertRegistryDiagnosis(
    _ preview: LegacyConversationEligiblePreview,
    affected: LegacyBoundedCount,
    conversation: LegacyBoundedCount = .exact(0),
    stable: LegacyBoundedCount = .exact(0)
) {
    #expect(preview.state == .blocked)
    #expect(preview.rooms.isEmpty && preview.counts == .zero)
    #expect(preview.conflictDiagnosis == nil)
    #expect(preview.readOnly && !preview.changed && !preview.safeForBackfill && !preview.safeForShadowWrites)
    #expect(preview.registryMappingDiagnosis == .init(affectedRegistryRecordCount: affected, counts: [
        .init(kind: .conversationIdentityMapping, conflictingMappingGroups: conversation),
        .init(kind: .stableRoomMapping, conflictingMappingGroups: stable),
    ]))
}

@MainActor
private struct PlannedParityReader: ConversationCoreParityReading {
    let existingRoom: ConversationRoom
    let existingBinding: ConversationRuntimeBinding

    init(
        room: LegacyConversationRoomPlanRecord,
        binding: LegacyConversationBindingPlanRecord,
        roomUpdatedAt: Date? = nil,
        bindingUpdatedAt: Date? = nil
    ) {
        existingRoom = ConversationRoom(
            id: room.id,
            stableKey: room.stableKey,
            title: room.title,
            kind: room.kind,
            lifecycleState: room.lifecycleState,
            nextTurnSequence: room.nextTurnSequence,
            nextMessageSequence: room.nextMessageSequence,
            metadata: room.metadata,
            createdAt: room.createdAt,
            updatedAt: roomUpdatedAt ?? room.updatedAt,
            archivedAt: room.archivedAt,
            trashedAt: nil
        )
        existingBinding = ConversationRuntimeBinding(
            id: binding.id,
            roomID: binding.roomID,
            parentBindingID: binding.parentBindingID,
            runtimeID: binding.runtimeID,
            transportID: binding.transportID,
            sourceNamespace: binding.sourceNamespace,
            externalSessionID: binding.externalSessionID,
            state: binding.state,
            cursorMessageID: binding.cursorMessageID,
            cursorTimestamp: binding.cursorTimestamp,
            metadata: binding.metadata,
            createdAt: binding.createdAt,
            updatedAt: bindingUpdatedAt ?? binding.updatedAt
        )
    }

    func room(id: UUID) throws -> ConversationRoom? { id == existingRoom.id ? existingRoom : nil }
    func room(stableKey: String) throws -> ConversationRoom? {
        stableKey == existingRoom.stableKey ? existingRoom : nil
    }
    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding] {
        roomID == existingRoom.id ? [existingBinding] : []
    }
    func turn(id: UUID) throws -> ConversationTurn? { nil }
    func messages(roomID: UUID) throws -> [ConversationMessage] { [] }
}

private final class RevalidationMutatingFileManager:
    FileManager,
    @unchecked Sendable
{
    private let targetDirectoryPath: String
    private let targetPath: String
    private var targetDirectoryReads = 0

    init(targetURL: URL) {
        targetDirectoryPath = targetURL.deletingLastPathComponent().path
        targetPath = targetURL.path
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if url.path == targetDirectoryPath {
            targetDirectoryReads += 1
            if targetDirectoryReads == 2 {
                try Data("changed during revalidation".utf8).write(
                    to: URL(fileURLWithPath: targetPath),
                    options: .atomic
                )
            }
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

@MainActor
private func withEligibleFixture(_ body: (EligibleFixture) throws -> Void) throws {
    let fixture = try EligibleFixture()
    defer { fixture.remove() }
    try body(fixture)
}

@MainActor
private final class EligibleFixture {
    struct InputFingerprint: Equatable {
        let bytes: Data
        let sha256: String
        let inode: UInt64
        let size: UInt64
        let modifiedAt: TimeInterval
    }

    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let service: LegacyConversationEligiblePreviewService
    private let encoder: JSONEncoder
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        registryDirectory = root.appendingPathComponent("33333333-3333-4333-8333-333333333333", isDirectory: true)
        conversationDirectory = root.appendingPathComponent("44444444-4444-4444-8444-444444444444", isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        database = CiderDatabase()
        try database.open(at: root.appendingPathComponent("55555555-5555-4555-8555-555555555555.db"))
        repository = ConversationRepository(database: database)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        service = LegacyConversationEligiblePreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: ConversationRepositoryParityReader(repository: repository),
            canonicalIsHonestlyEmpty: { true }
        )
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    func writeRoom(
        index: Int,
        messageID: UUID = UUID(),
        privateText: String = "temporary message",
        titleOverride: String? = nil,
        messages suppliedMessages: [AIAssistantMessage]? = nil,
        sourceIDOverride: String? = nil,
        sessionOverride: String? = nil,
        roleOverride: AIAssistantMessage.Role = .user,
        conversationIDOverride: UUID? = nil,
        stableIDOverride: String? = nil
    ) throws {
        let roomID = conversationIDOverride ?? roomID(index: index)
        let title = titleOverride ?? "Temporary \(index)"
        let session = sessionOverride ?? "session-\(index)"
        let record = CiderAgentChatRecord(
            stableID: stableIDOverride ?? "temporary.\(index)", title: title, kind: "chat", conversationID: roomID,
            runtimeID: "hermes", activeRuntimeSessionID: session, runtimeSessionLineage: [session],
            lastSyncedMessageID: nil, lastSyncedTimestamp: nil, lastImportedRuntimeSessionID: session,
            scope: "temporary-test", archived: false, createdAt: timestamp,
            updatedAt: timestamp.addingTimeInterval(Double(index)), defaultInCider: false
        )
        try encoder.encode(record).write(to: registryURL(index: index))

        var metadata = AIConversationMeta(id: roomID, title: title, model: "hermes")
        metadata.updated = record.updatedAt
        let roomMessages = suppliedMessages ?? [AIAssistantMessage(
            id: messageID, role: roleOverride, content: privateText, timestamp: timestamp,
            sourceID: sourceIDOverride ?? "hermes:room-\(index):message", sourceSessionID: session, sourceName: "Hermes"
        )]
        metadata.messageCount = roomMessages.count
        metadata.runtimeID = "hermes"
        metadata.activeRuntimeSessionID = session
        metadata.runtimeSessionLineage = [session]
        metadata.runtimeLastImportedSessionID = session
        let rows = try [encoder.encode(metadata)] + roomMessages.map(encoder.encode)
        try rows.reduce(into: Data()) { data, row in data.append(row); data.append(0x0a) }
            .write(to: conversationDirectory.appendingPathComponent("\(roomID.uuidString).jsonl"))
    }

    func writeOrphan(index: Int, messageID: UUID, sourceID: String) throws {
        let orphanID = UUID(uuidString: String(format: "99999999-9999-4999-8999-%012d", index))!
        var metadata = AIConversationMeta(id: orphanID, title: "orphan", model: "hermes")
        metadata.messageCount = 1
        let message = AIAssistantMessage(
            id: messageID, role: .user, content: "sentinel-orphan", timestamp: timestamp,
            sourceID: sourceID, sourceSessionID: nil, sourceName: nil
        )
        let rows = try [encoder.encode(metadata), encoder.encode(message)]
        try rows.reduce(into: Data()) { data, row in data.append(row); data.append(0x0a) }
            .write(to: conversationDirectory.appendingPathComponent("\(orphanID.uuidString).jsonl"))
    }

    func registryURL(index: Int) -> URL {
        registryDirectory.appendingPathComponent("\(roomID(index: index).uuidString).json")
    }

    func roomID(index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }

    func messages(count: Int, roomIndex: Int) -> [AIAssistantMessage] {
        (1...count).map { sequence in
            AIAssistantMessage(
                id: UUID(uuidString: String(format: "%08d-0000-4000-8000-%012d", roomIndex, sequence))!,
                role: sequence.isMultiple(of: 2) ? .assistant : .user,
                content: "temporary-\(sequence)",
                timestamp: timestamp.addingTimeInterval(Double(sequence)),
                sourceID: "hermes:room-\(roomIndex):\(sequence)",
                sourceSessionID: "session-\(roomIndex)",
                sourceName: "Hermes"
            )
        }
    }

    func makeService(
        parityReader: (any ConversationCoreParityReading)? = nil,
        canonicalIsHonestlyEmpty: @escaping () throws -> Bool = { true },
        limits: LegacyConversationEligiblePreviewService.Limits = .init(),
        fileManager: FileManager = .default
    ) -> LegacyConversationEligiblePreviewService {
        LegacyConversationEligiblePreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: parityReader ?? ConversationRepositoryParityReader(repository: repository),
            canonicalIsHonestlyEmpty: canonicalIsHonestlyEmpty,
            limits: limits,
            fileManager: fileManager
        )
    }

    func inputSnapshot() throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for directory in [registryDirectory, conversationDirectory] {
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                snapshot["\(directory.lastPathComponent)/\(name)"] = try Data(contentsOf: directory.appendingPathComponent(name))
            }
        }
        return snapshot
    }

    func inputFingerprint() throws -> [String: InputFingerprint] {
        var snapshot: [String: InputFingerprint] = [:]
        for directory in [registryDirectory, conversationDirectory] {
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                let url = directory.appendingPathComponent(name)
                let bytes = try Data(contentsOf: url)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                snapshot["\(directory.lastPathComponent)/\(name)"] = .init(
                    bytes: bytes,
                    sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                    inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                    size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                    modifiedAt: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                )
            }
        }
        return snapshot
    }

    func databaseSnapshot() throws -> [Int64] {
        let statement = try database.prepare("""
            SELECT
              (SELECT COUNT(*) FROM conversation_rooms),
              (SELECT COUNT(*) FROM conversation_runtime_bindings),
              (SELECT COUNT(*) FROM conversation_turns),
              (SELECT COUNT(*) FROM conversation_messages),
              COALESCE((SELECT SUM(next_turn_sequence) FROM conversation_rooms), 0),
              COALESCE((SELECT SUM(next_message_sequence) FROM conversation_rooms), 0);
            """)
        guard try statement.step() else { return [] }
        return (0..<6).map { statement.int64(at: Int32($0)) }
    }
}
