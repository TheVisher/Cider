enum MetadataRailSectionKind {
    case title
    case source
    case folder
    case tags
    case notes
    case sources
    case history
    case intelligence
    case images
    case keywords
    case linked
    case info
}

enum MetadataRailExpansionPolicy {
    static func defaultExpanded(for section: MetadataRailSectionKind, hasContent: Bool) -> Bool {
        switch section {
        case .title, .source, .info:
            return true
        case .folder, .tags, .notes, .sources, .history, .intelligence, .images, .keywords, .linked:
            return hasContent
        }
    }
}
