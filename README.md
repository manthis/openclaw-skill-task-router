# openclaw-skill-task-router

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue.svg)](https://github.com/manthis/openclaw-skill-task-router)

**Model selector for OpenClaw sub-agents** — analyzes tasks to delegate and recommends which model (Opus vs Sonnet) to use, with timeout and cost estimates.

> **Not a universal message router.** The agent handles conversational messages directly. This tool is only called when the agent has decided to spawn a sub-agent.

## Quick Start

```bash
# Clone
git clone https://github.com/manthis/openclaw-skill-task-router.git ~/.openclaw/workspace/skills/openclaw-skill-task-router

# Symlink for easy access
ln -sf ~/.openclaw/workspace/skills/openclaw-skill-task-router/scripts/task-router.sh ~/bin/task-router.sh

# Use it (when you've decided to spawn)
task-router.sh --task "Refactor authentication module" --json --no-notify
# { "recommendation": "spawn", "model": "anthropic/claude-opus-4-6", ... }

task-router.sh --task "Write a summary email" --json --no-notify
# { "recommendation": "spawn", "model": "anthropic/claude-sonnet-4-5", ... }
```

## Workflow

The agent decides when to spawn — task-router decides **which model**:

```
User message
    │
    ├── Conversational? → Agent responds directly (no task-router)
    │
    └── Needs delegation? → task-router.sh --task "..." --json --no-notify
                                │
                                ├── Normal task → Sonnet
                                └── Complex task → Opus
```

## Features

- **Structural analysis** — linguistic signals, not keyword dictionaries
- **Complexity estimation** from word count, grammar, and task structure
- **Model selection** (Opus / Sonnet) based on estimated complexity
- **Protection mode** awareness — respects budget constraints (Opus → Sonnet)
- **User message generation** — ready-to-send feedback for the user
- **Command generation** — ready-to-use spawn commands

## Usage

```bash
task-router.sh --task "description" [OPTIONS]

Options:
  --task <description>    Task to analyze (required)
  --json                  Output as JSON
  --check-protection      Check if protection mode is active
  --dry-run               Simulation mode
  --no-notify             No Telegram notification (default)
  --use-notify            Send Telegram notification via spawn-notify.sh
  -h, --help              Show help
```

## Examples

```bash
# Normal task → Sonnet
$ task-router.sh --task "Write API documentation for the auth module" --json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-sonnet-4-5",
  "complexity": "normal",
  "estimated_seconds": 50,
  ...
}

# Complex task → Opus
$ task-router.sh --task "Refactor authentication, add tests, and fix the race condition" --json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-opus-4-6",
  "complexity": "complex",
  "estimated_seconds": 120,
  ...
}

# Protection mode → forces Sonnet
$ PROTECTION_MODE=true task-router.sh --task "Debug complex distributed bug" --json
{
  "model": "anthropic/claude-sonnet-4-5",
  "protection_mode_override": true,
  ...
}
```

## How It Works

**Pure structural analysis — no configuration needed:**

1. **Categorization** — identifies task type (code, debug, content, search, deploy, config, etc.)
2. **Complexity scoring** — word count, multi-step indicators, combined categories
3. **Time estimation** — based on category + scope signals
4. **Model selection:**
   - Normal complexity (≤2) → **Sonnet**
   - Complex (3) → **Opus**
   - Protection mode active → always **Sonnet**

## Tests

```bash
./tests/test-router.sh
```

## Dependencies

- `bash` (4.0+)
- `jq`

## License

MIT
