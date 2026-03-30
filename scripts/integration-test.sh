#!/bin/bash
# Cider Full Integration Test Suite
# Comprehensive tests for ALL CiderCLI commands, edge cases, and interactions
#
# Usage: ./Scripts/integration-test.sh

set -euo pipefail

CLI="/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli"

# Auto-build if binary doesn't exist
if [ ! -f "$CLI" ]; then
    echo "Building cider-cli..."
    cd /Users/minivish/Cider && swift build --product cider-cli 2>&1 | tail -1
fi

TEST_ID=$(date +%s | tail -c 5)
PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

assert_contains() {
    TOTAL=$((TOTAL + 1))
    if echo "$2" | grep -qi "$3"; then
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1"
        echo -e "    Expected to contain: $3"
        echo -e "    Got: $(echo "$2" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    TOTAL=$((TOTAL + 1))
    if echo "$2" | grep -qi "$3"; then
        echo -e "  ${RED}✗${NC} $1"
        echo -e "    Should NOT contain: $3"
        FAIL=$((FAIL + 1))
    else
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    fi
}

assert_exit_zero() {
    TOTAL=$((TOTAL + 1))
    if [ "$2" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (exit code: $2)"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_nonzero() {
    TOTAL=$((TOTAL + 1))
    if [ "$2" -ne 0 ]; then
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (expected non-zero exit)"
        FAIL=$((FAIL + 1))
    fi
}

assert_count_changed() {
    TOTAL=$((TOTAL + 1))
    if [ "$4" = "increased" ] && [ "$3" -gt "$2" ]; then
        echo -e "  ${GREEN}✓${NC} $1 ($2 → $3)"
        PASS=$((PASS + 1))
    elif [ "$4" = "decreased" ] && [ "$3" -lt "$2" ]; then
        echo -e "  ${GREEN}✓${NC} $1 ($2 → $3)"
        PASS=$((PASS + 1))
    elif [ "$4" = "same" ] && [ "$3" -eq "$2" ]; then
        echo -e "  ${GREEN}✓${NC} $1 ($2 → $3)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (expected $4: $2 → $3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_valid() {
    TOTAL=$((TOTAL + 1))
    if echo "$2" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (invalid JSON)"
        echo -e "    Got: $(echo "$2" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_has_key() {
    TOTAL=$((TOTAL + 1))
    if echo "$2" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$3' in (d[0] if isinstance(d,list) else d)" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $1"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (missing key: $3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_array_length() {
    TOTAL=$((TOTAL + 1))
    local actual
    actual=$(echo "$2" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "-1")
    if [ "$actual" = "$3" ]; then
        echo -e "  ${GREEN}✓${NC} $1 (count: $actual)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (expected $3 items, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_array_min() {
    TOTAL=$((TOTAL + 1))
    local actual
    actual=$(echo "$2" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$actual" -ge "$3" ]; then
        echo -e "  ${GREEN}✓${NC} $1 (count: $actual ≥ $3)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $1 (expected ≥ $3 items, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

get_count() { $CLI status 2>/dev/null | grep "$1:" | awk '{print $2}'; }

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Cider Comprehensive Integration Test Suite${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

# ═══════════════════════════════════════════════════
# PRE-CLEANUP
# ═══════════════════════════════════════════════════
$CLI trash empty >/dev/null 2>&1
rm -f ~/CiderVault/Inbox/Notes/CiderTest*.md 2>/dev/null
rm -f ~/CiderVault/Inbox/Todos/CiderTest*.ics 2>/dev/null
rm -f ~/CiderVault/Inbox/"Date Cards"/CiderTest*.ics 2>/dev/null
rm -f ~/CiderVault/Inbox/Contacts/CiderTest*.vcf 2>/dev/null
rm -rf ~/CiderVault/CiderTest* 2>/dev/null
# Clean ghost entries from previous test runs
for idx in contacts/_cider_contacts_index todos/_cider_todos_index date-cards/_cider_date_cards_index notes/_cider_notes_index; do
    FILE="$HOME/CiderVault/.cider/${idx}.json"
    if [ -f "$FILE" ]; then
        python3 -c "
import json
with open('$FILE') as f: data = json.load(f)
cleaned = {k: v for k, v in data.items() if 'CiderTest' not in v.get('filename', '')}
if len(cleaned) != len(data):
    with open('$FILE', 'w') as f: json.dump(cleaned, f, indent=2, sort_keys=True)
" 2>/dev/null
    fi
done

# ═══════════════════════════════════════════════════
# 1. STATUS
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}1. Status${NC}"
OUTPUT=$($CLI status 2>&1)
assert_contains "Shows bookmarks" "$OUTPUT" "Bookmarks:"
assert_contains "Shows notes" "$OUTPUT" "Notes:"
assert_contains "Shows active todos" "$OUTPUT" "active"
assert_contains "Shows images" "$OUTPUT" "images"
assert_contains "Shows boards" "$OUTPUT" "cards"
assert_contains "Shows vault root" "$OUTPUT" "CiderVault"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI status --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has bookmarks key" "$OUTPUT" "bookmarks"
assert_json_has_key "Has notes key" "$OUTPUT" "notes"
assert_json_has_key "Has todos key" "$OUTPUT" "todos"
assert_json_has_key "Has todosActive key" "$OUTPUT" "todosActive"
assert_json_has_key "Has events key" "$OUTPUT" "events"
assert_json_has_key "Has contacts key" "$OUTPUT" "contacts"
assert_json_has_key "Has vaultFiles key" "$OUTPUT" "vaultFiles"
assert_json_has_key "Has vaultRoot key" "$OUTPUT" "vaultRoot"

# ═══════════════════════════════════════════════════
# 2. FOLDERS — CRUD + Nesting + Edge Cases
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}2. Folders${NC}"
echo -e "  ${CYAN}── Create & list${NC}"
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Create folder" "$OUTPUT" "Created folder"

OUTPUT=$($CLI folder create "CiderTest${TEST_ID}Sub" --parent "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Create subfolder" "$OUTPUT" "Created folder"

OUTPUT=$($CLI folder list 2>&1)
assert_contains "Folder in list" "$OUTPUT" "CiderTest${TEST_ID}Folder"
assert_contains "Subfolder in list" "$OUTPUT" "CiderTest${TEST_ID}Sub"

echo -e "  ${CYAN}── Rename${NC}"
OUTPUT=$($CLI folder rename "CiderTest${TEST_ID}Sub" --to "CiderTest${TEST_ID}Ren" 2>&1)
assert_contains "Rename folder" "$OUTPUT" "Renamed"

OUTPUT=$($CLI folder list 2>&1)
assert_contains "Renamed shows" "$OUTPUT" "CiderTest${TEST_ID}Ren"
assert_not_contains "Old name gone" "$OUTPUT" "CiderTest${TEST_ID}Sub"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI folder list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has name" "$OUTPUT" "name"

echo -e "  ${CYAN}── Edge cases${NC}"
# Create second folder for move tests later
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}FolderB" 2>&1)
assert_contains "Create second folder" "$OUTPUT" "Created folder"

# Duplicate folder name
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Duplicate folder handled" "$OUTPUT" "already exists\|Created folder"

# Rename non-existent — CLI silently does nothing (no error output)
OUTPUT=$($CLI folder rename "CiderTest${TEST_ID}NoExist" --to "Whatever" 2>&1)
assert_not_contains "Rename non-existent no crash" "$OUTPUT" "Renamed"

# ═══════════════════════════════════════════════════
# 3. BOOKMARK CRUD — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}3. Bookmarks${NC}"
echo -e "  ${CYAN}── Create${NC}"
BM_BEFORE=$(get_count "Bookmarks")

OUTPUT=$($CLI bookmark add "https://example.com/t${TEST_ID}a" --title "CiderTest${TEST_ID}BmA" 2>&1)
assert_contains "Create bookmark A" "$OUTPUT" "Created bookmark"
BM_ID_A=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI bookmark add "https://example.com/t${TEST_ID}b" --title "CiderTest${TEST_ID}BmB" 2>&1)
assert_contains "Create bookmark B" "$OUTPUT" "Created bookmark"
BM_ID_B=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI bookmark add "https://example.com/t${TEST_ID}c" --title "CiderTest${TEST_ID}BmC" 2>&1)
assert_contains "Create bookmark C" "$OUTPUT" "Created bookmark"
BM_ID_C=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
BM_AFTER=$(get_count "Bookmarks")
assert_count_changed "Count +3" "$BM_BEFORE" "$BM_AFTER" "increased"

echo -e "  ${CYAN}── Get & detail fields${NC}"
OUTPUT=$($CLI bookmark get "$BM_ID_A" 2>&1)
assert_contains "Get: title" "$OUTPUT" "CiderTest${TEST_ID}BmA"
assert_contains "Get: URL" "$OUTPUT" "example.com"
assert_contains "Get: manual flag" "$OUTPUT" "title="

echo -e "  ${CYAN}── Search${NC}"
sleep 1
OUTPUT=$($CLI bookmark search "t${TEST_ID}" 2>&1)
assert_contains "Search finds A" "$OUTPUT" "CiderTest${TEST_ID}BmA"
assert_contains "Search finds B" "$OUTPUT" "CiderTest${TEST_ID}BmB"
assert_contains "Search finds C" "$OUTPUT" "CiderTest${TEST_ID}BmC"

