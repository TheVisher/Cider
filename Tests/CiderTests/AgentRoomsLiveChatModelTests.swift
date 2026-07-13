import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentRoomsLiveChatModelTests {
    @Test("test room is created only by explicit action and is a live continuation")
    func explicitCreation() async {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [])
        let model = makeModel(transport)

        #expect(model.testRoom == nil)
        #expect(!model.isComposerEnabled(selectedRoomID: nil))

        await model.startTestChat()

        #expect(model.testRoom?.title == "Cider Test Chat")
        #expect(model.testRoom?.continuity == .liveContinuation)
        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(model.isComposerEnabled(selectedRoomID: model.testRoom?.id))
        #expect(AgentRoomContinuity.historicalReplay != AgentRoomContinuity.liveContinuation)
    }

    @Test("only a selected test room with Runs transport enables its composer")
    func composerArbitration() async {
        let ready = makeModel(RoomsScriptedTransport(availability: .apiRuns, scripts: []))
        await ready.startTestChat()
        #expect(ready.isComposerEnabled(selectedRoomID: ready.testRoom?.id))
        #expect(!ready.isComposerEnabled(selectedRoomID: "ambiguous-legacy-room"))

        let fallback = makeModel(RoomsScriptedTransport(availability: .cliFallback, scripts: []))
        await fallback.startTestChat()
        #expect(fallback.transportState == .blocked)
        #expect(!fallback.isComposerEnabled(selectedRoomID: fallback.testRoom?.id))
        #expect(fallback.composerMessage == AgentRoomsLiveChatModel.unavailableMessage)
    }

    @Test("happy path keeps optimistic user order and source-backed terminal receipt")
    func happyPath() async throws {
        let transport = RoomsScriptedTransport(
            availability: .apiRuns,
            scripts: [.success(events: [
                .runStarted("run-805"),
                .messageDelta("Hello"),
                .completed(output: "Hello, Visher"),
                .completed(output: "duplicate terminal event"),
            ], envelope: envelope(runID: "run-805", user: "Tonight?", assistant: "Hello, Visher"))]
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Tonight?", selectedRoomID: roomID)

        let room = try #require(model.testRoom)
        #expect(room.transcript.messages.map(\.role) == [.human, .agent])
        #expect(room.transcript.messages.map(\.body) == ["Tonight?", "Hello, Visher"])
        #expect(room.transcript.messages[0].id.hasPrefix("cider-room-client:"))
        #expect(room.transcript.messages[0].deliveryState == .sent)
        #expect(room.transcript.receipt?.status == .completed)
        #expect(room.transcript.receipt?.continuity == .liveContinuation)
        #expect(room.transcript.receipt?.sourceBackedTransport == true)
        #expect(room.transcript.receipt?.detail == "Completed · Source-backed · Live continuation")
        #expect(room.transcript.receipt?.sourceIdentity == "Hermes Runs API")
        #expect(room.transcript.receipt?.runIdentity == "run-805")
        #expect(room.transcript.receipt?.activity.isEmpty == true)
        #expect(room.transcript.receipt?.id == "cider-room-receipt:run-805")
        #expect(await transport.sentTexts() == ["Tonight?"])
    }

    @Test("one explicit canonical task reference projects a bounded safe-open receipt")
    func canonicalTaskReceipt() async throws {
        let reference = HermesCiderReference(
            kind: "task",
            id: "8d2bd6",
            title: "Show source-backed task receipts",
            boardID: "2afee0",
            projectID: nil,
            artifactType: nil,
            source: "cider",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )
        let receipt = try #require(AgentRoomsCiderReceiptProjector.project([reference])?.first)

        #expect(receipt.kind == .task)
        #expect(receipt.title == "Show source-backed task receipts")
        #expect(receipt.identifier == "Kanban card · 8d2bd6")
        #expect(receipt.provenance == "Cider canonical read")
        #expect(receipt.truthBoundary == "Source-backed object, not transcript truth")
        #expect(receipt.openRoute == .card(boardID: "2afee0", cardID: "8d2bd6"))
        #expect(receipt.openRoute.userInfo == [
            CiderExternalOpenBridge.Key.targetType: "card",
            CiderExternalOpenBridge.Key.targetID: "8d2bd6",
            CiderExternalOpenBridge.Key.boardID: "2afee0",
        ])
    }

    @Test("one explicit canonical project artifact projects a native note route")
    func canonicalArtifactReceipt() throws {
        let noteID = UUID(uuidString: "80900000-0000-4000-8000-000000000001")!
        let reference = HermesCiderReference(
            kind: "project_artifact",
            id: noteID.uuidString,
            title: "Rooms receipt QA",
            boardID: nil,
            projectID: "cider",
            artifactType: "qa",
            source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let receipt = try #require(AgentRoomsCiderReceiptProjector.project([reference])?.first)

        #expect(receipt.kind == .projectArtifact)
        #expect(receipt.identifier == "Cider · QA")
        #expect(receipt.openRoute == .note(noteID: noteID))
        #expect(receipt.openRoute.userInfo == [
            CiderExternalOpenBridge.Key.targetType: "note",
            CiderExternalOpenBridge.Key.targetID: noteID.uuidString,
        ])
    }

    @Test("validated Cider references project one bounded deduplicated deterministic source collection")
    func canonicalSourceCollection() throws {
        let bookmarkID = UUID(uuidString: "80900000-0000-4000-8000-000000000010")!
        let noteID = UUID(uuidString: "80900000-0000-4000-8000-000000000011")!
        let artifactID = UUID(uuidString: "80900000-0000-4000-8000-000000000012")!
        let thumbnail = AgentRoomsBookmarkThumbnailReference(
            bookmarkID: bookmarkID,
            relativePath: ".thumbnails/\(bookmarkID.uuidString).png",
            modifiedAt: 1_805_000_000
        )
        let bookmark = HermesCiderReference(
            kind: "bookmark", id: bookmarkID.uuidString, title: "Cider reference",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "bookmark:\(bookmarkID.uuidString)"
        )
        let note = HermesCiderReference(
            kind: "note", id: noteID.uuidString, title: "Daily note",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let task = HermesCiderReference(
            kind: "task", id: "8d2bd6", title: "Receipt task", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )
        let artifact = HermesCiderReference(
            kind: "project_artifact", id: artifactID.uuidString, title: "Receipt QA",
            boardID: nil, projectID: "cider", artifactType: "qa", source: "cider",
            sourceRef: "note:\(artifactID.uuidString)"
        )

        let projected = AgentRoomsCiderReceiptProjector.project(
            [artifact, task, bookmark, note, task],
            bookmarkThumbnail: { $0 == bookmarkID ? thumbnail : nil }
        )
        let receipts = try #require(projected)

        #expect(AgentRoomsCiderReceiptProjector.maximumReferenceCount > 1)
        #expect(receipts.map(\.kind) == [.bookmark, .note, .task, .projectArtifact])
        #expect(receipts.map(\.openRoute) == [
            .bookmark(bookmarkID: bookmarkID),
            .note(noteID: noteID),
            .card(boardID: "2afee0", cardID: "8d2bd6"),
            .note(noteID: artifactID),
        ])
        #expect(receipts.first?.bookmarkThumbnail == thumbnail)
        #expect(Set(receipts.map(\.id)).count == receipts.count)
    }

    @Test("one malformed cross-identity unsupported or over-broad reference rejects the whole source collection")
    func invalidSourceCollectionFailsClosed() {
        let noteID = UUID(uuidString: "80900000-0000-4000-8000-000000000013")!
        let note = HermesCiderReference(
            kind: "note", id: noteID.uuidString, title: "Daily note",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let malformed = HermesCiderReference(
            kind: "task", id: "../escape", title: "Unsafe", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/../escape"
        )
        let crossIdentity = HermesCiderReference(
            kind: "project_artifact", id: noteID.uuidString, title: "Conflicting identity",
            boardID: nil, projectID: "cider", artifactType: "qa", source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let unsupported = HermesCiderReference(
            kind: "contact", id: noteID.uuidString, title: "Unsupported",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "contact:\(noteID.uuidString)"
        )

        #expect(AgentRoomsCiderReceiptProjector.project([note, malformed]) == nil)
        #expect(AgentRoomsCiderReceiptProjector.project([note, crossIdentity]) == nil)
        #expect(AgentRoomsCiderReceiptProjector.project([note, unsupported]) == nil)
        #expect(AgentRoomsCiderReceiptProjector.project(
            Array(repeating: note, count: AgentRoomsCiderReceiptProjector.maximumReferenceCount + 1)
        ) == nil)
    }

    @Test("missing malformed ambiguous and non-Cider references fail closed")
    func malformedReferencesFailClosed() {
        let valid = HermesCiderReference(
            kind: "task", id: "8d2bd6", title: "Task", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )
        let malformed = HermesCiderReference(
            kind: "task", id: "../escape", title: "Task", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/../escape"
        )
        let nonCider = HermesCiderReference(
            kind: "task", id: "8d2bd6", title: "Task", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "hermes-prose",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )

        #expect(AgentRoomsCiderReceiptProjector.project([]) == nil)
        #expect(AgentRoomsCiderReceiptProjector.project([valid, valid])?.count == 1)
        #expect(AgentRoomsCiderReceiptProjector.project([malformed]) == nil)
        #expect(AgentRoomsCiderReceiptProjector.project([nonCider]) == nil)
    }

    @Test("projection is bounded and does not parse transcript prose")
    func receiptProjectionIsBounded() throws {
        let rawTitle = String(repeating: "Receipt ", count: 100)
        let reference = HermesCiderReference(
            kind: "task", id: "8d2bd6", title: rawTitle, boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )
        let receipt = try #require(AgentRoomsCiderReceiptProjector.project([reference])?.first)

        #expect(receipt.title.count == AgentRoomsCiderReceiptProjector.maximumTitleLength)
        #expect(AgentRoomsCiderReceiptProjector.maximumReferenceCount > 1)
        #expect(AgentRoomsCiderReceiptProjector.project([
            .init(
                kind: "prose", id: "CID-809", title: "Open card 8d2bd6", boardID: nil,
                projectID: nil, artifactType: nil, source: "cider", sourceRef: "CID-809"
            )
        ]) == nil)
    }

    @Test("valid terminal reference is attached only after terminal receipt validation")
    func terminalReferenceProjection() async throws {
        let reference = HermesCiderReference(
            kind: "task", id: "8d2bd6", title: "Receipt task", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/8d2bd6"
        )
        let transport = RoomsScriptedTransport(
            availability: .apiRuns,
            scripts: [.success(
                events: [.runStarted("run-ref")],
                envelope: envelope(runID: "run-ref", user: "Open it", assistant: "Done", ciderReferences: [reference])
            )]
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Open it", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.receipt?.objectReceipts.first?.openRoute == .card(boardID: "2afee0", cardID: "8d2bd6"))
    }

    @Test("current terminal output shape promotes one canonical saved bookmark to a native Open route")
    func terminalSavedBookmarkURLProjection() async throws {
        let bookmarkID = UUID(uuidString: "80900000-0000-4000-8000-000000000002")!
        let backpackURL = URL(string: "https://chromeindustries.com/products/cohesive-35l-backpack")!
        let thumbnail = AgentRoomsBookmarkThumbnailReference(
            bookmarkID: bookmarkID,
            relativePath: ".thumbnails/\(bookmarkID.uuidString).png",
            modifiedAt: 1_805_000_000
        )
        let assistant = """
        I found the saved Chrome Industries Cohesive 35L Backpack:
        https://chromeindustries.com/products/cohesive-35l-backpack
        """
        let transport = RoomsScriptedTransport(
            availability: .apiRuns,
            scripts: [.success(
                events: [.runStarted("run-bookmark")],
                envelope: envelope(runID: "run-bookmark", user: "Find my Chrome backpack", assistant: assistant)
            )]
        )
        let model = makeModel(transport) { url in
            url == backpackURL
                ? [.init(
                    id: bookmarkID,
                    title: "Chrome Industries Cohesive 35L Backpack",
                    url: backpackURL,
                    thumbnail: thumbnail
                )]
                : []
        }
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Find my Chrome backpack", selectedRoomID: roomID)

        let receipt = try #require(model.testRoom?.transcript.receipt?.objectReceipts.first)
        #expect(receipt.kind == .bookmark)
        #expect(receipt.title == "Chrome Industries Cohesive 35L Backpack")
        #expect(receipt.identifier == "Saved bookmark · chromeindustries.com")
        #expect(receipt.bookmarkThumbnail == thumbnail)
        #expect(receipt.openRoute == .bookmark(bookmarkID: bookmarkID))
        #expect(receipt.openRoute.userInfo == [
            CiderExternalOpenBridge.Key.targetType: "bookmark",
            CiderExternalOpenBridge.Key.targetID: bookmarkID.uuidString,
        ])
    }

    @Test("terminal URL fallback fails closed unless exactly one safe standalone URL has one canonical saved match")
    func terminalSavedBookmarkURLFailClosed() {
        let bookmarkID = UUID(uuidString: "80900000-0000-4000-8000-000000000003")!
        let validURL = URL(string: "https://chromeindustries.com/products/cohesive-35l-backpack")!
        let saved = AgentRoomsSavedBookmarkReference(id: bookmarkID, title: "Cohesive 35L Backpack", url: validURL)

        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: "No source-backed URL here.",
            matching: { _ in [saved] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: "https://chromeindustries.com/products/cohesive-35l-backpack extra prose",
            matching: { _ in [saved] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: "The URL is https://chromeindustries.com/products/cohesive-35l-backpack but this line is prose.",
            matching: { _ in [saved] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: "ftp://chromeindustries.com/products/cohesive-35l-backpack",
            matching: { _ in [saved] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: "https://chromeindustries.com/products/cohesive-35l-backpack\nhttps://example.com/other",
            matching: { _ in [saved] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: validURL.absoluteString,
            matching: { _ in [] }
        ) == nil)
        #expect(AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: validURL.absoluteString,
            matching: { _ in [saved, saved] }
        ) == nil)

        let mismatchedThumbnail = AgentRoomsBookmarkThumbnailReference(
            bookmarkID: UUID(),
            relativePath: ".thumbnails/mismatch.png",
            modifiedAt: 1
        )
        let receipt = AgentRoomsCiderReceiptProjector.projectSavedBookmark(
            terminalOutput: validURL.absoluteString,
            matching: { _ in [.init(
                id: bookmarkID,
                title: saved.title,
                url: validURL,
                thumbnail: mismatchedThumbnail
            )] }
        )
        #expect(receipt?.bookmarkThumbnail == nil)
        #expect(receipt?.openRoute == .bookmark(bookmarkID: bookmarkID))
    }

    @Test("incremental deltas are sanitized, bounded, and reconciled with the final assistant")
    func incrementalStreamingReconcilesFinal() async throws {
        let transport = RoomsGateTransport(
            envelope: envelope(runID: "run-stream", user: "Stream", assistant: "Hello world")
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Stream", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await transport.emit(.messageDelta("Hello\u{0000}"))
        await transport.emit(.messageDelta(" world"))
        await transport.emit(.messageDelta(""))

        let streaming = try #require(model.testRoom?.transcript.messages.last)
        #expect(streaming.role == .agent)
        #expect(streaming.body == "Hello world")
        #expect(model.turnState == .streaming)

        await transport.release()
        await send.value
        let completed = try #require(model.testRoom?.transcript.messages)
        #expect(completed.map(\.body) == ["Stream", "Hello world"])
        #expect(model.turnState == .completed)
    }

    @Test("tool and reasoning events preserve ordering without exposing malformed or unbounded text")
    func eventProjectionIsOrderedAndBounded() async throws {
        let transport = RoomsGateTransport(
            envelope: envelope(runID: "run-events", user: "Work", assistant: "Done")
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Work", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await transport.emit(.reasoningAvailable("  Planning\u{0007}  "))
        await transport.emit(.toolStarted(name: " Search ", preview: String(repeating: "x", count: 2_000)))
        await transport.emit(.toolCompleted(name: "Search", isError: false))

        #expect(model.liveActivity.map(\.kind) == [.reasoning, .toolStarted, .toolCompleted])
        #expect(model.liveActivity.first?.detail == "Planning")
        #expect(model.liveActivity.allSatisfy { $0.detail.count <= AgentRoomsLiveChatModel.maximumEventDetailLength })

        await transport.release()
        await send.value

        let receiptActivity = try #require(model.testRoom?.transcript.receipt?.activity)
        #expect(receiptActivity.map(\.kind) == [.reasoning, .toolStarted, .toolCompleted])
        #expect(receiptActivity.map(\.detail).first == "Planning")
        #expect(model.testRoom?.transcript.receipt?.runIdentity == "run-events")
    }

    @Test("terminal receipt freezes only the newest bounded ordered activity")
    func terminalReceiptActivityIsBounded() async throws {
        let transport = RoomsGateTransport(
            envelope: envelope(runID: "run-bounded", user: "Work", assistant: "Done")
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Work", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        for index in 0..<(AgentRoomsLiveChatModel.maximumLiveActivityCount + 3) {
            await transport.emit(.reasoningAvailable("Step \(index)"))
        }
        await transport.emit(.reasoningAvailable(" \u{0000}\n "))
        await transport.release()
        await send.value

        let activity = try #require(model.testRoom?.transcript.receipt?.activity)
        #expect(activity.count == AgentRoomsLiveChatModel.maximumLiveActivityCount)
        #expect(activity.first?.detail == "Step 3")
        #expect(activity.last?.detail == "Step 26")
    }

    @Test("empty and out-of-order events fail closed without leaking a partial assistant")
    func malformedEventsFailClosed() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .success(
                events: [.messageDelta("too early"), .runStarted(""), .messageDelta("")],
                envelope: envelope(runID: "run-malformed", user: "Check", assistant: "Do not show")
            ),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Check", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.turnState == .failed)
        #expect(model.testRoom?.transcript.receipt?.sourceIdentity == "Hermes Runs API")
        #expect(model.testRoom?.transcript.receipt?.runIdentity == nil)
        #expect(model.testRoom?.transcript.receipt?.activity.isEmpty == true)
    }

    @Test("pre-accept failure restores a one-shot draft and retry remains idempotent")
    func failedDraftRecovery() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [], error: .disconnected),
            .success(events: [.runStarted("run-restored")], envelope: envelope(runID: "run-restored", user: "Keep this", assistant: "Kept")),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Keep this", selectedRoomID: roomID)
        #expect(model.turnState == .failed)
        #expect(model.takeRecoveredDraft() == "Keep this")
        #expect(model.takeRecoveredDraft() == nil)

        let clientID = try #require(model.testRoom?.transcript.messages.first?.id)
        let first = Task { await model.retry(clientMessageID: clientID, selectedRoomID: roomID) }
        await model.retry(clientMessageID: clientID, selectedRoomID: roomID)
        await first.value
        #expect(await transport.sentTexts() == ["Keep this", "Keep this"])
    }

    @Test("follow policy follows only near the bottom and resumes after returning")
    func transcriptFollowPolicy() {
        var policy = AgentRoomsTranscriptFollowPolicy()
        let initiallyFollows = policy.shouldFollow(distanceFromBottom: 12)
        #expect(initiallyFollows)
        let followsAfterScrollingUp = policy.shouldFollow(distanceFromBottom: 240)
        #expect(!followsAfterScrollingUp)
        #expect(!policy.shouldAutoScrollForNewContent)
        let followsAfterReturning = policy.shouldFollow(distanceFromBottom: 20)
        #expect(followsAfterReturning)
        #expect(policy.shouldAutoScrollForNewContent)
    }

    @Test("whitespace and over-limit messages never reach transport")
    func validation() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send(" \n\t ", selectedRoomID: roomID)
        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(model.composerMessage == "Type a message before sending.")
        #expect(model.isComposerEnabled(selectedRoomID: roomID))
        await model.send(String(repeating: "x", count: AgentRoomsLiveChatModel.maximumMessageLength + 1), selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(await transport.sentTexts().isEmpty)
        #expect(model.composerMessage == "Messages can be up to 4000 characters.")
    }

    @Test("double submit creates one optimistic message and one transport call")
    func doubleSubmit() async throws {
        let transport = RoomsGateTransport(envelope: envelope(runID: "run-gate", user: "Once", assistant: "Once received"))
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        let first = Task { await model.send("Once", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()
        await model.send("Once", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.count == 1)
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .pending)
        #expect(await transport.sendCount == 1)
        await transport.release()
        await first.value
        #expect(model.testRoom?.transcript.messages.count == 2)
    }

    @Test("pre-accept failure retries with the stable client id and no duplicate optimistic turn")
    func retryIsIdempotent() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [], error: .disconnected),
            .success(events: [.runStarted("run-retry")], envelope: envelope(runID: "run-retry", user: "Retry me", assistant: "Recovered")),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Retry me", selectedRoomID: roomID)
        let clientID = try #require(model.testRoom?.transcript.messages.first?.id)
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.testRoom?.transcript.messages.first?.canRetry == true)
        #expect(model.composerMessage == AgentRoomsLiveChatModel.failedMessage)
        #expect(model.testRoom?.transcript.receipt?.status == .failed)
        #expect(model.testRoom?.transcript.receipt?.sourceIdentity == "Hermes Runs API")
        #expect(model.testRoom?.transcript.receipt?.runIdentity == nil)

        await model.retry(clientMessageID: clientID, selectedRoomID: roomID)

        let messages = try #require(model.testRoom?.transcript.messages)
        #expect(messages.map(\.id).filter { $0 == clientID }.count == 1)
        #expect(messages.map(\.body) == ["Retry me", "Recovered"])
        #expect(await transport.sentTexts() == ["Retry me", "Retry me"])
    }

    @Test("accepted interruption is sanitized and cannot be retried")
    func acceptedFailureDoesNotRetry() async throws {
        let rawRunID = "accepted\u{0000}-run" + String(repeating: "x", count: 200)
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [.runStarted(rawRunID)], error: .privateDetail),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Sensitive", selectedRoomID: roomID)

        let message = try #require(model.testRoom?.transcript.messages.first)
        #expect(message.deliveryState == .failed)
        #expect(!message.canRetry)
        #expect(model.composerMessage == AgentRoomsLiveChatModel.acceptedInterruptionMessage)
        #expect(model.composerMessage?.contains("credential") == false)
        #expect(model.testRoom?.transcript.receipt?.runIdentity?.hasPrefix("accepted-run") == true)
        #expect(model.testRoom?.transcript.receipt?.runIdentity?.contains("\u{0000}") == false)
        #expect(model.testRoom?.transcript.receipt?.runIdentity?.count == AgentRoomsLiveChatModel.maximumRunIdentityLength)
        #expect(model.testRoom?.transcript.receipt?.id.contains("\u{0000}") == false)
        await model.retry(clientMessageID: message.id, selectedRoomID: roomID)
        #expect(await transport.sentTexts() == ["Sensitive"])
    }

    @Test("conflicting run events fail closed without appending an assistant response")
    func outOfOrderResponseFailsClosed() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .success(
                events: [.runStarted("run-one"), .runStarted("run-two")],
                envelope: envelope(runID: "run-one", user: "Check", assistant: "Must not render")
            ),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Check", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.testRoom?.transcript.receipt?.status == .failed)
    }

    @Test("cancel invalidates a late terminal result and uses stop for the accepted run")
    func cancellationDropsLateResult() async throws {
        let transport = RoomsGateTransport(envelope: envelope(runID: "run-late", user: "Stop", assistant: "Late private response"))
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Stop", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await model.cancelActiveSend()
        await transport.release()
        await send.value

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.receipt?.status == .cancelled)
        #expect(model.testRoom?.transcript.receipt?.sourceIdentity == "Hermes Runs API")
        #expect(model.testRoom?.transcript.receipt?.runIdentity == "run-late")
        #expect(await transport.stoppedRunIDs == ["run-late"])
    }

    @Test("production composition injects real transport and does not use fixtures or repository writes")
    func productionCompositionIsRealAndSessionOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let composition = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let appDelegate = try String(contentsOf: root.appendingPathComponent("Sources/Cider/App/AppDelegate.swift"), encoding: .utf8)
        let liveModel = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Services/Conversation/AgentRoomsLiveChatModel.swift"), encoding: .utf8)

        #expect(appDelegate.contains("AgentRoomsSessionModel(transport: HermesRunTransport())"))
        #expect(composition.contains("session: agentRoomsSession"))
        #expect(composition.contains("handleExternalOpenTarget(route.userInfo)"))
        #expect(!composition.contains("AgentRoomsLiveChatModel(transport:"))
        #expect(!composition.contains("AgentRoomsFixtureProvider"))
        #expect(!liveModel.contains("ConversationRepository"))
        #expect(!liveModel.contains("LegacyConversation"))
        #expect(!liveModel.contains("ConversationShadow"))
        #expect(!liveModel.contains("CiderAgentChatRegistry"))
        #expect(!liveModel.contains("HermesSessionService"))
        #expect(!liveModel.contains("AIConversationStorage"))
        #expect(!liveModel.contains("CiderVault"))

        let view = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"), encoding: .utf8)
        for required in [
            "Start Cider Test Chat",
            "Live continuation",
            "TextField(composerPlaceholder(roomID: roomID)",
            "Button(\"Send\")",
            ".onSubmit",
            "Shift-Return adds a line",
            "Retry failed message",
            "DisclosureGroup",
            "Turn activity receipt",
            "Cider sources",
            "Sources do not verify the assistant response",
            "ForEach(receipts)",
            "Button(\"Open\")",
            "Source-backed Cider",
            "onOpenCiderReference(receipt.openRoute)",
            "onOpenCiderReference(route)",
            "AgentRoomsBookmarkReceiptThumbnailView(",
            "AgentRoomsBookmarkReceiptThumbnailLoader()",
            "await loader.load(",
            "Color.clear",
            ".accessibilityElement(children: .contain)",
            "Legacy messaging stays disabled; Cider Test Chat remains separate.",
            "Open Live Chat",
        ] {
            #expect(view.contains(required))
        }
        #expect(view.components(separatedBy: "Button(\"Open\")").count - 1 == 2)
        #expect(!view.contains("sourceRef"))
        #expect(!view.contains("relativePath"))
    }

    private func makeModel(
        _ transport: some HermesBridgeTransport,
        savedBookmarkMatches: @escaping @MainActor (URL) -> [AgentRoomsSavedBookmarkReference] = { _ in [] }
    ) -> AgentRoomsLiveChatModel {
        AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            savedBookmarkMatches: savedBookmarkMatches
        )
    }
}

