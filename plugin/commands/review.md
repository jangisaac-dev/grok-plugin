---
description: Run a read-only Grok review against local git state
argument-hint: ''
allowed-tools: Read, Bash(bash:*)
---

Run a read-only Grok review of the current local changes. Grok runs with
`--permission-mode plan`, which hard-blocks any file modification.

Run this (use a generous timeout — up to 600000 ms — since a review may take
minutes):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" review "$ARGUMENTS"
```

Then `Read` the `result.md` path printed by the command and present Grok's
findings to the user. This command is review-only: do not apply fixes yourself
unless the user explicitly asks. If the status is `capture_failed`, tell the
user and show `stderr.log`.

Note: the repo context (including the git diff) is sent to the grok backend for
analysis. Mention this if the user has not already accepted it.
