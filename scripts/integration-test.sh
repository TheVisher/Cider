#!/bin/bash
# Cider Integration Test Suite
# Exercises all major code paths via CiderCLI
#
# Usage: ./Scripts/integration-test.sh
# Prerequisites: swift build --product cider-cli

set -euo pipefail

CLI="/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

assert_contains() {
    local description="$1"
    local output="$2"
    local expected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qi "$expected"; then
        echo -e "  ${GREEN}✓${NC} $description"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    Expected to contain: $expected"
        echo -e "    Got: $(echo "$output" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local description="$1"
    local output="$2"
    local unexpected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qi "$unexpected"; then
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    Should NOT contain: $unexpected"
        FAIL=$((FAIL + 1))
    else
        echo -e "  ${GREEN}✓${NC} $description"
        PASS=$((PASS + 1))
    fi
}

assert_count_changed() {
    local description="$1"
    local before="$2"
    local after="$3"
    local direction="$4" # "increased" or "decreased"
    TOTAL=$((TOTAL + 1))
    if [ "$direction" = "increased" ] && [ "$after" -gt "$before" ]; then
        echo -e "  ${GREEN}✓${NC} $description ($before → $after)"
        PASS=$((PASS + 1))
    elif [ "$direction" = "decreased" ] && [ "$after" -lt "$before" ]; then
        echo -e "  ${GREEN}✓${NC} $description ($before → $after)"
        PASS=$((PASS + 1))
    elif [ "$direction" = "equal" ] && [ "$after" -eq "$before" ]; then
        echo -e "  ${GREEN}✓${NC} $description ($before = $after)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $description (expected $direction: $before → $after)"
        FAIL=$((FAIL + 1))
    fi
}

get_count() {
    local type="$1"
    $CLI status 2>/dev/null | grep "$type:" | awk '{print $NF}'
}

echo ""
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}  Cider Integration Test Suite${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""

# ──────────────────────────────────────────────
echo -e "${YELLOW}1. Status Command${NC}"
# ──────────────────────────────────────────────

OUTPUT=$($CLI status 2>&1)
assert_contains "Status shows Bookmarks count" "$OUTPUT" "Bookmarks:"
assert_contains "Status shows Notes count" "$OUTPUT" "Notes:"
assert_contains "Status shows Todos count" "$OUTPUT" "Todos:"
assert_contains "Status shows Vault Files count" "$OUTPUT" "Vault Files:"
assert_contains "Status shows Folders count" "$OUTPUT" "Folders:"
assert_contains "Status shows Labels count" "$OUTPUT" "Labels:"
assert_contains "Status shows Trash count" "$OUTPUT" "Trash:"
assert_contains "Status shows Vault Root" "$OUTPUT" "CiderVault"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}2. Folder Operations${NC}"
# ──────────────────────────────────────────────

FOLDER_COUNT_BEFORE=$(get_count "Folders")

OUTPUT=$($CLI folder create "CLI Test Folder" 2>&1)
assert_contains "Create folder succeeds" "$OUTPUT" "Created folder"

OUTPUT=$($CLI folder list 2>&1)
assert_contains "New folder appears in list" "$OUTPUT" "CLI Test Folder"

FOLDER_COUNT_AFTER=$(get_count "Folders")
assert_count_changed "Folder count increased" "$FOLDER_COUNT_BEFORE" "$FOLDER_COUNT_AFTER" "increased"

# Subfolder
OUTPUT=$($CLI folder create "CLI Subfolder" --parent "CLI Test Folder" 2>&1)
assert_contains "Create subfolder succeeds" "$OUTPUT" "Created folder"

OUTPUT=$($CLI folder list 2>&1)
assert_contains "Subfolder appears in list" "$OUTPUT" "CLI Subfolder"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}3. Bookmark CRUD${NC}"
# ──────────────────────────────────────────────

BM_COUNT_BEFORE=$(get_count "Bookmarks")

# Create
OUTPUT=$($CLI bookmark add "https://example.com/cli-test" --title "CLI Test Bookmark" 2>&1)
assert_contains "Create bookmark succeeds" "$OUTPUT" "Created bookmark"
BM_ID=$(echo "$OUTPUT" | grep -o '([a-fA-F0-9]\{8\})' | tr -d '()')

BM_COUNT_AFTER=$(get_count "Bookmarks")
assert_count_changed "Bookmark count increased" "$BM_COUNT_BEFORE" "$BM_COUNT_AFTER" "increased"

# List
OUTPUT=$($CLI bookmark list 2>&1)
assert_contains "New bookmark appears in list" "$OUTPUT" "CLI Test Bookmark"

# Search
OUTPUT=$($CLI bookmark search "cli-test" 2>&1)
assert_contains "Bookmark found by URL search" "$OUTPUT" "CLI Test Bookmark"

OUTPUT=$($CLI bookmark search "CLI Test" 2>&1)
assert_contains "Bookmark found by title search" "$OUTPUT" "CLI Test Bookmark"

# Delete
OUTPUT=$($CLI bookmark delete "$BM_ID" 2>&1)
assert_contains "Delete bookmark succeeds" "$OUTPUT" "Deleted"
assert_contains "Delete shows trash message" "$OUTPUT" "trash"

