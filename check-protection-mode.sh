#!/bin/bash
# check-protection-mode.sh — Check if Claude usage protection mode is active
# Reads memory/claude-usage-state.json and returns true/false
#
# Usage: check-protection-mode.sh
# Output: "true" or "false"
#
set -euo pipefail

PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"

# Environment override
if [[ "${PROTECTION_MODE:-}" == "true" ]]; then
    echo "true"
    exit 0
fi

# Read from state file
if [[ -f "$PROTECTION_STATE_FILE" ]]; then
    RESULT=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")
    echo "$RESULT"
else
    echo "false"
fi
