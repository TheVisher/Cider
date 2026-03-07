import SwiftUI

struct StackManagerSheet: View {
    let availableItems: [LibraryItemV2]
    let initialSelectedStackID: UUID?

    @ObservedObject private var stackStorage = CardStackStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var selectedStackID: UUID?
    @Environment(\.dismiss) private var dismiss

    private var selectedStack: CardStack? {
        guard let selectedStackID else { return nil }
        return stackStorage.stack(for: selectedStackID)
    }

    init(availableItems: [LibraryItemV2] = [], initialSelectedStackID: UUID? = nil) {
        self.availableItems = availableItems
        self.initialSelectedStackID = initialSelectedStackID
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Stacks")
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)

                    Spacer(minLength: 0)

                    Menu {
                        Button("New Blank Stack") {
                            let created = stackStorage.createStack(template: .blank, nameOverride: "New Stack")
                            selectedStackID = created.id
                        }
                        Divider()
                        Button("New Bills Stack") {
                            let created = stackStorage.createStack(template: .bills)
                            selectedStackID = created.id
                        }
                        Button("New Birthdays Stack") {
                            let created = stackStorage.createStack(template: .birthdays)
                            selectedStackID = created.id
                        }
                        Button("New Schedule Stack") {
                            let created = stackStorage.createStack(template: .schedule)
                            selectedStackID = created.id
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(stackStorage.stacks) { stack in
                            stackRow(stack)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(Spacing.md)
            .frame(width: 220)

            Divider()

            VStack(alignment: .leading, spacing: Spacing.md) {
                if let stack = selectedStack {
                    editor(stack)
                } else {
                    EmptyStateView(
                        icon: "square.stack.3d.up",
                        title: "Select a stack",
                        subtitle: "Choose a stack on the left to edit its rules."
                    )
                }
            }
            .padding(Spacing.md)
            .frame(minWidth: 420)
        }
        .frame(minWidth: 700, minHeight: 420)
        .background(CiderColors.surfaceSubtle)
        .onAppear {
            if selectedStackID == nil {
                if let initialSelectedStackID,
                   stackStorage.stacks.contains(where: { $0.id == initialSelectedStackID }) {
                    selectedStackID = initialSelectedStackID
                } else {
                    selectedStackID = stackStorage.stacks.first?.id
                }
            }
        }
    }

    private func stackRow(_ stack: CardStack) -> some View {
        let isSelected = selectedStackID == stack.id
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "square.stack.3d.up")
                .font(CiderFont.captionSemibold)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)

