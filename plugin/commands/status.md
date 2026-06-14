---
description: List recent grok jobs (or show one) from .ai-runs/grok, including background job state
argument-hint: '[job-id]'
disable-model-invocation: true
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" status "$ARGUMENTS"`

Render the output above for the user.

- Without a job-id it is a table of recent runs in this repo. Keep it compact.
  A `running?` status means the job's process is gone before it finalized
  (likely crashed) — point the user at that job's `worker.log`.
- With a job-id, present the full status. For a `running` job the line below the
  JSON says whether the process is still alive.
