# openclaw-skill-task-router

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue.svg)](https://github.com/manthis/openclaw-skill-task-router)

Intelligent task routing CLI for OpenClaw — analyzes tasks and recommends spawn vs direct execution, model selection, and generates commands.

## Quick Start

```bash
# Clone
git clone https://github.com/manthis/openclaw-skill-task-router.git ~/.openclaw/workspace/skills/openclaw-skill-task-router

# Symlink for easy access
ln -sf ~/.openclaw/workspace/skills/openclaw-skill-task-router/scripts/task-router.sh ~/bin/task-router.sh

# Use it
task-router.sh --task "Read HEARTBEAT.md"
# ⚡ EXECUTE DIRECTLY

task-router.sh --task "Create a new skill and publish on GitHub" --json
# { "recommendation": "spawn", "model": "anthropic/claude-opus-4-6", ... }
```

## Features

- **Structural analysis** — NO regex, NO keyword dictionaries, pure linguistic signals
- **Complexity estimation** from word count, grammar, and task structure
- **Smart routing** — `ask_user` for ambiguous tasks, automatic model selection
- **Model selection** (Opus / Sonnet) based on estimated complexity
- **Protection mode** awareness — respects budget constraints
- **Command generation** — ready-to-use spawn commands
- **JSON or human-readable** output

## Usage

```bash
task-router.sh --task "description" [OPTIONS]

Options:
  --task <description>    Task to analyze (required)
  --json                  Output as JSON
  --check-protection      Check if protection mode is active
  --dry-run               Simulation mode
  -h, --help              Show help
```

## Examples

```bash
# Simple task → execute directly
$ task-router.sh --task "Check git status"
⚡ EXECUTE DIRECTLY
  Complexity: simple
  Reasoning: Task matches direct execution patterns...

# Complex task → spawn with Opus
$ task-router.sh --task "Refactor authentication and deploy" --json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-opus-4-6",
  "timeout_seconds": 1800,
  "estimated_cost": "high",
  ...
}

# Protection mode → forces Sonnet
$ PROTECTION_MODE=true task-router.sh --task "Debug complex bug" --json
{
  "model": "anthropic/claude-sonnet-4-5",
  "protection_mode_override": true,
  ...
}
```

## How It Works

**Pure structural analysis — no configuration needed:**

1. **Text metrics** — word count, sentence count, list items
2. **Grammar signals** — connectors, conditionals, technical references
3. **Task type detection** — questions, imperatives, trivial messages
4. **Time estimation** — based on complexity indicators
5. **Smart routing:**
   - `< 30s` → `execute_direct`
   - `≥ 30s + ambiguous` → `ask_user` (prompt for clarification)
   - `≥ 30s + normal` → spawn Sonnet
   - `≥ 30s + complex` → spawn Opus

## Tests

```bash
./tests/test-router.sh
```

## Dependencies

- `bash` (4.0+)
- `jq`

## Related

- [openclaw-skill-orchestrator-config](https://github.com/manthis/openclaw-skill-orchestrator-config) — Templates and docs for orchestration

## License

MIT
