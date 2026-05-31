#!/usr/bin/env bash
# Cider canonical capture integration smoke test.
#
# This script intentionally uses a temporary vault for every cider-cli command.
# It verifies the supported agent capture path:
#   capture add --kind ... --json -> receipt side effects -> item/review follow-up

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/.build/debug/cider-cli"}
TEST_VAULT=$(mktemp -d "${TMPDIR:-/tmp}/cider-integration-vault.XXXXXX")
TEST_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/cider-integration-work.XXXXXX")
TEST_ID=$(date +%s)

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEST_VAULT" "$TEST_WORKDIR"
}
trap cleanup EXIT

if [ ! -x "$CLI" ]; then
    echo "Building cider-cli..."
    (cd "$REPO_ROOT" && swift build --product cider-cli >/dev/null)
fi

run_cli() {
    "$CLI" --vault "$TEST_VAULT" "$@"
}

record_pass() {
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}✓${NC} $1"
}

record_fail() {
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}✗${NC} $1"
    if [ "${2:-}" != "" ]; then
        echo -e "    $2"
    fi
}

extract_json() {
    python3 -c '
import sys
text = sys.stdin.read()
start = text.find("{")
end = text.rfind("}")
if start < 0 or end < start:
    raise SystemExit("no JSON object found")
print(text[start:end + 1])
'
}

assert_json_valid() {
    local label=$1
    local payload=$2
    if printf '%s' "$payload" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        record_pass "$label"
    else
        record_fail "$label" "invalid JSON: $(printf '%s' "$payload" | head -3)"
    fi
}

assert_capture_receipt() {
    local label=$1
    local payload=$2
    local expected_kind=$3

    if JSON_PAYLOAD="$payload" python3 - "$expected_kind" <<'PY'
import json
import os
import sys

expected_kind = sys.argv[1]
receipt = json.loads(os.environ["JSON_PAYLOAD"])

assert receipt.get("command") == "capture.add"
item = receipt.get("item") or {}
assert item.get("id"), "missing item.id"
assert item.get("type"), "missing item.type"
assert receipt.get("captureEventID"), "missing captureEventID"
assert (receipt.get("provenance") or {}).get("status") == "recorded"
assert (receipt.get("indexing") or {}).get("status") in {"indexed", "unavailable"}
assert (receipt.get("routing") or {}).get("status") == "recorded"
assert (receipt.get("duplicate") or {}).get("status"), "missing duplicate.status"
assert receipt.get("nextSafeAction"), "missing nextSafeAction"
assert isinstance(receipt.get("safeNextCommands"), list)
assert receipt["safeNextCommands"], "missing safeNextCommands"

expected_item_types = {
    "bookmark": {"bookmark"},
    "note": {"note"},
    "todo": {"todo"},
    "file": {"vaultFile", "file"},
    "event": {"event", "dateCard"},
    "contact": {"contact"},
}
assert item["type"] in expected_item_types[expected_kind], (expected_kind, item["type"])
PY
    then
        record_pass "$label receipt has capture side effects"
    else
        record_fail "$label receipt has capture side effects" "$(printf '%s' "$payload" | head -20)"
    fi
}

json_value() {
    local payload=$1
    local key_path=$2
    JSON_PAYLOAD="$payload" python3 - "$key_path" <<'PY'
import json
import os
import sys

data = json.loads(os.environ["JSON_PAYLOAD"])
value = data
for key in sys.argv[1].split("."):
    value = value[key]
print(value)
PY
}

capture_json() {
    local output
    output=$("$@" 2>&1)
    printf '%s' "$output" | extract_json
}

capture_stdin_json() {
    local text=$1
    shift
    local output
    output=$(printf '%s' "$text" | "$@" 2>&1)
    printf '%s' "$output" | extract_json
}