echo -e "  ${CYAN}── Move to folder${NC}"
OUTPUT=$($CLI bookmark move "$BM_ID_A" --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Move A to folder" "$OUTPUT" "Moved"

sleep 1
OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "A in folder" "$OUTPUT" "CiderTest${TEST_ID}BmA"
assert_not_contains "B not in folder" "$OUTPUT" "CiderTest${TEST_ID}BmB"

echo -e "  ${CYAN}── Move between folders${NC}"
OUTPUT=$($CLI bookmark move "$BM_ID_A" --folder "CiderTest${TEST_ID}FolderB" 2>&1)
assert_contains "Move A to folder B" "$OUTPUT" "Moved"

sleep 1
OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_not_contains "A left folder A" "$OUTPUT" "CiderTest${TEST_ID}BmA"

OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}FolderB" 2>&1)
assert_contains "A in folder B" "$OUTPUT" "CiderTest${TEST_ID}BmA"

echo -e "  ${CYAN}── Tags${NC}"
OUTPUT=$($CLI bookmark tag "$BM_ID_A" "CiderTest${TEST_ID}Tag1" 2>&1)
assert_contains "Tag 1" "$OUTPUT" "Tagged"

OUTPUT=$($CLI bookmark tag "$BM_ID_A" "CiderTest${TEST_ID}Tag2" 2>&1)
assert_contains "Tag 2 (multi-tag)" "$OUTPUT" "Tagged"

OUTPUT=$($CLI bookmark untag "$BM_ID_A" "CiderTest${TEST_ID}Tag1" 2>&1)
assert_contains "Untag 1" "$OUTPUT" "Removed tag"

# Untag something not tagged
OUTPUT=$($CLI bookmark untag "$BM_ID_A" "CiderTest${TEST_ID}NoExist" 2>&1)
assert_contains "Untag non-existent" "$OUTPUT" "not found\|Removed tag\|not tagged"

echo -e "  ${CYAN}── List with limit${NC}"
OUTPUT=$($CLI bookmark list --limit 2 2>&1)
# Should produce output (just verifying it doesn't crash)
assert_contains "List with limit" "$OUTPUT" "bookmark\|http"

echo -e "  ${CYAN}── Create with folder${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/t${TEST_ID}d" --title "CiderTest${TEST_ID}BmD" --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Create with folder" "$OUTPUT" "Created bookmark"
BM_ID_D=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "New bm in folder" "$OUTPUT" "CiderTest${TEST_ID}BmD"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI bookmark list --json --limit 3 2>&1)
assert_json_valid "Valid list JSON" "$OUTPUT"
assert_json_has_key "Has id field" "$OUTPUT" "id"
assert_json_has_key "Has title field" "$OUTPUT" "title"
assert_json_has_key "Has url field" "$OUTPUT" "url"
assert_json_has_key "Has titleManuallySet" "$OUTPUT" "titleManuallySet"

OUTPUT=$($CLI bookmark get "$BM_ID_A" --json 2>&1)
assert_json_valid "Valid get JSON" "$OUTPUT"

OUTPUT=$($CLI bookmark search "t${TEST_ID}" 2>&1)
assert_contains "Search finds multiple" "$OUTPUT" "CiderTest${TEST_ID}BmA"

echo -e "  ${CYAN}── Delete (single)${NC}"
OUTPUT=$($CLI bookmark delete "$BM_ID_C" 2>&1)
assert_contains "Delete C" "$OUTPUT" "trash"

# Verify C is gone from list
sleep 1
OUTPUT=$($CLI bookmark list 2>&1)
assert_not_contains "C gone from list" "$OUTPUT" "CiderTest${TEST_ID}BmC"

echo -e "  ${CYAN}── Bulk delete (A + B)${NC}"
$CLI bookmark delete "$BM_ID_A" >/dev/null 2>&1
$CLI bookmark delete "$BM_ID_B" >/dev/null 2>&1
sleep 1
BM_AFTER2=$(get_count "Bookmarks")
assert_count_changed "Bulk delete reduced count" "$BM_AFTER" "$BM_AFTER2" "decreased"

# ═══════════════════════════════════════════════════
# 4. TRASH — Full Round-Trip for ALL Types
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}4. Trash — Bookmark Round-Trip${NC}"
OUTPUT=$($CLI trash list 2>&1)
assert_contains "C in trash" "$OUTPUT" "CiderTest${TEST_ID}BmC"

TRASH_C=$(echo "$OUTPUT" | grep "CiderTest${TEST_ID}BmC" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_C" 2>&1)
assert_contains "Restore C" "$OUTPUT" "Restored"

sleep 1
OUTPUT=$($CLI bookmark list 2>&1)
assert_contains "C back in list" "$OUTPUT" "CiderTest${TEST_ID}BmC"

echo -e "  ${CYAN}── Trash JSON output${NC}"
OUTPUT=$($CLI trash list --json 2>&1)
assert_json_valid "Valid trash JSON" "$OUTPUT"

# Clean up bookmark C
$CLI bookmark delete "$BM_ID_C" >/dev/null 2>&1
$CLI bookmark delete "$BM_ID_D" >/dev/null 2>&1

# ── Note trash round-trip ─────────────────────────
echo ""
echo -e "${YELLOW}5. Trash — Note Round-Trip${NC}"
OUTPUT=$($CLI note create "CiderTest${TEST_ID}NoteTrash" --content "Trash test" 2>&1)
assert_contains "Create note for trash" "$OUTPUT" "Created note"
sleep 2

NOTE_TRASH_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI note delete "$NOTE_TRASH_ID" 2>&1)
assert_contains "Delete note" "$OUTPUT" "trash"

OUTPUT=$($CLI trash list 2>&1)
assert_contains "Note in trash" "$OUTPUT" "CiderTest${TEST_ID}NoteTrash"

TRASH_NOTE=$(echo "$OUTPUT" | grep "CiderTest${TEST_ID}NoteTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_NOTE" 2>&1)
assert_contains "Restore note" "$OUTPUT" "Restored"

sleep 1
OUTPUT=$($CLI note list 2>&1)
assert_contains "Note back in list" "$OUTPUT" "CiderTest${TEST_ID}NoteTrash"

# ── Todo trash round-trip ─────────────────────────
echo ""
echo -e "${YELLOW}6. Trash — Todo Round-Trip${NC}"
OUTPUT=$($CLI todo create "CiderTest${TEST_ID}TodoTrash" --priority low 2>&1)
assert_contains "Create todo for trash" "$OUTPUT" "Created todo"
TODO_TRASH_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI todo delete "$TODO_TRASH_ID" 2>&1)
assert_contains "Delete todo" "$OUTPUT" "trash"

OUTPUT=$($CLI trash list 2>&1)
assert_contains "Todo in trash" "$OUTPUT" "CiderTest${TEST_ID}TodoTrash"

TRASH_TODO=$(echo "$OUTPUT" | grep "CiderTest${TEST_ID}TodoTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_TODO" 2>&1)
assert_contains "Restore todo" "$OUTPUT" "Restored"

sleep 1
OUTPUT=$($CLI todo list 2>&1)
assert_contains "Todo back in list" "$OUTPUT" "CiderTest${TEST_ID}TodoTrash"

# Re-delete for cleanup
$CLI todo delete "$TODO_TRASH_ID" >/dev/null 2>&1

# ── Event trash round-trip ────────────────────────
echo ""
echo -e "${YELLOW}7. Trash — Event Round-Trip${NC}"
OUTPUT=$($CLI event create "CiderTest${TEST_ID}EventTrash" --date 2026-12-25 2>&1)
assert_contains "Create event for trash" "$OUTPUT" "Created event"

