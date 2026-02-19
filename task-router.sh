#!/bin/bash
# task-router.sh — Two-axis task routing: Time × Complexity → Decision
# Estimates execution time AND cognitive complexity independently, then decides.
# Usage: task-router.sh --task "description" [--json] [--check-protection] [--dry-run] [--no-notify]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTECTION_STATE_FILE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/claude-usage-state.json"

TASK="" JSON_OUTPUT=false CHECK_PROTECTION=false DRY_RUN=false USE_NOTIFY=false

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
WORD_COUNT=$(echo "$TASK" | wc -w | tr -d ' ')

# ============================================================
# STEP 1: CATEGORIZE THE TASK
# Identify the primary nature of the task (what kind of work?)
# A task can match multiple categories; we take the dominant one.
# ============================================================

# Pre-compute question detection for tie-breaking
IS_QUESTION_EARLY=false
if echo "$TASK_LOWER" | grep -qE '\?$'; then IS_QUESTION_EARLY=true; fi
if echo "$TASK_LOWER" | grep -qE '^\s*(c.est quoi|qu.est-ce que|what is|what.s|why does|pourquoi|how |comment |explique|explain|describe|décris)'; then IS_QUESTION_EARLY=true; fi

# Category scores (0 = no match, higher = stronger signal)
CAT_CONVERSATION=0   # greetings, chat, opinions, simple Q&A
CAT_LOOKUP=0         # check status, read info, weather, time, calendar
CAT_SEARCH=0         # web research, find articles, investigate topics
CAT_CONTENT=0        # write text, draft email, create document (non-code)
CAT_FILEMOD=0        # edit/update/modify existing files
CAT_CODE=0           # create/write code, scripts, functions, skills
CAT_DEBUG=0          # fix bugs, resolve errors, troubleshoot
CAT_ARCHITECTURE=0   # design systems, plan, architect, multi-component
CAT_DEPLOY=0         # deploy, publish, release, CI/CD
CAT_CONFIG=0         # install, configure, setup environments

# --- Conversation signals ---
if echo "$TASK_LOWER" | grep -qE '^(ok|oui|non|yes|no|merci|thanks|super|cool|bien|parfait|good|great|salut|hello|hi|bonjour|bonsoir|hey|yo|ciao|d.accord|okay|vas-y|go|fais-le|lance|c.est bon|top|nice|lol|mdr|haha|👍|❤️|🙏)$'; then
    CAT_CONVERSATION=10
