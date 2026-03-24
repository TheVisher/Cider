import AppKit
import SwiftUI


struct ContactCardCardView: View {
    let contact: ContactCard
    var onOpen: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @State private var isHovered = false

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }
    @State private var avatarImage: NSImage?
    @State private var cardWidth: CGFloat = 220

    private var avatarSize: CGFloat {
        // 40% of card width, clamped so it never gets absurdly small or large
        min(max(cardWidth * 0.40, 36), 130)
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header: large avatar top-left + name / relationship
                HStack(alignment: .top, spacing: Spacing.sm) {
                    avatarCircle(size: avatarSize)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(contact.displayName)
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(3)

                        if !contact.relationshipLabel.isEmpty {
                            Text(contact.relationshipLabel)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, Spacing.xxs)
                }

                // Notes
                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(3)
                }

                // Metadata (birthday, email, phone, address) with separator
                let hasAnyMeta = contact.birthday != nil
                    || !contact.email.isEmpty
                    || !contact.phone.isEmpty
                    || !contact.address.isEmpty
                if hasAnyMeta {
                    Divider()
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if let birthday = contact.birthday {
                            metaRow(icon: "gift",
                                    text: birthday.formatted(.dateTime.month(.abbreviated).day()))
                        }
                        if !contact.email.isEmpty {
                            metaRow(icon: "envelope", text: contact.email)
                        }
                        if !contact.phone.isEmpty {
                            metaRow(icon: "phone", text: contact.phone)
                        }
                        if !contact.address.isEmpty {
                            metaRow(icon: "mappin.and.ellipse", text: contact.address)
                        }
                    }
                }

                if !contact.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: contact.labelIDs,
                        labels: CardLabelStorage.shared.labels
                    )
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { cardWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in cardWidth = w }
            })
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
        .contactContextMenu(
            onOpen: { onOpen?() },
            labelIDs: contact.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = contact
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = ContactStorage.shared.updateContact(updated)
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
        .task(id: contact.updatedAt) {
            await loadAvatar()
        }
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 12)
            Text(text)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
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
                .fill(CiderColors.surfaceInput)
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

    // MARK: - Avatar Loading

    private func loadAvatar() async {
        guard contact.hasAvatar else {
            avatarImage = nil
            return
        }
        let url = ContactStorage.shared.avatarURL(for: contact.id)
        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
        avatarImage = image
    }
}

// MARK: - ContactListRow

struct ContactListRow: View {
    let contact: ContactCard
    var onOpen: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @State private var avatarImage: NSImage?

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    SelectionCheckmark()
                }

                avatarCircle(size: 28)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(contact.displayName)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)

                        if !contact.email.isEmpty {
                            Text("\u{00B7}")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                            Text(contact.email)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        } else if let birthday = contact.birthday {
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
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        isFocused ? CiderColors.controlAccent : (isSelected ? CiderColors.controlAccent : Color.clear),
                        lineWidth: isFocused ? 1.5 : (isSelected ? CiderBorder.innerStrokeWidth : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .contactContextMenu(
            onOpen: { onOpen?() },
            labelIDs: contact.labelIDs,
            folders: folders,
            onMoveToFolder: { onMoveToFolder?($0) },
            onDelete: { onDelete?() },
            onToggleLabel: { labelID in
                var updated = contact
                if updated.labelIDs.contains(labelID) {
                    updated.labelIDs.removeAll { $0 == labelID }
                } else {
                    updated.labelIDs.append(labelID)
                }
                _ = ContactStorage.shared.updateContact(updated)
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
        .task(id: contact.updatedAt) {
            await loadAvatar()
        }
    }

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
                .fill(CiderColors.surfaceInput)
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(CiderFont.captionMedium)
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

    private func loadAvatar() async {
        guard contact.hasAvatar else {
            avatarImage = nil
            return
        }
        let url = ContactStorage.shared.avatarURL(for: contact.id)
        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
        avatarImage = image
    }
}