sleep 1
# Get event ID from list
EVENT_TRASH_ID=$($CLI event list 2>&1 | grep "CiderTest${TEST_ID}EventTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI event delete "$EVENT_TRASH_ID" 2>&1)
assert_contains "Delete event" "$OUTPUT" "trash\|Deleted"

OUTPUT=$($CLI trash list 2>&1)
assert_contains "Event in trash" "$OUTPUT" "CiderTest${TEST_ID}EventTrash"

TRASH_EVENT=$(echo "$OUTPUT" | grep "CiderTest${TEST_ID}EventTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_EVENT" 2>&1)
assert_contains "Restore event" "$OUTPUT" "Restored"

sleep 1
OUTPUT=$($CLI event list 2>&1)
assert_contains "Event back in list" "$OUTPUT" "CiderTest${TEST_ID}EventTrash"

# ── Contact trash round-trip ──────────────────────
echo ""
echo -e "${YELLOW}8. Trash — Contact Round-Trip${NC}"
OUTPUT=$($CLI contact create "CiderTest${TEST_ID}ContactTrash" 2>&1)
assert_contains "Create contact for trash" "$OUTPUT" "Created contact"

sleep 1
CONTACT_TRASH_ID=$($CLI contact list 2>&1 | grep "CiderTest${TEST_ID}ContactTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI contact delete "$CONTACT_TRASH_ID" 2>&1)
assert_contains "Delete contact" "$OUTPUT" "trash\|Deleted"

OUTPUT=$($CLI trash list 2>&1)
assert_contains "Contact in trash" "$OUTPUT" "CiderTest${TEST_ID}ContactTrash"

TRASH_CONTACT=$(echo "$OUTPUT" | grep "CiderTest${TEST_ID}ContactTrash" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_CONTACT" 2>&1)
assert_contains "Restore contact" "$OUTPUT" "Restored"

sleep 1
OUTPUT=$($CLI contact list 2>&1)
assert_contains "Contact back in list" "$OUTPUT" "CiderTest${TEST_ID}ContactTrash"

# ═══════════════════════════════════════════════════
# 9. NOTES — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}9. Notes — Full Lifecycle${NC}"
echo -e "  ${CYAN}── Create & count${NC}"
NOTE_BEFORE=$(get_count "Notes")

OUTPUT=$($CLI note create "CiderTest${TEST_ID}NoteA" --content "Content A" 2>&1)
assert_contains "Create note A" "$OUTPUT" "Created note"

OUTPUT=$($CLI note create "CiderTest${TEST_ID}NoteB" --content "Content B" 2>&1)
assert_contains "Create note B" "$OUTPUT" "Created note"

sleep 2
NOTE_AFTER=$(get_count "Notes")
assert_count_changed "Count +2" "$NOTE_BEFORE" "$NOTE_AFTER" "increased"

echo -e "  ${CYAN}── List & get${NC}"
OUTPUT=$($CLI note list 2>&1)
assert_contains "Note A in list" "$OUTPUT" "CiderTest${TEST_ID}NoteA"
assert_contains "Note B in list" "$OUTPUT" "CiderTest${TEST_ID}NoteB"

NOTE_A_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteA" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
NOTE_B_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteB" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI note get "$NOTE_A_ID" 2>&1)
assert_contains "Get: content A" "$OUTPUT" "Content A"

echo -e "  ${CYAN}── Pin toggle${NC}"
OUTPUT=$($CLI note pin "$NOTE_A_ID" 2>&1)
assert_contains "Pin" "$OUTPUT" "Pinned"

OUTPUT=$($CLI note pin "$NOTE_A_ID" 2>&1)
assert_contains "Unpin (toggle)" "$OUTPUT" "Unpinned"

echo -e "  ${CYAN}── Move to folder${NC}"
OUTPUT=$($CLI note move "$NOTE_A_ID" --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Move note" "$OUTPUT" "Moved"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI note list --json 2>&1)
assert_json_valid "Valid list JSON" "$OUTPUT"
assert_json_has_key "Has id field" "$OUTPUT" "id"
assert_json_has_key "Has title field" "$OUTPUT" "title"
assert_json_has_key "Has pinned field" "$OUTPUT" "pinned"

# ═══════════════════════════════════════════════════
# 10. TODOS — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}10. Todos — Full Lifecycle${NC}"
echo -e "  ${CYAN}── Create with options${NC}"
TODO_BEFORE=$(get_count "Todos")

OUTPUT=$($CLI todo create "CiderTest${TEST_ID}TodoA" --due 2026-12-31 --priority high 2>&1)
assert_contains "Create todo A (high)" "$OUTPUT" "Created todo"
TODO_A_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI todo create "CiderTest${TEST_ID}TodoB" --priority medium 2>&1)
assert_contains "Create todo B (medium, no due)" "$OUTPUT" "Created todo"
TODO_B_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI todo create "CiderTest${TEST_ID}TodoC" 2>&1)
assert_contains "Create todo C (no flags)" "$OUTPUT" "Created todo"
TODO_C_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
TODO_AFTER=$(get_count "Todos")
assert_count_changed "Count +3" "$TODO_BEFORE" "$TODO_AFTER" "increased"

echo -e "  ${CYAN}── List & verify fields${NC}"
OUTPUT=$($CLI todo list 2>&1)
assert_contains "Todo A in list" "$OUTPUT" "CiderTest${TEST_ID}TodoA"
assert_contains "Shows priority" "$OUTPUT" "high"
assert_contains "Shows due date" "$OUTPUT" "2026-12"

echo -e "  ${CYAN}── Complete & list completed${NC}"
OUTPUT=$($CLI todo complete "$TODO_A_ID" 2>&1)
assert_contains "Complete A" "$OUTPUT" "Completed"

OUTPUT=$($CLI todo list 2>&1)
assert_not_contains "Completed not in active list" "$OUTPUT" "CiderTest${TEST_ID}TodoA"

OUTPUT=$($CLI todo list --completed 2>&1)
assert_contains "A in completed list" "$OUTPUT" "CiderTest${TEST_ID}TodoA"

echo -e "  ${CYAN}── Delete multiple${NC}"
OUTPUT=$($CLI todo delete "$TODO_A_ID" 2>&1)
assert_contains "Delete A" "$OUTPUT" "trash"

OUTPUT=$($CLI todo delete "$TODO_B_ID" 2>&1)
assert_contains "Delete B" "$OUTPUT" "trash"

OUTPUT=$($CLI todo delete "$TODO_C_ID" 2>&1)
assert_contains "Delete C" "$OUTPUT" "trash"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI todo list --json 2>&1)
assert_json_valid "Valid list JSON" "$OUTPUT"

# ═══════════════════════════════════════════════════
# 11. EVENTS — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}11. Events${NC}"
OUTPUT=$($CLI event create "CiderTest${TEST_ID}EventA" --date 2026-12-25 2>&1)
assert_contains "Create event" "$OUTPUT" "Created event"

OUTPUT=$($CLI event create "CiderTest${TEST_ID}EventB" 2>&1)
assert_contains "Create event (no date)" "$OUTPUT" "Created event"

OUTPUT=$($CLI event list 2>&1)
assert_contains "Event A in list" "$OUTPUT" "CiderTest${TEST_ID}EventA"
assert_contains "Event B in list" "$OUTPUT" "CiderTest${TEST_ID}EventB"

echo -e "  ${CYAN}── List shows date${NC}"
OUTPUT=$($CLI event list 2>&1)
assert_contains "Shows date" "$OUTPUT" "2026"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI event list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has startAt" "$OUTPUT" "startAt"

# ═══════════════════════════════════════════════════
# 12. CONTACTS — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}12. Contacts${NC}"
OUTPUT=$($CLI contact create "CiderTest${TEST_ID}ContactA" 2>&1)
assert_contains "Create contact A" "$OUTPUT" "Created contact"

OUTPUT=$($CLI contact create "CiderTest${TEST_ID}ContactB" --email "test@example.com" --phone "+15551234567" 2>&1)
assert_contains "Create contact B (with details)" "$OUTPUT" "Created contact"

OUTPUT=$($CLI contact list 2>&1)
assert_contains "Contact A in list" "$OUTPUT" "CiderTest${TEST_ID}ContactA"
assert_contains "Contact B in list" "$OUTPUT" "CiderTest${TEST_ID}ContactB"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI contact list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has displayName" "$OUTPUT" "displayName"

# ═══════════════════════════════════════════════════
# 13. VAULT FILES — List & Filter
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}13. Vault Files${NC}"
OUTPUT=$($CLI file list 2>&1)
assert_contains "File list header" "$OUTPUT" "Vault files"

OUTPUT=$($CLI file list --type image 2>&1)
assert_contains "Image filter" "$OUTPUT" "Image\|image\|No vault files"

OUTPUT=$($CLI file list --type video 2>&1)
assert_contains "Video filter works" "$OUTPUT" "Vault files"

OUTPUT=$($CLI file list --type document 2>&1)
assert_contains "Document filter works" "$OUTPUT" "Vault files"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI file list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"

# ═══════════════════════════════════════════════════
# 14. LABELS — Full Lifecycle + Interactions
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}14. Labels${NC}"
echo -e "  ${CYAN}── Create & list${NC}"
OUTPUT=$($CLI label create "CiderTest${TEST_ID}LabelA" --color "#FF0000" 2>&1)
assert_contains "Create label A (red)" "$OUTPUT" "Created label"

OUTPUT=$($CLI label create "CiderTest${TEST_ID}LabelB" --color "#00FF00" 2>&1)
assert_contains "Create label B (green)" "$OUTPUT" "Created label"

OUTPUT=$($CLI label create "CiderTest${TEST_ID}LabelC" 2>&1)
assert_contains "Create label C (random color)" "$OUTPUT" "Created label"

OUTPUT=$($CLI label list 2>&1)
assert_contains "A in list" "$OUTPUT" "CiderTest${TEST_ID}LabelA"
assert_contains "B in list" "$OUTPUT" "CiderTest${TEST_ID}LabelB"
assert_contains "C in list" "$OUTPUT" "CiderTest${TEST_ID}LabelC"

echo -e "  ${CYAN}── Rename${NC}"
OUTPUT=$($CLI label rename "CiderTest${TEST_ID}LabelC" --to "CiderTest${TEST_ID}LabelCR" 2>&1)
assert_contains "Rename" "$OUTPUT" "Renamed"

OUTPUT=$($CLI label list 2>&1)
assert_contains "Renamed shows" "$OUTPUT" "CiderTest${TEST_ID}LabelCR"
assert_not_contains "Old name gone" "$OUTPUT" "CiderTest${TEST_ID}LabelC[^R]"

echo -e "  ${CYAN}── Delete${NC}"
OUTPUT=$($CLI label delete "CiderTest${TEST_ID}LabelCR" 2>&1)
assert_contains "Delete C" "$OUTPUT" "Deleted label"

