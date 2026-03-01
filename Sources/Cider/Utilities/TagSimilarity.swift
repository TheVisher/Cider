import Foundation

struct SimilarTagGroup: Identifiable {
    let id = UUID()
    let labels: [CardLabel]
    let reason: String
}

enum TagSimilarity {

    /// Returns groups of similar tags that could be merged.
    static func findSimilarGroups(in labels: [CardLabel]) -> [SimilarTagGroup] {
        guard labels.count >= 2 else { return [] }

        var grouped: [[CardLabel]] = []
        var reasons: [String] = []
        var consumed = Set<UUID>()

        // Pass 1: Punctuation-only differences
        groupBy(labels: labels, consumed: &consumed, grouped: &grouped, reasons: &reasons) { a, b in
            let strippedA = a.trimmingCharacters(in: .punctuationCharacters)
            let strippedB = b.trimmingCharacters(in: .punctuationCharacters)
            guard strippedA.localizedCaseInsensitiveCompare(strippedB) == .orderedSame else { return nil }
            guard a != b else { return nil }
            return "Punctuation difference"
        }

        // Pass 2: Plural/conjugation variants
        groupBy(labels: labels, consumed: &consumed, grouped: &grouped, reasons: &reasons) { a, b in
            let stemA = stemmedForm(a.lowercased())
            let stemB = stemmedForm(b.lowercased())
            guard stemA == stemB, a.lowercased() != b.lowercased() else { return nil }
            return "Plural variants"
        }

        // Pass 3: Case difference (should be rare due to findOrCreate, but catches legacy)
        groupBy(labels: labels, consumed: &consumed, grouped: &grouped, reasons: &reasons) { a, b in
            guard a.localizedCaseInsensitiveCompare(b) == .orderedSame else { return nil }
            guard a != b else { return nil }
            return "Case difference"
        }

        // Pass 4: High string similarity (Levenshtein)
        groupBy(labels: labels, consumed: &consumed, grouped: &grouped, reasons: &reasons) { a, b in
            let dist = editDistance(a.lowercased(), b.lowercased())
            let threshold = max(a.count, b.count) <= 6 ? 2 : 3
            guard dist > 0, dist <= threshold else { return nil }
            return "Similar spelling"
        }

        return zip(grouped, reasons).map { SimilarTagGroup(labels: $0.0, reason: $0.1) }
    }

    /// Suggests the best merge target from a group — shortest, cleanest name.
    static func suggestedTarget(in group: SimilarTagGroup) -> CardLabel {
        group.labels.min { a, b in
            let cleanA = a.name.trimmingCharacters(in: .punctuationCharacters)
            let cleanB = b.name.trimmingCharacters(in: .punctuationCharacters)
            if cleanA.count != cleanB.count { return cleanA.count < cleanB.count }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        } ?? group.labels[0]
    }

    // MARK: - String Utilities

    /// Levenshtein edit distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    /// Strip common English suffixes to get a rough stem.
    static func stemmedForm(_ word: String) -> String {
        let suffixes = ["ing", "tion", "sion", "ment", "ness", "able", "ible", "ed", "er", "est", "ly", "es", "s"]
        var result = word
        for suffix in suffixes {
            if result.count > suffix.count + 2, result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result
    }

    // MARK: - Grouping Helper

    /// Groups labels by a pairwise matcher. `matcher` returns a reason string if two names should group, nil otherwise.
    private static func groupBy(
        labels: [CardLabel],
        consumed: inout Set<UUID>,
        grouped: inout [[CardLabel]],
        reasons: inout [String],
        matcher: (String, String) -> String?
    ) {
        let available = labels.filter { !consumed.contains($0.id) }
        var localConsumed = Set<UUID>()

        for i in available.indices {
            guard !localConsumed.contains(available[i].id) else { continue }
            var group = [available[i]]
            var reason = ""

            for j in available.indices where j > i {
                guard !localConsumed.contains(available[j].id) else { continue }
                if let r = matcher(available[i].name, available[j].name) {
                    group.append(available[j])
                    reason = r
                    localConsumed.insert(available[j].id)
                }
            }

            if group.count >= 2 {
                localConsumed.insert(available[i].id)
                grouped.append(group)
                reasons.append(reason)
            }
        }

        consumed.formUnion(localConsumed)
    }
}
