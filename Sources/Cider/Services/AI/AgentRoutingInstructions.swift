import Foundation

enum AgentRoutingInstructions {
    static let vaultSaveRoutingDoctrine = """
    Vault save routing rules:
    - Do not invent new top-level folders.
    - Use the existing vault domains: Inbox, People, Projects, Tech, Food, Hobbies, Life, Media.
    - For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear.
    - For bookmark capture, prefer saving the raw URL to the chosen destination without overriding the title; let Cider perform native title and thumbnail capture before agents add enrichment.
    - For person facts and new contacts, prefer People/{Name}-style routing.
    - Food and recipe content should usually route into Food rather than Inbox.
    - Tech troubleshooting and how-to content should usually route into Tech rather than Inbox.
    - If the destination is unclear, save to Inbox and explain why.
    - After a bookmark exists, AI may observe the Cider-created item and add AI-owned enrichment such as aiSummary, but should not replace Cider's native capture pipeline.
    - In the final response, tell the user where the item was saved.
    """
}
