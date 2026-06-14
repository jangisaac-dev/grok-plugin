#!/usr/bin/env bash
# common.sh — shared helpers for the local AI bridge runners (grok / agy).
# Sourced by grok-run.sh and agy-run.sh. No `set -e`: callers handle status
# explicitly so a non-zero `git diff` etc. never aborts the run mid-way.
set -uo pipefail

# --- repo / workspace resolution ------------------------------------------

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# new_job_dir <tool>  ->  prints an empty, collision-free job dir under
# <repo>/.ai-runs/<tool>/. Artifacts for one run live here.
new_job_dir() {
  local tool="$1" base
  base="$(repo_root)/.ai-runs/$tool"
  mkdir -p "$base"
  mktemp -d "$base/$(date +%Y%m%d-%H%M%S)-XXXXXX"
}

# collect_context <out_file> : current branch + diffs + changed files, or a
# plain listing when not in a git repo.
collect_context() {
  local out="$1"
  {
    echo "# Repository context"
    echo
    if is_git_repo; then
      echo "## Branch"
      git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)"
      echo
      echo "## Changed files (git status --short)"
      git status --short 2>/dev/null
      echo
      echo "## Unstaged diff"
      echo '```diff'
      git diff 2>/dev/null
      echo '```'
      echo
      echo "## Staged diff"
      echo '```diff'
      git diff --staged 2>/dev/null
      echo '```'
    else
      echo "(not a git repository — top-level listing)"
      ls -la 2>/dev/null
    fi
  } >"$out"
}

# --- isolated workspace (worktree / copy) ---------------------------------
# make_workspace : prints a path to an isolated checkout of the repo so a
# write-capable CLI run never touches the live working tree. git repos get a
# detached worktree; otherwise an rsync copy. Workspace lives outside the repo
# (system temp) to avoid nested-worktree confusion.
make_workspace() {
  local ws
  ws="$(mktemp -d "${TMPDIR:-/tmp}/aibridge-ws.XXXXXX")"
  if is_git_repo && git worktree add --detach "$ws" HEAD >/dev/null 2>&1; then
    # Mirror the current working tree's uncommitted (tracked) changes into the
    # workspace so the CLI builds on the user's actual state, then commit them as
    # a baseline. capture_diff (git diff --cached HEAD) then shows ONLY the CLI's
    # edits, not the user's pre-existing changes.
    git diff HEAD 2>/dev/null | git -C "$ws" apply --whitespace=nowarn >/dev/null 2>&1 || true
    # also bring untracked, non-ignored files so the CLI sees the full working state
    local root; root="$(repo_root)"
    git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
      mkdir -p "$ws/$(dirname "$f")" && cp "$root/$f" "$ws/$f" 2>/dev/null || true
    done
    git -C "$ws" add -A >/dev/null 2>&1
    git -C "$ws" -c user.email=ai@bridge -c user.name=aibridge \
      commit -q -m "aibridge baseline" >/dev/null 2>&1 || true
    printf '%s\tgit\n' "$ws"
  else
    rsync -a --delete --exclude '.ai-runs' --exclude '.git' "$(repo_root)/" "$ws/" >/dev/null 2>&1
    printf '%s\tcopy\n' "$ws"
  fi
}

# capture_diff <ws> <kind> <out.diff> : write a unified diff of the changes the
# CLI made inside the workspace. Returns 0 if there were changes.
capture_diff() {
  local ws="$1" kind="$2" out="$3"
  if [ "$kind" = "git" ]; then
    git -C "$ws" add -A >/dev/null 2>&1
    git -C "$ws" diff --cached HEAD -- . \
      ':(exclude)**/__pycache__/**' ':(exclude)**/*.pyc' \
      ':(exclude)**/node_modules/**' ':(exclude)**/.DS_Store' >"$out" 2>/dev/null
  else
    # non-git copy: best-effort changed-file listing (no baseline to diff).
    {
      echo "# non-git workspace — changed/added files (mtime within run)"
      find "$ws" -type f -newer "$ws/.aibridge-start" 2>/dev/null | sed "s#$ws/##"
    } >"$out"
  fi
  [ -s "$out" ]
}

remove_workspace() {
  local ws="$1" kind="$2"
  if [ "$kind" = "git" ]; then
    git worktree remove --force "$ws" >/dev/null 2>&1 || rm -rf "$ws"
  else
    rm -rf "$ws"
  fi
}

# --- status ---------------------------------------------------------------

# write_status <dir> <command> <mode> <exit_code> <status> [extra_diff_path]
write_status() {
  local dir="$1" cmd="$2" mode="$3" code="$4" status="$5" diff="${6:-}"
  local diff_field=""
  [ -n "$diff" ] && diff_field=",
  \"changes_diff\": \"$diff\""
  cat >"$dir/status.json" <<EOF
{
  "job_id": "$(basename "$dir")",
  "command": "$cmd",
  "mode": "$mode",
  "exit_code": $code,
  "status": "$status",
  "ended_at": "$(now_utc)"$diff_field
}
EOF
}

# final_exit <status> : map a run status to a shell exit code so failures
# propagate to callers / pipelines instead of being masked as success.
final_exit() {
  case "${1:-}" in
    ok|no_changes) exit 0 ;;
    *) exit 1 ;;
  esac
}

# emit_result_pointer <dir> [diff_path] : final stdout line(s) Claude reads to
# locate the artifacts.
emit_result_pointer() {
  local dir="$1" diff="${2:-}"
  echo
  echo "=== AI bridge run complete ==="
  echo "job_dir: $dir"
  [ -f "$dir/result.md" ] && echo "result:  $dir/result.md"
  [ -n "$diff" ] && [ -f "$diff" ] && echo "diff:    $diff"
  echo "status:  $dir/status.json"
  echo "(Reminder: add .ai-runs/ to this repo's .gitignore.)"
}