fi
if echo "$TASK_LOWER" | grep -qE '^\s*(quel |quelle |comment |pourquoi |combien |où |quand |est-ce que |what |how |why |when |where |which |who |is |are |can |do |does )'; then
    CAT_CONVERSATION=$((CAT_CONVERSATION + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\?$'; then
    CAT_CONVERSATION=$((CAT_CONVERSATION + 3))
fi
# Opinion/preference/recommendation questions (still conversational)
if echo "$TASK_LOWER" | grep -qE '\b(penses|think|opinion|avis|recommend|conseille|préfère|prefer|choix|choice)\b'; then
    CAT_CONVERSATION=$((CAT_CONVERSATION + 4))
fi

# --- Lookup signals (quick tool calls, status checks) ---
if echo "$TASK_LOWER" | grep -qE '\b(check|vérifie|show|affiche|list|liste|status|état|info|get|récupère|dis-moi|tell me|regarde|look|montre)\b'; then
    CAT_LOOKUP=$((CAT_LOOKUP + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(calendar|calendrier|agenda|weather|météo|meteo|heure|time|date|aujourd.hui|today|demain|tomorrow|rappelle|remind)\b'; then
    CAT_LOOKUP=$((CAT_LOOKUP + 6))
fi
if echo "$TASK_LOWER" | grep -qE '\b(read|lis|log|logs|git status|git log|git diff)\b'; then
    CAT_LOOKUP=$((CAT_LOOKUP + 4))
fi

# --- Search/research signals ---
if echo "$TASK_LOWER" | grep -qE '\b(recherche|cherche|search|find|trouve|trouver|articles?|papers?|sources?|références?)\b'; then
    CAT_SEARCH=$((CAT_SEARCH + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(investigate|explore|analyze|analyse|compare|audit|review|evaluate|évalue|benchmark|état de l.art|state of the art)\b'; then
    CAT_SEARCH=$((CAT_SEARCH + 5))
fi
# Quantified research ("find 10 articles", "cherche 5 exemples")
if echo "$TASK_LOWER" | grep -qE '\b[0-9]+\s*(articles?|exemples?|sources?|liens?|links?|results?|résultats?|options?|alternatives?)\b'; then
    CAT_SEARCH=$((CAT_SEARCH + 4))
fi

# --- Content creation signals (non-code writing) ---
if echo "$TASK_LOWER" | grep -qE '\b(rédige|draft|compose|write|écris|résume|summarize|summary|résumé|traduis|translate)\b'; then
    CAT_CONTENT=$((CAT_CONTENT + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(email|mail|message|lettre|letter|article|blog|post|doc|documentation|readme|rapport|report)\b'; then
    CAT_CONTENT=$((CAT_CONTENT + 4))
fi

# --- File modification signals ---
if echo "$TASK_LOWER" | grep -qE '\b(update|met à jour|modifie|modify|change|edit|édite|améliore|improve|réécris|rewrite|ajoute|add|supprime|remove|delete|rename|renomme)\b'; then
    CAT_FILEMOD=$((CAT_FILEMOD + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(fichier|file|config|\.json|\.yaml|\.yml|\.toml|\.env|\.md|\.txt)\b'; then
    CAT_FILEMOD=$((CAT_FILEMOD + 3))
fi

# --- Code creation signals ---
if echo "$TASK_LOWER" | grep -qE '\b(code|script|function|fonction|implement|implémente|développe|develop|programme|program|endpoint|api|route|handler|middleware|class|module|package|library|lib)\b'; then
    CAT_CODE=$((CAT_CODE + 6))
fi
if echo "$TASK_LOWER" | grep -qE '\b(crée|créer|create|build|write a|écris un)\b'; then
    # "create" is ambiguous — boost code only if other code signals present
    if [[ $CAT_CODE -gt 0 ]]; then
        CAT_CODE=$((CAT_CODE + 4))
    else
        # Could be content or code; give slight boost to both
        CAT_CONTENT=$((CAT_CONTENT + 2))
        CAT_CODE=$((CAT_CODE + 2))
    fi
fi
if echo "$TASK_LOWER" | grep -qE '\b(skill|plugin|tool|bot|cli|daemon|service|worker|cron|webhook|docker|container|k8s|kubernetes)\b'; then
    CAT_CODE=$((CAT_CODE + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(test|tests|spec|unittest|jest|pytest|ci|cd|pipeline|lint|eslint|prettier|type.?check)\b'; then
    CAT_CODE=$((CAT_CODE + 4))
fi
if echo "$TASK_LOWER" | grep -qE '\b(refactor|refactorise|optimize|optimise|clean.?up|restructure)\b'; then
    CAT_CODE=$((CAT_CODE + 5))
    CAT_FILEMOD=$((CAT_FILEMOD + 3))
fi

# --- Debug/fix signals ---
# Imperative debug verbs (actual work requested) vs informational
if echo "$TASK_LOWER" | grep -qE '\b(fix|corrige|résous|resolve|troubleshoot|répare)\b'; then
    CAT_DEBUG=$((CAT_DEBUG + 8))  # Strong: clearly requesting action
fi
if echo "$TASK_LOWER" | grep -qE '\b(debug|debugge|diagnose|diagnostique)\b'; then
    CAT_DEBUG=$((CAT_DEBUG + 6))  # Medium: could be question or action
fi
if echo "$TASK_LOWER" | grep -qE '\b(error|erreur|bug|issue|broken|cassé|crash|fail|failed|marche pas|doesn.t work|not working|problem|problème|weird|bizarre|strange|étrange)\b'; then
    CAT_DEBUG=$((CAT_DEBUG + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(stack.?trace|traceback|exception|segfault|undefined|null|nan|timeout|502|500|404|403|401)\b'; then
    CAT_DEBUG=$((CAT_DEBUG + 4))
fi

# --- Architecture/design signals ---
if echo "$TASK_LOWER" | grep -qE '\b(architect|architecture|design|conception|plan|planifie|stratégie|strategy|roadmap|spec|specification)\b'; then
    CAT_ARCHITECTURE=$((CAT_ARCHITECTURE + 7))
fi
if echo "$TASK_LOWER" | grep -qE '\b(système|system|infrastructure|infra|stack|database|db|schema|migration|migrate|scale|scaling)\b'; then
    CAT_ARCHITECTURE=$((CAT_ARCHITECTURE + 4))
fi
if echo "$TASK_LOWER" | grep -qE '\b(multi|plusieurs composants|several components|microservice|monorepo|event.?driven|pub.?sub|queue|message broker)\b'; then
    CAT_ARCHITECTURE=$((CAT_ARCHITECTURE + 5))
fi

# --- Deploy signals ---
if echo "$TASK_LOWER" | grep -qE '\b(deploy|déploie|publish|publie|release|ship|merge|pr |pull request|push to|vercel|netlify|heroku|aws|gcp|azure)\b'; then
    CAT_DEPLOY=$((CAT_DEPLOY + 6))
fi
# Deployment validation/verification actions
if echo "$TASK_LOWER" | grep -qE '\b(assure.?toi|assure.?toi que|ensure|make sure|vérifie que|vérife que|check that|synchronise|sync|met à jour|update)\b'; then
    # These are technical action verbs BUT can be conversational too
    # Only boost if followed by technical object (detected below)
    CAT_DEPLOY=$((CAT_DEPLOY + 2))
    CAT_CONFIG=$((CAT_CONFIG + 2))
fi

# --- Config/setup signals ---
if echo "$TASK_LOWER" | grep -qE '\b(install|installe|configure|setup|set up|config|provision|bootstrap|init|initialize)\b'; then
    CAT_CONFIG=$((CAT_CONFIG + 5))
fi
if echo "$TASK_LOWER" | grep -qE '\b(ssh|ssl|tls|cert|certificate|dns|domain|nginx|apache|proxy|firewall|port|env|environment)\b'; then
    CAT_CONFIG=$((CAT_CONFIG + 4))
fi

# --- Technical object detection (boosts deploy/config when present) ---
# Presence of technical objects makes action verbs more significant
HAS_TECHNICAL_OBJECT=false
if echo "$TASK_LOWER" | grep -qE '\b(repo|repository|github|gitlab|bitbucket|git |npm|yarn|pnpm|docker|container|image|service|daemon|server|api|endpoint|database|db|version|package|module|lib|library|branch|main|master|prod|production|staging|dev)\b'; then
    HAS_TECHNICAL_OBJECT=true
    # Boost deploy/config categories when technical object is present
    if [[ $CAT_DEPLOY -ge 2 || $CAT_CONFIG -ge 2 ]]; then
        CAT_DEPLOY=$((CAT_DEPLOY + 6))
        CAT_CONFIG=$((CAT_CONFIG + 4))
    fi
fi

# ============================================================
# STEP 2: DETERMINE DOMINANT CATEGORY → TIME + COMPLEXITY
# ============================================================

# Find the dominant category
DOMINANT="conversation"
MAX_SCORE=$CAT_CONVERSATION

for cat_name in lookup search content filemod code debug architecture deploy config; do
    upper_name=$(echo "$cat_name" | tr '[:lower:]' '[:upper:]')
    eval "score=\$CAT_${upper_name}"
    if [[ $score -gt $MAX_SCORE ]]; then
        MAX_SCORE=$score
        DOMINANT=$cat_name
    fi
done

# If no strong signal at all (max_score <= 2), treat as conversation
if [[ $MAX_SCORE -le 2 ]]; then
    DOMINANT="conversation"
fi

# Tie-breaking: if conversation score is close to dominant AND it's a short question,
# prefer conversation (asking about something ≠ doing something)
if [[ "$DOMINANT" != "conversation" && "$IS_QUESTION_EARLY" == "true" && $WORD_COUNT -le 6 ]]; then
    SCORE_DIFF=$((MAX_SCORE - CAT_CONVERSATION))
    if [[ $SCORE_DIFF -le 3 ]]; then
        DOMINANT="conversation"
        MAX_SCORE=$CAT_CONVERSATION
    fi
fi

# Map dominant category → base time estimate + complexity level
# Complexity: 1=simple, 2=normal, 3=complex
case "$DOMINANT" in
    conversation)
        BASE_TIME=10
        COMPLEXITY=1
        COMPLEXITY_NAME="simple"
        ;;
    lookup)
        BASE_TIME=12
        COMPLEXITY=1
        COMPLEXITY_NAME="simple"
        ;;
    search)
        BASE_TIME=45
        COMPLEXITY=2
        COMPLEXITY_NAME="normal"
        ;;
    content)
        BASE_TIME=50
        COMPLEXITY=2
        COMPLEXITY_NAME="normal"
        ;;
    filemod)
        BASE_TIME=40
        COMPLEXITY=2
        COMPLEXITY_NAME="normal"
        ;;
    code)
        BASE_TIME=80
        COMPLEXITY=3
        COMPLEXITY_NAME="complex"
        ;;
    debug)
        BASE_TIME=90
        COMPLEXITY=3
        COMPLEXITY_NAME="complex"
        ;;
    architecture)
        BASE_TIME=120
        COMPLEXITY=3
        COMPLEXITY_NAME="complex"
        ;;
    deploy)
        BASE_TIME=60
        COMPLEXITY=2
        COMPLEXITY_NAME="normal"
        ;;
    config)
        BASE_TIME=50
        COMPLEXITY=2
        COMPLEXITY_NAME="normal"
        ;;
esac

# ============================================================
# STEP 2b: QUESTION DAMPENER
# Short questions about technical topics are usually asking for
# an explanation, not requesting actual work. Downgrade them.
# "C'est quoi cette erreur ?" → conversation, not debug
# "Why does X fail?" → lookup/explanation, not full troubleshooting
# ============================================================

IS_QUESTION=false
if echo "$TASK_LOWER" | grep -qE '\?$'; then
    IS_QUESTION=true
fi
if echo "$TASK_LOWER" | grep -qE '^\s*(c.est quoi|qu.est-ce que|what is|what.s|why does|why is|pourquoi|how does|how is|comment ça|explique|explain|describe|décris)'; then
    IS_QUESTION=true
fi

# Short question (≤ 8 words) + high-complexity category → downgrade
if [[ "$IS_QUESTION" == "true" && $WORD_COUNT -le 8 ]]; then
    if [[ "$DOMINANT" == "debug" || "$DOMINANT" == "code" || "$DOMINANT" == "architecture" ]]; then
        # It's an explanation question, not actual work
        # Downgrade to simple/normal depending on signals
        if [[ $WORD_COUNT -le 5 ]]; then
            COMPLEXITY=1
            COMPLEXITY_NAME="simple"
            BASE_TIME=15
        else
            COMPLEXITY=2
            COMPLEXITY_NAME="normal"
            BASE_TIME=25
        fi
    fi
fi

# Medium-length questions (≤ 12 words) + question words → cap complexity
if [[ "$IS_QUESTION" == "true" && $WORD_COUNT -le 12 ]]; then
    if echo "$TASK_LOWER" | grep -qE '^\s*(c.est quoi|qu.est-ce que|what is|what.s|explain|explique|how does|comment|describe|décris)'; then
        # Explanation-type questions: cap at normal complexity
        if [[ $COMPLEXITY -ge 3 ]]; then
            COMPLEXITY=2
            COMPLEXITY_NAME="normal"
            BASE_TIME=$((BASE_TIME < 40 ? BASE_TIME : 40))
        fi
    fi
fi

# ============================================================
# STEP 3: ADJUST TIME BASED ON SCOPE SIGNALS
# ============================================================

ESTIMATED_SECONDS=$BASE_TIME

# Multi-step / scope amplifiers
if echo "$TASK_LOWER" | grep -qE '\b(and then|et ensuite|puis|après ça|ensuite|step.?by.?step|étape par étape)\b'; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 30))
fi
if echo "$TASK_LOWER" | grep -qE '\b(multiple|plusieurs|every|chaque|all|tous|toutes|each|batch|bulk)\b'; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 20))
fi
# Comma-separated list of things to do → multi-step
COMMA_COUNT=$(echo "$TASK" | tr -cd ',' | wc -c | tr -d ' ')
if [[ $COMMA_COUNT -ge 2 ]]; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + COMMA_COUNT * 10))
fi

