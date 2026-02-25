import SwiftUI
import FoundationModels

struct IntelligenceSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var isAppleIntelligenceAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }
}