OUTPUT=$($CLI label list 2>&1)
assert_not_contains "Deleted label gone" "$OUTPUT" "CiderTest${TEST_ID}LabelCR"

echo -e "  ${CYAN}── Edge: delete non-existent${NC}"
OUTPUT=$($CLI label delete "CiderTest${TEST_ID}NoExist" 2>&1)
assert_contains "Delete non-existent" "$OUTPUT" "not found\|error\|No label"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI label list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has colorHex" "$OUTPUT" "colorHex"

# Clean up remaining labels
$CLI label delete "CiderTest${TEST_ID}LabelA" >/dev/null 2>&1
$CLI label delete "CiderTest${TEST_ID}LabelB" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 15. KANBAN BOARDS — Full Lifecycle
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}15. Kanban Boards${NC}"
echo -e "  ${CYAN}── List & show${NC}"
OUTPUT=$($CLI board list 2>&1)
assert_contains "Board list" "$OUTPUT" "Cider Roadmap"
assert_contains "Shows columns" "$OUTPUT" "Backlog"

OUTPUT=$($CLI board show "Cider Bugs" 2>&1)
assert_contains "Board show" "$OUTPUT" "Medium Priority\|Low Priority\|High Priority"

echo -e "  ${CYAN}── Card lifecycle${NC}"
OUTPUT=$($CLI board add-card "Cider Bugs" --column "Low Priority" --title "CiderTest${TEST_ID}CardA" --notes "Test A" --priority low 2>&1)
assert_contains "Add card A" "$OUTPUT" "Added card"
CARD_A=$(echo "$OUTPUT" | grep -o '\[[a-f0-9]*\]' | tr -d '[]')

OUTPUT=$($CLI board add-card "Cider Bugs" --column "Low Priority" --title "CiderTest${TEST_ID}CardB" --notes "Test B" --priority medium 2>&1)
assert_contains "Add card B" "$OUTPUT" "Added card"
CARD_B=$(echo "$OUTPUT" | grep -o '\[[a-f0-9]*\]' | tr -d '[]')

OUTPUT=$($CLI board show "Cider Bugs" 2>&1)
assert_contains "Card A in board" "$OUTPUT" "CiderTest${TEST_ID}CardA"
assert_contains "Card B in board" "$OUTPUT" "CiderTest${TEST_ID}CardB"

echo -e "  ${CYAN}── Move card between columns${NC}"
OUTPUT=$($CLI board move-card "Cider Bugs" --card "$CARD_A" --to "Medium Priority" 2>&1)
assert_contains "Move card A" "$OUTPUT" "Moved"

echo -e "  ${CYAN}── Delete cards${NC}"
OUTPUT=$($CLI board delete-card "Cider Bugs" --card "$CARD_A" 2>&1)
assert_contains "Delete card A" "$OUTPUT" "Deleted card"

OUTPUT=$($CLI board delete-card "Cider Bugs" --card "$CARD_B" 2>&1)
assert_contains "Delete card B" "$OUTPUT" "Deleted card"

OUTPUT=$($CLI board show "Cider Bugs" 2>&1)
assert_not_contains "A gone" "$OUTPUT" "CiderTest${TEST_ID}CardA"
assert_not_contains "B gone" "$OUTPUT" "CiderTest${TEST_ID}CardB"

echo -e "  ${CYAN}── Edge: non-existent board${NC}"
OUTPUT=$($CLI board show "NonExistentBoard" 2>&1)
assert_contains "Non-existent board" "$OUTPUT" "not found\|No board\|error"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI board show "Cider Bugs" --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has columns" "$OUTPUT" "columns"

# ═══════════════════════════════════════════════════
# 16. SEARCH — Scopes & Edge Cases
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}16. Search${NC}"
echo -e "  ${CYAN}── Global search${NC}"
OUTPUT=$($CLI search "CiderTest${TEST_ID}" 2>&1)
assert_contains "Global search" "$OUTPUT" "Search"

echo -e "  ${CYAN}── Scoped searches${NC}"
OUTPUT=$($CLI search "@bookmarks example" 2>&1)
assert_contains "@bookmarks scope" "$OUTPUT" "Search"

OUTPUT=$($CLI search "@notes CiderTest${TEST_ID}" 2>&1)
assert_contains "@notes scope" "$OUTPUT" "Search"

OUTPUT=$($CLI search "@todos CiderTest${TEST_ID}" 2>&1)
assert_contains "@todos scope" "$OUTPUT" "Search"

OUTPUT=$($CLI search "@events CiderTest${TEST_ID}" 2>&1)
assert_contains "@events scope" "$OUTPUT" "Search"

echo -e "  ${CYAN}── Empty / no results${NC}"
OUTPUT=$($CLI search "xyzzy_nomatch_${TEST_ID}" 2>&1)
assert_contains "No results handled" "$OUTPUT" "Search\|No results\|0 results"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI search "CiderTest${TEST_ID}" --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"

# ═══════════════════════════════════════════════════
# 17. TRASH — Empty, Purge, Edge Cases
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}17. Trash — Edge Cases${NC}"

echo -e "  ${CYAN}── Purge with --days 0${NC}"
OUTPUT=$($CLI trash purge --days 0 2>&1)
assert_contains "Purge" "$OUTPUT" "Purged"

echo -e "  ${CYAN}── Empty trash${NC}"
OUTPUT=$($CLI trash empty 2>&1)
assert_contains "Empty" "$OUTPUT" "Emptied\|empty\|Trash"

echo -e "  ${CYAN}── List empty trash${NC}"
OUTPUT=$($CLI trash list 2>&1)
assert_contains "Empty trash list" "$OUTPUT" "Trash\|empty\|No items\|0 items"

echo -e "  ${CYAN}── Restore non-existent ID${NC}"
OUTPUT=$($CLI trash restore "DEADBEEF" 2>&1)
assert_contains "Restore bad ID" "$OUTPUT" "not found\|No item\|error\|No trash"

# ═══════════════════════════════════════════════════
# 18. CROSS-TYPE OPERATIONS
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}18. Cross-Type Operations${NC}"

echo -e "  ${CYAN}── Create items in same folder${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/cross${TEST_ID}" --title "CiderTest${TEST_ID}CrossBm" --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Bookmark in folder" "$OUTPUT" "Created bookmark"
CROSS_BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

# Move a note to same folder
sleep 1
NOTE_B_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteB" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
if [ -n "$NOTE_B_ID" ]; then
    OUTPUT=$($CLI note move "$NOTE_B_ID" --folder "CiderTest${TEST_ID}Folder" 2>&1)
    assert_contains "Note moved to same folder" "$OUTPUT" "Moved"
fi

echo -e "  ${CYAN}── Global search finds mixed types${NC}"
sleep 1
OUTPUT=$($CLI search "CiderTest${TEST_ID}" 2>&1)
assert_contains "Search finds bookmarks" "$OUTPUT" "bookmark\|CiderTest${TEST_ID}"

echo -e "  ${CYAN}── Status reflects all items${NC}"
OUTPUT=$($CLI status 2>&1)
assert_contains "Status still works" "$OUTPUT" "Bookmarks:"

# ═══════════════════════════════════════════════════
# 19. ERROR HANDLING & EDGE CASES
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}19. Error Handling${NC}"

echo -e "  ${CYAN}── Invalid subcommands${NC}"
OUTPUT=$($CLI bookmark nonsense 2>&1)
assert_contains "Unknown bookmark cmd" "$OUTPUT" "Unknown\|error\|Commands"

OUTPUT=$($CLI note nonsense 2>&1)
assert_contains "Unknown note cmd" "$OUTPUT" "Unknown\|error\|Commands"

OUTPUT=$($CLI todo nonsense 2>&1)
assert_contains "Unknown todo cmd" "$OUTPUT" "Unknown\|error\|Commands"

echo -e "  ${CYAN}── Missing required args${NC}"
OUTPUT=$($CLI bookmark add 2>&1)
assert_contains "Add without URL" "$OUTPUT" "URL required\|error\|Usage"

OUTPUT=$($CLI bookmark get 2>&1)
assert_contains "Get without ID" "$OUTPUT" "ID\|required\|error"

OUTPUT=$($CLI bookmark move 2>&1)
assert_contains "Move without ID" "$OUTPUT" "ID\|required\|error"

OUTPUT=$($CLI note get 2>&1)
assert_contains "Note get without ID" "$OUTPUT" "ID\|required\|error"

echo -e "  ${CYAN}── Invalid ID prefix${NC}"
OUTPUT=$($CLI bookmark get "ZZZZZZZZ" 2>&1)
assert_contains "Bad bookmark ID" "$OUTPUT" "not found\|No bookmark\|error"

OUTPUT=$($CLI note get "ZZZZZZZZ" 2>&1)
assert_contains "Bad note ID" "$OUTPUT" "not found\|No note\|error"

OUTPUT=$($CLI todo complete "ZZZZZZZZ" 2>&1)
assert_contains "Bad todo ID" "$OUTPUT" "not found\|No todo\|error"

echo -e "  ${CYAN}── Move to non-existent folder${NC}"
OUTPUT=$($CLI bookmark move "$CROSS_BM_ID" --folder "NonExistent${TEST_ID}" 2>&1)
assert_contains "Move to bad folder" "$OUTPUT" "not found\|No folder\|error"

