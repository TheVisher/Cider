# Todos Tab Vision

A dedicated tab for daily planning, task management, and organization. Separate from notes — this is purpose-built for tracking actionable items rather than capturing long-form content.

---

## Status: Not Yet Implemented

This tab is planned but no work has started. Ideas below are initial brainstorming.

## Core Concept

A lightweight personal planner that lives inside Cider's floating panel. Quick-add tasks, organize by day or project, check things off. Not a full project management tool — it's the digital equivalent of a daily to-do list on your desk.

## Possible Features

### Task Management
- Quick-add tasks (type and hit enter)
- Checkboxes with satisfying check-off animation
- Due dates (optional)
- Priority levels (optional — could be as simple as a star/flag)
- Subtasks / nested items
- Drag to reorder

### Views
- **Today** — tasks due today + overdue items
- **Upcoming** — tasks with future due dates, grouped by day
- **All** — everything, filterable
- **Completed** — archive of done items (auto-hide after N days?)

### Daily Lists
- Create a named daily list (e.g., "Items to accomplish 2/20/2026")
- Daily lists auto-archive after their date passes
- Template support (recurring daily lists with the same structure)

### Organization
- Folders or categories for tasks
- Tags
- Search

### Integration with Notes
- Pull checkbox items from notes into unified todo view
- Create a note from a todo (expand a task into a full note)
- Link todos to notes for context

### Quick Capture
- Global hotkey to add a todo without opening the panel
- Capture from clipboard
- Natural language date parsing ("tomorrow", "next Friday")

## Data Model (Sketch)

```swift
struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: TodoPriority?     // .low, .medium, .high
    var notes: String?
    var parentID: UUID?             // for subtasks
    var sortOrder: Int
    var listID: UUID?
    var tags: [String]
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

enum TodoPriority: String, Codable {
    case low, medium, high
}

struct TodoList: Identifiable, Codable {
    let id: UUID
    var name: String
    var date: Date?                 // for daily lists
    var isTemplate: Bool
    var createdAt: Date
    var updatedAt: Date
}
```