verify_item_get() {
    local label=$1
    local item_type=$2
    local item_id=$3
    local payload

    # Explicit bookmark path kept visible for the script contract:
    # run_cli item get bookmark "$item_id" --json
    payload=$(capture_json run_cli item get "$item_type" "$item_id" --json)
    assert_json_valid "$label item get $item_type" "$payload"
}

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Cider Canonical Capture Integration Test${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "  ${CYAN}Vault:${NC} $TEST_VAULT"
echo ""

echo -e "${YELLOW}1. Capture receipts${NC}"

BOOKMARK_JSON=$(capture_json run_cli capture add --kind bookmark --url "https://example.com/cider-integration-${TEST_ID}" --title "Cider Integration Bookmark ${TEST_ID}" --no-wait --json)
assert_capture_receipt "bookmark" "$BOOKMARK_JSON" bookmark
BOOKMARK_ID=$(json_value "$BOOKMARK_JSON" item.id)
verify_item_get "bookmark" bookmark "$BOOKMARK_ID"

NOTE_JSON=$(capture_stdin_json "Cider integration note body ${TEST_ID}" run_cli capture add --kind note --title "Cider Integration Note ${TEST_ID}" --stdin --json)
assert_capture_receipt "note" "$NOTE_JSON" note
NOTE_ID=$(json_value "$NOTE_JSON" item.id)
verify_item_get "note" note "$NOTE_ID"

TODO_JSON=$(capture_stdin_json "Review Cider integration todo ${TEST_ID}" run_cli capture add --kind todo --stdin --json)
assert_capture_receipt "todo" "$TODO_JSON" todo
TODO_ID=$(json_value "$TODO_JSON" item.id)
verify_item_get "todo" todo "$TODO_ID"

TEST_FILE="$TEST_WORKDIR/cider-integration-file-${TEST_ID}.txt"
printf 'Cider integration file body %s\n' "$TEST_ID" > "$TEST_FILE"
FILE_JSON=$(capture_json run_cli capture add --kind file --path "$TEST_FILE" --json)
assert_capture_receipt "file" "$FILE_JSON" file
FILE_ID=$(json_value "$FILE_JSON" item.id)
FILE_ITEM_TYPE=$(json_value "$FILE_JSON" item.type)
verify_item_get "file" "$FILE_ITEM_TYPE" "$FILE_ID"

EVENT_JSON=$(capture_stdin_json "Event notes ${TEST_ID}" run_cli capture add --kind event --title "Cider Integration Event ${TEST_ID}" --date 2026-06-15 --time "9:30 AM" --location "Test Room" --stdin --json)
assert_capture_receipt "event" "$EVENT_JSON" event
EVENT_ID=$(json_value "$EVENT_JSON" item.id)
verify_item_get "event" event "$EVENT_ID"

CONTACT_JSON=$(capture_stdin_json "Contact notes ${TEST_ID}" run_cli capture add --kind contact --name "Cider Integration Contact ${TEST_ID}" --email "integration${TEST_ID}@example.com" --phone "555-0101" --stdin --json)
assert_capture_receipt "contact" "$CONTACT_JSON" contact
CONTACT_ID=$(json_value "$CONTACT_JSON" item.id)
verify_item_get "contact" contact "$CONTACT_ID"

echo ""
echo -e "${YELLOW}2. Duplicate and review follow-up${NC}"

DUPLICATE_JSON=$(capture_json run_cli capture add --kind bookmark --url "https://example.com/cider-integration-${TEST_ID}" --title "Duplicate Cider Integration Bookmark ${TEST_ID}" --no-wait --json)
assert_capture_receipt "duplicate bookmark" "$DUPLICATE_JSON" bookmark
DUPLICATE_STATUS=$(json_value "$DUPLICATE_JSON" duplicate.status)
if [ "$DUPLICATE_STATUS" = "duplicate" ] || [ "$DUPLICATE_STATUS" = "existing" ]; then
    record_pass "duplicate bookmark reports existing state"
else
    record_fail "duplicate bookmark reports existing state" "duplicate.status was $DUPLICATE_STATUS"
fi

REVIEW_JSON=$(capture_json run_cli review list --json)
assert_json_valid "review list --json" "$REVIEW_JSON"

echo ""
echo -e "${YELLOW}3. Isolated vault safety${NC}"
if [ -d "$TEST_VAULT/.cider" ]; then
    record_pass "temporary vault received Cider state"
else
    record_fail "temporary vault received Cider state" "$TEST_VAULT/.cider missing"
fi

if find "$TEST_VAULT" -maxdepth 4 -type f | grep -q .; then
    record_pass "temporary vault contains captured files"
else
    record_fail "temporary vault contains captured files" "no captured files found"
fi

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}ALL $TOTAL TESTS PASSED${NC}"
else
    echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL tests"
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

exit "$FAIL"
