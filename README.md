# grok-plugin — local Grok bridge for Claude Code

Call the local `grok` CLI from Claude Code as a secondary reviewer / write-capable
helper. No server, no token sharing — uses your own `grok login` session.

## Install

```bash
./install.sh --dry-run   # preview
./install.sh --apply     # register local marketplace + enable plugin
```

Then start a new Claude Code session. `install` snapshot-copies the plugin into
`~/.claude/plugins/cache/`, so **after editing the source, re-install** to refresh
it: `claude plugin uninstall grok@grok-local && claude plugin install grok@grok-local`
(same version is otherwise cached).

## Commands

| Command | Mode | What it does |
|---|---|---|
| `/grok:review` | read-only | Review local git changes. Runs with `--permission-mode plan` (hard-blocks writes). |
| `/grok:adversarial-review` | read-only | Attacks the change for weak assumptions / failure modes. |
| `/grok:rescue <task>` | write | Implements a focused fix in an isolated git worktree; returns a diff to review. Live tree is never modified directly. |
| `/grok:setup` | — | Check that `grok` is installed + logged in (local, no network call). |
| `/grok:status [job-id]` | — | List recent jobs (or show one), including background-job state. |
| `/grok:cancel [job-id]` | — | Stop a running background job and clean up its worktree. |
| `/grok:result [job-id]` | — | Show the latest (or given) saved run. |

Add `--background` (or `-b`) to `review` / `adversarial-review` / `rescue` to run
it detached: the command returns a `job_id` immediately, and you track it with
`/grok:status` and stop it with `/grok:cancel`.

## Safety

- read-only commands cannot write — verified at the CLI level (`--permission-mode plan`).
- `rescue` runs in a throwaway worktree; you apply the diff only after review.
- Repo context (git diff) is sent to the grok backend. No local secret scanner —
  this mirrors Codex and assumes your own trusted machine + auth.
- Artifacts are written to `<repo>/.ai-runs/grok/<job-id>/`. Add `.ai-runs/` to
  your repo `.gitignore`.
- `rescue` works on a copy of your current working state (tracked changes +
  untracked non-ignored files). Files excluded by `.gitignore` are not visible
  to it.

## Use as a Codex / agents skill

This repo also ships the same bridge as a self-contained skill under [`skill/`](skill/)
(SKILL.md + `agents/openai.yaml` + `references/` + `assets/` + bundled scripts), in
the format used by Codex and the `~/.agents/skills` hub.

To install it for Codex: copy `skill/` to `~/.agents/skills/grok-bridge`, then create
an absolute symlink `~/.codex/skills/grok-bridge -> ~/.agents/skills/grok-bridge`
(and `~/.claude/skills/grok-bridge` for Claude), and restart Codex.

> Note: the skill currently references its runner by an absolute
> `~/.agents/skills/grok-bridge/...` path. A portable `install-skill.sh` that
> rewrites this on install is tracked in [TODO.md](TODO.md).

Inside Codex, the skill asks before running outside the sandbox (grok needs network
+ `~/.grok` access); under Claude Code it runs directly. Same commands either way.

## Repo layout

- `plugin/` — Claude Code plugin (commands, internal skill, runner scripts).
- `.claude-plugin/marketplace.json`, `install.sh` — local-marketplace install.
- `skill/` — Codex/agents skill version of the same bridge.
- `GROK_BRIDGE_PROJECT.md` — original design spec. `TODO.md` — roadmap.

The runner logic (`grok-run.sh` + `lib/common.sh`) is currently duplicated in
`plugin/scripts/` and `skill/scripts/`; unifying it is a TODO.

## Requirements

`grok` (logged in), `git`, `jq`, `bash`. `claude` CLI for `install.sh`.
