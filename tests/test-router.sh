#!/bin/bash
# test-router.sh — Unit tests for task-router.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${SCRIPT_DIR}/../scripts/task-router.sh"

PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✅ PASS${NC}: ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: ${test_name}"
        echo "  Expected: ${expected}"
        echo "  Actual:   ${actual}"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if echo "$actual" | grep -q "$expected"; then
        echo -e "${GREEN}✅ PASS${NC}: ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: ${test_name}"
        echo "  Expected to contain: ${expected}"
        echo "  Actual: ${actual}"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Task Router Tests ==="
echo ""

# Test 1: Simple read → execute_direct
result=$("$ROUTER" --task "Read HEARTBEAT.md" --json)
rec=$(echo "$result" | jq -r '.recommendation')
assert_eq "Simple read → execute_direct" "execute_direct" "$rec"

# Test 2: Create skills → spawn + Opus
result=$("$ROUTER" --task "Create 6 skills and publish on GitHub" --json)
model=$(echo "$result" | jq -r '.model')
assert_eq "Create skills → Opus" "anthropic/claude-opus-4-6" "$model"

# Test 3: Protection mode → Force Sonnet
result=$(PROTECTION_MODE=true "$ROUTER" --task "Build and deploy the application" --json)
model=$(echo "$result" | jq -r '.model')
assert_eq "Protection mode → Force Sonnet" "anthropic/claude-sonnet-4-5" "$model"

# Test 4: Protection mode override flag
result=$(PROTECTION_MODE=true "$ROUTER" --task "Debug complex authentication bug" --json)
override=$(echo "$result" | jq -r '.protection_mode_override')
assert_eq "Protection mode sets override flag" "true" "$override"

# Test 5: Write task → spawn + Sonnet
result=$("$ROUTER" --task "Write documentation for the API" --json)
model=$(echo "$result" | jq -r '.model')
assert_eq "Write docs → Sonnet" "anthropic/claude-sonnet-4-5" "$model"

# Test 6: Check status → execute_direct
result=$("$ROUTER" --task "Check git status" --json)
rec=$(echo "$result" | jq -r '.recommendation')
assert_eq "Check status → execute_direct" "execute_direct" "$rec"

# Test 7: Complex multi-step → spawn
result=$("$ROUTER" --task "Refactor the authentication module and then deploy it" --json)
rec=$(echo "$result" | jq -r '.recommendation')
assert_eq "Complex multi-step → spawn" "spawn" "$rec"

# Test 8: Label generation
result=$("$ROUTER" --task "Create a new skill" --json)
label=$(echo "$result" | jq -r '.label')
assert_contains "Label is non-empty" "create" "$label"

# Test 9: Timeout is numeric
result=$("$ROUTER" --task "Build the frontend" --json)
timeout=$(echo "$result" | jq -r '.timeout_seconds')
assert_eq "Timeout is numeric" "true" "$([[ "$timeout" =~ ^[0-9]+$ ]] && echo true || echo false)"

# Test 10: JSON output is valid
result=$("$ROUTER" --task "List files" --json)
valid=$(echo "$result" | jq -r 'type' 2>/dev/null || echo "invalid")
assert_eq "JSON output is valid" "object" "$valid"

# Test 11: Dry run flag
result=$("$ROUTER" --task "Deploy to production" --json --dry-run)
dry_run=$(echo "$result" | jq -r '.dry_run')
assert_eq "Dry run flag set" "true" "$dry_run"

# Test 12: Cost estimation present
result=$("$ROUTER" --task "Audit security vulnerabilities" --json)
cost=$(echo "$result" | jq -r '.estimated_cost')
assert_contains "Cost is set" "$cost" "low medium high"

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
echo "All tests passed! ✅"
