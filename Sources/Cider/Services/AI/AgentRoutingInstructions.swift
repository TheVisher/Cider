import Foundation

enum AgentRoutingInstructions {
    static let vaultSaveRoutingDoctrine = """
    Vault save routing rules:
    - Do not invent new top-level folders.
    - Use the existing vault domains: Inbox, People, Projects, Tech, Food, Hobbies, Life, Media.
    - For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear.
    - For person facts and new contacts, prefer People/{Name}-style routing.
    - Food and recipe content should usually route into Food rather than Inbox.
    - Tech troubleshooting and how-to content should usually route into Tech rather than Inbox.
    - If the destination is unclear, save to Inbox and explain why.
    - In the final response, tell the user where the item was saved.
    """
}
