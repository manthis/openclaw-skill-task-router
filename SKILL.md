# SKILL.md — task-router

## What This Skill Does

**You are a task router.** When a user asks you to do something, you decide: handle it directly, or spawn a sub-agent? And if you spawn, which model?

This skill gives you the framework to make that decision consistently, and two scripts to execute it.

**Install → it works.** Follow these instructions for every incoming task.

---

## The Routing Flow

```
User message arrives
    │
    ├─ Can you answer in < 30s without tools or with a quick tool call?
    │   └─ YES → Respond directly. Done.
    │
    └─ NO → Estimate complexity (1-3) and duration (seconds)
            │
            └─ Run: get-recommended-model.sh --complexity N --duration S
                    │
                    ├─ "direct"  → Handle it yourself
                    ├─ "sonnet"  → Spawn sub-agent with anthropic/claude-sonnet-4-5
                    └─ "opus"    → Spawn sub-agent with anthropic/claude-opus-4-6
```

**Always give immediate feedback** when spawning: tell the user what you're doing, which model, and estimated time. Don't make them wait in silence.

---

## Step 1: Estimate Complexity (1–3)

Complexity = how much reasoning, creativity, or expertise the task requires.

### Complexity 1 — Simple
> Straightforward, no ambiguity, one-step or mechanical.

- Status checks, lookups, reading files
- Simple questions with factual answers
- Calendar, weather, reminders
- Copy-paste operations, renaming
- "What time is my next meeting?"
- "Show me git log for today"

### Complexity 2 — Normal
> Requires some thinking, multiple steps, or content creation.

- Writing emails, summaries, documentation
- Web research and synthesis
- File modifications with context
- Simple deploys, config changes
- Translation, formatting
- "Draft an email to X about Y"
- "Search for the best Rust HTTP libraries and compare them"
- "Update the README with the new API endpoints"

### Complexity 3 — Complex
> Deep reasoning, debugging, architecture, creative code, multi-system coordination.

- Writing new code (functions, modules, services)
- Debugging and troubleshooting
- Architecture design, system planning
- Refactoring across multiple files
- Security analysis, performance optimization
- Multi-step technical tasks with dependencies
- "Refactor the auth module and add tests"
- "Debug why the WebSocket connection drops under load"
- "Design the data model for the new billing system"

### Quick Reference

| Signal | Complexity |
|--------|-----------|
| Question with factual answer | 1 |
| Status check, lookup, read | 1 |
| Write content, search + synthesize | 2 |
| Edit existing files with context | 2 |
| Deploy, configure, install | 2 |
| Write new code, create scripts | 3 |
| Debug, fix, troubleshoot | 3 |
| Architect, design, plan systems | 3 |
| Refactor, optimize, restructure | 3 |

### ⚠️ Watch Out: Questions ≠ Work

"What does this error mean?" → Complexity **1** (explanation)
"Fix this error" → Complexity **3** (debugging work)

"How does WebSocket work?" → Complexity **1** (explanation)
"Implement WebSocket support" → Complexity **3** (code creation)

A question about a complex topic is still simple if you're just explaining.

---

## Step 2: Estimate Duration (seconds)

Duration = how long the task will actually take to execute (not think about).

### Duration Guidelines

| Task Type | Typical Range |
|-----------|--------------|
| Direct answer, greeting, opinion | 5–15s |
| Lookup (calendar, file, git status) | 10–20s |
| Web search + summary | 30–60s |
| Write email/doc/content | 40–80s |
| Edit/modify existing files | 30–60s |
| Deploy, config change | 40–90s |
| Write new code/script | 60–120s |
| Debug/troubleshoot | 60–150s |
| Architecture/design | 90–180s |
| Multi-step project (code + test + deploy) | 120–300s |

### Duration Multipliers

Add time for these patterns:
- **Multi-step** ("do X, then Y, then Z"): +30s per additional step
- **Batch operations** ("for all files", "every module"): +30–60s
- **Long description** (>20 words): the scope is probably bigger, +20–40s
- **Includes testing** ("and write tests"): +30–60s
- **Includes git operations** ("commit and push"): +15s

### Examples

| Task | Duration | Why |
|------|----------|-----|
| "What's the weather?" | 10s | One API call |
| "Summarize this article" | 40s | Read + synthesize |
| "Write a bash script to backup my DB" | 80s | Code creation, single file |
| "Refactor auth + add tests + commit" | 180s | Multi-step, code + tests + git |
| "Debug the flaky CI pipeline" | 120s | Investigation + fix |

---

## Step 3: Get the Recommendation

Run the script:

```bash
get-recommended-model.sh --complexity <1|2|3> --duration <seconds>
```

Output is one word: `direct`, `sonnet`, or `opus`.

### The Decision Matrix

```
              │ Simple (1)    │ Normal (2)     │ Complex (3)
──────────────┼───────────────┼────────────────┼──────────────
  ≤ 30s       │ direct        │ direct         │ direct
  31–120s     │ direct        │ sonnet         │ opus
  > 120s      │ sonnet        │ sonnet         │ opus
```

