# SKILL.md — openclaw-skill-task-router

## Purpose

**Model selector for sub-agents.** When the main agent decides to spawn a sub-agent, this tool analyzes the task and recommends which model (Opus vs Sonnet) to use, with timeout and cost estimates.

**This is NOT a universal message router.** The agent handles conversational messages directly. This tool is only called when a task needs delegation.

## Usage

```bash
# Basic usage — when you've decided to spawn
task-router.sh --task "description of the task to delegate"

# JSON output (recommended for programmatic use)
task-router.sh --task "description" --json --no-notify

# Check protection mode
task-router.sh --task "description" --check-protection

# Dry run
task-router.sh --task "description" --dry-run
```

## How It Works

1. Analyzes the task description (category, complexity, scope)
2. Estimates execution time and cognitive complexity
3. Selects appropriate model:
   - **Sonnet** → normal tasks (write, search, modify, deploy, content)
   - **Opus** → complex tasks (debug, refactor, architecture, multi-step code)
4. Checks protection mode (budget constraints → Opus downgraded to Sonnet)
5. Generates spawn command with timeout and label
6. Returns `user_message` for immediate feedback to user

## Decision Matrix

```
              | Normal (≤2)      | Complex (3)
--------------|------------------|------------------
30-120s       | spawn Sonnet     | spawn Opus
> 120s        | spawn Sonnet     | spawn Opus
```

Protection mode: Opus → Sonnet downgrade when budget threshold exceeded.

## Output (JSON)

```json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-opus-4-6",
  "model_name": "Opus",
  "complexity": "complex",
  "category": "debug",
  "estimated_seconds": 90,
  "timeout_seconds": 450,
  "estimated_cost": "high",
  "user_message": "Ok, je lance un sub-agent Opus pour debug (~90s)",
  "label": "fix-auth-bug",
  "protection_mode": false,
  "protection_mode_override": false
}
```

## Dependencies

- `bash` (4.0+)
- `jq`

## Configuration

- Model config: `lib/model-config.json`
- Protection mode state: `$OPENCLAW_WORKSPACE/memory/claude-usage-state.json`

## Environment Variables

- `PROTECTION_MODE=true` — Force protection mode
- `OPENCLAW_WORKSPACE` — Path to workspace (default: `~/.openclaw/workspace`)
