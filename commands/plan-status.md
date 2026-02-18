---
description: Show plan-guard backup status and plan file inventory
disable-model-invocation: true
---

Check the plan-guard backup status by running:

```bash
echo "=== Active Plan Files ==="
ls -lt ~/.claude/plans/*.md 2>/dev/null | head -10 || echo "No plan files found"

echo ""
echo "=== Plan Backups ==="
ls -lt ~/.claude/plans/.backups/*.md 2>/dev/null | head -20 || echo "No backups found"

echo ""
echo "=== Backup Disk Usage ==="
du -sh ~/.claude/plans/.backups/ 2>/dev/null || echo "No backup directory"
```

Report the results to the user in a clear summary.
