# TODO — grok-bridge / grok-plugin

Future work to make this as capable as the official Codex skills. The current
release is a working v1 (read-only review + adversarial review + worktree-isolated
rescue), usable both as a Claude Code plugin and a Codex/agents skill.

## Packaging / portability
- [ ] `install-skill.sh`: copy `skill/` into `~/.agents/skills/grok-bridge`,
      rewrite the hard-coded `~/.agents/skills/...` runner path to the installing
      user's home, and expose symlinks to `~/.codex/skills` and `~/.claude/skills`.
      (Right now the skill paths assume this author's machine layout.)
- [ ] Unify the runner source: `plugin/scripts` and `skill/scripts` are duplicate
      copies of the same `grok-run.sh` + `lib/common.sh`. Make one canonical source
      and have packaging copy it into both layouts.
- [ ] Provide PNG icons (raster) in addition to the SVGs for UI surfaces that need them.

## Features (Codex-skill parity)
- [ ] Background jobs: `--background` runs + `/grok:status` and `/grok:cancel`
      (the v1 deferred these; runner is currently synchronous/foreground only).
- [ ] Session resume: continue a previous grok conversation (`grok --continue`).
- [ ] `best-of-n`: expose `grok --best-of-n` for higher-quality rescue drafts.
- [ ] Self-verification: optional `grok --check` loop on rescue.
- [ ] Model selection passthrough (`--model`) and a sane effort default per model.
- [ ] More commands: `plan` (design alternatives before coding), `explain`,
      `test` (generate tests).
- [ ] Stop-time review gate hook (like the Codex plugin's `Stop` hook) to auto-run
      a grok review before a turn ends.
- [ ] `agents/openai.yaml` `dependencies`/`policy` blocks if/when MCP or implicit
      invocation tuning is needed.

## Robustness
- [ ] Detect `grok` not-logged-in vs network failure and give a targeted message.
- [ ] Streaming progress for long runs (`--output-format streaming-json`).
- [ ] CI: shellcheck the runners; smoke-test against a fixture repo.
- [ ] Handle very large diffs explicitly (chunking / summarize-then-review).