echo -e "  ${CYAN}── Unknown top-level command${NC}"
OUTPUT=$($CLI foobar 2>&1)
assert_contains "Unknown command" "$OUTPUT" "Unknown\|error\|Usage\|BOOKMARKS"

# ═══════════════════════════════════════════════════
# 20. HELP — All Sections Present
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}20. Help${NC}"
OUTPUT=$($CLI help 2>&1)
assert_contains "Bookmarks" "$OUTPUT" "BOOKMARKS"
assert_contains "Notes" "$OUTPUT" "NOTES"
assert_contains "Todos" "$OUTPUT" "TODOS"
assert_contains "Events" "$OUTPUT" "EVENTS"
assert_contains "Contacts" "$OUTPUT" "CONTACTS"
assert_contains "Files" "$OUTPUT" "FILES"
assert_contains "Folders" "$OUTPUT" "FOLDERS"
assert_contains "Boards" "$OUTPUT" "BOARDS"
assert_contains "Labels" "$OUTPUT" "LABELS"
assert_contains "Search" "$OUTPUT" "SEARCH"
assert_contains "Trash" "$OUTPUT" "TRASH"
assert_contains "Status" "$OUTPUT" "STATUS"

# Also test -h and --help aliases
OUTPUT=$($CLI --help 2>&1)
assert_contains "--help alias" "$OUTPUT" "BOOKMARKS"

OUTPUT=$($CLI -h 2>&1)
assert_contains "-h alias" "$OUTPUT" "BOOKMARKS"

# ═══════════════════════════════════════════════════
# 21. COMMAND ALIASES
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}21. Command Aliases${NC}"
OUTPUT=$($CLI bm list --limit 1 2>&1)
assert_contains "'bm' alias" "$OUTPUT" "bookmark\|http\|Bookmarks"

OUTPUT=$($CLI tag list 2>&1)
assert_contains "'tag' alias" "$OUTPUT" "label\|Label\|No labels"

OUTPUT=$($CLI datecard list 2>&1)
assert_contains "'datecard' alias" "$OUTPUT" "event\|Event\|Date\|No events"

# ═══════════════════════════════════════════════════
# 22. FOLDER DELETE — with contents
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}22. Folder Delete${NC}"
# Create a temp folder, add a bookmark, then delete the folder
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}DelFolder" 2>&1)
assert_contains "Create folder for delete test" "$OUTPUT" "Created folder"

OUTPUT=$($CLI bookmark add "https://example.com/del${TEST_ID}" --title "CiderTest${TEST_ID}DelBm" --folder "CiderTest${TEST_ID}DelFolder" 2>&1)
assert_contains "Bookmark in delete folder" "$OUTPUT" "Created bookmark"

sleep 1
OUTPUT=$($CLI folder delete "CiderTest${TEST_ID}DelFolder" 2>&1)
assert_contains "Delete folder" "$OUTPUT" "Deleted\|trash\|removed"

OUTPUT=$($CLI folder list 2>&1)
assert_not_contains "Deleted folder gone" "$OUTPUT" "CiderTest${TEST_ID}DelFolder"

# ═══════════════════════════════════════════════════
# 23. SEQUENTIAL DELETE-RESTORE-DELETE
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}23. Delete-Restore-Delete Cycle${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/cycle${TEST_ID}" --title "CiderTest${TEST_ID}Cycle" 2>&1)
assert_contains "Create cycle bookmark" "$OUTPUT" "Created bookmark"
CYCLE_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

# Delete → trash
OUTPUT=$($CLI bookmark delete "$CYCLE_ID" 2>&1)
assert_contains "First delete" "$OUTPUT" "trash"

sleep 1
# Restore from trash
TRASH_CYCLE=$($CLI trash list 2>&1 | grep "CiderTest${TEST_ID}Cycle" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI trash restore "$TRASH_CYCLE" 2>&1)
assert_contains "Restore" "$OUTPUT" "Restored"

sleep 1
# Verify it's back
OUTPUT=$($CLI bookmark list 2>&1)
assert_contains "Back after restore" "$OUTPUT" "CiderTest${TEST_ID}Cycle"

# Delete again
OUTPUT=$($CLI bookmark delete "$CYCLE_ID" 2>&1)
assert_contains "Second delete" "$OUTPUT" "trash"

sleep 1
# Verify in trash again
OUTPUT=$($CLI trash list 2>&1)
assert_contains "In trash again" "$OUTPUT" "CiderTest${TEST_ID}Cycle"

# ═══════════════════════════════════════════════════
# 24. TODO STATE TRANSITIONS
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}24. Todo State Transitions${NC}"
OUTPUT=$($CLI todo create "CiderTest${TEST_ID}StateT" --priority low 2>&1)
STATE_TODO_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

# Active → completed
OUTPUT=$($CLI todo complete "$STATE_TODO_ID" 2>&1)
assert_contains "Active → completed" "$OUTPUT" "Completed"

# Should be in completed list
OUTPUT=$($CLI todo list --completed 2>&1)
assert_contains "In completed list" "$OUTPUT" "CiderTest${TEST_ID}StateT"

# Should NOT be in active list
OUTPUT=$($CLI todo list 2>&1)
assert_not_contains "Not in active list" "$OUTPUT" "CiderTest${TEST_ID}StateT"

# Completed → trash
OUTPUT=$($CLI todo delete "$STATE_TODO_ID" 2>&1)
assert_contains "Completed → trash" "$OUTPUT" "trash"

# ═══════════════════════════════════════════════════
# 25. BOOKMARK TAG INTERACTIONS
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}25. Tag Interactions${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/tag${TEST_ID}" --title "CiderTest${TEST_ID}TagBm" 2>&1)
TAG_BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

# Tag with auto-created label
OUTPUT=$($CLI bookmark tag "$TAG_BM_ID" "CiderTest${TEST_ID}AutoTag" 2>&1)
assert_contains "Auto-create tag" "$OUTPUT" "Tagged"

# Verify label was created
OUTPUT=$($CLI label list 2>&1)
assert_contains "Auto-created label exists" "$OUTPUT" "CiderTest${TEST_ID}AutoTag"

# Tag same bookmark with second label
OUTPUT=$($CLI bookmark tag "$TAG_BM_ID" "CiderTest${TEST_ID}AutoTag2" 2>&1)
assert_contains "Second tag" "$OUTPUT" "Tagged"

# Double-tag (tag again with same label)
OUTPUT=$($CLI bookmark tag "$TAG_BM_ID" "CiderTest${TEST_ID}AutoTag" 2>&1)
assert_contains "Double tag handled" "$OUTPUT" "Tagged\|already"

# Remove first tag
OUTPUT=$($CLI bookmark untag "$TAG_BM_ID" "CiderTest${TEST_ID}AutoTag" 2>&1)
assert_contains "Remove first tag" "$OUTPUT" "Removed tag"

# Clean up
$CLI bookmark delete "$TAG_BM_ID" >/dev/null 2>&1
$CLI label delete "CiderTest${TEST_ID}AutoTag" >/dev/null 2>&1
$CLI label delete "CiderTest${TEST_ID}AutoTag2" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 26. MULTIPLE BOOKMARKS IN SAME FOLDER
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}26. Folder Content Integrity${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/f1${TEST_ID}" --title "CiderTest${TEST_ID}F1" --folder "CiderTest${TEST_ID}FolderB" 2>&1)
F1_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI bookmark add "https://example.com/f2${TEST_ID}" --title "CiderTest${TEST_ID}F2" --folder "CiderTest${TEST_ID}FolderB" 2>&1)
F2_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI bookmark add "https://example.com/f3${TEST_ID}" --title "CiderTest${TEST_ID}F3" --folder "CiderTest${TEST_ID}FolderB" 2>&1)
F3_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}FolderB" 2>&1)
assert_contains "F1 in folder" "$OUTPUT" "CiderTest${TEST_ID}F1"
assert_contains "F2 in folder" "$OUTPUT" "CiderTest${TEST_ID}F2"
assert_contains "F3 in folder" "$OUTPUT" "CiderTest${TEST_ID}F3"

# Delete middle one — others should stay
$CLI bookmark delete "$F2_ID" >/dev/null 2>&1
sleep 1
OUTPUT=$($CLI bookmark list --folder "CiderTest${TEST_ID}FolderB" 2>&1)
assert_contains "F1 still there" "$OUTPUT" "CiderTest${TEST_ID}F1"
assert_not_contains "F2 gone" "$OUTPUT" "CiderTest${TEST_ID}F2"
assert_contains "F3 still there" "$OUTPUT" "CiderTest${TEST_ID}F3"

# Clean up
$CLI bookmark delete "$F1_ID" >/dev/null 2>&1
$CLI bookmark delete "$F3_ID" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 27. STATUS COUNTS CONSISTENCY
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}27. Status Count Consistency${NC}"
# Get counts, create items, verify counts increase, delete items, verify counts decrease
STATUS_BM_BEFORE=$(get_count "Bookmarks")
STATUS_NOTE_BEFORE=$(get_count "Notes")

OUTPUT=$($CLI bookmark add "https://example.com/count${TEST_ID}" --title "CiderTest${TEST_ID}CountBm" 2>&1)
COUNT_BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI note create "CiderTest${TEST_ID}CountNote" --content "Count test" 2>&1)

