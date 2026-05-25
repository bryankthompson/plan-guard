# plan-guard

**Automatic plan file backup and recovery for Claude Code.**

Never lose a plan to context compaction again.

## The Problem

Claude Code's plan mode writes plans to `~/.claude/plans/*.md`. After context compacting, writes to these files frequently fail with "Error writing file" — wasting tokens and losing your work.

Known issues:
- [#12434](https://github.com/anthropics/claude-code/issues/12434) — Plan agent cannot write plan file, state lost (but tokens billed)
- [#24151](https://github.com/anthropics/claude-code/issues/24151) — Plan mode: first file write always fails
- [#23389](https://github.com/anthropics/claude-code/issues/23389) — Claude saves incomplete/wrong plan content

## The Solution

`plan-guard` uses three hooks to protect your plan files:

| Hook | Event | What it does |
|------|-------|--------------|
| **Backup** | `PreCompact` | Backs up active plan files before compaction happens |
| **Re-inject** | `SessionStart (compact)` | Feeds plan content back to Claude after compaction |
| **Recovery** | `PostToolUseFailure` | Catches write failures, creates a recovery file, and tells Claude to use it |

## Install

### From marketplace

```
/plugin marketplace add kodareef5/plan-guard
/plugin install plan-guard
```

### Local install (for testing)

```bash
claude --plugin-dir ./plan-guard
```

## Usage

Once installed, `plan-guard` runs automatically. No configuration needed.

- **Backups** are stored in `~/.claude/plans/.backups/` (last 20 kept)
- **Recovery files** are created alongside the original with a `-recovered-<timestamp>` suffix
- Run `/plan-guard:plan-status` to see your backup inventory

## How It Works

### 1. PreCompact — Backup

Before every compaction (auto or manual), all plan files modified in the last 30 minutes are copied to `.backups/`.

### 2. SessionStart (compact) — Re-inject

After compaction, the most recent plan file's content (first 150 lines) is fed back to Claude as context, so it remembers the plan file path and contents.

### 3. PostToolUseFailure — Recovery

When a Write or Edit to a plan file fails:
1. Checks for a backup of that plan
2. Creates a new plan file with the backup content (or empty if no backup)
3. Tells Claude: "Write to this new file instead"

## Requirements

- `jq` (pre-installed on macOS, `apt install jq` on Linux)
- Claude Code with plugin support

## License

MIT

<!-- self-pin auto-bump enabled 2026-05-25 — see .github/workflows/bump-self-pin.yml -->
