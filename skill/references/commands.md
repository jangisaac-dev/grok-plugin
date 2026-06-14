# grok-bridge — command reference

Runner: `bash $HOME/.agents/skills/grok-bridge/scripts/grok-run.sh <command> [args]`
Run from the user's repo dir, with escalated permissions (see `codex-network.md`).

## Commands

### `review`  (read-only)
```bash
bash …/grok-run.sh review [--effort <low|medium|high>]
```
Reviews the current local git changes for bugs, security, regressions, missing
tests. Runs grok with `--permission-mode plan` → file writes are hard-blocked.
`--effort` is optional and model-dependent (the default fast model rejects it
with HTTP 400 — omit unless asked).

### `adversarial-review`  (read-only)
```bash
bash …/grok-run.sh adversarial-review [--effort <…>]
```
Same read-only mode; grok attacks the change for weak assumptions, hidden
coupling, and production failure modes. Output is structured as blockers /
high-risk assumptions / failure scenarios / simpler alternatives / verdict.

### `rescue "<task>"`  (write)
```bash
bash …/grok-run.sh rescue "add a zero-division guard to divide()"
```
Implements a focused fix. Runs in an isolated git worktree with
`--permission-mode bypassPermissions` (the only headless mode that actually
executes multi-step edits). The live working tree is never modified; the edit is
captured as `changes.diff`.

## Artifacts — `<repo>/.ai-runs/grok/<job-id>/`

| file | meaning |
|---|---|
| `prompt.md` | the exact prompt sent to grok |
| `context.txt` | branch + git diff used as context |
| `result.json` | raw grok JSON (`.text` = answer, or `{type:error}`) |
| `result.md` | extracted answer (`jq -r '.text'`) |
| `changes.diff` | (rescue) the proposed edit — NOT applied |
| `stderr.log` | grok stderr |
| `status.json` | run metadata (below) |

## `status.json` status values

| status | meaning | action |
|---|---|---|
| `ok` | success | present `result.md` (and `changes.diff` for rescue) |
| `no_changes` | rescue produced no edits | tell the user; show `result.md` |
| `error` | grok returned an error / nonzero exit | show `result.md` + `stderr.log` |
| `capture_failed` | empty/unparseable output | show `stderr.log` |
| `timed_out` | killed by timeout | suggest rerun / narrower task |

The runner exits non-zero unless status is `ok` or `no_changes`.

## The worktree (rescue)

The worktree mirrors the user's current working state — tracked uncommitted
changes AND untracked non-ignored files — then commits a baseline, so
`changes.diff` shows ONLY grok's edits, not the user's pre-existing work.
`.gitignore`d files are not visible. Non-git repos fall back to an rsync copy.