# Long descriptions = more scope
if [[ $WORD_COUNT -gt 30 ]]; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 40))
    # Very long descriptions with complex category → bump complexity
    if [[ $COMPLEXITY -ge 2 ]]; then
        COMPLEXITY=3
        COMPLEXITY_NAME="complex"
    fi
elif [[ $WORD_COUNT -gt 15 ]]; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 20))
elif [[ $WORD_COUNT -le 4 && "$DOMINANT" == "conversation" ]]; then
    # Very short + conversation → definitely fast
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS > 10 ? 10 : ESTIMATED_SECONDS))
fi

# Secondary category signals can amplify
# If both code + debug signals → harder problem
if [[ $CAT_CODE -ge 3 && $CAT_DEBUG -ge 3 ]]; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 30))
    COMPLEXITY=3
    COMPLEXITY_NAME="complex"
fi
# If architecture + code → bigger project
if [[ $CAT_ARCHITECTURE -ge 3 && $CAT_CODE -ge 3 ]]; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 40))
    COMPLEXITY=3
    COMPLEXITY_NAME="complex"
fi

# "commit", "push", "test" at the end → adds execution steps
if echo "$TASK_LOWER" | grep -qE '\b(commit|push|test|tests)\s*[,.]?\s*$|\bcommit.*(push|et push)'; then
    ESTIMATED_SECONDS=$((ESTIMATED_SECONDS + 15))
