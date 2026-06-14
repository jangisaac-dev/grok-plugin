#!/usr/bin/env bash
# grok-run.sh — call the local `grok` CLI as a Claude Code helper.
#
#   grok-run.sh review              [--effort <lvl>]
#   grok-run.sh adversarial-review  [--effort <lvl>]
#   grok-run.sh rescue              [--effort <lvl>] <task text...>
#
# review / adversarial-review : read-only. Runs in the live repo with
#   `--permission-mode plan`, which hard-blocks writes (verified).
# rescue : write-capable. Runs in an isolated git worktree with
#   `--permission-mode bypassPermissions`, captures the diff, and leaves integration
#   to Claude / the user. The live working tree is never modified directly.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

COMMAND="${1:-review}"; shift || true

# Slash commands pass their whole argument string as one quoted "$ARGUMENTS"
# (injection-safe). Re-split it in-process so flags + task text parse normally.
# This only word-splits a data string (set -f disables globbing); it is never
# eval'd, so a ';' in the task text stays a literal arg, not a command.
if [ "$#" -le 1 ]; then set -f; set -- ${1-}; set +f; fi

# status / cancel / setup operate on existing jobs (or report a missing CLI), so
# they must run before the `command -v grok` guard and before any job dir is made.
case "$COMMAND" in
  status) cmd_status grok "${1:-}"; exit 0 ;;
  cancel) cmd_cancel grok "${1:-}"; exit 0 ;;
  setup)  cmd_setup  grok grok "$HOME/.grok/auth.json"; exit 0 ;;
esac

EFFORT=""
BACKGROUND=0
TASK_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --effort) EFFORT="${2:-}"; shift 2 || shift ;;
    --background|-b) BACKGROUND=1; shift ;;
    *) TASK_ARGS+=("$1"); shift ;;
  esac
done
TASK_TEXT="${TASK_ARGS[*]:-}"

if ! command -v grok >/dev/null 2>&1; then
  echo "ERROR: 'grok' CLI not found on PATH. Install it and run 'grok login' first." >&2
  exit 127
fi

if [ "$COMMAND" = "rescue" ] && [ -z "$TASK_TEXT" ]; then
  echo "ERROR: rescue needs a task description." >&2; exit 2
fi
case "$COMMAND" in
  review|adversarial-review|rescue) : ;;
  *) echo "Unknown command: $COMMAND" >&2; exit 2 ;;
esac

JOB_DIR="$(new_job_dir grok)"
collect_context "$JOB_DIR/context.txt"

# --- prompt templates ------------------------------------------------------

review_prompt() {
  cat <<'EOF'
You are Grok running as a local secondary reviewer for this repository.

Task: review the provided git diff and repository context.

Focus: correctness bugs, security risks, regression risk, unnecessary
complexity, missing tests, edge cases, maintainability.

Rules:
- Do not rewrite the whole solution. Do not modify files.
- Do not suggest unrelated architecture changes.
- Return concise, actionable findings, prioritized by severity.
- If no serious issue exists, say so directly.

Output:
1. Critical issues
2. Important issues
3. Minor suggestions
4. Missing tests
5. Final verdict
EOF
}

adversarial_prompt() {
  cat <<'EOF'
You are Grok running as an adversarial reviewer.

Task: attack the current change. Assume it may be subtly wrong. Find the
weakest assumptions, hidden coupling, bad abstractions, and cases where this
fails in production.

Rules:
- Be concrete; cite exact files / functions / diff sections.
- Do not be polite. Do not invent issues.
- Separate real blockers from preferences. Do not modify files.

Output:
- Blockers
- High-risk assumptions
- Failure scenarios
- Simpler alternatives
- Final verdict
EOF
}

rescue_prompt() {
  cat <<'EOF'
You are Grok running as a local implementation helper in an ISOLATED worktree
(a throwaway checkout). Your edits here do not touch the user's working tree;
they are captured as a diff for the user to review and apply.

Rules:
- Keep changes minimal and focused on the requested task.
- Do not touch authentication, tokens, secrets, or deployment config.
- Do not run destructive or deploy commands.
- Prefer small, isolated edits. Add or update tests when relevant.

Requested task:
EOF
  printf '%s\n' "$TASK_TEXT"
}

# --- assemble prompt.md ----------------------------------------------------