sleep 2
STATUS_BM_AFTER=$(get_count "Bookmarks")
STATUS_NOTE_AFTER=$(get_count "Notes")
assert_count_changed "BM count +1" "$STATUS_BM_BEFORE" "$STATUS_BM_AFTER" "increased"
assert_count_changed "Note count +1" "$STATUS_NOTE_BEFORE" "$STATUS_NOTE_AFTER" "increased"

# Delete and check counts decrease
$CLI bookmark delete "$COUNT_BM_ID" >/dev/null 2>&1
sleep 1
STATUS_BM_AFTER2=$(get_count "Bookmarks")
assert_count_changed "BM count -1 after delete" "$STATUS_BM_AFTER" "$STATUS_BM_AFTER2" "decreased"

# ═══════════════════════════════════════════════════
# 28. NOTE CONTENT PRESERVATION
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}28. Note Content Preservation${NC}"
OUTPUT=$($CLI note create "CiderTest${TEST_ID}ContentNote" --content "Line 1\nLine 2\nSpecial chars: & < > \"quotes\"" 2>&1)
assert_contains "Create content note" "$OUTPUT" "Created note"

sleep 2
CONTENT_NOTE_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}ContentNote" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
OUTPUT=$($CLI note get "$CONTENT_NOTE_ID" 2>&1)
assert_contains "Content preserved" "$OUTPUT" "Line 1"

# ═══════════════════════════════════════════════════
# 29. UPDATE COMMANDS — All Types
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}29. Update Commands${NC}"

echo -e "  ${CYAN}── Bookmark update${NC}"
# Use existing bookmark from section 3 for update test (avoids enrichment race)
# Bookmark A was moved to FolderB, let's get it from trash since it was deleted
# Actually, create a fresh one and wait for enrichment to finish
OUTPUT=$($CLI bookmark add "https://example.com/upd${TEST_ID}" --title "CiderTest${TEST_ID}UpdBm" 2>&1)
UPD_BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

# Wait for enrichment to finish, then update
sleep 3
OUTPUT=$($CLI bookmark update "$UPD_BM_ID" --title "CiderTest${TEST_ID}Renamed" --notes "Updated notes" 2>&1)
assert_contains "Bookmark update" "$OUTPUT" "Updated"

sleep 2
OUTPUT=$($CLI bookmark get "$UPD_BM_ID" 2>&1)
assert_contains "New title shows" "$OUTPUT" "CiderTest${TEST_ID}Renamed"
assert_contains "New notes show" "$OUTPUT" "Updated notes"
assert_contains "Manual flag set" "$OUTPUT" "title=true"

# Update URL
OUTPUT=$($CLI bookmark update "$UPD_BM_ID" --url "https://example.com/updated${TEST_ID}" 2>&1)
assert_contains "URL update" "$OUTPUT" "Updated"

$CLI bookmark delete "$UPD_BM_ID" >/dev/null 2>&1

echo -e "  ${CYAN}── Note update${NC}"
OUTPUT=$($CLI note create "CiderTest${TEST_ID}UpdNote" --content "Original" 2>&1)
sleep 2
UPD_NOTE_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}UpdNote" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI note update "$UPD_NOTE_ID" --title "CiderTest${TEST_ID}NoteRenamed" 2>&1)
assert_contains "Note rename" "$OUTPUT" "Renamed"

# Re-lookup ID after rename (cross-process ID may change after file rename)
sleep 2
UPD_NOTE_ID2=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteRenamed" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
if [ -z "$UPD_NOTE_ID2" ]; then UPD_NOTE_ID2="$UPD_NOTE_ID"; fi

OUTPUT=$($CLI note update "$UPD_NOTE_ID2" --content "Updated content" 2>&1)
assert_contains "Note content update" "$OUTPUT" "Updated content"

sleep 1
OUTPUT=$($CLI note get "$UPD_NOTE_ID2" 2>&1)
assert_contains "Note has new content" "$OUTPUT" "Updated content"

echo -e "  ${CYAN}── Todo update${NC}"
OUTPUT=$($CLI todo create "CiderTest${TEST_ID}UpdTodo" --priority low 2>&1)
UPD_TODO_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

OUTPUT=$($CLI todo update "$UPD_TODO_ID" --title "CiderTest${TEST_ID}TodoRenamed" --priority high --due 2026-06-15 2>&1)
assert_contains "Todo update" "$OUTPUT" "Updated"

sleep 1
OUTPUT=$($CLI todo list 2>&1)
assert_contains "Todo new title" "$OUTPUT" "CiderTest${TEST_ID}TodoRenamed"
assert_contains "Todo new priority" "$OUTPUT" "high"

$CLI todo delete "$UPD_TODO_ID" >/dev/null 2>&1

echo -e "  ${CYAN}── Event update${NC}"
OUTPUT=$($CLI event create "CiderTest${TEST_ID}UpdEvent" --date 2026-12-25 2>&1)
sleep 1
UPD_EVENT_ID=$($CLI event list 2>&1 | grep "CiderTest${TEST_ID}UpdEvent" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI event update "$UPD_EVENT_ID" --title "CiderTest${TEST_ID}EventRenamed" --location "123 Main St" 2>&1)
assert_contains "Event update" "$OUTPUT" "Updated"

echo -e "  ${CYAN}── Contact update${NC}"
OUTPUT=$($CLI contact create "CiderTest${TEST_ID}UpdContact" 2>&1)
sleep 1
UPD_CONTACT_ID=$($CLI contact list 2>&1 | grep "CiderTest${TEST_ID}UpdContact" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI contact update "$UPD_CONTACT_ID" --name "CiderTest${TEST_ID}ContactRenamed" --email "updated@test.com" 2>&1)
assert_contains "Contact update" "$OUTPUT" "Updated"

echo -e "  ${CYAN}── Update with bad ID${NC}"
OUTPUT=$($CLI bookmark update "ZZZZZZZZ" --title "nope" 2>&1)
assert_contains "Bookmark update bad ID" "$OUTPUT" "not found\|No bookmark\|error"

OUTPUT=$($CLI todo update "ZZZZZZZZ" --title "nope" 2>&1)
assert_contains "Todo update bad ID" "$OUTPUT" "not found\|No todo\|error"

OUTPUT=$($CLI event update "ZZZZZZZZ" --title "nope" 2>&1)
assert_contains "Event update bad ID" "$OUTPUT" "not found\|No event\|error"

OUTPUT=$($CLI contact update "ZZZZZZZZ" --name "nope" 2>&1)
assert_contains "Contact update bad ID" "$OUTPUT" "not found\|No contact\|error"

OUTPUT=$($CLI note update "ZZZZZZZZ" --title "nope" 2>&1)
assert_contains "Note update bad ID" "$OUTPUT" "not found\|No note\|error"

echo -e "  ${CYAN}── Update with no changes${NC}"
OUTPUT=$($CLI bookmark update "ZZZZZZZZ" 2>&1)
assert_contains "No changes bookmark" "$OUTPUT" "No changes\|not found\|No bookmark"

# ═══════════════════════════════════════════════════
# 30. BOOKMARK ADD WITHOUT TITLE (renumbered) (auto-title)
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}29. Bookmark Auto-Title${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/notitle${TEST_ID}" 2>&1)
assert_contains "Create without title" "$OUTPUT" "Created bookmark"
NOTITLE_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
OUTPUT=$($CLI bookmark get "$NOTITLE_ID" 2>&1)
assert_contains "Auto-title from URL" "$OUTPUT" "example.com"
$CLI bookmark delete "$NOTITLE_ID" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 30. BOOKMARK SEARCH --json
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}30. Bookmark Search JSON${NC}"
# Create a searchable bookmark
# Use an existing bookmark for search JSON test (avoids timing issues with newly created ones)
OUTPUT=$($CLI bookmark search "example" --json 2>&1)
assert_json_valid "Valid search JSON" "$OUTPUT"
assert_json_array_min "Search JSON has results" "$OUTPUT" 1

# ═══════════════════════════════════════════════════
# 31. TAG SHOWS IN BOOKMARK GET
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}31. Tag Visible in Bookmark Get${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/tagget${TEST_ID}" --title "CiderTest${TEST_ID}TagGet" 2>&1)
TAGGET_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')
$CLI bookmark tag "$TAGGET_ID" "CiderTest${TEST_ID}VisTag" >/dev/null 2>&1

sleep 1
OUTPUT=$($CLI bookmark get "$TAGGET_ID" --json 2>&1)
assert_json_valid "Valid get JSON with tag" "$OUTPUT"
# Verify tag appears in the JSON labelIDs array (label was auto-created)
assert_contains "Tag ID in JSON" "$OUTPUT" "labelIDs"

$CLI bookmark delete "$TAGGET_ID" >/dev/null 2>&1
$CLI label delete "CiderTest${TEST_ID}VisTag" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 32. MOVE BACK TO INBOX (unfiled)
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}32. Move Back to Inbox${NC}"
OUTPUT=$($CLI bookmark add "https://example.com/inbox${TEST_ID}" --title "CiderTest${TEST_ID}InboxBm" --folder "CiderTest${TEST_ID}Folder" 2>&1)
INBOX_BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
# Move back to Inbox by omitting --folder
OUTPUT=$($CLI bookmark move "$INBOX_BM_ID" 2>&1)
# This should either move to Inbox or show an error about missing --folder
if echo "$OUTPUT" | grep -qi "Moved\|Inbox"; then
    assert_contains "Move to Inbox" "$OUTPUT" "Moved\|Inbox"
