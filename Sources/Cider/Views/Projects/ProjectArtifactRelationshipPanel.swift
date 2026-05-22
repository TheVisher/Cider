import SwiftUI

struct ProjectArtifactRelationshipPanel: View {
    let model: ProjectArtifactRelationshipPanelModel

    var body: some View {
        if !model.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                relationshipSection("Derived Cards", rows: model.derivedCards, symbol: "rectangle.and.pencil.and.ellipsis")
                relationshipSection("Source Note / Plan", rows: model.sourceArtifacts, symbol: "doc.text.magnifyingglass")
                relationshipSection("Related Decisions", rows: model.relatedDecisions, symbol: "checkmark.seal")
                relationshipSection("QA Findings", rows: model.qaFindings, symbol: "checklist.checked")
                relationshipSection("Other Links", rows: model.otherLinks, symbol: "link")
            }
        }
    }

    @ViewBuilder
    private func relationshipSection(_ title: String, rows: [ProjectArtifactRelationshipRow], symbol: String) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(rows) { row in
                        relationshipRow(row, symbol: symbol)
                    }
                }
            }
        }
    }

    private func relationshipRow(_ row: ProjectArtifactRelationshipRow, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(row.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                Text(row.subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)

                if !row.evidence.isEmpty {
                    Text(row.evidence)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
        .help(row.subtitle)
    }
}
