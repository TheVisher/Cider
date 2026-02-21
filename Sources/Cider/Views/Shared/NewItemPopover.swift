import SwiftUI

// MARK: - NewItemPopover

struct NewItemPopover: View {
    let folders: [Folder]
    var onCreateBookmark: (String, String?) -> Void
    var onCreateNote: (String, String) -> Void
    var onCreateEvent: (String, Date, Bool) -> Void
    var onCreateContact: (String, String) -> Void
    var onCreateFolder: (String, UUID?) -> Void
    var onCreateProject: (String) -> Void
    var onDismiss: () -> Void

    @State private var step: NewItemStep = .picker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .picker:
                pickerView
                    .transition(.opacity)
            case .bookmark:
                BookmarkCreationForm(
                    onBack: back,
                    onCreate: { url, title in
                        onCreateBookmark(url, title)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            case .note:
                NoteCreationForm(
                    onBack: back,
                    onCreate: { title, content in
                        onCreateNote(title, content)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            case .event:
                EventCreationForm(
                    onBack: back,
                    onCreate: { title, date, allDay in
                        onCreateEvent(title, date, allDay)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            case .contact:
                ContactCreationForm(
                    onBack: back,
                    onCreate: { name, relationship in
                        onCreateContact(name, relationship)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            case .folder:
                FolderCreationForm(
                    folders: folders,
                    onBack: back,
                    onCreate: { name, parentID in
                        onCreateFolder(name, parentID)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            case .project:
                ProjectCreationForm(
                    onBack: back,
                    onCreate: { name in
                        onCreateProject(name)
                        onDismiss()
                    }
                )
                .transition(.opacity)
            }
        }
        .frame(width: 264)
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: step)
    }

    private func back() {
        withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
            step = .picker
        }
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
                typeCard(.project)
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
        withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
            switch type {
            case .bookmark: step = .bookmark
            case .note:     step = .note
            case .event:    step = .event
            case .contact:  step = .contact
            case .folder:   step = .folder
            case .project:  step = .project
            }
        }
    }
}

// MARK: - Step

private enum NewItemStep: Equatable {
    case picker, bookmark, note, event, contact, folder, project
}

// MARK: - Item Types

enum NewItemType: String, CaseIterable, Identifiable {
    case bookmark, note, event, contact, folder, project

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bookmark: "Bookmark"
        case .note:     "Note"
        case .event:    "Event"
        case .contact:  "Contact"
        case .folder:   "Folder"
        case .project:  "Project"
        }
    }

    var systemImage: String {
        switch self {
        case .bookmark: "bookmark"
        case .note:     "note.text"
        case .event:    "calendar.badge.plus"
        case .contact:  "person.badge.plus"
        case .folder:   "folder.badge.plus"
        case .project:  "tray.full"
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
                .foregroundColor(.white)
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
    @FocusState private var urlFocused: Bool

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
                    .focused($urlFocused)
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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            urlFocused = true
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
    @FocusState private var titleFocused: Bool

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
                    .focused($titleFocused)
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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            titleFocused = true
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
    let onBack: () -> Void
    let onCreate: (String, Date, Bool) -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var allDay = false
    @State private var errorMessage = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Event", onBack: onBack)

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
                    .focused($titleFocused)
                    .onSubmit(commit)

                DatePicker(
                    "Date",
                    selection: $date,
                    displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
                .font(CiderFont.body)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            titleFocused = true
        }
    }

    private func commit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required"
            return
        }
        onCreate(trimmedTitle, date, allDay)
    }
}

// MARK: - Contact Form

private struct ContactCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var relationship = ""
    @State private var errorMessage = ""
    @FocusState private var nameFocused: Bool

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
                    .focused($nameFocused)
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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            nameFocused = true
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
    @FocusState private var nameFocused: Bool

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
                    .focused($nameFocused)
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
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            nameFocused = true
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

// MARK: - Project Form

private struct ProjectCreationForm: View {
    let onBack: () -> Void
    let onCreate: (String) -> Void

    @State private var name = ""
    @State private var errorMessage = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FormHeader(title: "New Project", onBack: onBack)

            TextField("Project name", text: $name)
                .textFieldStyle(.plain)
                .font(CiderFont.body)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .focused($nameFocused)
                .onSubmit(commit)
                .padding(.horizontal, Spacing.md)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
            }

            AddButton(label: "Create Project", action: commit)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            nameFocused = true
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        onCreate(trimmedName)
    }
}
