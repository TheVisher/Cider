import Foundation
import SwiftUI

struct CiderExternalOpenModifier: ViewModifier {
    let isMainWindow: Bool
    let open: ([AnyHashable: Any]?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .openCiderExternalTarget)) { notification in
            guard isMainWindow else { return }
            open(notification.userInfo)
        }
    }
}

extension CiderPanelView {
    func handleExternalOpenTarget(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let targetType = userInfo[CiderExternalOpenBridge.Key.targetType] as? String,
              let targetID = userInfo[CiderExternalOpenBridge.Key.targetID] as? String else {
            return
        }

        switch targetType {
        case "bookmark":
            guard let id = UUID(uuidString: targetID),
                  let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == id }) else { return }
            openBookmarkDetails(bookmark)
        case "note":
            guard let id = UUID(uuidString: targetID),
                  let note = notesViewModel.notes.first(where: { $0.id == id }) else { return }
            openNoteDetail(note)
        case "dateCard":
            guard let id = UUID(uuidString: targetID),
                  let dateCard = DateCardStorage.shared.dateCard(for: id) else { return }
            openDateCardDetail(dateCard)
        case "contact":
            guard let id = UUID(uuidString: targetID),
                  let contact = ContactStorage.shared.contact(for: id) else { return }
            openContactDetail(contact)
        case "todo":
            guard let id = UUID(uuidString: targetID),
                  let todo = TodoCardStorage.shared.todoCard(for: id) else { return }
            openTodoDetail(todo)
        case "vaultFile":
            guard let id = UUID(uuidString: targetID),
                  let file = VaultFileService.shared.file(for: id) else { return }
            openVaultFileDetail(file)
        case "card":
            guard let boardID = userInfo[CiderExternalOpenBridge.Key.boardID] as? String else { return }
            applyWorkspaceRouteIntent(
                WorkspaceRouteIntentPolicy.intent(
                    forExternalTargetType: targetType,
                    targetID: targetID,
                    boardID: boardID
                )
            )
        case "board":
            applyWorkspaceRouteIntent(
                WorkspaceRouteIntentPolicy.intent(
                    forExternalTargetType: targetType,
                    targetID: targetID,
                    boardID: nil
                )
            )
        default:
            break
        }
    }
}
