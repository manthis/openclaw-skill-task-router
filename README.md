# openclaw-skill-task-router

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue.svg)](https://github.com/manthis/openclaw-skill-task-router)

Intelligent task routing for OpenClaw — the agent estimates duration and type, this script applies the decision matrix and handles model availability.

## Quick Start

```bash
git clone https://github.com/manthis/openclaw-skill-task-router.git ~/Projects/openclaw-skill-task-router
ln -sf ~/Projects/openclaw-skill-task-router/get-recommended-model.sh ~/bin/get-recommended-model.sh

# Use it
get-recommended-model.sh --duration 10
# direct

get-recommended-model.sh --duration 90 --type code --json
# { "recommendation": "codex", "ask_user": true, ... }
```

## Decision Matrix

```
Duration < 30s                → direct
Duration ≥ 30s + normal       → sonnet
Duration ≥ 30s + code         → model availability logic:
  Codex + Opus available       → codex  (ask user to confirm or switch to Opus)
  Only Codex available         → codex  (no confirmation needed)
  Only Opus available          → opus   (no confirmation needed)
  Neither available            → qwen-coder (fallback)
```

**Code-type tasks**: code writing, debugging, architecture, refactoring.  
**Normal tasks**: everything else (content, research, config, deploy...).

## Model Availability

Tracked in `~/.openclaw/state/model-limits.json`:

```json
{
  "codex": { "last_429": 1740000000, "cooldown_until": 1740000600 },
  "opus":  { "last_429": 0, "cooldown_until": 0 }
}
```

Cooldown = **10 minutes** after a 429 error. The router checks this before every code task.

## Usage

```bash
get-recommended-model.sh [OPTIONS]

Options:
  --duration <seconds>   Estimated task duration (required)
  --type <code|normal>   Task type: 'code' for code/debug/arch, 'normal' for rest (default: normal)
  --json                 Output as JSON with extra fields
  -h, --help             Show help
```

## JSON Output Fields

| Field | Description |
|-------|-------------|
| `recommendation` | `direct`, `sonnet`, `codex`, `opus`, or `qwen-coder` |
| `model_id` | Full model ID |
| `ask_user` | `true` when both Codex & Opus available → ask user to confirm or switch |
| `model_selection` | `both_available`, `codex_only`, `opus_only`, `fallback_qwen`, `normal`, `fast` |
| `codex_available` | Whether Codex is off cooldown |
| `opus_available` | Whether Opus is off cooldown |
| `protection_mode` | Whether budget protection is active (Opus → Sonnet) |

## Examples

```bash
# Fast task → direct
get-recommended-model.sh --duration 10
# direct

# Content task → Sonnet
get-recommended-model.sh --duration 60 --type normal
# sonnet

# Code task, both models available → Codex + ask user
get-recommended-model.sh --duration 90 --type code --json
# { "recommendation": "codex", "ask_user": true, "model_selection": "both_available" }

# Code task, Codex on cooldown → Opus
get-recommended-model.sh --duration 90 --type code --json
# { "recommendation": "opus", "ask_user": false, "model_selection": "opus_only" }

# Code task, both on cooldown → Qwen Coder
get-recommended-model.sh --duration 90 --type code --json
# { "recommendation": "qwen-coder", "model_selection": "fallback_qwen" }

# Protection mode active → Opus replaced by Sonnet
PROTECTION_MODE=true get-recommended-model.sh --duration 90 --type code --json
# { "recommendation": "sonnet", "protection_mode": true }
```

## Orchestration Workflow

When `ask_user=true` (both models available):
1. Send user: *"Tâche code détectée. Je propose Codex — veux-tu Opus à la place ?"*
2. Wait for confirmation
3. Spawn with confirmed model

When `ask_user=false` + `recommendation != direct`:
1. Send user: *"Ok, je lance [model] pour cette tâche (~Xs)"*
2. Spawn immediately
3. Send result when done

## Other Scripts

- **`check-protection-mode.sh`** — checks if budget protection is active