fi

# ============================================================
# STEP 4: DECISION MATRIX (Time × Complexity)
#
#              | Simple (1)      | Normal (2)       | Complex (3)
# -------------|-----------------|------------------|------------------
# < 30s        | execute_direct  | execute_direct   | execute_direct
# 30-120s      | execute_direct* | spawn Sonnet     | spawn Opus
# > 120s       | spawn Sonnet    | spawn Sonnet     | spawn Opus
#
# * Simple tasks 30-120s: still direct (e.g. a lookup that takes a bit)
# ============================================================

if [[ $ESTIMATED_SECONDS -le 30 ]]; then
    REC="execute_direct"
elif [[ $ESTIMATED_SECONDS -le 120 ]]; then
    if [[ $COMPLEXITY -le 1 ]]; then
        REC="execute_direct"
    else
        REC="spawn"
    fi
else
    REC="spawn"
fi

# Model selection for spawns
MODEL="" MODEL_NAME="" TIMEOUT=10 COST="low"
if [[ "$REC" == "spawn" ]]; then
    if [[ $COMPLEXITY -ge 3 ]]; then
        MODEL="anthropic/claude-opus-4-6" MODEL_NAME="Opus" COST="high"
        TIMEOUT=$((ESTIMATED_SECONDS * 3 > 1800 ? 1800 : ESTIMATED_SECONDS * 3))
    else
        MODEL="anthropic/claude-sonnet-4-5" MODEL_NAME="Sonnet" COST="medium"
        TIMEOUT=$((ESTIMATED_SECONDS * 3 > 600 ? 600 : ESTIMATED_SECONDS * 3))
    fi
