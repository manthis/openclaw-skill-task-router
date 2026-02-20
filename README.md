# openclaw-skill-task-router

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue.svg)](https://github.com/manthis/openclaw-skill-task-router)

**Plug-and-play model routing for OpenClaw agents.** Install the skill → agents automatically learn when to handle tasks directly, when to spawn sub-agents, and which model to use.

## How It Works

The **agent** estimates two things about each incoming task:
- **Complexity** (1=simple, 2=normal, 3=complex)
- **Duration** (estimated seconds)

The **scripts** apply a deterministic decision matrix:

```
              │ Simple (1)    │ Normal (2)     │ Complex (3)
──────────────┼───────────────┼────────────────┼──────────────
  ≤ 30s       │ direct        │ direct         │ direct
  31–120s     │ direct        │ sonnet         │ opus
  > 120s      │ sonnet        │ sonnet         │ opus
```

## Install

```bash
# Clone into skills directory
git clone https://github.com/manthis/openclaw-skill-task-router.git \
    ~/.openclaw/workspace/skills/task-router

# Make scripts executable
chmod +x ~/.openclaw/workspace/skills/task-router/*.sh

# Optional: symlink for CLI access
ln -sf ~/.openclaw/workspace/skills/task-router/get-recommended-model.sh ~/bin/get-recommended-model.sh
ln -sf ~/.openclaw/workspace/skills/task-router/check-protection-mode.sh ~/bin/check-protection-mode.sh
```

That's it. The agent reads `SKILL.md` and knows what to do.

## Usage

```bash
# Get model recommendation
get-recommended-model.sh --complexity 3 --duration 120
# → "opus"

get-recommended-model.sh --complexity 2 --duration 60
# → "sonnet"

get-recommended-model.sh --complexity 1 --duration 10
# → "direct"

# Check protection mode
check-protection-mode.sh
# → "false"
```

## Protection Mode

When weekly Claude usage exceeds 50% of budget, protection mode activates automatically. The routing script reads `memory/claude-usage-state.json` and downgrades Opus → Sonnet.

```bash
# Force protection mode
PROTECTION_MODE=true get-recommended-model.sh --complexity 3 --duration 120
# → "sonnet" (instead of "opus")
```

## Agent Instructions

All routing guidelines, complexity estimation rules, duration estimates, and annotated examples are in **[SKILL.md](SKILL.md)**. This is what the agent reads to learn the routing behavior — no configuration needed.

## Tests

```bash
./tests/test-router.sh
```

## Files

```
skills/task-router/
├── SKILL.md                    # Agent instructions (the brain)
├── README.md                   # This file
├── get-recommended-model.sh    # complexity × duration → model
├── check-protection-mode.sh    # Protection mode check
├── tests/
│   └── test-router.sh          # Automated tests
└── LICENSE
```

## Dependencies

- `bash` (4.0+)
- `jq`

## License

MIT