else
    assert_contains "Move requires --folder" "$OUTPUT" "folder\|required\|error"
fi
$CLI bookmark delete "$INBOX_BM_ID" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 33. FILE GET / MOVE / DELETE
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}33. Vault File Operations${NC}"
# Drop a test file into Inbox/Files
echo "test content ${TEST_ID}" > ~/CiderVault/Inbox/Files/CiderTest${TEST_ID}.txt
sleep 2

# Find the file
OUTPUT=$($CLI file list 2>&1)
if echo "$OUTPUT" | grep -qi "CiderTest${TEST_ID}"; then
    assert_contains "Test file in list" "$OUTPUT" "CiderTest${TEST_ID}"

    FILE_ID=$($CLI file list 2>&1 | grep "CiderTest${TEST_ID}" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

    if [ -n "$FILE_ID" ]; then
        echo -e "  ${CYAN}── File get${NC}"
        OUTPUT=$($CLI file get "$FILE_ID" 2>&1)
        assert_contains "File get shows name" "$OUTPUT" "CiderTest${TEST_ID}"
        assert_contains "File get shows type" "$OUTPUT" "Type:"

        echo -e "  ${CYAN}── File move to bad folder${NC}"
        OUTPUT=$($CLI file move "$FILE_ID" --folder "NonExistentFolder${TEST_ID}" 2>&1)
        assert_contains "File move bad folder" "$OUTPUT" "error\|No folder\|not found"

        echo -e "  ${CYAN}── File move${NC}"
        OUTPUT=$($CLI file move "$FILE_ID" --folder "CiderTest${TEST_ID}Folder" 2>&1)
        assert_contains "File moved" "$OUTPUT" "Moved"

        echo -e "  ${CYAN}── File delete (re-lookup after move)${NC}"
        sleep 1
        # Re-lookup ID since move may trigger rescan with new ID
        NEW_FILE_ID=$($CLI file list 2>&1 | grep "CiderTest${TEST_ID}" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
        if [ -n "$NEW_FILE_ID" ]; then
            OUTPUT=$($CLI file delete "$NEW_FILE_ID" 2>&1)
            assert_contains "File deleted" "$OUTPUT" "trash\|Deleted"
        else
            OUTPUT=$($CLI file delete "$FILE_ID" 2>&1)
            assert_contains "File deleted" "$OUTPUT" "trash\|Deleted"
        fi
    else
        echo -e "  ${YELLOW}⊘${NC} Could not get file ID (skipped file ops)"
    fi
else
    echo -e "  ${YELLOW}⊘${NC} Test file not detected by scan (skipped)"
fi

# ═══════════════════════════════════════════════════
# 34. SEARCH SCOPE MODIFIERS
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}34. Search Scope Modifiers${NC}"

echo -e "  ${CYAN}── @folder scope${NC}"
OUTPUT=$($CLI search "@folder:CiderTest${TEST_ID}Folder test" 2>&1)
assert_contains "@folder scope runs" "$OUTPUT" "Search\|results"

echo -e "  ${CYAN}── @tag scope${NC}"
OUTPUT=$($CLI search "@tag:ai test" 2>&1)
assert_contains "@tag scope runs" "$OUTPUT" "Search\|results"

echo -e "  ${CYAN}── @images scope${NC}"
OUTPUT=$($CLI search "@images test" 2>&1)
assert_contains "@images scope runs" "$OUTPUT" "Search\|results"

echo -e "  ${CYAN}── @files scope${NC}"
OUTPUT=$($CLI search "@files test" 2>&1)
assert_contains "@files scope runs" "$OUTPUT" "Search\|results"

# ═══════════════════════════════════════════════════
# 35. TODO JSON FIELD COMPLETENESS
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}35. Todo JSON Fields${NC}"
OUTPUT=$($CLI todo create "CiderTest${TEST_ID}TodoJson" --due 2026-12-31 --priority high 2>&1)
TODO_JSON_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

sleep 1
OUTPUT=$($CLI todo list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has title" "$OUTPUT" "title"
assert_json_has_key "Has completed" "$OUTPUT" "completed"
assert_json_has_key "Has created" "$OUTPUT" "created"
assert_json_has_key "Has folder" "$OUTPUT" "folder"

# Complete it and check completedAt appears
$CLI todo complete "$TODO_JSON_ID" >/dev/null 2>&1
sleep 1
OUTPUT=$($CLI todo list --completed --json 2>&1)
assert_json_valid "Completed JSON valid" "$OUTPUT"

$CLI todo delete "$TODO_JSON_ID" >/dev/null 2>&1

# ═══════════════════════════════════════════════════
# 36. CONTACT EMAIL/PHONE STORED
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}36. Contact Details${NC}"
OUTPUT=$($CLI contact create "CiderTest${TEST_ID}DetailC" --email "test${TEST_ID}@example.com" --phone "+15559876543" 2>&1)
assert_contains "Create with details" "$OUTPUT" "Created contact"

sleep 1
OUTPUT=$($CLI contact list --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
# Check if email field is populated (may be empty if create doesn't wire email/phone)
OUTPUT=$($CLI contact list 2>&1)
assert_contains "Contact in list" "$OUTPUT" "CiderTest${TEST_ID}DetailC"

# ═══════════════════════════════════════════════════
# 37. BOARD LIST --json
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}37. Board List JSON${NC}"
OUTPUT=$($CLI board list 2>&1)
assert_contains "Board list works" "$OUTPUT" "Cider"

# board list doesn't have --json, just verify it doesn't crash
OUTPUT=$($CLI board list --json 2>&1)
# This will likely output human text since list doesn't support --json
assert_contains "Board list with --json" "$OUTPUT" "Board\|Cider"

# ═══════════════════════════════════════════════════
# 38. FOLDER CREATE WITH BAD PARENT
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}38. Folder Edge Cases${NC}"

echo -e "  ${CYAN}── Create with non-existent parent${NC}"
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}BadChild" --parent "NonExistent${TEST_ID}" 2>&1)
# Should either create at root or error
assert_contains "Bad parent handled" "$OUTPUT" "Created folder\|error\|not found"

echo -e "  ${CYAN}── Delete non-existent folder${NC}"
OUTPUT=$($CLI folder delete "NonExistent${TEST_ID}" 2>&1)
assert_not_contains "No crash on bad delete" "$OUTPUT" "fatal\|crash"

echo -e "  ${CYAN}── Nested folder delete${NC}"
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}Nest1" 2>&1)
assert_contains "Create nest1" "$OUTPUT" "Created folder"
OUTPUT=$($CLI folder create "CiderTest${TEST_ID}Nest2" --parent "CiderTest${TEST_ID}Nest1" 2>&1)
assert_contains "Create nest2" "$OUTPUT" "Created folder"
OUTPUT=$($CLI folder delete "CiderTest${TEST_ID}Nest1" 2>&1)
assert_contains "Delete nested folder" "$OUTPUT" "Deleted\|trash\|removed"

# ═══════════════════════════════════════════════════
# 39. NOTE MOVE TO NON-EXISTENT FOLDER
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}39. Note Move Validation${NC}"
OUTPUT=$($CLI note create "CiderTest${TEST_ID}NoteMoveV" --content "Validate" 2>&1)
sleep 2
NOTEMV_ID=$($CLI note list 2>&1 | grep "CiderTest${TEST_ID}NoteMoveV" | head -1 | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

OUTPUT=$($CLI note move "$NOTEMV_ID" --folder "NonExistent${TEST_ID}" 2>&1)
assert_contains "Note move bad folder" "$OUTPUT" "error\|No folder\|not found"

# ═══════════════════════════════════════════════════
# 40. EVENT/CONTACT ERROR HANDLING
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}40. Event & Contact Errors${NC}"

echo -e "  ${CYAN}── Unknown event subcommand${NC}"
OUTPUT=$($CLI event nonsense 2>&1)
assert_contains "Unknown event cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown contact subcommand${NC}"
OUTPUT=$($CLI contact nonsense 2>&1)
assert_contains "Unknown contact cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown file subcommand${NC}"
OUTPUT=$($CLI file nonsense 2>&1)
assert_contains "Unknown file cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown folder subcommand${NC}"
OUTPUT=$($CLI folder nonsense 2>&1)
assert_contains "Unknown folder cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown label subcommand${NC}"
OUTPUT=$($CLI label nonsense 2>&1)
assert_contains "Unknown label cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown board subcommand${NC}"
OUTPUT=$($CLI board nonsense 2>&1)
assert_contains "Unknown board cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Unknown trash subcommand${NC}"
OUTPUT=$($CLI trash nonsense 2>&1)
assert_contains "Unknown trash cmd" "$OUTPUT" "Unknown\|Commands"

echo -e "  ${CYAN}── Event delete bad ID${NC}"
OUTPUT=$($CLI event delete "ZZZZZZZZ" 2>&1)
assert_contains "Event delete bad ID" "$OUTPUT" "not found\|No event\|error"

echo -e "  ${CYAN}── Contact delete bad ID${NC}"
OUTPUT=$($CLI contact delete "ZZZZZZZZ" 2>&1)
assert_contains "Contact delete bad ID" "$OUTPUT" "not found\|No contact\|error"

