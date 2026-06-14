---
description: Delegate a focused fix to Grok in an isolated worktree, then review its diff
argument-hint: '<task description>'
allowed-tools: Read, Bash(bash:*), Bash(git:*)
---

Delegate a focused implementation task to Grok. Grok works in an **isolated git
worktree** (a throwaway checkout) with `--permission-mode bypassPermissions` (the
only headless mode that actually performs edits), so it can edit files there
without ever touching the user's live working tree. Safety comes from the
worktree isolation, not from the permission mode. The result is captured as a
diff for review.

Run this (use a generous timeout — up to 600000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" rescue "$ARGUMENTS"
```

The command prints a `diff:` path and a `result:` path. Then:
1. `Read` the `changes.diff` and `result.md`.
2. Present Grok's proposed changes and reasoning to the user.
3. Integration into the live working tree is **your** responsibility — apply the
   diff only after the user approves (e.g. `git apply <changes.diff>` or by
   re-creating the edits). Do not apply blindly.

If status is `no_changes`, tell the user Grok proposed no edits and show
`result.md`. Note: the task text and repo context are sent to the grok backend.
