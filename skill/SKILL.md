---
name: grok-bridge
description: Call the local grok CLI as a secondary code reviewer or write-capable fixer. Use when the user wants a second-opinion review of local git changes, an adversarial critique of a change, or to delegate a focused fix to grok and get back a reviewable diff. Read-only reviews never modify files; fixes run in an isolated worktree and return a diff to apply.
metadata:
  author: Isaac-dev
---

# grok-bridge

Run the local `grok` CLI as a helper from inside the user's project, on their own
`grok login` session. grok gives a strong independent second opinion and, unlike
the sibling `agy-bridge`, has a **hard read-only mode**.

## Execution environment

**Claude Code (and any runtime that does not sandbox shell commands):** run the
runner directly — no sandbox prompt, nothing extra. Skip to "Runner".

**Codex only:** Codex sandboxes shell commands by default, and `grok` needs
outbound network + write access to `~/.grok` (outside the workspace), so a
sandboxed run fails (`FS_PERMISSION_DENIED`, `Settings fetch failed`, `127.0.0.1:0`
bind). So, **when running under Codex**:
1. **Ask the user first**, e.g. "이 스킬은 grok 백엔드 호출과 `~/.grok` 접근 때문에 Codex 샌드박스 밖(escalated)에서 실행해야 합니다. 진행할까요?"
2. On approval, run the runner with escalated permissions (`sandbox_permissions=require_escalated`). Do not silently retry inside the sandbox.

Details / permanent fix: `references/codex-network.md`.

## Runner

```bash
bash $HOME/.agents/skills/grok-bridge/scripts/grok-run.sh <command> [args]
```

Run from the user's repo directory, with a generous timeout (1–4 min). It prints
a `result:` path (and `diff:` for `rescue`) and exits non-zero on failure.

| Command | Mode | Use for |
|---|---|---|
| `review` | read-only (hard) | Review current git changes for bugs/security/regressions. |
| `adversarial-review` | read-only (hard) | Attack the change — weak assumptions, failure modes. |
| `rescue "<task>"` | write (worktree) | Implement a focused fix; returns a diff to apply. |

read-only commands use `--permission-mode plan` (writes hard-blocked). `rescue`
runs in a throwaway git worktree and never touches the live tree.

## After a run

- Read the printed `result.md` and relay grok's findings (a second opinion, not
  ground truth). For `review`/`adversarial-review`, don't change code unless asked.
- For `rescue`: read `changes.diff`, show it, and apply only with user approval
  (`git apply …/changes.diff`), then verify.
- Check `status.json`: `ok` / `no_changes` / `error` / `capture_failed` / `timed_out`.
  On `error`/`capture_failed`, show `stderr.log`.

See `references/commands.md` for the full command/flag/status/artifact reference,
and `references/workflow.md` for choosing commands, grok-vs-agy, and applying diffs.

## Notes

- Repo context (git diff) is sent to grok's backend; there is no local secret
  scanner — assumes the user's own trusted machine and auth.
- Remind the user to add `.ai-runs/` to their repo `.gitignore`.
- Requires `grok` (logged in), `git`, `jq`, `bash`.
