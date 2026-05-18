import Foundation

enum AgentRoutingInstructions {
    static let vaultSaveRoutingDoctrine = """
    Second-brain tool rules:
    - Treat Cider's item/capture/review/storage APIs as the source of truth. Do not infer truth by scraping folders, YAML, Markdown, or legacy command output.
    - For new user material, use the capture door first: capture add. Let Cider create, enrich, route, and mark review state before adding AI-owned enrichment.
    - For existing material, inspect through item get, item search, item context, item related, and item why-surfaced before acting.
    - For uncertain placement, use review/routing flows and leave a reviewable reason. Do not guess a folder just to finish.
    - Mutating actions must use a blessed second-brain mutation/capture/review/storage path that can return confirmed state and provenance.
    - Avoid legacy-first surfaces such as bookmark/note/todo/file direct mutation commands, memory, embeddings, folder kanban, old search/query/recent/snapshot/status, or raw filesystem edits unless the user explicitly asks for a legacy/admin operation.
    - If the needed affordance does not exist behind the blessed surface, report the resistance so it can become a Kanban card instead of working around the backend.
    - In the final response, tell the user the verified item identity, route/review state, and any caveat.
    """
}
