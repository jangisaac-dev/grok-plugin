---
description: Check whether the local grok CLI is installed and authenticated
argument-hint: ''
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/grok-run.sh" setup`

Present the readiness report to the user. This check is local only — it does not
make a network call. If the CLI is `NOT FOUND`, tell the user to install `grok`
and then run `grok login`. If `auth` is not detected, tell them to run
`grok login`. Do not attempt to install or authenticate on the user's behalf.
