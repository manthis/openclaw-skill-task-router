# SKILL.md — openclaw-skill-task-router

## Purpose

CLI tool that analyzes task descriptions and recommends whether to execute directly or spawn a sub-agent, which model to use, and generates the appropriate command.

## Usage

```bash
# Basic usage
task-router.sh --task "description"

# JSON output
task-router.sh --task "description" --json

# Check protection mode
task-router.sh --task "description" --check-protection

# Dry run
task-router.sh --task "description" --dry-run
```

## How It Works

1. Parses the task description
2. Matches keywords against decision rules (`lib/decision-rules.json`)
3. Estimates task complexity
4. Selects appropriate model (Opus/Sonnet/Codex)
5. Checks protection mode status
6. Generates spawn command with timeout and label
7. Outputs recommendation (JSON or human-readable)

## Decision Logic

| Category | Keywords | Model | Timeout |
|----------|----------|-------|---------|
| Direct | read, check, list, show, get | None | 10s |
| Sonnet | write, create, format, search, analyze | Sonnet | 600s |
| Opus | build, fix, debug, audit, refactor | Opus | 1800s |
| Codex | fallback, general | Codex | 600s |

## Dependencies

- `bash` (4.0+)
- `jq`

## Configuration

- Decision rules: `lib/decision-rules.json`
- Model config: `lib/model-config.json`
- Protection mode state: `$OPENCLAW_WORKSPACE/memory/claude-usage-state.json`

## Environment Variables

- `PROTECTION_MODE=true` — Force protection mode
- `OPENCLAW_WORKSPACE` — Path to workspace (default: `~/.openclaw/workspace`)