private enum RoomsTransportError: Error, Sendable {
    case disconnected
    case privateDetail
}

private enum RoomsTransportScript: Sendable {
    case success(events: [HermesRunEvent], envelope: HermesRunCompletionEnvelope)
    case failure(events: [HermesRunEvent], error: RoomsTransportError)
}

private actor RoomsScriptedTransport: HermesBridgeTransport {
    let configuredAvailability: HermesBridgeAvailability
    private var scripts: [RoomsTransportScript]
    private var texts: [String] = []

    init(availability: HermesBridgeAvailability, scripts: [RoomsTransportScript]) {
        self.configuredAvailability = availability
        self.scripts = scripts
    }

    func availability() async -> HermesBridgeAvailability { configuredAvailability }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        texts.append(text)
        guard !scripts.isEmpty else { throw RoomsTransportError.disconnected }
        switch scripts.removeFirst() {
        case .success(let events, let envelope):
            for event in events { await onEvent?(event) }
            return HermesBridgeSendResult(completion: envelope)
        case .failure(let events, let error):
            for event in events { await onEvent?(event) }
            throw error
        }
    }

    func stop(runID: String) async throws {}
    func sentTexts() -> [String] { texts }
}

private actor RoomsGateTransport: HermesBridgeTransport {
    let resultEnvelope: HermesRunCompletionEnvelope
    private(set) var sendCount = 0
    private(set) var stoppedRunIDs: [String] = []
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventHandler: (@Sendable (HermesRunEvent) async -> Void)?

    init(envelope: HermesRunCompletionEnvelope) { self.resultEnvelope = envelope }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        eventHandler = onEvent
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await onEvent?(.runStarted(resultEnvelope.runID ?? ""))
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return HermesBridgeSendResult(completion: resultEnvelope)
    }

    func stop(runID: String) async throws { stoppedRunIDs.append(runID) }

    func waitUntilSendStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func emit(_ event: HermesRunEvent) async {
        await eventHandler?(event)
    }
}

