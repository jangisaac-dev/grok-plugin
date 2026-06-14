# Codex sandbox / network notes for grok-bridge

The `grok` CLI calls a remote backend (network) and writes its own config/session
files outside the workspace (~/.grok). Codex's default sandbox blocks both, so runs
fail with FS_PERMISSION_DENIED, "Settings fetch failed", log-write errors, or
127.0.0.1:0 bind failures.

## Recommended: escalate that one command (per-run)

Run the runner with escalated permissions so it executes outside the sandbox for
that single command. Codex prompts the user to approve each time. In the shell
tool this is `sandbox_permissions=require_escalated`. Always ask the user first.

This is the safe option: the escalation is scoped to one command and re-confirmed
every time.

## If you are prompted on every run

That is expected — each networked / outside-workspace command is approved
individually. Do **not** disable Codex's sandbox or approval policy globally to
silence the prompts (e.g. a permanent `danger-full-access` + `approval_policy =
"never"`): that removes the safety boundary for **all** your work, not just this
skill, and is dangerous in any untrusted repo. Keep approvals on and escalate
per-run.

## Safety

The grok-bridge runner only ever modifies an isolated git worktree (or nothing, for
read-only commands) — it does not target your live working tree. Residual risk:
`grok`, running outside the sandbox, could in principle write to absolute paths
outside the worktree (no flag fully prevents this). Only run it on a trusted local
machine and repo.
