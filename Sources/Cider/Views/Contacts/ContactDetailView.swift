import AppKit
import SwiftUI

struct ContactDetailView: View {
    let contact: ContactCard
    var onEdit: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var isMetadataExpanded = true
    @State private var avatarImage: NSImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @ObservedObject private var dateCardStorage = DateCardStorage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header: large avatar + name/relationship
            HStack(alignment: .center, spacing: Spacing.md) {
                avatarCircle(size: 80)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(contact.displayName)
                        .font(CiderFont.subheading)
                        .foregroundColor(CiderColors.primary)

                    if !contact.relationshipLabel.isEmpty {
                        Text(contact.relationshipLabel)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }

            Divider()

            // Notes
            if !contact.notes.isEmpty {
                Text(contact.notes)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Expandable metadata
            let hasMetadata = contact.birthday != nil
                || !contact.email.isEmpty
                || !contact.phone.isEmpty
                || !contact.address.isEmpty
                || !contact.labelIDs.isEmpty
                || contact.linkedEntities.contains(where: { $0.type == .dateCard })

            if hasMetadata {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) { isMetadataExpanded.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Details")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                        Spacer(minLength: 0)
                        Image(systemName: isMetadataExpanded ? "chevron.up" : "chevron.down")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isMetadataExpanded {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let birthday = contact.birthday {
                            detailRow(
                                icon: "gift",
                                text: birthday.formatted(.dateTime.month(.wide).day().year())
                            )
                        }

                        if !contact.email.isEmpty {
                            detailRow(icon: "envelope", text: contact.email)
                        }

                        if !contact.phone.isEmpty {
                            detailRow(icon: "phone", text: contact.phone)
                        }

                        if !contact.address.isEmpty {
                            detailRow(icon: "mappin.and.ellipse", text: contact.address)
                        }

                        let labels = labelStorage.labels.filter { contact.labelIDs.contains($0.id) }
                        if !labels.isEmpty {
                            detailRow(icon: "tag", text: labels.map(\.name).joined(separator: ", "))
                        }

                        ForEach(contact.linkedEntities.filter({ $0.type == .dateCard })) { ref in
                            if let card = dateCardStorage.dateCard(for: ref.entityID) {
                                detailRow(
                                    icon: "calendar",
                                    text: "\(card.title) · \(card.startAt.formatted(.dateTime.month(.abbreviated).day()))"
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                Button("Edit") {
                    onEdit?()
                }
                .buttonStyle(.borderless)
                .foregroundColor(CiderColors.secondary)

                Button("Done") {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task(id: contact.updatedAt) {
            await loadAvatar()
        }
    }

    // MARK: - Avatar Circle

    @ViewBuilder
    private func avatarCircle(size: CGFloat) -> some View {
        if let image = avatarImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(CiderColors.surfaceSubtle)
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                )
        }
    }

    private var initials: String {
        let parts = contact.displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(contact.displayName.prefix(2)).uppercased()
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Avatar Loading

    private func loadAvatar() async {
        guard contact.hasAvatar else {
            avatarImage = nil
            return
        }
        let url = ContactStorage.shared.avatarURL(for: contact.id)
        let data: Data? = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        if let data, let image = NSImage(data: data) {
            avatarImage = image
        } else {
            avatarImage = nil
        }
    }
}
