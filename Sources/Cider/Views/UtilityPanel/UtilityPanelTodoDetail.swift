import SwiftUI

struct UtilityPanelTodoDetail: View {
    let todoID: UUID

    private var todoCard: TodoCard? {
        TodoCardStorage.shared.todoCard(for: todoID)
    }

    var body: some View {
        if let todoCard {
            ScrollView {
                TodoDetailView(todoCard: todoCard)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
            }
        } else {
            PlaceholderMode().contentView
        }
    }
}
