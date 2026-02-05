import SwiftUI

/// A view that displays text with highlighted search matches
struct HighlightedText: View {
    let text: String
    let searchText: String
    let highlightColor: Color

    init(_ text: String, highlight searchText: String, color: Color = .accentColor) {
        self.text = text
        self.searchText = searchText
        self.highlightColor = color
    }

    var body: some View {
        if searchText.isEmpty {
            Text(text)
        } else {
            highlightedTextView
        }
    }

    private var highlightedTextView: some View {
        let query = searchText.lowercased()
        let textLower = text.lowercased()

        // Find all ranges where the search text matches
        var result = Text("")
        var currentIndex = text.startIndex

        while let range = textLower.range(of: query, range: currentIndex..<textLower.endIndex) {
            // Add non-matching text before this match
            if currentIndex < range.lowerBound {
                let beforeText = String(text[currentIndex..<range.lowerBound])
                result = result + Text(beforeText)
            }

            // Add highlighted matching text
            let matchText = String(text[range])
            result = result + Text(matchText)
                .fontWeight(.semibold)
                .foregroundColor(highlightColor)

            currentIndex = range.upperBound
        }

        // Add remaining text after last match
        if currentIndex < text.endIndex {
            let afterText = String(text[currentIndex...])
            result = result + Text(afterText)
        }

        return result
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        HighlightedText("Safari Browser", highlight: "saf")
        HighlightedText("Visual Studio Code", highlight: "code")
        HighlightedText("No Match Here", highlight: "xyz")
        HighlightedText("Multiple matches: test test", highlight: "test")
    }
    .padding()
}
