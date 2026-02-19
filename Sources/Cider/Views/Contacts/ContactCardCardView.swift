import SwiftUI

struct ContactCardCardView: View {
    let contact: ContactCard
    var onOpen: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "person.crop.circle")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.controlAccent)
                    Text(contact.displayName)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                }

                if !contact.relationshipLabel.isEmpty {
                    Text(contact.relationshipLabel)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }

                if let birthday = contact.birthday {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gift")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                        Text(birthday.formatted(.dateTime.month(.abbreviated).day()))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(4)
                }

                Text(contact.updatedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
    }
}

struct ContactListRow: View {
    let contact: ContactCard
    var onOpen: (() -> Void)? = nil

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "person.crop.circle")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.displayName)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)

                        if let birthday = contact.birthday {
                            Text("\u{00B7}")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                            Text(birthday.formatted(.dateTime.month(.abbreviated).day()))
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                        }
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(contact.updatedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
    }
}
