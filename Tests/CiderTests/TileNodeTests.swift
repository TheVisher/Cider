import Testing
import CoreGraphics
@testable import Cider

@Suite("TileNode Tests")
struct TileNodeTests {
    private struct LCG {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 1 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1
            return state
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            let width = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % width)
        }

        mutating func bool() -> Bool {
            (next() & 1) == 0
        }

        mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
            let raw = Double(next() & 0xFFFF_FFFF) / Double(UInt32.max)
            return range.lowerBound + CGFloat(raw) * (range.upperBound - range.lowerBound)
        }
    }

    private func makeRandomTree(leafCount: Int, rng: inout LCG, nextID: inout UInt32) -> TileNode {
        if leafCount <= 1 {
            nextID += 1
            let id = CGWindowID(nextID)
            return .leaf(windowID: id, pid: pid_t(id))
        }

        let leftLeaves = rng.int(in: 1...(leafCount - 1))
        let rightLeaves = leafCount - leftLeaves
        let orientation: SplitOrientation = rng.bool() ? .horizontal : .vertical
        let ratio = rng.cgFloat(in: 0.2...0.8)
        let left = makeRandomTree(leafCount: leftLeaves, rng: &rng, nextID: &nextID)
        let right = makeRandomTree(leafCount: rightLeaves, rng: &rng, nextID: &nextID)
        return .split(orientation: orientation, ratio: ratio, left: left, right: right)
    }

    private func countSplits(_ node: TileNode) -> Int {
        switch node {
        case .leaf:
            return 0
        case .split(_, _, let left, let right):
            return 1 + countSplits(left) + countSplits(right)
        }
    }

    private func approxEqual(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - calculateFrames

    @Test("Two leaves with horizontal split produce correct frames with gap")
    func calculateFramesTwoLeaves() {
        let node = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: .leaf(windowID: 2, pid: 200)
        )

        let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let gap: CGFloat = 10
        let frames = node.calculateFrames(in: rect, gap: gap)

        #expect(frames.count == 2)

        let leftFrame = frames.first(where: { $0.0 == 1 })!.2
        let rightFrame = frames.first(where: { $0.0 == 2 })!.2

        // Left: x=0, width = 500 - 5 = 495
        #expect(abs(leftFrame.origin.x - 0) < 0.01)
        #expect(abs(leftFrame.width - 495) < 0.01)
        #expect(abs(leftFrame.height - 800) < 0.01)

        // Right: x = 505, width = 495
        #expect(abs(rightFrame.origin.x - 505) < 0.01)
        #expect(abs(rightFrame.width - 495) < 0.01)
    }

    @Test("Three leaves with nested split produce correct frames")
    func calculateFramesThreeLeaves() {
        // Split: left=window1, right=(split: top=window2, bottom=window3)
        let innerSplit = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: innerSplit
        )

        let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = root.calculateFrames(in: rect, gap: 10)

        #expect(frames.count == 3)

        // All three windows should be present
        let ids = Set(frames.map { $0.0 })
        #expect(ids == [1, 2, 3])
    }

    @Test("Randomized trees produce valid frames and consistent split metadata")
    func randomizedTreeStress() {
        let rootRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 10

        for seed in 1...200 {
            var rng = LCG(seed: UInt64(seed))
            var nextID: UInt32 = 0
            let leaves = rng.int(in: 2...8)
            let tree = makeRandomTree(leafCount: leaves, rng: &rng, nextID: &nextID)

            let frames = tree.calculateFrames(in: rootRect, gap: gap)
            #expect(frames.count == leaves)

            for i in frames.indices {
                let frame = frames[i].2
                #expect(frame.width > 0)
                #expect(frame.height > 0)
                #expect(frame.minX >= rootRect.minX - 0.5)
                #expect(frame.minY >= rootRect.minY - 0.5)
                #expect(frame.maxX <= rootRect.maxX + 0.5)
                #expect(frame.maxY <= rootRect.maxY + 0.5)

                for j in (i + 1)..<frames.count {
                    let overlap = frame.intersection(frames[j].2)
                    let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
                    #expect(overlapArea <= 1.0)
                }
            }

            let splitLines = tree.splitLines(in: rootRect, gap: gap)
            #expect(splitLines.count == countSplits(tree))

            for line in splitLines {
                let resolved = tree.splitRect(at: line.path, in: rootRect, gap: gap)
                #expect(resolved != nil)
                if let resolved {
                    #expect(approxEqual(resolved.minX, line.boundingRect.minX))
                    #expect(approxEqual(resolved.minY, line.boundingRect.minY))
                    #expect(approxEqual(resolved.width, line.boundingRect.width))
                    #expect(approxEqual(resolved.height, line.boundingRect.height))
                }
            }
        }
    }

    @Test("Randomized ratio updates keep frames valid")
    func randomizedRatioUpdateStress() {
        let rootRect = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let gap: CGFloat = 10

        for seed in 1...120 {
            var rng = LCG(seed: UInt64(10_000 + seed))
            var nextID: UInt32 = 0
            let leaves = rng.int(in: 2...8)
            var tree = makeRandomTree(leafCount: leaves, rng: &rng, nextID: &nextID)

            for _ in 0..<25 {
                let lines = tree.splitLines(in: rootRect, gap: gap)
                guard !lines.isEmpty else { break }
                let chosen = lines[rng.int(in: 0...(lines.count - 1))]
                let newRatio = rng.cgFloat(in: 0.0...1.0)
                tree = tree.updateRatioAtPath(chosen.path, newRatio: newRatio)

                let frames = tree.calculateFrames(in: rootRect, gap: gap)
                #expect(frames.count == leaves)
                for (_, _, frame) in frames {
                    #expect(frame.width > 0)
                    #expect(frame.height > 0)
                    #expect(frame.minX >= rootRect.minX - 0.5)
                    #expect(frame.minY >= rootRect.minY - 0.5)
                    #expect(frame.maxX <= rootRect.maxX + 0.5)
                    #expect(frame.maxY <= rootRect.maxY + 0.5)
                }
            }
        }
    }

    // MARK: - removeLeaf

    @Test("Remove leaf from 3-leaf tree collapses the empty parent")
    func removeLeafNormalization() {
        let innerSplit = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: innerSplit
        )

        // Remove window 2 from the inner split
        let result = root.removeLeaf(windowID: 2)
        #expect(result != nil)

        // Should have 2 windows remaining
        let remaining = result!.allWindowIDs()
        #expect(remaining.count == 2)
        #expect(remaining.contains(where: { $0.0 == 1 }))
        #expect(remaining.contains(where: { $0.0 == 3 }))

        // The result should be a single split (not nested)
        if case .split(_, _, let left, let right) = result! {
            if case .leaf = left, case .leaf = right {
                // Good: both children are leaves
            } else {
                Issue.record("Expected both children to be leaves after normalization")
            }
        } else {
            Issue.record("Expected a split node")
        }
    }

    @Test("Remove leaf from 2-leaf tree returns single leaf (dissolve)")
    func removeLeafDissolve() {
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: .leaf(windowID: 2, pid: 200)
        )

        let result = root.removeLeaf(windowID: 1)
        #expect(result != nil)

        if case .leaf(let wid, let pid) = result! {
            #expect(wid == 2)
            #expect(pid == 200)
        } else {
            Issue.record("Expected a single leaf after removing from 2-leaf tree")
        }
    }

    // MARK: - updateRatio

    @Test("updateRatio clamps to valid range")
    func updateRatioClamping() {
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: .leaf(windowID: 2, pid: 200)
        )

        // Try setting ratio too low
        let lowResult = root.updateRatio(forWindow: 1, newRatio: 0.0)
        if case .split(_, let ratio, _, _) = lowResult {
            #expect(ratio >= 0.1)
        }

        // Try setting ratio too high
        let highResult = root.updateRatio(forWindow: 1, newRatio: 1.0)
        if case .split(_, let ratio, _, _) = highResult {
            #expect(ratio <= 0.9)
        }

        // Valid ratio passes through
        let validResult = root.updateRatio(forWindow: 1, newRatio: 0.6)
        if case .split(_, let ratio, _, _) = validResult {
            #expect(abs(ratio - 0.6) < 0.001)
        }
    }

    @Test("updateRatioAtPath updates only the targeted nested split")
    func updateRatioAtPathNested() {
        let nested = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: nested
        )

        let result = root.updateRatioAtPath([1], newRatio: 0.7)

        guard case .split(_, let rootRatio, _, let right) = result else {
            Issue.record("Expected root split")
            return
        }
        #expect(abs(rootRatio - 0.5) < 0.001)

        guard case .split(_, let nestedRatio, _, _) = right else {
            Issue.record("Expected nested right split")
            return
        }
        #expect(abs(nestedRatio - 0.7) < 0.001)
    }

    // MARK: - parentSplitInfo / splitRect

    @Test("parentSplitInfo returns direct split path and child index")
    func parentSplitInfoPath() {
        let nested = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: nested
        )

        let infoForThree = root.parentSplitInfo(of: 3)
        #expect(infoForThree?.path == [1])
        #expect(infoForThree?.orientation == .vertical)
        #expect(infoForThree?.childIndex == 1)

        let infoForOne = root.parentSplitInfo(of: 1)
        #expect(infoForOne?.path == [])
        #expect(infoForOne?.orientation == .horizontal)
        #expect(infoForOne?.childIndex == 0)
    }

    @Test("splitRect resolves nested split bounds")
    func splitRectNestedBounds() {
        let nested = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: nested
        )

        let rootRect = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let gap: CGFloat = 10

        guard let nestedRect = root.splitRect(at: [1], in: rootRect, gap: gap) else {
            Issue.record("Expected nested split rect")
            return
        }

        #expect(abs(nestedRect.origin.x - 505) < 0.01)
        #expect(abs(nestedRect.origin.y - 0) < 0.01)
        #expect(abs(nestedRect.width - 495) < 0.01)
        #expect(abs(nestedRect.height - 800) < 0.01)
    }

    // MARK: - replaceLeaf

    @Test("replaceLeaf inserts new split at correct position")
    func replaceLeafInsertion() {
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: .leaf(windowID: 2, pid: 200)
        )

        let newSplit = TileNode.split(
            orientation: .vertical,
            ratio: 0.5,
            left: .leaf(windowID: 2, pid: 200),
            right: .leaf(windowID: 3, pid: 300)
        )

        let result = root.replaceLeaf(windowID: 2, with: newSplit)
        let allWindows = result.allWindowIDs()
        #expect(allWindows.count == 3)
        #expect(allWindows.contains(where: { $0.0 == 1 }))
        #expect(allWindows.contains(where: { $0.0 == 2 }))
        #expect(allWindows.contains(where: { $0.0 == 3 }))
    }

    // MARK: - containsWindow

    @Test("containsWindow traverses the tree")
    func containsWindowTraversal() {
        let root = TileNode.split(
            orientation: .horizontal,
            ratio: 0.5,
            left: .leaf(windowID: 1, pid: 100),
            right: .split(
                orientation: .vertical,
                ratio: 0.5,
                left: .leaf(windowID: 2, pid: 200),
                right: .leaf(windowID: 3, pid: 300)
            )
        )

        #expect(root.containsWindow(1) == true)
        #expect(root.containsWindow(2) == true)
        #expect(root.containsWindow(3) == true)
        #expect(root.containsWindow(4) == false)
    }
}
