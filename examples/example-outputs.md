# Example Outputs

## Example 1: Simple Read (Direct Execution)

```bash
$ task-router.sh --task "Read HEARTBEAT.md" --json
```

```json
{
  "recommendation": "execute_direct",
  "model": "",
  "reasoning": "Task matches direct execution patterns (simple, quick). Keywords matched: 1.",
  "command": "",
  "timeout_seconds": 10,
  "estimated_cost": "low",
  "protection_mode": false,
  "protection_mode_override": false,
  "complexity": "simple",
  "label": "read-heartbeatmd"
}
```

## Example 2: Create Skills (Opus)

```bash
$ task-router.sh --task "Create 6 skills and publish on GitHub" --json
```

```json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-opus-4-6",
  "reasoning": "Task matches complex patterns requiring Opus. Keywords matched: opus=2, sonnet=1.",
  "command": "sessions_spawn --task 'Create 6 skills and publish on GitHub' --model 'anthropic/claude-opus-4-6' --label 'create-6-skills-and'",
  "timeout_seconds": 1800,
  "estimated_cost": "high",
  "protection_mode": false,
  "complexity": "complex"
}
```

## Example 3: Protection Mode Active

```bash
$ PROTECTION_MODE=true task-router.sh --task "Debug authentication bug" --json
```

```json
{
  "recommendation": "spawn",
  "model": "anthropic/claude-sonnet-4-5",
  "reasoning": "Task matches complex patterns. ⚠️ Protection mode active: forced to Sonnet.",
  "command": "sessions_spawn --task 'Debug authentication bug' --model 'anthropic/claude-sonnet-4-5' --label 'debug-authentication-bug'",
  "timeout_seconds": 1800,
  "estimated_cost": "medium",
  "protection_mode": true,
  "protection_mode_override": true
}
```
