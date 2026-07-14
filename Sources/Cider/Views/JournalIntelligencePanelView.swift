import SwiftUI

struct JournalIntelligenceDayReviewView: View {
    let state: JournalIntelligenceDayReviewLoadState
    @Binding var isExpanded: Bool
    let onReload: () -> Void
    let onOpenSource: (JournalIntelligenceSourceNavigation) -> Void

    var body: some View {
        Group {
            switch state {
            case .loading:
                loadingView
            case .unavailable:
                unavailableView
            case .ready(let model):
                reviewView(model)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiderColors.accentSubtle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var loadingView: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Journal Review")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text(JournalIntelligenceDayReviewHealth.loading.message)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
            }
        }
        .accessibilityLabel("Journal Review is loading. \(JournalIntelligenceDayReviewHealth.loading.message)")
    }

    private var unavailableView: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(CiderColors.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Journal Review")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text(JournalIntelligenceDayReviewHealth.unavailable.message)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                Button("Try again", action: onReload)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Try loading Journal Review again")
            }
            Spacer(minLength: 0)
        }
    }

    private func reviewView(_ model: JournalIntelligenceDayReviewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundColor(CiderColors.controlAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(model.statement)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                    if model.health != .ready || model.suppressedCount > 0 {
                        Text(statusCopy(model))
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.secondary)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Button(isExpanded ? "Close review" : "Open Journal Review") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(isExpanded ? "Close" : "Open") Journal Review. \(model.statement)")
            }

            if isExpanded {
                Divider()
                    .background(CiderColors.separator)

                Label(model.truthBoundaryCopy, systemImage: "shield.lefthalf.filled")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                    .accessibilityLabel("Truth boundary. \(model.truthBoundaryCopy)")

                if model.groups.isEmpty {
                    Text(model.healthMessage)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.vertical, Spacing.xs)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        ForEach(model.groups) { group in
                            reviewGroup(group)
                        }
                    }
                }
            }
        }
    }

    private func statusCopy(_ model: JournalIntelligenceDayReviewModel) -> String {
        if model.suppressedCount > 0, model.health == .ready {
            let noun = model.suppressedCount == 1 ? "suggestion" : "suggestions"
            return "Cider held back \(model.suppressedCount) uncertain \(noun)."
        }
        if model.suppressedCount > 0 {
            let noun = model.suppressedCount == 1 ? "suggestion" : "suggestions"
            return "\(model.healthMessage) Cider held back \(model.suppressedCount) uncertain \(noun)."
        }
        return model.healthMessage
    }

    private func reviewGroup(_ group: JournalIntelligenceReviewGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(group.label)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text("\(group.proposals.count)")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(CiderColors.separatorSubtle, in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.label), \(group.proposals.count) suggestions")

            ForEach(group.proposals) { proposal in
                proposalCard(proposal)
            }
        }
    }

    private func proposalCard(_ proposal: JournalIntelligenceReviewProposal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(proposal.value)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .textSelection(.enabled)
                Text(proposal.statusLabel)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text("\(proposal.candidateType). \(proposal.confidenceReason)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(proposal.reconciliation.label)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text(proposal.reconciliation.explanation)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
                ForEach(proposal.reconciliation.likelyMatches) { match in
                    Text("Likely match: \(match.label) · \(match.kindLabel)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Source evidence")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)
                Text("\(proposal.source.timestamp24Hour) · \(proposal.source.typeLabel) · \(proposal.source.channelLabel)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                Text("“\(proposal.source.quote)”")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .textSelection(.enabled)
                Text("Exact captured-text span \(proposal.source.spanStart)–\(proposal.source.spanEnd)")
                    .font(CiderFont.captionMonospacedMedium)
                    .foregroundColor(CiderColors.tertiary)

                if proposal.sourceNavigation.captureCardID != nil {
                    Button(proposal.sourceNavigation.actionLabel) {
                        onOpenSource(proposal.sourceNavigation)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(proposal.sourceNavigation.actionLabel) at \(proposal.source.timestamp24Hour)")
                    .accessibilityHint(proposal.sourceNavigation.boundaryCopy)
                } else {
                    Text(proposal.sourceNavigation.boundaryCopy)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CiderColors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiderColors.surfaceInput.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.separatorSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(proposal.statusLabel). \(proposal.value). \(proposal.reconciliation.label). Source at \(proposal.source.timestamp24Hour).")
    }
}

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