BM_COUNT_DELETED=$(get_count "Bookmarks")
assert_count_changed "Bookmark count decreased after delete" "$BM_COUNT_AFTER" "$BM_COUNT_DELETED" "decreased"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}4. Trash Round-Trip${NC}"
# ──────────────────────────────────────────────

# Verify in trash
OUTPUT=$($CLI trash list 2>&1)
assert_contains "Deleted bookmark appears in trash" "$OUTPUT" "CLI Test Bookmark"

# Get trash ID
TRASH_ID=$(echo "$OUTPUT" | grep "CLI Test Bookmark" | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')

# Restore
OUTPUT=$($CLI trash restore "$TRASH_ID" 2>&1)
assert_contains "Restore succeeds" "$OUTPUT" "Restored"

# Verify restored
BM_COUNT_RESTORED=$(get_count "Bookmarks")
assert_count_changed "Bookmark count restored" "$BM_COUNT_DELETED" "$BM_COUNT_RESTORED" "increased"

OUTPUT=$($CLI bookmark list 2>&1)
assert_contains "Restored bookmark back in list" "$OUTPUT" "CLI Test Bookmark"

# Verify no longer in trash
OUTPUT=$($CLI trash list 2>&1)
assert_not_contains "Restored bookmark not in trash" "$OUTPUT" "CLI Test Bookmark"

# Clean up — delete again permanently
OUTPUT=$($CLI bookmark delete "$BM_ID" 2>&1)
TRASH_ID_2=$(echo "$($CLI trash list 2>&1)" | grep "CLI Test Bookmark" | grep -o '\[[a-fA-F0-9]\{8\}\]' | tr -d '[]')
if [ -n "$TRASH_ID_2" ]; then
    $CLI trash restore "$TRASH_ID_2" >/dev/null 2>&1
    $CLI bookmark delete "$BM_ID" >/dev/null 2>&1
fi

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}5. Note Operations${NC}"
# ──────────────────────────────────────────────

NOTE_COUNT_BEFORE=$(get_count "Notes")

OUTPUT=$($CLI note create "CLI Test Note" --content "This is a test note from the CLI" 2>&1)
assert_contains "Create note succeeds" "$OUTPUT" "Created note"

NOTE_COUNT_AFTER=$(get_count "Notes")
assert_count_changed "Note count increased" "$NOTE_COUNT_BEFORE" "$NOTE_COUNT_AFTER" "increased"

OUTPUT=$($CLI note list 2>&1)
assert_contains "New note appears in list" "$OUTPUT" "CLI Test Note"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}6. Todo Operations${NC}"
# ──────────────────────────────────────────────

TODO_COUNT_BEFORE=$(get_count "Todos")

OUTPUT=$($CLI todo create "CLI Test Todo" --due 2026-04-15 --priority medium 2>&1)
assert_contains "Create todo succeeds" "$OUTPUT" "Created todo"

TODO_COUNT_AFTER=$(get_count "Todos")
assert_count_changed "Todo count increased" "$TODO_COUNT_BEFORE" "$TODO_COUNT_AFTER" "increased"

OUTPUT=$($CLI todo list 2>&1)
assert_contains "New todo appears in list" "$OUTPUT" "CLI Test Todo"
assert_contains "Todo has priority" "$OUTPUT" "medium"
assert_contains "Todo has due date" "$OUTPUT" "2026-04"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}7. Vault File Operations${NC}"
# ──────────────────────────────────────────────

OUTPUT=$($CLI file list 2>&1)
assert_contains "File list works" "$OUTPUT" "Vault files"

OUTPUT=$($CLI file list --type image 2>&1)
assert_contains "File type filter works" "$OUTPUT" "Image"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}8. Global Search${NC}"
# ──────────────────────────────────────────────

OUTPUT=$($CLI search "CLI Test" 2>&1)
assert_contains "Search finds test bookmark" "$OUTPUT" "CLI Test"

OUTPUT=$($CLI search "@bookmarks example" 2>&1)
# This may or may not find results depending on state
assert_contains "Scoped search returns results header" "$OUTPUT" "Search results"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}9. Help Output${NC}"
# ──────────────────────────────────────────────

OUTPUT=$($CLI help 2>&1)
assert_contains "Help shows bookmark commands" "$OUTPUT" "bookmark"
assert_contains "Help shows note commands" "$OUTPUT" "note"
assert_contains "Help shows todo commands" "$OUTPUT" "todo"
assert_contains "Help shows search" "$OUTPUT" "search"
assert_contains "Help shows trash" "$OUTPUT" "trash"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}10. Cleanup${NC}"
# ──────────────────────────────────────────────

# Clean up test data
# Note: we leave the test folder and note for now — they can be manually cleaned
echo -e "  ${YELLOW}⚠${NC} Test data left in vault: 'CLI Test Folder', 'CLI Test Note', 'CLI Test Todo'"
echo -e "  ${YELLOW}⚠${NC} Clean up manually if desired"

# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}ALL $TOTAL TESTS PASSED${NC}"
else
    echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL tests"
fi
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""

exit $FAIL
