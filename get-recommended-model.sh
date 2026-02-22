#!/bin/bash
# get-recommended-model.sh — Routing: duration × type × model availability → recommendation
# The calling agent estimates duration and type; this script applies the matrix.
#
# Usage: get-recommended-model.sh --duration [seconds] [--type code|normal] [--json]
# Output: "direct" | "sonnet" | "codex" | "opus" | "qwen-coder"
#
# Decision Matrix:
#   Duration < 30s              → direct
#   Duration ≥ 30s + normal     → sonnet
#   Duration ≥ 30s + code       → model availability logic:
#     Codex + Opus available     → codex  (+ ask_user=true: confirm or switch to Opus)
#     Only Codex available       → codex
#     Only Opus available        → opus
#     Neither available          → qwen-coder
#
# Model availability: ~/.openclaw/state/model-limits.json
#   { "codex": {"cooldown_until": <epoch>}, "opus": {"cooldown_until": <epoch>} }
#   Cooldown = 10 min after a 429 error.
#
set -euo pipefail

DURATION=0
TYPE="normal"   # "code" or "normal"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --duration)   DURATION="$2"; shift 2 ;;
        --type)       TYPE="$2"; shift 2 ;;
        --json)       JSON_OUTPUT=true; shift ;;
        -h|--help)
            echo "Usage: get-recommended-model.sh --duration [seconds] [--type code|normal] [--json]"
            echo "Output: direct | sonnet | codex | opus | qwen-coder"
            echo ""
            echo "  --duration  Estimated duration in seconds"
            echo "  --type      Task type: 'code' (code/debug/arch) or 'normal' (default)"
            echo "  --json      Output as JSON with extra fields"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ $DURATION -lt 0 ]]; then
    echo "Error: --duration must be >= 0" >&2
    exit 1
fi

# ============================================================
# Model availability check
# ============================================================
MODEL_LIMITS_FILE="$HOME/.openclaw/state/model-limits.json"
mkdir -p "$HOME/.openclaw/state"

model_available() {
    local model="$1"
    local now
    now=$(date +%s)

    if [[ ! -f "$MODEL_LIMITS_FILE" ]]; then
        echo "true"; return
    fi

    local cooldown_until
    cooldown_until=$(python3 -c "
import json, sys
try:
    data = json.load(open('$MODEL_LIMITS_FILE'))
    val = data.get('$model', {}).get('cooldown_until', 0)
    print(int(val))
except:
    print(0)
" 2>/dev/null || echo "0")

    [[ $now -lt $cooldown_until ]] && echo "false" || echo "true"
}

CODEX_AVAILABLE=$(model_available "codex")
OPUS_AVAILABLE=$(model_available "opus")

# ============================================================
# Protection mode check
# ============================================================
PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"
PROTECTION="false"
[[ "${PROTECTION_MODE:-}" == "true" ]] && PROTECTION="true"
if [[ "$PROTECTION" == "false" && -f "$PROTECTION_STATE_FILE" ]]; then
    PROTECTION=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")
fi

# ============================================================
# Decision matrix
# ============================================================
RECOMMENDATION=""
ASK_USER=false
MODEL_SELECTION=""

if [[ $DURATION -le 30 ]]; then
    RECOMMENDATION="direct"
    MODEL_SELECTION="fast"

elif [[ "$TYPE" != "code" ]]; then
    # Normal task ≥ 30s → Sonnet
    RECOMMENDATION="sonnet"
    MODEL_SELECTION="normal"

else
    # Code task ≥ 30s → availability logic
    if [[ "$CODEX_AVAILABLE" == "true" && "$OPUS_AVAILABLE" == "true" ]]; then
        RECOMMENDATION="codex"
        ASK_USER=true
        MODEL_SELECTION="both_available"
    elif [[ "$CODEX_AVAILABLE" == "true" ]]; then
        RECOMMENDATION="codex"
        MODEL_SELECTION="codex_only"
    elif [[ "$OPUS_AVAILABLE" == "true" ]]; then
        RECOMMENDATION="opus"
        MODEL_SELECTION="opus_only"
    else
        RECOMMENDATION="qwen-coder"
        MODEL_SELECTION="fallback_qwen"
    fi
fi

# Protection mode override: opus → sonnet
if [[ "$PROTECTION" == "true" && "$RECOMMENDATION" == "opus" ]]; then
    RECOMMENDATION="sonnet"
    MODEL_SELECTION="${MODEL_SELECTION}_prot_override"
fi

# Full model IDs
case "$RECOMMENDATION" in
    direct)      MODEL_ID="" ;;
    sonnet)      MODEL_ID="anthropic/claude-sonnet-4-6" ;;
    codex)       MODEL_ID="openai-codex/gpt-5.3-codex" ;;
    opus)        MODEL_ID="anthropic/claude-opus-4-6" ;;
    qwen-coder)  MODEL_ID="qwen-portal/coder-model" ;;
esac

# ============================================================
# Output
# ============================================================
if [[ "$JSON_OUTPUT" == "true" ]]; then
    cat <<EOF
{
  "recommendation": "$RECOMMENDATION",
  "model_id": "$MODEL_ID",
  "ask_user": $ASK_USER,
  "model_selection": "$MODEL_SELECTION",
  "codex_available": $CODEX_AVAILABLE,
  "opus_available": $OPUS_AVAILABLE,
  "protection_mode": $([[ "$PROTECTION" == "true" ]] && echo true || echo false),
  "duration": $DURATION,
  "type": "$TYPE"
}
EOF
else
    echo "$RECOMMENDATION"
fi
