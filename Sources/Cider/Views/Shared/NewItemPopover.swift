import SwiftUI

// MARK: - NewItemPopover

struct NewItemPopover: View {
    let folders: [Folder]
    var initialStep: String?
    var ocrData: [String: Any] = [:]
    var onCreateBookmark: (String, String?) -> Void
    var onCreateNote: (String, String) -> Void
    var onCreateEvent: (String, Date, Bool) -> Void
    var onCreateContact: (String, String) -> Void
    var onCreateFolder: (String, UUID?) -> Void
    var onCreateTab: (String, Set<LibraryEntityType>) -> Void
    var onCreateTag: (String, String) -> Void
    var onDismiss: () -> Void

    @State private var step: NewItemStep = .picker

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .picker:
                pickerView
            case .bookmark:
                BookmarkCreationForm(
                    onBack: back,
                    onCreate: { url, title in
                        onCreateBookmark(url, title)
                        onDismiss()
                    }
                )
            case .note:
                NoteCreationForm(
                    onBack: back,
                    onCreate: { title, content in
                        onCreateNote(title, content)
                        onDismiss()
                    }
                )
            case .event:
                EventCreationForm(
                    prefillTitle: ocrData["suggestedTitle"] as? String,
                    prefillDate: (ocrData["detectedDates"] as? [Date])?.first,
                    onBack: back,
                    onCreate: { title, date, allDay in
                        onCreateEvent(title, date, allDay)
                        onDismiss()
                    }
                )
            case .contact:
                ContactCreationForm(
                    prefillName: ocrData["suggestedTitle"] as? String,
                    prefillEmail: (ocrData["detectedEmails"] as? [String])?.first,
                    prefillPhone: (ocrData["detectedPhones"] as? [String])?.first,
                    onBack: back,
                    onCreate: { name, relationship in
                        onCreateContact(name, relationship)
                        onDismiss()
                    }
                )
            case .folder:
                FolderCreationForm(
                    folders: folders,
                    onBack: back,
                    onCreate: { name, parentID in
                        onCreateFolder(name, parentID)
                        onDismiss()
                    }
                )
            case .tab:
                TabCreationForm(
                    onBack: back,
                    onCreate: { name, entityTypes in
                        onCreateTab(name, entityTypes)
                        onDismiss()
                    }
                )
            case .tag:
                TagCreationForm(
                    onBack: back,
                    onCreate: { name, colorHex in
                        onCreateTag(name, colorHex)
                        onDismiss()
                    }
                )
            }
        }
        // No animation on step changes: animating popover content size via ViewBridge
        // (RemoteViewService XPC) causes crashes in non-activating NSPanel popovers.
        .frame(width: 264)
        .onAppear {
            if let initialStep {
                switch initialStep {
                case "event": step = .event
                case "contact": step = .contact
                case "bookmark": step = .bookmark
                case "note": step = .note
                default: break
                }
            }
        }
    }

    private func back() {
        step = .picker
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Create")
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.top, Spacing.md)
                .padding(.horizontal, Spacing.md)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Spacing.xs
            ) {
                typeCard(.bookmark)
                typeCard(.note)
                typeCard(.event)
                typeCard(.contact)
                typeCard(.folder)
                typeCard(.tab)
                typeCard(.tag)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    private func typeCard(_ type: NewItemType) -> some View {
        Button {
            handleTypeTap(type)
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(CiderColors.secondary)

                Text(type.displayName)
                    .font(CiderFont.label)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleTypeTap(_ type: NewItemType) {
        switch type {
        case .bookmark: step = .bookmark
        case .note:     step = .note
        case .event:    step = .event
        case .contact:  step = .contact
        case .folder:   step = .folder
        case .tab:      step = .tab
        case .tag:      step = .tag
        }
    }
}

// MARK: - Step

private enum NewItemStep: Equatable {
    case picker, bookmark, note, event, contact, folder, tab, tag
}

// MARK: - Item Types

enum NewItemType: String, CaseIterable, Identifiable {
    case bookmark, note, event, contact, folder, tab, tag

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bookmark: "Bookmark"
        case .note:     "Note"
        case .event:    "Event"
        case .contact:  "Contact"
        case .folder:   "Folder"
        case .tab:      "Tab"
        case .tag:      "Tag"
        }
    }

    var systemImage: String {
        switch self {
        case .bookmark: "bookmark"
        case .note:     "note.text"
        case .event:    "calendar.badge.plus"
        case .contact:  "person.badge.plus"
        case .folder:   "folder.badge.plus"
        case .tab:      "rectangle.badge.plus"
        case .tag:      "tag"
        }
    }
}