{
  case "$COMMAND" in
    review)              review_prompt ;;
    adversarial-review)  adversarial_prompt ;;
    rescue)              rescue_prompt ;;
    *) echo "Unknown command: $COMMAND" >&2; exit 2 ;;
  esac
  echo
  echo "---"
  echo
  cat "$JOB_DIR/context.txt"
} >"$JOB_DIR/prompt.md"

GROK_COMMON=(--prompt-file "$JOB_DIR/prompt.md" --output-format json)
# --effort is only supported by some models (e.g. fast models reject it). Pass
# through only when the user explicitly asked; never default it.
[ -n "$EFFORT" ] && GROK_COMMON+=(--effort "$EFFORT")

# extract_outcome <result.json> <result.md> : writes result.md and prints the
# derived status (ok | error | capture_failed).
extract_outcome() {
  local json="$1" md="$2"
  if [ ! -s "$json" ]; then echo "capture_failed"; return; fi
  if [ "$(jq -r '.type // empty' "$json" 2>/dev/null)" = "error" ]; then
    jq -r '.message // "unknown grok error"' "$json" >"$md" 2>/dev/null
    echo "error"; return
  fi
  jq -r '.text // empty' "$json" >"$md" 2>/dev/null
  [ -s "$md" ] && echo "ok" || echo "capture_failed"
}

# execute_job : the heavy part (CLI call + diff + final status). Run inline for
# foreground, or inside a disowned subshell for --background.
execute_job() {
  case "$COMMAND" in
    review|adversarial-review)
      MODE="read-only"
      grok "${GROK_COMMON[@]}" --permission-mode plan \
        >"$JOB_DIR/result.json" 2>"$JOB_DIR/stderr.log"
      CODE=$?
      STATUS="$(extract_outcome "$JOB_DIR/result.json" "$JOB_DIR/result.md")"
      [ "$CODE" -ne 0 ] && [ "$STATUS" = "ok" ] && STATUS="error"
      [ "$STATUS" != "ok" ] && echo "WARNING: grok status=$STATUS (exit $CODE; see stderr.log / result.md)." >&2
      write_status "$JOB_DIR" "$COMMAND" "$MODE" "$CODE" "$STATUS"
      emit_result_pointer "$JOB_DIR"
      ;;

    rescue)
      MODE="write"
      IFS=$'\t' read -r WS WS_KIND < <(make_workspace "$JOB_DIR/workspace.path")
      [ "$WS_KIND" = "copy" ] && touch "$WS/.aibridge-start"
      # bypassPermissions is the only mode that actually executes multi-step edits
      # in headless `-p` (default/acceptEdits/auto only announce). Safe here because
      # the run is confined to a throwaway worktree.
      ( cd "$WS" && grok "${GROK_COMMON[@]}" --permission-mode bypassPermissions ) \
        >"$JOB_DIR/result.json" 2>"$JOB_DIR/stderr.log"
      CODE=$?
      OUTCOME="$(extract_outcome "$JOB_DIR/result.json" "$JOB_DIR/result.md")"
      DIFF="$JOB_DIR/changes.diff"
      if [ "$OUTCOME" = "error" ] || [ "$CODE" -ne 0 ]; then
        STATUS="error"; : >"$DIFF"
      elif capture_diff "$WS" "$WS_KIND" "$DIFF"; then
        STATUS="ok"
      else
        STATUS="no_changes"
      fi
      remove_workspace "$WS" "$WS_KIND"
      rm -f "$JOB_DIR/workspace.path"
      write_status "$JOB_DIR" "$COMMAND" "$MODE" "$CODE" "$STATUS" "$DIFF"
      [ "$STATUS" = "error" ] && echo "WARNING: grok status=error (exit $CODE; see stderr.log)." >&2
      emit_result_pointer "$JOB_DIR" "$DIFF"
      ;;
  esac
  final_exit "$STATUS"
}

if [ "$BACKGROUND" -eq 1 ]; then
  write_running_status "$JOB_DIR" "$COMMAND" "$([ "$COMMAND" = rescue ] && echo write || echo read-only)"
  ( execute_job ) >"$JOB_DIR/worker.log" 2>&1 &
  echo $! >"$JOB_DIR/job.pid"
  disown 2>/dev/null || true
  emit_background_pointer "$JOB_DIR" grok
  exit 0
fi

execute_job
