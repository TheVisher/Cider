import SwiftUI

struct SyncSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Sync") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "externaldrive")
                            .foregroundColor(CiderColors.tertiary)
                            .font(CiderFont.label)

                        Text("Local storage only")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Text("Bookmarks, notes, and folders are saved locally. Remote account sync is unavailable while the sync backend is rebuilt.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