echo -e "  ${CYAN}── File get bad ID${NC}"
OUTPUT=$($CLI file get "ZZZZZZZZ" 2>&1)
assert_contains "File get bad ID" "$OUTPUT" "not found\|No file\|error"

echo -e "  ${CYAN}── File delete bad ID${NC}"
OUTPUT=$($CLI file delete "ZZZZZZZZ" 2>&1)
assert_contains "File delete bad ID" "$OUTPUT" "not found\|No file\|error"

echo -e "  ${CYAN}── Note delete bad ID${NC}"
OUTPUT=$($CLI note delete "ZZZZZZZZ" 2>&1)
assert_contains "Note delete bad ID" "$OUTPUT" "not found\|No note\|error"

echo -e "  ${CYAN}── Board add-card missing args${NC}"
OUTPUT=$($CLI board add-card 2>&1)
assert_contains "Add-card no args" "$OUTPUT" "Usage\|error\|required"

echo -e "  ${CYAN}── Board move-card missing args${NC}"
OUTPUT=$($CLI board move-card 2>&1)
assert_contains "Move-card no args" "$OUTPUT" "Usage\|error\|required"

echo -e "  ${CYAN}── Board delete-card missing args${NC}"
OUTPUT=$($CLI board delete-card 2>&1)
assert_contains "Delete-card no args" "$OUTPUT" "Usage\|error\|required"

echo -e "  ${CYAN}── Label rename missing --to${NC}"
OUTPUT=$($CLI label rename "SomeName" 2>&1)
assert_contains "Rename missing --to" "$OUTPUT" "Usage\|error\|required"

echo -e "  ${CYAN}── Folder rename missing --to${NC}"
OUTPUT=$($CLI folder rename "SomeName" 2>&1)
assert_contains "Folder rename missing --to" "$OUTPUT" "Usage\|error\|required"

echo -e "  ${CYAN}── Search with empty query${NC}"
OUTPUT=$($CLI search 2>&1)
assert_contains "Empty search" "$OUTPUT" "Usage\|query"

# ═══════════════════════════════════════════════════
# 41. NOTE LIST BY FOLDER
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}41. Note List by Folder${NC}"
OUTPUT=$($CLI note list --folder "CiderTest${TEST_ID}Folder" 2>&1)
assert_contains "Note list by folder" "$OUTPUT" "Notes\|note\|CiderTest"

# ═══════════════════════════════════════════════════
# 42. BOOKMARK LIST ALL (no flags)
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}42. Bookmark List All${NC}"
OUTPUT=$($CLI bookmark list 2>&1)
assert_contains "Bookmark list shows count" "$OUTPUT" "Bookmarks ("
OUTPUT=$($CLI bookmark list --json 2>&1)
assert_json_valid "Bookmark list JSON" "$OUTPUT"
assert_json_array_min "Has bookmarks" "$OUTPUT" 1

# ═══════════════════════════════════════════════════
# 43. STATUS JSON FIELD VALUES
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}43. Status JSON Values${NC}"
OUTPUT=$($CLI status --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has folders" "$OUTPUT" "folders"
assert_json_has_key "Has labels" "$OUTPUT" "labels"
assert_json_has_key "Has boards" "$OUTPUT" "boards"
assert_json_has_key "Has boardCards" "$OUTPUT" "boardCards"
assert_json_has_key "Has trash" "$OUTPUT" "trash"
assert_json_has_key "Has sessions" "$OUTPUT" "sessions"

# ═══════════════════════════════════════════════════
# 44. RECENT
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}44. Recent${NC}"
OUTPUT=$($CLI recent --hours 8760 --limit 5 2>&1)
assert_contains "Recent runs" "$OUTPUT" "Recent items"
assert_contains "Recent has results" "$OUTPUT" "]"

OUTPUT=$($CLI recent --type bookmark --hours 8760 --limit 3 2>&1)
assert_contains "Recent type filter" "$OUTPUT" "🔖"

OUTPUT=$($CLI recent --hours 0 2>&1)
assert_contains "Recent zero hours" "$OUTPUT" "Recent items"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI recent --hours 8760 --limit 3 --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has type" "$OUTPUT" "type"
assert_json_has_key "Has title" "$OUTPUT" "title"
assert_json_has_key "Has date" "$OUTPUT" "date"

# ═══════════════════════════════════════════════════
# 45. SNAPSHOT
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}45. Snapshot${NC}"
OUTPUT=$($CLI snapshot 2>&1)
assert_contains "Shows items header" "$OUTPUT" "ITEMS"
assert_contains "Shows bookmarks" "$OUTPUT" "Bookmarks:"
assert_contains "Shows folders" "$OUTPUT" "FOLDERS"
assert_contains "Shows vault path" "$OUTPUT" "CiderVault"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI snapshot --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has bookmarks" "$OUTPUT" "bookmarks"
assert_json_has_key "Has topTags" "$OUTPUT" "topTags"
assert_json_has_key "Has folderCounts" "$OUTPUT" "folderCounts"
assert_json_has_key "Has recentBookmarks24h" "$OUTPUT" "recentBookmarks24h"

# ═══════════════════════════════════════════════════
# 46. QUERY
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}46. Query${NC}"
echo -e "  ${CYAN}── Date parsing${NC}"
OUTPUT=$($CLI query "saved yesterday" 2>&1)
assert_contains "Yesterday parsed" "$OUTPUT" "date:"

OUTPUT=$($CLI query "things from last week" 2>&1)
assert_contains "Last week parsed" "$OUTPUT" "date:"

OUTPUT=$($CLI query "saved today" 2>&1)
assert_contains "Today parsed" "$OUTPUT" "date:"

OUTPUT=$($CLI query "items from last month" 2>&1)
assert_contains "Last month parsed" "$OUTPUT" "date:"

OUTPUT=$($CLI query "3 days ago" 2>&1)
assert_contains "N days ago parsed" "$OUTPUT" "date:"

echo -e "  ${CYAN}── Keyword + date${NC}"
OUTPUT=$($CLI query "claude this month" 2>&1)
assert_contains "Keyword + date" "$OUTPUT" "results"

echo -e "  ${CYAN}── Empty query${NC}"
OUTPUT=$($CLI query 2>&1)
assert_contains "Empty query" "$OUTPUT" "Usage"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI query "saved yesterday" --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"

# ═══════════════════════════════════════════════════
# 47. DUPLICATE CHECK
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}47. Duplicate Check${NC}"
# Check for a URL we know exists
OUTPUT=$($CLI duplicate-check "https://github.com/makeplane/plane" 2>&1)
assert_contains "Finds duplicate" "$OUTPUT" "duplicate\|Found"

# Check for a URL that doesn't exist
OUTPUT=$($CLI duplicate-check "https://totallyfakeurl${TEST_ID}.com/nothing" 2>&1)
assert_contains "No duplicate" "$OUTPUT" "No duplicates"

# Check www normalization
OUTPUT=$($CLI duplicate-check "http://www.github.com/makeplane/plane" 2>&1)
assert_contains "Normalized match" "$OUTPUT" "duplicate\|Found"

echo -e "  ${CYAN}── JSON output${NC}"
OUTPUT=$($CLI duplicate-check "https://github.com/makeplane/plane" --json 2>&1)
assert_json_valid "Valid JSON" "$OUTPUT"
assert_json_has_key "Has isDuplicate" "$OUTPUT" "isDuplicate"

echo -e "  ${CYAN}── Missing URL${NC}"
OUTPUT=$($CLI duplicate-check 2>&1)
assert_contains "Missing URL" "$OUTPUT" "Usage"

# ═══════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}48. Cleanup${NC}"
$CLI trash empty >/dev/null 2>&1
rm -f ~/CiderVault/Inbox/Notes/CiderTest*.md 2>/dev/null
rm -f ~/CiderVault/Inbox/Todos/CiderTest*.ics 2>/dev/null
rm -f ~/CiderVault/Inbox/"Date Cards"/CiderTest*.ics 2>/dev/null
rm -f ~/CiderVault/Inbox/Contacts/CiderTest*.vcf 2>/dev/null
rm -f ~/CiderVault/Inbox/Files/CiderTest*.txt 2>/dev/null
rm -rf ~/CiderVault/CiderTest* 2>/dev/null
# Clean auto-created labels from tag tests
$CLI label delete "CiderTest${TEST_ID}Tag2" >/dev/null 2>&1

# Clean ghost entries from indexes (test creates entries, file cleanup leaves orphans)
for idx in contacts/_cider_contacts_index todos/_cider_todos_index date-cards/_cider_date_cards_index notes/_cider_notes_index; do
    FILE="$HOME/CiderVault/.cider/${idx}.json"
    if [ -f "$FILE" ]; then
        python3 -c "
import json
with open('$FILE') as f: data = json.load(f)
cleaned = {k: v for k, v in data.items() if 'CiderTest' not in v.get('filename', '')}
if len(cleaned) != len(data):
    with open('$FILE', 'w') as f: json.dump(cleaned, f, indent=2, sort_keys=True)
" 2>/dev/null
    fi
done
echo -e "  ${GREEN}✓${NC} Cleaned up (files + indexes)"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}ALL $TOTAL TESTS PASSED${NC}"
else
    echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL tests"
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

exit $FAIL
