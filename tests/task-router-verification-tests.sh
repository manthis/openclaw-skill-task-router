#!/bin/bash
# Test suite for verification question routing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="$HOME/bin/task-router.sh"

echo "🧪 Testing task-router verification question detection"
echo "======================================================="
echo

test_case() {
    local task="$1"
    local expected_rec="$2"
    local expected_max_time="$3"
    
    echo "📝 Task: $task"
    result=$("$ROUTER" --task "$task" --json)
    rec=$(echo "$result" | jq -r '.recommendation')
    time=$(echo "$result" | jq -r '.estimated_seconds')
    verification=$(echo "$result" | jq -r '.is_verification')
    
    # For spawn/ask_user, we just check the recommendation matches
    # For execute_direct, we also check time is under threshold
    if [[ "$expected_rec" == "execute_direct" ]]; then
        if [[ "$rec" == "$expected_rec" ]] && [[ "$time" -le "$expected_max_time" ]]; then
            echo "✅ PASS: $rec (${time}s, verification=$verification)"
        else
            echo "❌ FAIL: Expected $expected_rec (≤${expected_max_time}s), got $rec (${time}s, verification=$verification)"
        fi
    else
        # For spawn/ask_user, just check recommendation (ask_user is acceptable for ambiguous short tasks)
        if [[ "$rec" == "$expected_rec" ]] || [[ "$rec" == "ask_user" ]]; then
            echo "✅ PASS: $rec (${time}s, verification=$verification)"
        else
            echo "❌ FAIL: Expected $expected_rec, got $rec (${time}s, verification=$verification)"
        fi
    fi
    echo
}

echo "━━━ Verification Questions (should be execute_direct, < 30s) ━━━"
echo
test_case "super tu as mis à jour le task router et la skill et le repo github ainsi que son readme sont à jour ?" "execute_direct" 30
test_case "tu as mis à jour le task router et la skill ?" "execute_direct" 30
test_case "le repo github est à jour ?" "execute_direct" 30
test_case "tout est synchronisé ?" "execute_direct" 30
test_case "est-ce que X est à jour ?" "execute_direct" 30
test_case "X est correct ?" "execute_direct" 30
test_case "tu as fait le commit ?" "execute_direct" 30
test_case "le readme est terminé ?" "execute_direct" 30

echo "━━━ Action Commands (should be spawn, ≥ 30s) ━━━"
echo
test_case "mets à jour le task router et la skill" "spawn" 0
test_case "déploie le service" "spawn" 0
test_case "crée une nouvelle API" "spawn" 0

echo "━━━ Communication Verbs (should be execute_direct, < 30s) ━━━"
echo
test_case "annonce les résultats" "execute_direct" 30
test_case "montre moi le status" "execute_direct" 30

echo
echo "✅ All tests completed"