### What Each Recommendation Means

- **direct** → Handle the task yourself, in the current session. No spawn.
- **sonnet** → Spawn a sub-agent using `anthropic/claude-sonnet-4-5`. Good for content, search, edits, deploys.
- **opus** → Spawn a sub-agent using `anthropic/claude-opus-4-6`. For complex code, debugging, architecture.

### Timeout Calculation

When spawning, set a timeout:
- **Sonnet**: `duration × 3` (cap at 600s)
- **Opus**: `duration × 5` (cap at 1800s)

---

## Step 4: Act on the Recommendation

### If "direct"
Just do it. No spawn needed.

### If "sonnet" or "opus"

1. **Immediately tell the user** what you're doing:
   > "Je lance un sub-agent Sonnet pour [résumé tâche] (~60s)"
   > "Spawning an Opus sub-agent for [task summary] (~120s)"

2. **Spawn** with the recommended model.

3. **When the sub-agent completes**, relay the result. Don't repeat the announcement.

---

## Protection Mode

Protection mode activates when Claude usage exceeds 50% of the weekly budget. When active, **Opus is downgraded to Sonnet** for non-critical tasks.

### Check Protection Mode

```bash
check-protection-mode.sh
# Output: "true" or "false"
```

The `get-recommended-model.sh` script **already checks protection mode internally** — it will never output "opus" when protection is active. You don't need to check separately unless you want to inform the user.

### Override

For truly critical/urgent tasks explicitly requested by the user, you can set `PROTECTION_MODE=false` as an environment variable to force the override. Use sparingly.

---

## Full Annotated Examples

### Example 1: Simple greeting
```
User: "Salut !"
→ Complexity: 1 (greeting)
→ Duration: 5s
→ No need to even call the script. Respond directly.
```

### Example 2: Calendar check
```
User: "What's on my calendar tomorrow?"
→ Complexity: 1 (lookup)
→ Duration: 12s
→ get-recommended-model.sh --complexity 1 --duration 12 → "direct"
→ Handle it yourself.
```

### Example 3: Write documentation
```
User: "Write API docs for the auth endpoints"
→ Complexity: 2 (content creation)
→ Duration: 60s
→ get-recommended-model.sh --complexity 2 --duration 60 → "sonnet"
→ Tell user: "Je lance un sub-agent Sonnet pour la doc API (~60s)"
→ Spawn with anthropic/claude-sonnet-4-5, timeout 180s
```

### Example 4: Debug a crash
```
User: "The server crashes on WebSocket reconnect, fix it"
→ Complexity: 3 (debugging)
→ Duration: 120s
→ get-recommended-model.sh --complexity 3 --duration 120 → "opus"
→ Tell user: "Je lance un sub-agent Opus pour debug WebSocket (~120s)"
→ Spawn with anthropic/claude-opus-4-6, timeout 600s
```

### Example 5: Multi-step refactor
```
User: "Refactor the task-router skill: simplify scripts, rewrite docs, add tests, commit and push"
→ Complexity: 3 (refactoring + multi-step)
→ Duration: 200s (refactor 80s + docs 40s + tests 40s + git 20s + overhead 20s)
→ get-recommended-model.sh --complexity 3 --duration 200 → "opus"
→ Tell user: "Je lance un sub-agent Opus pour le refactoring (~200s)"
→ Spawn with anthropic/claude-opus-4-6, timeout 1000s
```

### Example 6: Complex question (but just a question)
```
User: "How does Kubernetes handle pod scheduling?"
→ Complexity: 1 (it's a question, not work)
→ Duration: 15s
→ get-recommended-model.sh --complexity 1 --duration 15 → "direct"
→ Answer directly.
```

### Example 7: Protection mode active
```
User: "Refactor the billing module"
→ Complexity: 3, Duration: 150s
→ get-recommended-model.sh --complexity 3 --duration 150 → "sonnet" (protection active!)
→ Tell user: "🛡️ Protection mode active — je lance un sub-agent Sonnet pour le refactoring (~150s)"
→ Spawn with anthropic/claude-sonnet-4-5
```

---

## Scripts Reference

### get-recommended-model.sh

```bash
get-recommended-model.sh --complexity <1|2|3> --duration <seconds>
# Output: "direct" | "sonnet" | "opus"
```

Applies the decision matrix. Checks protection mode automatically.

### check-protection-mode.sh

```bash
check-protection-mode.sh
# Output: "true" | "false"
```

Reads `memory/claude-usage-state.json`. Respects `PROTECTION_MODE` env var override.

---

## Files

```
skills/task-router/
├── SKILL.md                    # This file (agent instructions)
├── README.md                   # Project README for humans/GitHub
├── get-recommended-model.sh    # Routing: complexity × duration → model
├── check-protection-mode.sh    # Protection mode check
├── tests/
│   └── test-router.sh          # Automated tests
└── LICENSE
```
