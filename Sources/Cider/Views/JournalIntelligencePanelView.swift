import SwiftUI

struct JournalIntelligencePanelView: View {
    var onDock: CiderFloatingDockAction?
    @State private var snapshot: JournalIntelligenceSnapshot = .empty()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    noteSection
                    captureHealthSection
                    candidateSection(title: "Graph Candidates", candidates: snapshot.graphCandidates)
                    candidateSection(title: "Memory Candidates", candidates: snapshot.memoryCandidates)
                    missingOpportunitySection
                    safeCommandsSection
                }
                .padding(Spacing.lg)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(.regularMaterial)
        .task { reload() }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(CiderColors.controlAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Journal Intelligence")
                    .font(.headline)
                Text("Debug read-only surface for latest Daily Journal backend outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reload") { reload() }
                .buttonStyle(.bordered)
            Button {
                onDock?()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Journal Intelligence")
        }
        .padding(Spacing.md)
    }

    private var noteSection: some View {
        GroupBox("Latest Journal") {
            if let note = snapshot.note {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    labelled("Title", note.title)
                    labelled("ID", note.id.uuidString)
                    labelled("Path", note.relativePath ?? "—")
                    labelled("Updated", Self.dateFormatter.string(from: note.updatedAt))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No Daily Journal note found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captureHealthSection: some View {
        GroupBox("Capture Health") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                healthRow("Provenance", snapshot.captureHealth.provenanceStatus, snapshot.captureHealth.provenanceReason)
                healthRow("Indexing", snapshot.captureHealth.indexingStatus, snapshot.captureHealth.indexingReason)
                labelled("Chunk count", String(snapshot.captureHealth.chunkCount))
                if let captureEventID = snapshot.captureHealth.captureEventID {
                    labelled("Capture event", captureEventID)
                }
                if let sourceKind = snapshot.captureHealth.captureSourceKind {
                    labelled("Source kind", sourceKind)
                }
                if let surface = snapshot.captureHealth.captureSurface {
                    labelled("Surface", surface)
                }
                if let channel = snapshot.captureHealth.captureChannel {
                    labelled("Channel", channel)
                }
                if let capturedAt = snapshot.captureHealth.capturedAt {
                    labelled("Captured", Self.dateFormatter.string(from: capturedAt))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func candidateSection(title: String, candidates: [JournalIntelligenceCandidate]) -> some View {
        GroupBox("\(title) (\(candidates.count))") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if candidates.isEmpty {
                    Text("No \(title.lowercased()) for this journal.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var missingOpportunitySection: some View {
        GroupBox("Missing Useful-Memory Opportunities") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if snapshot.missingMemoryOpportunities.isEmpty {
                    Text("No missing-memory heuristic warnings for this snapshot.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.missingMemoryOpportunities) { opportunity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(opportunity.label)
                                .font(.subheadline.weight(.semibold))
                            Text(opportunity.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            commandText(opportunity.safeNextCommand)
                        }
                        .padding(Spacing.sm)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safeCommandsSection: some View {
        GroupBox("Safe Next Commands") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(snapshot.safeNextCommands, id: \.self) { command in
                    commandText(command)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func candidateCard(_ candidate: JournalIntelligenceCandidate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.mentionOrValue)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Text(candidate.reviewState)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
            labelled("Relation / type", candidate.relationOrType)
            if let targetKind = candidate.targetKind {
                labelled("Target kind", targetKind)
            }
            if let confidence = candidate.confidence {
                labelled("Confidence", String(format: "%.2f", confidence))
            }
            labelled("Truth boundary", candidate.truthBoundary)
            qualityView(candidate)
            labelled("Source quote", candidate.sourceQuote)
            labelled("Safe affordances", candidate.safeActions.joined(separator: ", "))
            ForEach(candidate.safeNextCommands.prefix(3), id: \.self) { command in
                commandText(command)
            }
        }
        .padding(Spacing.sm)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func qualityView(_ candidate: JournalIntelligenceCandidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            labelled("Quality", candidate.qualityLevel)
            if !candidate.qualityFlags.isEmpty {
                labelled("Quality flags", candidate.qualityFlags.joined(separator: ", "))
            }
            Text(candidate.qualityExplanation)
                .font(.caption)
                .foregroundStyle(candidate.qualityLevel == "low" ? .orange : .secondary)
                .textSelection(.enabled)
        }
    }

    private func healthRow(_ label: String, _ status: String, _ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            labelled(label, status)
            Text(reason)
                .font(.caption)
                .foregroundStyle(status == "indexed" || status == "recorded" ? Color.secondary : Color.orange)
                .textSelection(.enabled)
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text("\(label):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func commandText(_ command: String) -> some View {
        Text(command)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(.vertical, 2)
    }

    private func reload() {
        do {
            snapshot = try JournalIntelligencePanelService().latestSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