            Text(stack.name)
                .font(CiderFont.bodyMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.separatorMedium : CiderColors.surfaceElevated)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStackID = stack.id
        }
    }

    private func editor(_ stack: CardStack) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                TextField(
                    "Stack name",
                    text: Binding(
                        get: { stack.name },
                        set: { newValue in
                            var updated = stack
                            updated.name = newValue
                            _ = stackStorage.updateStack(updated)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    _ = stackStorage.deleteStack(stack.id)
                    selectedStackID = stackStorage.stacks.first?.id
                } label: {
                    Image(systemName: "trash")
                        .font(CiderFont.bodySemibold)
                }
                .buttonStyle(.borderless)
            }

            Toggle("Pinned", isOn: Binding(
                get: { stack.isPinned },
                set: { newValue in
                    var updated = stack
                    updated.isPinned = newValue
                    _ = stackStorage.updateStack(updated)
                }
            ))

            Picker("Sort", selection: Binding(
                get: { stack.sortMode },
                set: { newValue in
                    var updated = stack
                    updated.sortMode = newValue
                    _ = stackStorage.updateStack(updated)
                }
            )) {
                Text("Attention").tag(StackSortMode.attention)
                Text("Time").tag(StackSortMode.time)
            }
            .pickerStyle(.segmented)

            Picker("Summary", selection: Binding(
                get: { stack.summaryModule },
                set: { newValue in
                    var updated = stack
                    updated.summaryModule = newValue
                    _ = stackStorage.updateStack(updated)
                }
            )) {
                Text("None").tag(StackSummaryModule.none)
                Text("Bills").tag(StackSummaryModule.bills)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Match Rules")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                matchToggle(stack: stack, title: "Has Date", condition: .hasDate)
                matchToggle(stack: stack, title: "Incomplete Only", condition: .isIncomplete)

                HStack(spacing: Spacing.xs) {
                    Text("Type")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                    entityTypeButton(stack: stack, type: .bookmark, label: "Bookmarks")
                    entityTypeButton(stack: stack, type: .note, label: "Notes")
                    entityTypeButton(stack: stack, type: .dateCard, label: "Date Cards")
                    entityTypeButton(stack: stack, type: .contact, label: "Contacts")
                }

                HStack(spacing: Spacing.xs) {
                    Text("Label")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Menu {
                        if labelStorage.labels.isEmpty {
                            Text("No labels available")
                        } else {
                            ForEach(labelStorage.labels) { label in
                                Button(label.name) {
                                    setLabelRule(stack: stack, labelID: label.id)
                                }
                            }
                        }
                    } label: {
                        Text(selectedLabelName(for: stack) ?? "Any")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.hairline)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CiderColors.separatorLight)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    if hasLabelRule(stack) {
                        Button("Clear") {
                            clearLabelRule(stack: stack)
                        }
                        .buttonStyle(.borderless)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.destructive)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Manual Items")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                HStack(spacing: Spacing.xs) {
                    Menu {
                        let candidates = availableItems.prefix(80)
                        if candidates.isEmpty {
                            Text("No items available in current view")
                        } else {
                            ForEach(Array(candidates), id: \.id) { item in
                                Button(item.title) {
                                    addManualItem(item, to: stack)
                                }
                            }
                        }
                    } label: {
                        Label("Add Item", systemImage: "plus")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    if !stack.manualItemRefs.isEmpty {
                        Button("Clear") {
                            var updated = stack
                            updated.manualItemRefs = []
                            _ = stackStorage.updateStack(updated)
                        }
                        .buttonStyle(.borderless)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.destructive)
                    }
                }

                if stack.manualItemRefs.isEmpty {
                    Text("No manual items added.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                } else {
                    ForEach(stack.manualItemRefs, id: \.id) { ref in
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: icon(for: ref.type))
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.controlAccent)
                            Text(title(for: ref))
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                removeManualItem(ref, from: stack)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                .fill(CiderColors.surfaceElevated)
                        )
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Surfacing")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                surfaceToggle(stack: stack, title: "Pin Until Done", type: .pinUntilDone)
                surfaceValueRuleRow(
                    stack: stack,
                    title: "Surface Days Before",
                    type: .surfaceDaysBeforeDate,
                    defaultValue: 7,
                    range: 0...90
                )
                surfaceValueRuleRow(
                    stack: stack,
                    title: "Remind Minutes Before",
                    type: .remindBeforeMinutes,
                    defaultValue: 10,
                    range: 0...240
                )
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func matchToggle(stack: CardStack, title: String, condition: StackMatchCondition) -> some View {
        let isOn = stack.matchRules.contains(where: { $0.condition == condition })
        return Toggle(title, isOn: Binding(
            get: { isOn },
            set: { newValue in
                var updated = stack
                updated.matchRules.removeAll(where: { $0.condition == condition })
                if newValue {
                    updated.matchRules.append(StackMatchRule(condition: condition))
                }
                _ = stackStorage.updateStack(updated)
            }
        ))
    }

    private func entityTypeButton(stack: CardStack, type: LibraryEntityType, label: String) -> some View {
        let current = stack.matchRules.first(where: { $0.condition == .entityType })?.value
        let isOn = current == type.rawValue
        return Button {
            var updated = stack
            if isOn {
                updated.matchRules.removeAll(where: { $0.condition == .entityType })
            } else {
                updated.matchRules.removeAll(where: { $0.condition == .entityType })
                updated.matchRules.append(StackMatchRule(condition: .entityType, value: type.rawValue))
            }
            _ = stackStorage.updateStack(updated)
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func surfaceToggle(stack: CardStack, title: String, type: SurfacingRuleType, value: Int? = nil) -> some View {
        let isOn = stack.surfaceRules.contains(where: { $0.type == type && $0.isEnabled })
        return Toggle(title, isOn: Binding(
            get: { isOn },
            set: { newValue in
                var updated = stack
                updated.surfaceRules.removeAll(where: { $0.type == type })
                if newValue {
                    updated.surfaceRules.append(
                        SurfacingRule(
                            type: type,
                            integerValue: value,
                            isEnabled: true
                        )
                    )
                }
                _ = stackStorage.updateStack(updated)
            }
        ))
    }

    private func surfaceValueRuleRow(
        stack: CardStack,
        title: String,
        type: SurfacingRuleType,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> some View {
        let existingRule = stack.surfaceRules.first(where: { $0.type == type })
        let isOn = existingRule?.isEnabled ?? false
        let currentValue = existingRule?.integerValue ?? defaultValue

        return HStack(spacing: Spacing.xs) {
            Toggle(title, isOn: Binding(
                get: { isOn },
                set: { newValue in
                    var updated = stack
                    updated.surfaceRules.removeAll(where: { $0.type == type })
                    if newValue {
                        updated.surfaceRules.append(
                            SurfacingRule(
                                type: type,
                                integerValue: currentValue,
                                isEnabled: true
                            )
                        )
                    }
                    _ = stackStorage.updateStack(updated)
                }
            ))

            if isOn {
                Stepper(
                    value: Binding(
                        get: { min(max(currentValue, range.lowerBound), range.upperBound) },
                        set: { newValue in
                            var updated = stack
                            updated.surfaceRules.removeAll(where: { $0.type == type })
                            updated.surfaceRules.append(
                                SurfacingRule(
                                    type: type,
                                    integerValue: min(max(newValue, range.lowerBound), range.upperBound),
                                    isEnabled: true
                                )
                            )
                            _ = stackStorage.updateStack(updated)
                        }
                    ),
                    in: range
                ) {
                    Text("\(currentValue)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .labelsHidden()
                .frame(width: 86, alignment: .trailing)
            }
        }
    }

    private func addManualItem(_ item: LibraryItemV2, to stack: CardStack) {
        let ref = libraryEntityRef(for: item)
        var updated = stack
        if !updated.manualItemRefs.contains(ref) {
            updated.manualItemRefs.append(ref)
            _ = stackStorage.updateStack(updated)
        }
    }

    private func hasLabelRule(_ stack: CardStack) -> Bool {
        stack.matchRules.contains(where: { $0.condition == .hasLabel })
    }

    private func selectedLabelName(for stack: CardStack) -> String? {
        guard let value = stack.matchRules.first(where: { $0.condition == .hasLabel })?.value,
              let id = UUID(uuidString: value) else {
            return nil
        }
        return labelStorage.label(for: id)?.name
    }

    private func setLabelRule(stack: CardStack, labelID: UUID) {
        var updated = stack
        updated.matchRules.removeAll(where: { $0.condition == .hasLabel })
        updated.matchRules.append(StackMatchRule(condition: .hasLabel, value: labelID.uuidString))
        _ = stackStorage.updateStack(updated)
    }

    private func clearLabelRule(stack: CardStack) {
        var updated = stack
        updated.matchRules.removeAll(where: { $0.condition == .hasLabel })
        _ = stackStorage.updateStack(updated)
    }

    private func removeManualItem(_ ref: LibraryEntityRef, from stack: CardStack) {
        var updated = stack
        updated.manualItemRefs.removeAll { $0 == ref }
        _ = stackStorage.updateStack(updated)
    }

    private func libraryEntityRef(for item: LibraryItemV2) -> LibraryEntityRef {
        switch item {
        case .bookmark(let bookmark):
            return LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        case .note(let note):
            return LibraryEntityRef(type: .note, entityID: note.id)
        case .dateCard(let dateCard):
            return LibraryEntityRef(type: .dateCard, entityID: dateCard.id)
        case .contact(let contact):
            return LibraryEntityRef(type: .contact, entityID: contact.id)
        case .todo(let todoCard):
            return LibraryEntityRef(type: .todo, entityID: todoCard.id)
        case .externalFile(let file):
            return LibraryEntityRef(type: .externalFile, entityID: file.id)
        }
    }

    private func title(for ref: LibraryEntityRef) -> String {
        if let item = availableItems.first(where: { item in
            switch item {
            case .bookmark(let bookmark):
                return ref.type == .bookmark && ref.entityID == bookmark.id
            case .note(let note):
                return ref.type == .note && ref.entityID == note.id
            case .dateCard(let dateCard):
                return ref.type == .dateCard && ref.entityID == dateCard.id
            case .contact(let contact):
                return ref.type == .contact && ref.entityID == contact.id
            case .todo(let todoCard):
                return ref.type == .todo && ref.entityID == todoCard.id
            case .externalFile(let file):
                return ref.type == .externalFile && ref.entityID == file.id
            }
        }) {
            return item.title
        }
        return "\(ref.type.rawValue): \(ref.entityID.uuidString.prefix(8))"
    }

    private func icon(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark:
            "bookmark"
        case .note:
            "note.text"
        case .dateCard:
            "calendar"
        case .contact:
            "person.crop.circle"
        case .todo:
            "checklist"
        case .externalFile:
            "folder.badge.gear"
        }
    }
}
