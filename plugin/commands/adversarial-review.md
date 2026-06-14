---
description: Run a read-only adversarial Grok review that attacks the current change
argument-hint: ''
allowed-tools: Read, Bash(bash:*)
---

Run a read-only adversarial Grok review — Grok deliberately attacks the current
change for weak assumptions and failure modes. Runs with `--permission-mode
plan` (no file modification possible).

Run this (use a generous timeout — up to 600000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" adversarial-review "$ARGUMENTS"
```

Then `Read` the printed `result.md` and present Grok's findings verbatim,
preserving the blockers / assumptions / failure-scenarios structure. Review-only:
do not act on the findings unless the user asks. If status is `capture_failed`,
show `stderr.log`.

Note: the repo context (git diff included) is sent to the grok backend.
