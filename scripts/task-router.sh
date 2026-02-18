#!/bin/bash
# task-router.sh — Intelligent task routing for OpenClaw orchestration
# Usage: task-router.sh --task "description" [--json] [--check-protection] [--dry-run]
#
# Analyzes a task description and recommends whether to execute directly
# or spawn a sub-agent, which model to use, and generates the command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
RULES_FILE="${LIB_DIR}/decision-rules.json"
MODEL_FILE="${LIB_DIR}/model-config.json"

# Defaults
TASK=""
JSON_OUTPUT=false
CHECK_PROTECTION=false
DRY_RUN=false
USE_NOTIFY=true
PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: task-router.sh --task "description" [OPTIONS]

Options:
  --task <description>    Task to analyze (required)
  --json                  Output as JSON
  --check-protection      Check if protection mode is active
  --dry-run               Simulation mode (don't execute anything)
  --use-notify            Use spawn-notify.sh instead of sessions_spawn (default: true)
  --no-notify             Use raw sessions_spawn (disable spawn-notify)
  -h, --help              Show this help

Environment:
  PROTECTION_MODE=true    Force protection mode
  OPENCLAW_WORKSPACE      Path to OpenClaw workspace

Examples:
  task-router.sh --task "Read HEARTBEAT.md"
  task-router.sh --task "Create a new skill and publish on GitHub" --json
  task-router.sh --task "Debug login endpoint" --check-protection
  PROTECTION_MODE=true task-router.sh --task "Complex audit" --json
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --task) TASK="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --check-protection) CHECK_PROTECTION=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --use-notify) USE_NOTIFY=true; shift ;;
        --no-notify) USE_NOTIFY=false; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$TASK" ]]; then
    echo "Error: --task is required" >&2
    usage
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Lowercase task for matching
TASK_LOWER="$(echo "$TASK" | tr '[:upper:]' '[:lower:]')"

# Check protection mode
is_protection_mode() {
    # Environment override
    if [[ "${PROTECTION_MODE:-false}" == "true" ]]; then
        echo "true"
        return
    fi
    
    # Check state file
    if [[ -f "$PROTECTION_STATE_FILE" ]]; then
        local mode
        mode=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")
        echo "$mode"
        return
    fi
    
    echo "false"
}

# Count weighted keyword matches for a category
count_matches() {
    local category="$1"
    local count=0
    
    # Check keywords with weights (support multiple tiers)
    for tier in "keywords_high" "keywords_medium" "keywords_low" "keywords"; do
        local weight_key="${tier/keywords/keyword_weight}"
        # Map tier to weight key
        case "$tier" in
            keywords_high) weight_key="keyword_weight_high" ;;
            keywords_medium) weight_key="keyword_weight_medium" ;;
            keywords_low) weight_key="keyword_weight_low" ;;
            keywords) weight_key="keyword_weight" ;;
        esac
        
        local weight
        weight=$(jq -r ".${category}.${weight_key} // 1" "$RULES_FILE" 2>/dev/null)
        
        local keywords
        keywords=$(jq -r ".${category}.${tier}[]?" "$RULES_FILE" 2>/dev/null)
        [[ -z "$keywords" ]] && continue
        
        while IFS= read -r keyword; do
            [[ -z "$keyword" ]] && continue
            # Match as whole word using word boundaries
            if echo "$TASK_LOWER" | grep -qwi "$keyword"; then
                ((count += weight))
            fi
        done <<< "$keywords"
    done
    
    # Check patterns
    local patterns
    patterns=$(jq -r ".${category}.patterns[]?" "$RULES_FILE" 2>/dev/null)
    while IFS= read -r pattern; do
        if [[ -n "$pattern" && "$TASK_LOWER" == *"$pattern"* ]]; then
            ((count += 3))  # Patterns weigh more
        fi
    done <<< "$patterns"
    
    echo "$count"
}

# Estimate task complexity (word count + keyword density)
estimate_complexity() {
    local word_count
    word_count=$(echo "$TASK" | wc -w | tr -d ' ')
    
    local complexity="simple"
    if [[ $word_count -gt 15 ]]; then
        complexity="complex"
    elif [[ $word_count -gt 7 ]]; then
        complexity="medium"
    fi
    
    # Check for complexity indicators (only strong signals)
    if echo "$TASK_LOWER" | grep -qE "(and then|after that|multiple|several|every|each|publish|deploy|github|npm)"; then
        complexity="complex"
    fi
    
    # Multi-action tasks (contains "and")
    if echo "$TASK_LOWER" | grep -qE " and (publish|deploy|push|test|then)"; then
        complexity="complex"
    fi
    
    echo "$complexity"
}

# Generate a label from task description
generate_label() {
    echo "$TASK_LOWER" | \
        sed 's/[^a-z0-9 ]//g' | \
        awk '{for(i=1;i<=NF && i<=4;i++) printf "%s-", $i; print ""}' | \
        sed 's/-$//' | \
        head -c 40
}

