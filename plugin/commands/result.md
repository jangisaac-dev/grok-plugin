---
description: Show the latest (or a specified) saved Grok run from .ai-runs/grok
argument-hint: '[job-id]'
allowed-tools: Bash(bash:*)
---

!`bash -c 'set -e; root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; base="$root/.ai-runs/grok"; id="$1"; if [ -n "$id" ]; then case "$id" in */*|*..*) echo "invalid job-id"; exit 0;; esac; dir="$base/$id"; else dir="$(ls -dt "$base"/*/ 2>/dev/null | head -1)"; fi; [ -d "$dir" ] || { echo "No grok run found under $base"; exit 0; }; echo "# Run: $(basename "$dir")"; echo; echo "## status.json"; cat "$dir/status.json" 2>/dev/null; echo; if [ -f "$dir/changes.diff" ]; then echo "## changes.diff"; cat "$dir/changes.diff"; echo; fi; echo "## result.md"; cat "$dir/result.md" 2>/dev/null || echo "(no result.md — see stderr.log)"' _ "$ARGUMENTS"`

Present the run above to the user. If a `changes.diff` is shown, remind the user
it has not been applied to the working tree.
