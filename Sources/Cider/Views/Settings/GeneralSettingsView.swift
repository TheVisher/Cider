import SwiftUI
import AppKit

// MARK: - Reusable Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    let subtitle: String?
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    init(title: String, subtitle: String? = nil, selection: Binding<T>, options: [T], label: @escaping (T) -> String) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: SettingsDesign.inlinePickerWidth)
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let labels: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.primary)

            HStack(spacing: Spacing.md) {
                Text(labels.0)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

                Slider(value: $value, in: range)
                    .tint(CiderColors.controlAccent)

                Text(labels.1)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
    }
}
