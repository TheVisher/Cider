import Foundation
import Testing
@testable import Cider

struct HermesBridgeTransportTests {
    @Test("run snapshot accumulates message deltas and final output")
    func runSnapshotAccumulatesDeltas() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.messageDelta("Hello"))
            .reducing(.messageDelta(", Cider"))
            .reducing(.completed(output: "Hello, Cider"))

        #expect(snapshot.visibleText == "Hello, Cider")
        #expect(snapshot.status == .completed("Hello, Cider"))
    }

    @Test("run snapshot uses final output when no deltas arrived")
    func runSnapshotUsesFinalOutputWhenNoDeltasArrived() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.completed(output: "Done"))

        #expect(snapshot.visibleText == "Done")
        #expect(snapshot.status == .completed("Done"))
    }

    @Test("run snapshot tracks tool preview separately from assistant text")
    func runSnapshotTracksToolPreviewSeparately() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.toolStarted(name: "terminal", preview: "swift test"))
            .reducing(.messageDelta("Tests passed"))

        #expect(snapshot.visibleText == "Tests passed")
        #expect(snapshot.toolSummary == "swift test")
    }
}
