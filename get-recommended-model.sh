#!/bin/bash
# get-recommended-model.sh — Pure routing: complexity × duration → model recommendation
# The calling agent estimates complexity and duration; this script just applies the matrix.
#
# Usage: get-recommended-model.sh --complexity [1-3] --duration [seconds]
# Output: "direct" | "sonnet" | "opus"
#
# Decision Matrix:
#              | Simple (1)    | Normal (2)     | Complex (3)
# -------------|---------------|----------------|------------------
# ≤ 30s        | direct        | direct         | direct
# 31-120s      | direct        | sonnet         | opus
# > 120s       | sonnet        | sonnet         | opus
#
set -euo pipefail

COMPLEXITY=0
DURATION=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --complexity) COMPLEXITY="$2"; shift 2 ;;
        --duration)   DURATION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: get-recommended-model.sh --complexity [1-3] --duration [seconds]"
            echo "Output: direct | sonnet | opus"
            echo ""
            echo "  --complexity  1=simple, 2=normal, 3=complex"
            echo "  --duration    Estimated duration in seconds"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate inputs
if [[ $COMPLEXITY -lt 1 || $COMPLEXITY -gt 3 ]]; then
    echo "Error: --complexity must be 1, 2, or 3" >&2
    exit 1
fi

if [[ $DURATION -lt 0 ]]; then
    echo "Error: --duration must be >= 0" >&2
    exit 1
fi

# Check protection mode
PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"
PROTECTION="false"
[[ "${PROTECTION_MODE:-}" == "true" ]] && PROTECTION="true"
if [[ "$PROTECTION" == "false" && -f "$PROTECTION_STATE_FILE" ]]; then
    PROTECTION=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")
fi

# Apply decision matrix
if [[ $DURATION -le 30 ]]; then
    echo "direct"
elif [[ $DURATION -le 120 ]]; then
    if [[ $COMPLEXITY -le 1 ]]; then
        echo "direct"
    elif [[ $COMPLEXITY -eq 2 ]]; then
        echo "sonnet"
    else
        # Complexity 3: opus, but respect protection mode
        if [[ "$PROTECTION" == "true" ]]; then
            echo "sonnet"
        else
            echo "opus"
        fi
    fi
else
    # > 120s
    if [[ $COMPLEXITY -ge 3 ]]; then
        if [[ "$PROTECTION" == "true" ]]; then
            echo "sonnet"
        else
            echo "opus"
        fi
    else
        echo "sonnet"
    fi
fi
