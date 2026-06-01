import XCTest
@testable import Cider

final class LegacyViewKindCompatibilityTests: XCTestCase {
    func testDashboardKindRoundTripsThroughCodable() throws {
        let legacyView = LegacyView(name: "Dashboard", kind: .dashboard)
        let data = try JSONEncoder.ciderTestEncoder.encode(legacyView)
        let decoded = try JSONDecoder.ciderTestDecoder.decode(LegacyView.self, from: data)

        XCTAssertEqual(decoded.kind, .dashboard)
        XCTAssertEqual(decoded.kind.systemImage, "gauge.medium")
    }

    func testLegacyLibraryKindStillDecodes() throws {
        let payload = """
        {
          "id" : "D0D7E2CC-04FE-4C55-B90E-3D0AE9AEE001",
          "name" : "Library",
          "kind" : {
            "type" : "library"
          },
          "createdAt" : "2026-04-19T18:00:00Z",
          "updatedAt" : "2026-04-19T18:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.ciderTestDecoder.decode(LegacyView.self, from: payload)

        XCTAssertEqual(decoded.kind, .library)
    }
}

private extension JSONEncoder {
    static var ciderTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var ciderTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
