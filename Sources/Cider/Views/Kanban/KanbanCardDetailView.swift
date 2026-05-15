import SwiftUI

/// Long-form editor for a Kanban card inside the shared Cider detail panel.
struct KanbanCardDetailView: View {
    @Binding var draft: KanbanCardDraft
    var onSave: () -> Void

    @FocusState private var notesFocused: Bool
    @State private var newHistoryType: KanbanCardHistoryEntryType = .note
    @State private var newHistoryBody = ""

    init(draft: Binding<KanbanCardDraft>, onSave: @escaping () -> Void) {
        _draft = draft
        self.onSave = onSave
    }

    private var qualityReport: KanbanCardQualityReport {
        KanbanCardQualityReport(notes: draft.notes)
    }

    private var notesOutline: KanbanCardNotesOutline {
        KanbanCardNotesOutline(notes: draft.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            KanbanCardQualityChecklistView(report: qualityReport)

            KanbanCardHistorySectionView(
                entries: $draft.historyEntries,
                newEntryType: $newHistoryType,
                newEntryBody: $newHistoryBody
            )

            if notesOutline.hasStructuredSections {
                KanbanCardNotesOutlineView(outline: notesOutline)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Spec / Notes")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                TextEditor(text: $draft.notes)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($notesFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .center, spacing: Spacing.md) {
                Text("Plain text for now. Export Markdown when you need a portable copy.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                Button("Save") {
                    onSave()
                }
                .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }
}

private struct KanbanCardNotesOutlineView: View {
    var outline: KanbanCardNotesOutline

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("Readable Sections")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(outline.sections.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CiderColors.surfaceInput))

                Spacer(minLength: Spacing.sm)

                Text("Preview only — raw notes stay editable below")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            if !outline.leadingText.isEmpty {
                Text(outline.leadingText)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm, alignment: .top)], alignment: .leading, spacing: Spacing.sm) {
                ForEach(outline.sections) { section in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(section.title)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.primary)

                        if section.bulletItems.isEmpty {
                            Text(section.body.isEmpty ? "No details yet." : section.body)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineSpacing(3)
                                .lineLimit(5)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(section.bulletItems.prefix(4), id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                        Text("•")
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.tertiary)
                                        Text(item)
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.secondary)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CiderColors.surfaceInput.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

private struct KanbanCardHistorySectionView: View {
    @Binding var entries: [KanbanCardHistoryEntry]
    @Binding var newEntryType: KanbanCardHistoryEntryType
    @Binding var newEntryBody: String

    private var sortedEntries: [KanbanCardHistoryEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    private var canAddEntry: Bool {
        !newEntryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("History")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("\(entries.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CiderColors.surfaceInput))

                Spacer(minLength: Spacing.sm)

                Text("Typed card memory")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            if entries.isEmpty {
                Text("No structured history yet. Add implementation notes, failed attempts, test evidence, summaries, or commits without replacing the main notes field.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(sortedEntries) { entry in
                        KanbanCardHistoryEntryRow(entry: entry)
                    }
                }
            }

            Divider()
                .overlay(CiderColors.borderSubtle)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Picker("Type", selection: $newEntryType) {
                        ForEach(KanbanCardHistoryEntryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    Spacer(minLength: Spacing.sm)

                    Button("Add History") {
                        addEntry()
                    }
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(!canAddEntry)
                }

                TextEditor(text: $newEntryBody)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.primary)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                    .frame(minHeight: 58, maxHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CiderColors.surfaceInput.opacity(0.6))
                    )
                    .overlay(alignment: .topLeading) {
                        if newEntryBody.isEmpty {
                            Text("Add a focused history entry…")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.sm)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CiderColors.borderDefault, lineWidth: 1)
                )
        )
    }

    private func addEntry() {
        let trimmedBody = newEntryBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        entries.append(
            KanbanCardHistoryEntry(
                type: newEntryType,
                body: trimmedBody,
                createdAt: Date()
            )
        )
        newEntryBody = ""
        newEntryType = .note
    }
}

private struct KanbanCardHistoryEntryRow: View {
    var entry: KanbanCardHistoryEntry

    private var timestamp: String {
        entry.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: entry.type.symbolName)
                .font(.caption)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(entry.type.displayName)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)

                    Text(timestamp)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    if let author = entry.author, !author.isEmpty {
                        Text("• \(author)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Text(entry.body)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }
}

private struct KanbanCardQualityChecklistView: View {
    var report: KanbanCardQualityReport

    private var statusColor: Color {
        switch report.status {
        case .ready:
            CiderColors.success
        case .needsContext:
            CiderColors.warning
        }
    }

    private var statusIcon: String {
        switch report.status {
        case .ready:
            "checkmark.seal.fill"
        case .needsContext:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)

                Text(report.summary)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: Spacing.sm)

                Text("Agent checklist")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: Spacing.xs)],
                alignment: .leading,
                spacing: Spacing.xs
            ) {
                ForEach(report.items) { item in
                    KanbanCardQualityChecklistChip(item: item)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

private struct KanbanCardQualityChecklistChip: View {
    var item: KanbanCardQualityReport.Item

    private var color: Color {
        item.isPresent ? CiderColors.success : CiderColors.tertiary
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isPresent ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(color)

            Text(item.section.displayName)
                .font(CiderFont.caption)
                .foregroundColor(item.isPresent ? CiderColors.secondary : CiderColors.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(item.isPresent ? 0.10 : 0.06))
        )
        .help(item.isPresent ? "Section detected" : "Missing optional/essential context")
    }
}