fi

REASONING="category=${DOMINANT} time=${ESTIMATED_SECONDS}s complexity=${COMPLEXITY_NAME} → ${REC}${MODEL_NAME:+ (${MODEL_NAME})}"

# ============================================================
# Protection mode check
# ============================================================
PROTECTION="false"
[[ "${PROTECTION_MODE:-false}" == "true" ]] && PROTECTION="true"
[[ "$PROTECTION" == "false" && -f "$PROTECTION_STATE_FILE" ]] && \
    PROTECTION=$(jq -r '.protection_mode // false' "$PROTECTION_STATE_FILE" 2>/dev/null || echo "false")

PROT_OVERRIDE=false
if [[ "$PROTECTION" == "true" && "$MODEL_NAME" == "Opus" ]]; then
    MODEL="anthropic/claude-sonnet-4-5" MODEL_NAME="Sonnet" COST="medium" PROT_OVERRIDE=true
    REASONING="${REASONING} ⚠️ Protection→Sonnet"
fi

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
    # Escape quotes in TASK for JSON
    TASK_ESCAPED=$(echo "$TASK" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
    cat <<EOF
{"recommendation":"${REC}","model":"${MODEL}","model_name":"${MODEL_NAME}","reasoning":"${REASONING}","command":"${CMD}","timeout_seconds":${TIMEOUT},"estimated_seconds":${ESTIMATED_SECONDS},"estimated_cost":"${COST}","complexity":"${COMPLEXITY_NAME}","category":"${DOMINANT}","protection_mode":$([[ "$PROTECTION" == "true" ]] && echo true || echo false),"protection_mode_override":$([[ "$PROT_OVERRIDE" == "true" ]] && echo true || echo false),"label":"${LABEL}","dry_run":$([[ "$DRY_RUN" == "true" ]] && echo true || echo false),"user_message":"${TASK_ESCAPED}"}
EOF
else
    echo ""
    [[ "$REC" == "execute_direct" ]] && echo "⚡ EXECUTE DIRECTLY (estimated ${ESTIMATED_SECONDS}s)" || echo "🔀 SPAWN SUB-AGENT (estimated ${ESTIMATED_SECONDS}s)"
    echo "  Task:       $TASK"
    echo "  Category:   $DOMINANT"
    echo "  Complexity: $COMPLEXITY_NAME ($COMPLEXITY/3)"
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