private func envelope(
    runID: String,
    user: String,
    assistant: String,
    ciderReferences: [HermesCiderReference] = []
) -> HermesRunCompletionEnvelope {
    let timestamp = Date(timeIntervalSince1970: 1_805_000_000)
    let sessionID = "session-805"
    let userSource = "hermes-run:\(runID):user"
    let assistantSource = "hermes-run:\(runID):assistant"
    let messages: [AIAssistantMessage] = [
        .init(role: .user, content: user, timestamp: timestamp, sourceID: userSource, sourceSessionID: sessionID, sourceName: "Hermes"),
        .init(role: .assistant, content: assistant, timestamp: timestamp, sourceID: assistantSource, sourceSessionID: sessionID, sourceName: "Hermes"),
    ]
    return HermesRunCompletionEnvelope(
        provenance: .hermesRunsAPI,
        runID: runID,
        terminalStatus: .completed,
        observedFacts: .none,
        finalSessionSynchronizationComplete: true,
        finalMessages: messages,
        finalState: HermesConversationState(
            conversationID: UUID(),
            activeRuntimeSessionID: sessionID,
            runtimeSessionLineage: [sessionID],
            title: "Cider Test Chat",
            source: "cider-rooms-live-continuation",
            lastSyncedAt: timestamp,
            lastSyncedMessageID: assistantSource,
            lastSyncedTimestamp: timestamp,
            lastImportedRuntimeSessionID: sessionID
        ),
        modelIdentity: "hermes-live",
        terminalSourceEvidence: .init(
            reportedTerminalRunID: runID,
            userSourceID: userSource,
            assistantSourceID: assistantSource,
            userSourceSessionID: sessionID,
            assistantSourceSessionID: sessionID
        ),
        ciderReferences: ciderReferences
    )
}
