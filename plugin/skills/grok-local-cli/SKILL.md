---
name: grok-local-cli
description: Internal contract for calling the local grok CLI runner from the grok bridge commands
user-invocable: false
---

# Grok local CLI runtime

Internal helper notes for the `/grok:*` commands. Not user-invokable.

## Runner

All commands shell out to one script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" <command> [--effort <lvl>] [task...]
```

Commands: `review`, `adversarial-review` (read-only), `rescue` (write-capable).
`result` reads `.ai-runs/grok/` directly and does not call the CLI.

## Safety model (verified, not assumed)

- **read-only** (`review`, `adversarial-review`): grok runs in the live repo
  with `--permission-mode plan`. This hard-blocks file writes at the CLI level —
  verified by probe (write attempts leave files untouched). Safe on the live tree.
- **write** (`rescue`): grok runs in an isolated git worktree (or rsync copy for
  non-git repos) with `--permission-mode bypassPermissions` (the only headless mode
  that performs edits — safety comes from the worktree isolation, not the mode).
  Edits land in the throwaway workspace, are captured as `changes.diff`, and the
  workspace is removed. The live working tree is never modified by grok; integration
  is done by Claude/the user after the user approves the diff.

## Artifacts

Each run writes to `<repo>/.ai-runs/grok/<job-id>/`:
`prompt.md`, `context.txt`, `result.json`, `result.md`, `status.json`,
`stderr.log`, and (rescue) `changes.diff`.

`status` values: `ok`, `no_changes`, `capture_failed` (empty/unparseable output),
`timed_out`.

## Rules

- Prefer the runner over hand-rolled `grok` invocations.
- Never apply a `rescue` diff without explicit user approval.
- Do not weaken the read-only commands to write mode.
- The repo context (git diff) is sent to the grok backend; surface this to the
  user. There is no local secret scanner — this mirrors how Codex operates and
  assumes the user runs on their own trusted machine with their own auth.
- Remind users to add `.ai-runs/` to their repo `.gitignore`.
