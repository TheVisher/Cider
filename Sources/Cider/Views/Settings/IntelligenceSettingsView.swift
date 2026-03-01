import SwiftUI
import FoundationModels

struct IntelligenceSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didRetag = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Hardware badge
            hardwareBadge

            SettingsSection(title: "On-Device Intelligence") {
                SettingsToggleRow(
                    title: "Auto-tagging",
                    subtitle: "Suggest tags from bookmark title and content using NaturalLanguage",
                    isOn: $viewModel.enableAutoTagging
                )

                retagAllButton

                SettingsToggleRow(
                    title: "Color extraction",
                    subtitle: "Extract dominant colors from thumbnail images for display",
                    isOn: $viewModel.enableColorExtraction
                )

                SettingsToggleRow(
                    title: "Find similar",
                    subtitle: "Compute semantic vectors so related bookmarks can be surfaced",
                    isOn: $viewModel.enableEmbeddings
                )

                SettingsToggleRow(
                    title: "Image text indexing (OCR)",
                    subtitle: "Extract text from thumbnail images to make them searchable",
                    isOn: $viewModel.enableOCRIndexing
                )
            }

            SettingsSection(title: "Apple Intelligence") {
                SettingsToggleRow(
                    title: "Page summaries",
                    subtitle: "Generate 2-sentence summaries in Reader mode using Foundation Models",
                    isOn: $viewModel.enablePageSummaries
                )
                .disabled(!isAppleIntelligenceAvailable)
                .opacity(isAppleIntelligenceAvailable ? 1.0 : CiderColors.disabledOpacity)

                if !isAppleIntelligenceAvailable {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                        Text("Apple Intelligence is not available on this device or has not been enabled in System Settings.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Hardware Badge

    @ViewBuilder
    private var hardwareBadge: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(isAppleIntelligenceAvailable ? CiderColors.successMuted : CiderColors.tertiary)
                .frame(width: 8, height: 8)
            Text(isAppleIntelligenceAvailable
                 ? "Apple Intelligence available on this device"
                 : "Apple Intelligence not available — on-device NLP features still work")
                .font(CiderFont.caption)
                .foregroundColor(isAppleIntelligenceAvailable ? CiderColors.successMuted : CiderColors.tertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isAppleIntelligenceAvailable
                      ? CiderColors.success.opacity(0.08)
                      : CiderColors.surfaceSubtle)
        )
    }

    // MARK: - Re-tag All

    @ViewBuilder
    private var retagAllButton: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                BookmarkAIEnrichment.shared.retagAll()
                didRetag = true
            } label: {
                Text(didRetag ? "Auto-tagging scheduled" : "Re-run Auto-Tagging on All Bookmarks")
                    .font(CiderFont.caption)
            }
            .buttonStyle(CiderSecondaryButtonStyle())
            .disabled(didRetag || !viewModel.enableAutoTagging)

            Text("Re-analyze all bookmarks with the latest tagging algorithm.")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.leading, Spacing.sm)
    }

    private var isAppleIntelligenceAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }
}
