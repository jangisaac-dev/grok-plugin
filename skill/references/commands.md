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

### `setup`  (read-only, local)
```bash
bash …/grok-run.sh setup
```
Reports whether `grok` is on PATH, its version, and whether `~/.grok/auth.json`
exists (logged in). No network call. Use it to diagnose a "CLI not found" or
auth error before a real run.

## Background jobs

Add `--background` (or `-b`) to any run command (`review`, `adversarial-review`,
`rescue`) to start it detached and return a `job_id` immediately instead of
blocking. The job runs the same pipeline in a disowned subshell and writes its
final `status.json` when done.

### `status [job-id]`
```bash
bash …/grok-run.sh status            # table of recent jobs in this repo
bash …/grok-run.sh status <job-id>   # full status for one job
```
A `running?` status means the job's process is gone before it finalized (likely
crashed) — check that job's `worker.log`.

### `cancel [job-id]`
```bash
bash …/grok-run.sh cancel            # cancel the most recent running job
bash …/grok-run.sh cancel <job-id>
```
Kills the job's process tree, removes its isolated worktree (even if `grok` was
killed mid-`worktree add`), and marks the job `cancelled`.

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
| `worker.log` | (background) the detached run's stdout/stderr |
| `job.pid` | (background) PID of the running job, for `status`/`cancel` |

## `status.json` status values

| status | meaning | action |
|---|---|---|
| `running` | background job still in progress | check later with `status` |
| `ok` | success | present `result.md` (and `changes.diff` for rescue) |
| `no_changes` | rescue produced no edits | tell the user; show `result.md` |
| `error` | grok returned an error / nonzero exit | show `result.md` + `stderr.log` |
| `capture_failed` | empty/unparseable output | show `stderr.log` |
| `cancelled` | stopped via `cancel` | run was killed; worktree cleaned up |
| `timed_out` | killed by timeout | suggest rerun / narrower task |

The runner exits non-zero unless status is `ok` or `no_changes`.

## The worktree (rescue)

The worktree mirrors the user's current working state — tracked uncommitted
changes AND untracked non-ignored files — then commits a baseline, so
`changes.diff` shows ONLY grok's edits, not the user's pre-existing work.
`.gitignore`d files are not visible. Non-git repos fall back to an rsync copy.
