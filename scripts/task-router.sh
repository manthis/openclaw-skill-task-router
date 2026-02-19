#!/bin/bash
# task-router.sh — Fast task routing for OpenClaw orchestration
# Usage: task-router.sh --task "description" [--json] [--check-protection] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${SCRIPT_DIR}/../lib/decision-rules.json"
PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"

TASK="" JSON_OUTPUT=false CHECK_PROTECTION=false DRY_RUN=false USE_NOTIFY=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --task) TASK="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --check-protection) CHECK_PROTECTION=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --use-notify) USE_NOTIFY=true; shift ;;
        --no-notify) USE_NOTIFY=false; shift ;;
        -h|--help) echo "Usage: task-router.sh --task \"description\" [--json] [--check-protection] [--dry-run] [--no-notify]"; exit 0 ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$TASK" ]] && { echo "Error: --task required" >&2; exit 1; }

TASK_LOWER="$(echo "$TASK" | tr '[:upper:]' '[:lower:]')"

# Single jq call: extract all keywords/patterns and compute scores
SCORES=$(jq -r --arg task "$TASK_LOWER" '
def match_word($t; $kw):
  $t | test("(^|[^a-zà-ÿ])" + $kw + "([^a-zà-ÿ]|$)"; "i");

def score_tier($t; $cat; $tier; $weight_key; $default_weight):
  ($cat[$weight_key] // $default_weight) as $w |
  ([$cat[$tier] // [] | .[] | select(match_word($t; .))] | length) * $w;

def score_patterns($t; $cat):
  ([$cat["patterns"] // [] | .[] | . as $p | select($t | contains($p))] | length) * 3;

def score_category($t; $cat):
  score_tier($t; $cat; "keywords_high"; "keyword_weight_high"; 3) +
  score_tier($t; $cat; "keywords_medium"; "keyword_weight_medium"; 2) +
  score_tier($t; $cat; "keywords_low"; "keyword_weight_low"; 5) +
  score_tier($t; $cat; "keywords"; "keyword_weight"; 2) +
  score_patterns($t; $cat);

{
  direct: score_category($task; .execute_direct),
  sonnet: score_category($task; .spawn_sonnet),
  opus: score_category($task; .spawn_opus),
  sonnet_timeout: (.spawn_sonnet.timeout_default // 600),
  opus_timeout: (.spawn_opus.timeout_default // 1800)
}
| "\(.direct) \(.sonnet) \(.opus) \(.sonnet_timeout) \(.opus_timeout)"
' "$RULES_FILE")

read -r DIRECT_SCORE SONNET_SCORE OPUS_SCORE SONNET_TIMEOUT OPUS_TIMEOUT <<< "$SCORES"

# Complexity estimate
WORD_COUNT=$(echo "$TASK" | wc -w | tr -d ' ')
COMPLEXITY="simple"
[[ $WORD_COUNT -gt 7 ]] && COMPLEXITY="medium"
[[ $WORD_COUNT -gt 15 ]] && COMPLEXITY="complex"
echo "$TASK_LOWER" | grep -qE " and (publish|deploy|push|test|then)|and then|after that|multiple|several|every|each|publish|deploy|github|npm" && COMPLEXITY="complex"

# Protection mode
PROTECTION="false"
[[ "${PROTECTION_MODE:-false}" == "true" ]] && PROTECTION="true"
[[ "$PROTECTION" == "false" && -f "$PROTECTION_STATE_FILE" ]] && \
    PROTECTION=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")

# Handle --check-protection
if [[ "$CHECK_PROTECTION" == "true" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"protection_mode_active\":$([[ "$PROTECTION" == "true" ]] && echo true || echo false)}"
    else
        [[ "$PROTECTION" == "true" ]] && echo "🛡️  Protection mode: ACTIVE" || echo "✅ Protection mode: INACTIVE"
    fi
fi

# Label
LABEL=$(echo "$TASK_LOWER" | sed 's/[^a-z0-9 ]//g' | awk '{for(i=1;i<=NF&&i<=4;i++) printf "%s-",$i}' | sed 's/-$//' | head -c 40)

# Decision
SPAWN_TOTAL=$((SONNET_SCORE + OPUS_SCORE))
REC="spawn" MODEL="anthropic/claude-sonnet-4-5" MODEL_NAME="Sonnet" TIMEOUT=$SONNET_TIMEOUT COST="medium" PROT_OVERRIDE=false

if [[ $DIRECT_SCORE -gt 0 && $DIRECT_SCORE -ge $SPAWN_TOTAL && ("$COMPLEXITY" == "simple" || "$COMPLEXITY" == "medium" || $DIRECT_SCORE -ge 10) ]]; then
    REC="execute_direct" MODEL="" MODEL_NAME="" TIMEOUT=10 COST="low"
    REASONING="Direct execution (score: direct=${DIRECT_SCORE} vs spawn=${SPAWN_TOTAL})"
elif [[ $OPUS_SCORE -gt $SONNET_SCORE || "$COMPLEXITY" == "complex" ]]; then
    MODEL="anthropic/claude-opus-4-6" MODEL_NAME="Opus" TIMEOUT=$OPUS_TIMEOUT COST="high"
    REASONING="Opus spawn (score: opus=${OPUS_SCORE}, sonnet=${SONNET_SCORE}, complexity=${COMPLEXITY})"
    if [[ "$PROTECTION" == "true" ]]; then
        MODEL="anthropic/claude-sonnet-4-5" MODEL_NAME="Sonnet" COST="medium" PROT_OVERRIDE=true
        REASONING="${REASONING} ⚠️ Protection→Sonnet"
    fi
else
    REASONING="Sonnet spawn (score: sonnet=${SONNET_SCORE}, opus=${OPUS_SCORE})"
fi

# Command
CMD=""
if [[ "$REC" == "spawn" ]]; then
    if [[ "$USE_NOTIFY" == "true" ]]; then
        CMD="spawn-notify.sh --task '${TASK}' --model '${MODEL}' --label '${LABEL}' --timeout ${TIMEOUT}"
    else
        CMD="sessions_spawn --task '${TASK}' --model '${MODEL}' --label '${LABEL}'"
    fi
fi

# Output
if [[ "$JSON_OUTPUT" == "true" ]]; then
    cat <<EOF
{"recommendation":"${REC}","model":"${MODEL}","model_name":"${MODEL_NAME}","reasoning":"${REASONING}","command":"${CMD}","timeout_seconds":${TIMEOUT},"estimated_cost":"${COST}","protection_mode":$([[ "$PROTECTION" == "true" ]] && echo true || echo false),"protection_mode_override":$([[ "$PROT_OVERRIDE" == "true" ]] && echo true || echo false),"complexity":"${COMPLEXITY}","label":"${LABEL}","dry_run":$([[ "$DRY_RUN" == "true" ]] && echo true || echo false)}
EOF
else
    echo ""
    [[ "$REC" == "execute_direct" ]] && echo "⚡ EXECUTE DIRECTLY" || echo "🔀 SPAWN SUB-AGENT"
    echo "  Task:       $TASK"
    echo "  Complexity: $COMPLEXITY"
    echo "  Model:      ${MODEL_NAME:-N/A} ${MODEL:+($MODEL)}"
    echo "  Timeout:    ${TIMEOUT}s"
    echo "  Cost:       $COST"
    echo "  Label:      $LABEL"
    echo "  Reasoning:  $REASONING"
    [[ -n "$CMD" ]] && echo "  Command:    $CMD"
    [[ "$PROTECTION" == "true" ]] && echo "  🛡️  Protection ACTIVE"
    [[ "$DRY_RUN" == "true" ]] && echo "  🧪 DRY RUN"
    echo ""
fi
