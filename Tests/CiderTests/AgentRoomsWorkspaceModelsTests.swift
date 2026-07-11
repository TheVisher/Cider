import XCTest
@testable import Cider

final class AgentRoomsWorkspaceModelsTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testFixtureIsDeterministicAndDemonstratesRoomsThreadReceiptAndLink() throws {
        guard case .loaded(let rooms, let selectedRoomID) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        XCTAssertEqual(rooms.map(\.id), ["cider-product", "weekly-review", "capture-quality"])
        XCTAssertEqual(rooms.map(\.title), ["Cider Product", "Weekly Review", "Capture Quality"])
        XCTAssertEqual(selectedRoomID, "cider-product")

        let selectedRoom = try XCTUnwrap(rooms.first)
        XCTAssertEqual(selectedRoom.transcript.runtimeLabel, "Hermes")
        XCTAssertEqual(selectedRoom.transcript.messages.map(\.role), [.human, .agent, .human, .agent])
        XCTAssertEqual(selectedRoom.transcript.receipt?.title, "Reviewed CID-786")
        XCTAssertEqual(selectedRoom.transcript.receipt?.status, .completed)
        XCTAssertEqual(selectedRoom.transcript.link?.title, "Cider")
        XCTAssertEqual(selectedRoom.transcript.link?.subtitle, "Project")
        XCTAssertNotNil(selectedRoom.transcript.futureArtifact)
    }

    func testWorkspaceStateProjectsLoadingEmptyFailureAndLoadedStates() {
        XCTAssertEqual(AgentRoomsWorkspaceState.loading.projection(), .loading)
        XCTAssertEqual(AgentRoomsWorkspaceState.empty.projection(), .empty)
        XCTAssertEqual(
            AgentRoomsWorkspaceState.failed(message: "Fixture unavailable").projection(),
            .failed(message: "Fixture unavailable")
        )

        guard case .loaded(let rooms, _) = AgentRoomsFixtureProvider.workspaceState,
              case .loaded(let projectedRooms, let selectedRoom) = AgentRoomsFixtureProvider.workspaceState.projection() else {
            return XCTFail("Expected loaded fixture projection")
        }
        XCTAssertEqual(projectedRooms, rooms)
        XCTAssertEqual(selectedRoom.id, "cider-product")
    }

    func testLoadedProjectionFallsBackToFirstRoomForInvalidSelection() {
        guard case .loaded(let rooms, _) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        let invalidStoredSelection = AgentRoomsWorkspaceState.loaded(
            rooms: rooms,
            selectedRoomID: "missing-room"
        )
        guard case .loaded(_, let storedFallback) = invalidStoredSelection.projection() else {
            return XCTFail("Expected loaded fallback projection")
        }
        XCTAssertEqual(storedFallback.id, rooms[0].id)

        guard case .loaded(_, let localFallback) = AgentRoomsFixtureProvider.workspaceState.projection(
            selectedRoomID: "missing-local-room"
        ) else {
            return XCTFail("Expected loaded local fallback projection")
        }
        XCTAssertEqual(localFallback.id, rooms[0].id)
        XCTAssertEqual(
            AgentRoomsWorkspaceState.loaded(rooms: [], selectedRoomID: "missing").projection(),
            .empty
        )
    }

    func testRoomsSourcesDoNotReferenceProductionConversationDependencies() throws {
        let relativePaths = [
            "Sources/Cider/Models/AgentRoomsWorkspaceModels.swift",
            "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift",
        ]
        let prohibitedTerms = [
            "ConversationRepository",
            "AIAssistantViewModel",
            "AIConversationStorage",
            "coordinator.save",
            "ConversationShadow",
            "HermesBridgeTransport",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            for term in prohibitedTerms {
                XCTAssertFalse(source.contains(term), "\(relativePath) must not reference \(term)")
            }
        }
    }
}