# Main routing logic
route_task() {
    local direct_score opus_score sonnet_score
    direct_score=$(count_matches "execute_direct")
    sonnet_score=$(count_matches "spawn_sonnet")
    opus_score=$(count_matches "spawn_opus")
    
    local complexity
    complexity=$(estimate_complexity)
    
    local protection
    protection=$(is_protection_mode)
    
    local recommendation="spawn"
    local model="anthropic/claude-sonnet-4-5"
    local model_name="Sonnet"
    local reasoning=""
    local timeout=600
    local cost="medium"
    local protection_override=false
    
    # If both direct and spawn keywords are present, spawn wins (mixed intent = action needed)
    local spawn_total=$((sonnet_score + opus_score))
    
    # Decision logic
    # Direct execution wins if it has highest score, no significant spawn keywords, AND (simple complexity OR dominant score)
    if [[ $direct_score -gt $sonnet_score && $direct_score -gt $opus_score && $spawn_total -lt 5 && ( "$complexity" == "simple" || $direct_score -ge 10 ) ]]; then
        recommendation="execute_direct"
        model=""
        model_name=""
        reasoning="Task matches direct execution patterns (simple, quick). Keywords matched: ${direct_score}."
        timeout=10
        cost="low"
    elif [[ $opus_score -gt $sonnet_score || "$complexity" == "complex" ]]; then
        recommendation="spawn"
        model="anthropic/claude-opus-4-6"
        model_name="Opus"
        reasoning="Task matches complex patterns requiring Opus (code/debug/build). Keywords matched: opus=${opus_score}, sonnet=${sonnet_score}."
        timeout=$(jq -r '.spawn_opus.timeout_default' "$RULES_FILE")
        cost="high"
        
        # Protection mode override
        if [[ "$protection" == "true" ]]; then
            model="anthropic/claude-sonnet-4-5"
            model_name="Sonnet"
            reasoning="${reasoning} ⚠️ Protection mode active: forced to Sonnet."
            cost="medium"
            protection_override=true
        fi
    else
        recommendation="spawn"
        model="anthropic/claude-sonnet-4-5"
        model_name="Sonnet"
        reasoning="Task matches standard patterns suitable for Sonnet. Keywords matched: sonnet=${sonnet_score}."
        timeout=$(jq -r '.spawn_sonnet.timeout_default' "$RULES_FILE")
        cost="medium"
    fi
    
    local label
    label=$(generate_label)
    
    local command=""
    if [[ "$recommendation" == "spawn" ]]; then
        if [[ "$USE_NOTIFY" == "true" ]]; then
            command="spawn-notify.sh --task '${TASK}' --model '${model}' --label '${label}' --timeout ${timeout}"
        else
            command="sessions_spawn --task '${TASK}' --model '${model}' --label '${label}'"
        fi
    fi
    
    # Output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n \
            --arg rec "$recommendation" \
            --arg model "$model" \
            --arg model_name "$model_name" \
            --arg reasoning "$reasoning" \
            --arg command "$command" \
            --argjson timeout "$timeout" \
            --arg cost "$cost" \
            --argjson protection "$([[ "$protection" == "true" ]] && echo true || echo false)" \
            --argjson protection_override "$([[ "$protection_override" == "true" ]] && echo true || echo false)" \
            --arg complexity "$complexity" \
            --arg label "$label" \
            --argjson dry_run "$([[ "$DRY_RUN" == "true" ]] && echo true || echo false)" \
            '{
                recommendation: $rec,
                model: $model,
                model_name: $model_name,
                reasoning: $reasoning,
                command: $command,
                timeout_seconds: $timeout,
                estimated_cost: $cost,
                protection_mode: $protection,
                protection_mode_override: $protection_override,
                complexity: $complexity,
                label: $label,
                dry_run: $dry_run
            }'
    else
        echo ""
        if [[ "$recommendation" == "execute_direct" ]]; then
            echo -e "${GREEN}⚡ EXECUTE DIRECTLY${NC}"
        else
            echo -e "${BLUE}🔀 SPAWN SUB-AGENT${NC}"
        fi
        echo ""
        echo -e "  Task:        ${TASK}"
        echo -e "  Complexity:  ${complexity}"
        echo -e "  Model:       ${model_name:-N/A} ${model:+($model)}"
        echo -e "  Timeout:     ${timeout}s"
        echo -e "  Est. Cost:   ${cost}"
        echo -e "  Label:       ${label}"
        echo ""
        echo -e "  ${YELLOW}Reasoning:${NC} ${reasoning}"
        
        if [[ -n "$command" ]]; then
            echo ""
            echo -e "  ${BLUE}Command:${NC}"
            echo -e "  ${command}"
        fi
        
        if [[ "$protection" == "true" ]]; then
            echo ""
            echo -e "  ${RED}🛡️  Protection mode is ACTIVE${NC}"
            if [[ "$protection_override" == "true" ]]; then
                echo -e "  ${YELLOW}   → Opus downgraded to Sonnet${NC}"
            fi
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo ""
            echo -e "  ${YELLOW}🧪 DRY RUN — no action taken${NC}"
        fi
        echo ""
    fi
}

# Handle --check-protection flag
if [[ "$CHECK_PROTECTION" == "true" ]]; then
    protection=$(is_protection_mode)
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --argjson active "$([[ "$protection" == "true" ]] && echo true || echo false)" \
            '{protection_mode_active: $active}'
    else
        if [[ "$protection" == "true" ]]; then
            echo -e "${RED}🛡️  Protection mode: ACTIVE${NC}"
        else
            echo -e "${GREEN}✅ Protection mode: INACTIVE${NC}"
        fi
    fi
fi

route_task
