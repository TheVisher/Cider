import Foundation

struct ExtractedRecipe: Equatable, Hashable {
    let title: String?
    let ingredients: [String]
    let instructions: [String]
    let servings: String?
    let totalTime: String?
    let status: RecipeExtractionStatus
}

enum RecipeExtractor {
    static func extract(from bookmark: Bookmark) -> ExtractedRecipe? {
        let text = [bookmark.notes, bookmark.aiSummary ?? "", bookmark.ocrText ?? ""]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let structured = extractJSONLD(from: text) {
            return structured
        }

        return extractCaption(from: text, fallbackTitle: cleanedSocialTitle(bookmark.title))
    }

    private static func extractJSONLD(from text: String) -> ExtractedRecipe? {
        let jsonBlocks = scriptJSONBlocks(in: text) + bareJSONBlocks(in: text)
        for block in jsonBlocks {
            guard let data = block.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = recipeObject(in: object),
               let extracted = extractedRecipe(from: recipe) {
                return extracted
            }
        }
        return nil
    }

    private static func scriptJSONBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var searchStart = text.startIndex
        while let typeRange = text.range(of: "application/ld+json", options: [.caseInsensitive], range: searchStart..<text.endIndex),
              let openEnd = text.range(of: ">", range: typeRange.upperBound..<text.endIndex)?.upperBound,
              let closeRange = text.range(of: "</script>", options: [.caseInsensitive], range: openEnd..<text.endIndex) {
            blocks.append(String(text[openEnd..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            searchStart = closeRange.upperBound
        }
        return blocks
    }

    private static func bareJSONBlocks(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\"@type\"") || trimmed.contains("schema.org/Recipe") else { return [] }
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return [trimmed]
        }
        return []
    }

    private static func recipeObject(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if isRecipeType(dict["@type"]) { return dict }
            if let graph = dict["@graph"] as? [Any] {
                return graph.compactMap(recipeObject(in:)).first
            }
            if let main = dict["mainEntity"] {
                return recipeObject(in: main)
            }
            if let itemListElement = dict["itemListElement"] {
                return recipeObject(in: itemListElement)
            }
        }
        if let array = object as? [Any] {
            return array.compactMap(recipeObject(in:)).first
        }
        return nil
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let string = value as? String { return string.localizedCaseInsensitiveContains("Recipe") }
        if let values = value as? [String] { return values.contains { $0.localizedCaseInsensitiveContains("Recipe") } }
        return false
    }

    private static func extractedRecipe(from recipe: [String: Any]) -> ExtractedRecipe? {
        let title = clean(recipe["name"] as? String)
        let ingredients = stringArray(recipe["recipeIngredient"])
        let instructions = instructionArray(recipe["recipeInstructions"])
        guard !ingredients.isEmpty || !instructions.isEmpty else { return nil }
        return ExtractedRecipe(
            title: title,
            ingredients: ingredients,
            instructions: instructions,
            servings: clean(recipe["recipeYield"] as? String) ?? clean((recipe["recipeYield"] as? [String])?.first),
            totalTime: normalizedDuration(clean(recipe["totalTime"] as? String) ?? clean(recipe["cookTime"] as? String) ?? clean(recipe["prepTime"] as? String)),
            status: .parsed
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.compactMap(clean)
        }
        if let value = value as? String, let cleaned = clean(value) {
            return [cleaned]
        }
        return []
    }

    private static func instructionArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings.compactMap(clean)
        }
        if let dicts = value as? [[String: Any]] {
            return dicts.flatMap { dict -> [String] in
                if let text = clean(dict["text"] as? String) { return [text] }
                if let itemList = dict["itemListElement"] { return instructionArray(itemList) }
                return []
            }
        }
        if let value = value as? String, let cleaned = clean(value) {
            return [cleaned]
        }
        return []
    }

    private static func extractCaption(from text: String, fallbackTitle: String?) -> ExtractedRecipe? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let ingredients = listItems(afterAnyOf: ["ingredients", "ingredient"], beforeAnyOf: ["steps", "instructions", "method", "directions"], in: lines)
        let instructions = listItems(afterAnyOf: ["steps", "instructions", "method", "directions"], beforeAnyOf: [], in: lines)
        guard !ingredients.isEmpty || !instructions.isEmpty else { return nil }

        let title = titleFromCaption(lines: lines, fallbackTitle: fallbackTitle)
        return ExtractedRecipe(
            title: title,
            ingredients: ingredients,
            instructions: instructions,
            servings: nil,
            totalTime: nil,
            status: .needsReview
        )
    }

    private static func listItems(afterAnyOf starts: [String], beforeAnyOf stops: [String], in lines: [String]) -> [String] {
        guard let match = sectionStart(in: lines, starts: starts) else { return [] }

        var values: [String] = match.inlineItems
        for line in lines.dropFirst(match.index + 1) {
            let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased()
            if stops.contains(normalized) || normalized.hasPrefix("by ") || normalized.hasPrefix("via ") { break }
            if starts.contains(normalized) { continue }
            if let item = cleanListItem(line) {
                values.append(item)
            }
        }
        return values
    }

    private static func sectionStart(in lines: [String], starts: [String]) -> (index: Int, inlineItems: [String])? {
        for (index, line) in lines.enumerated() {
            let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased()
            if starts.contains(normalized) { return (index, []) }
            for start in starts {
                guard let markerRange = line.range(of: "\(start):", options: [.caseInsensitive]) else { continue }
                let suffix = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (index, inlineRecipeItems(from: suffix))
            }
        }
        return nil
    }

    private static func inlineRecipeItems(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
        var parts = normalized.components(separatedBy: " - ")
        if parts.count == 1 {
            parts = normalized.components(separatedBy: ",")
        }
        return parts.flatMap { part -> [String] in
            let quantitySplit = part.replacingOccurrences(
                of: #" (?=\d+\s*(?:cup|cups|tsp|tbsp|g|grams?|ml|oz|lbs?)\b)"#,
                with: " | ",
                options: .regularExpression
            )
            return quantitySplit.components(separatedBy: " | ").compactMap(cleanListItem)
        }
    }

    private static func cleanListItem(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, ["-", "•", "*"].contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(of: #"^\d+[\.)]\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return clean(text)
    }

    private static func titleFromCaption(lines: [String], fallbackTitle: String?) -> String? {
        if let first = lines.first,
           !first.trimmingCharacters(in: CharacterSet(charactersIn: ":")).localizedCaseInsensitiveContains("ingredients"),
           !first.trimmingCharacters(in: CharacterSet(charactersIn: ":")).localizedCaseInsensitiveContains("steps") {
            if let fallbackTitle, fallbackTitle.localizedCaseInsensitiveCompare(first) == .orderedSame {
                return fallbackTitle
            }
            return clean(first)
        }
        return fallbackTitle
    }

    private static func cleanedSocialTitle(_ title: String) -> String? {
        clean(title
            .replacingOccurrences(of: "TikTok · ", with: "")
            .replacingOccurrences(of: "TikTok - ", with: ""))
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedDuration(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.hasPrefix("PT"), value.hasSuffix("M") {
            let minutes = value.dropFirst(2).dropLast()
            if let intValue = Int(minutes) {
                return "\(intValue) min"
            }
        }
        return value
    }
}
