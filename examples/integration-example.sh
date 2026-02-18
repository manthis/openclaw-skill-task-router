#!/bin/bash
# integration-example.sh — Example of integrating task-router into a workflow
set -euo pipefail

ROUTER="${HOME}/bin/task-router.sh"

# Example: Route a task and optionally execute the recommended command
route_and_execute() {
    local task="$1"
    local result
    result=$("$ROUTER" --task "$task" --json)
    
    local recommendation
    recommendation=$(echo "$result" | jq -r '.recommendation')
    
    if [[ "$recommendation" == "execute_direct" ]]; then
        echo "→ Executing directly (no sub-agent needed)"
        # Execute the task directly here
    else
        local command
        command=$(echo "$result" | jq -r '.command')
        local model
        model=$(echo "$result" | jq -r '.model_name')
        local timeout
        timeout=$(echo "$result" | jq -r '.timeout_seconds')
        
        echo "→ Spawning sub-agent (${model}, timeout: ${timeout}s)"
        echo "  Command: ${command}"
        
        # Uncomment to actually execute:
        # eval "$command"
    fi
}

# Examples
echo "=== Integration Examples ==="
echo ""

echo "Task 1: 'Read the config file'"
route_and_execute "Read the config file"
echo ""

echo "Task 2: 'Write API documentation'"
route_and_execute "Write API documentation"
echo ""

echo "Task 3: 'Build and deploy the application'"
route_and_execute "Build and deploy the application"
echo ""