// MARK: - Shared Helpers

private struct FormHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.primary)

            Spacer()
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
    }
}

private struct AddButton: View {
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.textOnColor)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(disabled ? CiderColors.separatorMedium : CiderColors.controlAccent)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private func inputField(
    _ placeholder: String,
    text: Binding<String>,
    axis: Axis = .horizontal,
    onSubmit: (() -> Void)? = nil
) -> some View {
    TextField(placeholder, text: text, axis: axis)
        .textFieldStyle(.plain)
        .font(CiderFont.body)
        .lineLimit(axis == .vertical ? 4 : 1)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
}

// MARK: - Bookmark Form

private struct BookmarkCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String, String?) -> Void

    @State private var url = ""
    @State private var title = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Bookmark", onBack: onBack)

            VStack(spacing: Spacing.xs) {
                TextField("https://", text: $url)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)

                TextField("Title (optional)", text: $title)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Add Bookmark", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
    }

    private func commit() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            errorMessage = "URL is required"
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedURL, trimmedTitle.isEmpty ? nil : trimmedTitle)
    }
}

// MARK: - Note Form

private struct NoteCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String, String) -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Note", onBack: onBack)

            VStack(spacing: Spacing.xs) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)

                TextField("Content (optional)", text: $content, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .lineLimit(4)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Create Note", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
    }

    private func commit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required"
            return
        }
        onCreate(trimmedTitle, content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Event Form

private struct EventCreationForm: View {
    var prefillTitle: String?
    var prefillDate: Date?
    let onBack: () -> Void
    let onCreate: (String, Date, Bool) -> Void

    @State private var title = ""
    @State private var dateText: String = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: Date())
    }()
    @State private var timeText: String = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }()
    @State private var allDay = false
    @State private var errorMessage = ""
    @State private var didApplyPrefill = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Event", onBack: onBack)

            VStack(spacing: Spacing.xs) {
                inputField("Title", text: $title, onSubmit: commit)

                Toggle("All Day", isOn: $allDay)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )

                inputField("Date (e.g. Feb 21, 2026)", text: $dateText, onSubmit: commit)

                if !allDay {
                    inputField("Time (e.g. 2:30 PM)", text: $timeText, onSubmit: commit)
                }
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Create Event", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
        .onAppear {
            guard !didApplyPrefill else { return }
            didApplyPrefill = true
            if let prefillTitle, !prefillTitle.isEmpty {
                title = prefillTitle
            }
            if let prefillDate {
                let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
                dateText = df.string(from: prefillDate)
                let tf = DateFormatter(); tf.dateFormat = "h:mm a"
                timeText = tf.string(from: prefillDate)
            }
        }
    }

    private func resolvedDate() -> Date {
        let trimmedDate = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTime = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentYear = Calendar.current.component(.year, from: Date())

        // Try date formats in order of specificity; handle year-less formats explicitly
        let dateFormats: [(String, Bool)] = [
            ("MMM d, yyyy",    true),
            ("MMMM d, yyyy",   true),
            ("M/d/yyyy",       true),
            ("yyyy-MM-dd",     true),
            ("MMM d",          false),   // year-less
            ("MMMM d",         false),
            ("M/d",            false)
        ]
        let df = DateFormatter()
        var parsedDate: Date?
        for (format, hasYear) in dateFormats {
            df.dateFormat = format
            if let d = df.date(from: trimmedDate) {
                if hasYear {
                    parsedDate = d
                } else {
                    // Inject current year into year-less parse result
                    var comps = Calendar.current.dateComponents([.month, .day], from: d)
                    comps.year = currentYear
                    parsedDate = Calendar.current.date(from: comps)
                }
                break
            }
        }
        var result = parsedDate ?? Date()

        if !allDay {
            let timeFormats = ["h:mm a", "H:mm", "h:mma", "ha", "h a"]
            let tf = DateFormatter()
            for format in timeFormats {
                tf.dateFormat = format
                if let t = tf.date(from: trimmedTime) {
                    let cal = Calendar.current
                    let h = cal.component(.hour, from: t)
                    let m = cal.component(.minute, from: t)
                    result = cal.date(bySettingHour: h, minute: m, second: 0, of: result) ?? result
                    break
                }
            }
        }
        return result
    }

    private func commit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required"
            return
        }
        onCreate(trimmedTitle, resolvedDate(), allDay)
    }
}

