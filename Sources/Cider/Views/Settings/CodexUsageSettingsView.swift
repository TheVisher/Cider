import SwiftUI

struct CodexUsageSettingsView: View {
    @ObservedObject var usageState: CodexUsageObservableState
    private let formatter = CodexUsageSettingsFormatter()

    private var content: CodexUsageSettingsContent {
        formatter.content(for: usageState.state)
    }

    var body: some View {
        SettingsSection(title: "Codex Usage") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header

                switch content {
                case .idle(let message, _), .loading(let message, _), .failed(let message, _):
                    Text(message)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                case .loaded(let display):
                    loadedContent(display)
                }
            }
        }
        .onDisappear {
            usageState.cancel(silently: true)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                headerSummary
                Spacer(minLength: Spacing.sm)
                refreshControls
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerSummary
                refreshControls
            }
        }
    }

    @ViewBuilder
    private var headerSummary: some View {
        if case .loaded(let display) = content {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(display.planLabel)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Last checked \(display.lastChecked)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Check your current Codex allowances when you choose.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshControls: some View {
        HStack(spacing: Spacing.sm) {
            if content.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Button(action: refresh) {
                Label(content.actionTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(CiderSecondaryButtonStyle())
            .disabled(content.isLoading)
            .accessibilityLabel(content.isLoading ? "Refreshing Codex usage" : "Refresh Codex usage")
            .accessibilityHint("Runs a read-only usage check only when activated. It does not start a model turn.")
            .accessibilityValue(content.accessibilityValue)
        }
    }

    private func refresh() {
        guard !content.isLoading else { return }
        usageState.refresh()
    }

    private func loadedContent(_ display: CodexUsageSettingsDisplay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CodexUsageSubsection(title: "Codex", rows: display.codexRows)

            if !display.sparkSections.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(display.sparkNotice)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(display.sparkSections.enumerated()), id: \.offset) { _, section in
                        CodexUsageSubsection(title: section.title, rows: section.rows)
                    }
                }
                .padding(.top, Spacing.xs)
            }

            ForEach(Array(display.additionalSections.enumerated()), id: \.offset) { _, section in
                CodexUsageSubsection(title: section.title, rows: section.rows)
            }
        }
    }
}

private struct CodexUsageSubsection: View {
    let title: String
    let rows: [CodexUsageSettingsDisplay.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider()
                            .opacity(CiderColors.dividerSecondaryOpacity)
                    }
                    CodexUsageRowView(row: row)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.thinStrokeWidth)
            )
        }
    }
}

private struct CodexUsageRowView: View {
    let row: CodexUsageSettingsDisplay.Row

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    rowTitle
                    Spacer(minLength: Spacing.sm)
                    severity
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    rowTitle
                    severity
                }
            }

            if let used = row.usedPercent, let remaining = row.remainingPercent {
                Text("\(used)% used · \(remaining)% remaining")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reset = row.reset {
                Text("Resets \(reset)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(row.guidance)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.label)
        .accessibilityValue(accessibilityValue)
    }

    private var rowTitle: some View {
        Text(row.label)
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var severity: some View {
        Text(row.severity)
            .font(CiderFont.captionSemibold)
            .foregroundColor(severityColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityValue: String {
        [
            row.usedPercent.map { "\($0) percent used" },
            row.remainingPercent.map { "\($0) percent remaining" },
            row.reset.map { "Resets \($0)" },
            row.severity,
            row.guidance,
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    private var severityColor: Color {
        switch row.severity {
        case "Normal": CiderColors.success
        case "Watch", "Warning", "High": CiderColors.warning
        case "Critical": CiderColors.destructive
        default: CiderColors.secondary
        }
    }
}
