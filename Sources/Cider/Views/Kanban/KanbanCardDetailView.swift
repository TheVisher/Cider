import SwiftUI

/// Long-form editor for a Kanban card inside the shared Cider detail panel.
struct KanbanCardDetailView: View {
    @Binding var draft: KanbanCardDraft
    var onSave: () -> Void

    @FocusState private var notesFocused: Bool

    init(draft: Binding<KanbanCardDraft>, onSave: @escaping () -> Void) {
        _draft = draft
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Spec / Notes")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                TextEditor(text: $draft.notes)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($notesFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .center, spacing: Spacing.md) {
                Text("Plain text for now. Export Markdown when you need a portable copy.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                Button("Save") {
                    onSave()
                }
                .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }
}
