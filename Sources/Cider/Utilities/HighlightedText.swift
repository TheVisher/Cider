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
            Text(highlightedAttributedString)
        }
    }

    private var highlightedAttributedString: AttributedString {
        var attributed = AttributedString(text)
        let query = searchText.lowercased()
        let textLower = text.lowercased()
        var searchStart = textLower.startIndex

        while let range = textLower.range(of: query, range: searchStart..<textLower.endIndex) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else {
                searchStart = range.upperBound
                continue
            }
            let attrRange = lower ..< upper
            attributed[attrRange].font = CiderFont.bodySemibold
            attributed[attrRange].foregroundColor = highlightColor
            searchStart = range.upperBound
        }

        return attributed
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
