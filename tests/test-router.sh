#!/bin/bash
# test-router.sh — Tests for get-recommended-model.sh and check-protection-mode.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="$SCRIPT_DIR/../get-recommended-model.sh"
CHECK_PROT="$SCRIPT_DIR/../check-protection-mode.sh"

PASS=0 FAIL=0

assert_eq() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✅ $test_name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $test_name — expected '$expected', got '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

# ============================================================
echo "=== get-recommended-model.sh ==="
echo ""

# --- Direct responses (≤ 30s always direct) ---
echo "— Short duration (≤ 30s) → always direct"
assert_eq "simple/10s"  "direct" "$($ROUTER --complexity 1 --duration 10)"
assert_eq "normal/20s"  "direct" "$($ROUTER --complexity 2 --duration 20)"
assert_eq "complex/30s" "direct" "$($ROUTER --complexity 3 --duration 30)"
assert_eq "simple/0s"   "direct" "$($ROUTER --complexity 1 --duration 0)"
echo ""

# --- Medium duration (31-120s) ---
echo "— Medium duration (31-120s)"
assert_eq "simple/60s → direct"  "direct" "$($ROUTER --complexity 1 --duration 60)"
assert_eq "simple/120s → direct" "direct" "$($ROUTER --complexity 1 --duration 120)"
assert_eq "normal/60s → sonnet"  "sonnet" "$($ROUTER --complexity 2 --duration 60)"
assert_eq "normal/120s → sonnet" "sonnet" "$($ROUTER --complexity 2 --duration 120)"
assert_eq "complex/60s → opus"   "opus"   "$($ROUTER --complexity 3 --duration 60)"
assert_eq "complex/120s → opus"  "opus"   "$($ROUTER --complexity 3 --duration 120)"
echo ""

# --- Long duration (> 120s) ---
echo "— Long duration (> 120s)"
assert_eq "simple/150s → sonnet"  "sonnet" "$($ROUTER --complexity 1 --duration 150)"
assert_eq "normal/200s → sonnet"  "sonnet" "$($ROUTER --complexity 2 --duration 200)"
assert_eq "complex/200s → opus"   "opus"   "$($ROUTER --complexity 3 --duration 200)"
assert_eq "complex/500s → opus"   "opus"   "$($ROUTER --complexity 3 --duration 500)"
echo ""

# --- Boundary cases ---
echo "— Boundary cases"
assert_eq "normal/31s → sonnet"   "sonnet" "$($ROUTER --complexity 2 --duration 31)"
assert_eq "complex/31s → opus"    "opus"   "$($ROUTER --complexity 3 --duration 31)"
assert_eq "simple/121s → sonnet"  "sonnet" "$($ROUTER --complexity 1 --duration 121)"
echo ""

# --- Protection mode (env var override) ---
echo "— Protection mode (env override)"
assert_eq "complex/60s + protection → sonnet"  "sonnet" "$(PROTECTION_MODE=true $ROUTER --complexity 3 --duration 60)"
assert_eq "complex/200s + protection → sonnet" "sonnet" "$(PROTECTION_MODE=true $ROUTER --complexity 3 --duration 200)"
assert_eq "normal/60s + protection → sonnet"   "sonnet" "$(PROTECTION_MODE=true $ROUTER --complexity 2 --duration 60)"
assert_eq "simple/60s + protection → direct"   "direct" "$(PROTECTION_MODE=true $ROUTER --complexity 1 --duration 60)"
assert_eq "simple/10s + protection → direct"   "direct" "$(PROTECTION_MODE=true $ROUTER --complexity 1 --duration 10)"
echo ""

# --- Error cases ---
echo "— Error handling"
if $ROUTER --complexity 0 --duration 10 2>/dev/null; then
    echo "  ❌ complexity 0 should fail"
    FAIL=$((FAIL + 1))
else
    echo "  ✅ complexity 0 rejected"
    PASS=$((PASS + 1))
fi

if $ROUTER --complexity 4 --duration 10 2>/dev/null; then
    echo "  ❌ complexity 4 should fail"
    FAIL=$((FAIL + 1))
else
    echo "  ✅ complexity 4 rejected"
    PASS=$((PASS + 1))
fi
echo ""

# ============================================================
echo "=== check-protection-mode.sh ==="
echo ""

# With env var
assert_eq "PROTECTION_MODE=true" "true" "$(PROTECTION_MODE=true $CHECK_PROT)"

# Without env var (reads from state file — depends on current state)
CURRENT=$($CHECK_PROT)
if [[ "$CURRENT" == "true" || "$CURRENT" == "false" ]]; then
    echo "  ✅ Returns valid boolean: $CURRENT"
    PASS=$((PASS + 1))
else
    echo "  ❌ Unexpected output: $CURRENT"
    FAIL=$((FAIL + 1))
fi
echo ""

# ============================================================
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
