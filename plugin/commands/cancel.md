---
description: Cancel a running background grok job in this repository
argument-hint: '[job-id]'
disable-model-invocation: true
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" cancel "$ARGUMENTS"`

Tell the user the result. Without a job-id, the most recent running job is
cancelled. Cancelling kills the job's process tree and cleans up its isolated
worktree, then marks the job `cancelled`.
