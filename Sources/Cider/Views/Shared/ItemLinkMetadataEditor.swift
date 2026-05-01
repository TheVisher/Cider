import SwiftUI

struct ItemLinkMetadataEditor: View {
    let sourceRef: LibraryEntityRef
    var showsSectionHeader = true
    var onOpenRef: ((LibraryEntityRef) -> Void)?

    @ObservedObject private var bookmarks = VaultBookmarkService.shared
    @ObservedObject private var notes = NotesStorage.shared
    @ObservedObject private var dateCards = DateCardStorage.shared
    @ObservedObject private var contacts = ContactStorage.shared
    @ObservedObject private var todos = TodoCardStorage.shared
    @ObservedObject private var files = VaultFileService.shared

    @State private var refreshID = UUID()
    @State private var errorMessage: String?

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if showsSectionHeader {
                HStack(spacing: Spacing.xs) {
                    Text("Linked")
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    addMenu
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    addMenu
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if linkedSummaries.isEmpty {
                Text(ItemLinkMetadataActions.emptyStateText(hasAddableTargets: hasAddableTargets))
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(linkedSummaries) { summary in
                        linkedRow(summary)
                    }
                }
            }
        }
        .id(refreshID)
    }

    private var addMenu: some View {
        Menu {
            if visibleCandidateGroups.isEmpty {
                Text("No items available")
            } else {
                ForEach(visibleCandidateGroups) { group in
                    Menu(group.title) {
                        ForEach(group.candidates) { candidate in
                            Button(candidate.title) {
                                add(candidate.ref)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(CiderFont.bodyMedium(scale: textScale))
                .foregroundColor(visibleCandidateGroups.isEmpty ? CiderColors.quaternary : CiderColors.controlAccent)
                .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .disabled(visibleCandidateGroups.isEmpty)
        .help(visibleCandidateGroups.isEmpty ? "No items available to link" : "Add linked item")
    }

    private func linkedRow(_ summary: ItemLinkSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Button {
                onOpenRef?(summary.ref)
            } label: {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: summary.symbol)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: Spacing.md, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                            .font(CiderFont.bodyMedium(scale: textScale))
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)

                        if !summary.subtitle.isEmpty {
                            Text(summary.subtitle)
                                .font(CiderFont.caption(scale: textScale))
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpenRef == nil)

            Button {
                remove(summary.ref)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove link")
        }
    }

    private var linkedRefs: [LibraryEntityRef] {
        _ = refreshID
        return (try? ItemLinkService.shared.relatedRefs(for: sourceRef)) ?? []
    }

    private var linkedSummaries: [ItemLinkSummary] {
        ItemLinkService.shared.summaries(for: linkedRefs)
    }

    private var visibleCandidateGroups: [ItemLinkMetadataCandidateGroup] {
        ItemLinkMetadataActions.visibleGroups(
            source: sourceRef,
            relatedRefs: linkedRefs,
            groups: candidateGroups
        )
    }

    private var hasAddableTargets: Bool {
        !visibleCandidateGroups.isEmpty
    }

    private var candidateGroups: [ItemLinkMetadataCandidateGroup] {
        [
            candidateGroup(title: "Bookmarks", candidates: bookmarks.bookmarks.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .bookmark, entityID: $0.id),
                    title: $0.title,
                    subtitle: $0.hostDisplay
                )
            }),
            candidateGroup(title: "Notes", candidates: notes.notes.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .note, entityID: $0.id),
                    title: $0.title,
                    subtitle: $0.relativePath.isEmpty ? "Note" : $0.relativePath
                )
            }),
            candidateGroup(title: "Todos", candidates: todos.todoCards.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .todo, entityID: $0.id),
                    title: $0.title,
                    subtitle: "Todo"
                )
            }),
            candidateGroup(title: "Date Cards", candidates: dateCards.dateCards.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .dateCard, entityID: $0.id),
                    title: $0.title,
                    subtitle: "Date card"
                )
            }),
            candidateGroup(title: "Contacts", candidates: contacts.contacts.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .contact, entityID: $0.id),
                    title: $0.displayName,
                    subtitle: $0.relationshipLabel.isEmpty ? "Contact" : $0.relationshipLabel
                )
            }),
            candidateGroup(title: "Files", candidates: files.files.map {
                ItemLinkMetadataCandidate(
                    ref: LibraryEntityRef(type: .vaultFile, entityID: $0.id),
                    title: $0.displayTitle,
                    subtitle: $0.relativePath
                )
            })
        ]
    }

    private func candidateGroup(
        title: String,
        candidates: [ItemLinkMetadataCandidate]
    ) -> ItemLinkMetadataCandidateGroup {
        ItemLinkMetadataCandidateGroup(title: title, candidates: candidates)
    }

    private func add(_ target: LibraryEntityRef) {
        do {
            try ItemLinkService.shared.addLink(from: sourceRef, to: target)
            errorMessage = nil
            refreshID = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ target: LibraryEntityRef) {
        do {
            try ItemLinkService.shared.removeLink(from: sourceRef, to: target)
            errorMessage = nil
            refreshID = UUID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