// MARK: - Contact Form

private struct ContactCreationForm: View {
    var prefillName: String?
    var prefillEmail: String?
    var prefillPhone: String?
    let onBack: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var relationship = ""
    @State private var errorMessage = ""
    @State private var didApplyPrefill = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Contact", onBack: onBack)

            VStack(spacing: Spacing.xs) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)

                TextField("Relationship (optional)", text: $relationship)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Create Contact", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
        .onAppear {
            guard !didApplyPrefill else { return }
            didApplyPrefill = true
            if let prefillName, !prefillName.isEmpty {
                name = prefillName
            }
            if let prefillEmail, !prefillEmail.isEmpty {
                // Show email/phone in relationship field as context
                relationship = prefillEmail
            } else if let prefillPhone, !prefillPhone.isEmpty {
                relationship = prefillPhone
            }
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        onCreate(trimmedName, relationship.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Folder Form

private struct FolderCreationForm: View {
    let folders: [Folder]
    let onBack: () -> Void
    let onCreate: (String, UUID?) -> Void

    @State private var name = ""
    @State private var parentID: UUID? = nil
    @State private var errorMessage = ""

    private var rootFolders: [Folder] {
        folders.filter { $0.parentID == nil }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Folder", onBack: onBack)

            VStack(spacing: Spacing.xs) {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onSubmit(commit)

                if !folders.isEmpty {
                    Picker("Parent", selection: $parentID) {
                        Text("No parent (root)")
                            .tag(UUID?.none)
                        ForEach(rootFolders) { folder in
                            Text(folder.name)
                                .tag(UUID?.some(folder.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Create Folder", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        onCreate(trimmedName, parentID)
    }
}

// MARK: - Tab Form

private struct TabCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String, Set<LibraryEntityType>) -> Void

    @State private var name = ""
    @State private var selectedTypes: Set<LibraryEntityType> = Set(LibraryEntityType.allCases)
    @State private var errorMessage = ""

    // Entity types shown as content filter pills (excludes externalFile — edge case)
    private let filterableTypes: [LibraryEntityType] = [.bookmark, .note, .dateCard, .contact]

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Tab", onBack: onBack)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                inputField("Tab name", text: $name, onSubmit: commit)

                Text("Show")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.top, Spacing.xxs)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: Spacing.xs
                ) {
                    ForEach(filterableTypes, id: \.self) { type in
                        contentTypePill(type)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(
                label: "Create Tab",
                disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: commit
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    private func contentTypePill(_ type: LibraryEntityType) -> some View {
        let isSelected = selectedTypes.contains(type)
        return Button {
            if isSelected && selectedTypes.count == 1 {
                // Can't deselect the last type
            } else if isSelected {
                selectedTypes.remove(type)
            } else {
                selectedTypes.insert(type)
            }
        } label: {
            Text(pillLabel(for: type))
                .font(CiderFont.label)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? CiderColors.surfaceElevated : CiderColors.surfaceInput)
                )
        }
        .buttonStyle(.plain)
    }

    private func pillLabel(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark:     return "Bookmarks"
        case .note:         return "Notes"
        case .dateCard:     return "Events"
        case .contact:      return "Contacts"
        case .externalFile: return "Files"
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        let types = selectedTypes.isEmpty ? Set(LibraryEntityType.allCases) : selectedTypes
        onCreate(trimmedName, types)
    }
}

// MARK: - Tag Form

private struct TagCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var selectedColorHex: String = CardLabelStorage.randomPresetColor()
    @State private var errorMessage = ""

    private let presets = CardLabelStorage.tagColorPresets

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Tag", onBack: onBack)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                inputField("Tag name", text: $name, onSubmit: commit)

                Text("Color")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.top, Spacing.xxs)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 28), spacing: Spacing.xs)],
                    spacing: Spacing.xs
                ) {
                    ForEach(presets, id: \.hex) { preset in
                        let isSelected = preset.hex.lowercased() == selectedColorHex.lowercased()
                        Button {
                            selectedColorHex = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex) ?? CiderColors.secondary)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if isSelected {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                            .frame(width: 18, height: 18)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(
                label: "Create Tag",
                disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: commit
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        onCreate(trimmedName, selectedColorHex)
    }
}
