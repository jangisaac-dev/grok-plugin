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
# make_workspace [record_file] : prints a path to an isolated checkout of the
# repo so a write-capable CLI run never touches the live working tree. git repos
# get a detached worktree; otherwise an rsync copy. Workspace lives outside the
# repo (system temp) to avoid nested-worktree confusion.
# If record_file is given, the "<path>\t<kind>" line is written there immediately
# after the temp dir is created — BEFORE `git worktree add` — so a job cancelled
# mid-creation can still find and remove the workspace (closes the leak window).
make_workspace() {
  local ws record="${1:-}" kind=copy
  # Defensive: drop any worktree entries orphaned by a crashed/cancelled run
  # before we add a new one (a cancelled background job may never reach cleanup).
  is_git_repo && git worktree prune >/dev/null 2>&1
  is_git_repo && kind=git
  ws="$(mktemp -d "${TMPDIR:-/tmp}/aibridge-ws.XXXXXX")"
  [ -n "$record" ] && printf '%s\t%s\n' "$ws" "$kind" >"$record"
  if [ "$kind" = git ] && git worktree add --detach "$ws" HEAD >/dev/null 2>&1; then
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
    # Not a git repo, or worktree add failed: fall back to an rsync copy and
    # correct the recorded kind so cleanup uses plain rm -rf.
    [ -n "$record" ] && printf '%s\tcopy\n' "$ws" >"$record"
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
    # `-f -f` (double force) overrides a worktree git marked "locked" — which
    # happens when `git worktree add` is killed mid-init (lock reason
    # "initializing"). Fall back to unlock + rm + prune for any other half-state.
    git worktree remove -f -f "$ws" >/dev/null 2>&1 || {
      git worktree unlock "$ws" >/dev/null 2>&1
      rm -rf "$ws"
      git worktree prune >/dev/null 2>&1
    }
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

# --- background jobs -------------------------------------------------------
# A background job is the same execute_job() run inside a disowned subshell. The
# parent records the subshell PID in <dir>/job.pid and writes an initial
# "running" status; the worker overwrites status.json when it finishes. PID and
# status live in separate files so the two writers never race.

# kill_tree <pid> : best-effort recursive kill of a process and its descendants.
# macOS has no setsid/`pkill -g`, so walk the tree via `pgrep -P`.
kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
  kill "$pid" 2>/dev/null || true
}

# write_running_status <dir> <command> <mode>
write_running_status() {
  local dir="$1" cmd="$2" mode="$3"
  cat >"$dir/status.json" <<EOF
{
  "job_id": "$(basename "$dir")",
  "command": "$cmd",
  "mode": "$mode",
  "status": "running",
  "started_at": "$(now_utc)"
}
EOF
}

# emit_background_pointer <dir> <tool>
emit_background_pointer() {
  local dir="$1" tool="$2"
  echo
  echo "=== AI bridge background job started ==="
  echo "job_id: $(basename "$dir")"
  echo "status: $dir/status.json (status=running)"
  echo "Check progress with the ${tool} 'status' command (optionally pass this job_id)."
  echo "Cancel with the ${tool} 'cancel' command."
}

# _job_dirs_newest_first <base> : print job dirs newest-first, one per line.
# Space-safe (job basenames are timestamped, so a reverse string sort = newest
# first) — avoids `$(ls -dt …)` word-splitting when the repo path contains spaces.
_job_dirs_newest_first() {
  local base="$1" d
  [ -d "$base" ] || return 0
  for d in "$base"/*/; do [ -d "$d" ] && printf '%s\n' "$d"; done | sort -r
}

# _bounded <secs> <cmd...> : run cmd with a hard timeout (macOS has no `timeout`).
# Used so cmd_setup's `--version` can never hang the whole command.
_bounded() {
  local secs="$1"; shift
  "$@" &
  local p=$!
  ( sleep "$secs"; kill "$p" 2>/dev/null ) >/dev/null 2>&1 &
  local w=$!
  wait "$p" 2>/dev/null; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}

# cmd_status <tool> [job-id] : list recent jobs as a table, or show one job.
cmd_status() {
  local tool="$1" id="${2:-}" base d st cmd when
  base="$(repo_root)/.ai-runs/$tool"
  if [ -n "$id" ]; then
    case "$id" in */*|*..*) echo "invalid job-id"; return 0;; esac
    [ -d "$base/$id" ] || { echo "No $tool job '$id' under $base"; return 0; }
    echo "# Job: $id"
    cat "$base/$id/status.json" 2>/dev/null; echo
    st="$(jq -r '.status // empty' "$base/$id/status.json" 2>/dev/null)"
    if [ "$st" = "running" ] && [ -f "$base/$id/job.pid" ]; then
      if kill -0 "$(cat "$base/$id/job.pid")" 2>/dev/null; then
        echo "(process alive — still running)"
      else
        echo "(process not found — job likely crashed before finishing; see worker.log)"
      fi
    fi
    return 0
  fi
  [ -d "$base" ] || { echo "No $tool runs yet under $base"; return 0; }
  printf '%-28s  %-18s  %-11s  %s\n' "JOB_ID" "COMMAND" "STATUS" "WHEN"
  while IFS= read -r d; do
    [ -f "$d/status.json" ] || continue
    st="$(jq -r '.status // "?"' "$d/status.json" 2>/dev/null)"
    cmd="$(jq -r '.command // "?"' "$d/status.json" 2>/dev/null)"
    when="$(jq -r '.ended_at // .started_at // "?"' "$d/status.json" 2>/dev/null)"
    if [ "$st" = "running" ] && [ -f "$d/job.pid" ] && ! kill -0 "$(cat "$d/job.pid")" 2>/dev/null; then
      st="running?"   # process gone before finalizing — likely crashed
    fi
    printf '%-28s  %-18s  %-11s  %s\n' "$(basename "$d")" "$cmd" "$st" "$when"
  done < <(_job_dirs_newest_first "$base")
  echo "(running? = process gone before it finalized — check that job's worker.log)"
}

# cmd_cancel <tool> [job-id] : cancel a running background job (default: most
# recent running one). Kills the process tree, cleans up any workspace the worker
# did not get to remove, and marks the job cancelled.
cmd_cancel() {
  local tool="$1" id="${2:-}" base dir d pid status ws wskind
  base="$(repo_root)/.ai-runs/$tool"
  if [ -n "$id" ]; then
    case "$id" in */*|*..*) echo "invalid job-id"; return 0;; esac
    dir="$base/$id"
  else
    while IFS= read -r d; do
      [ "$(jq -r '.status // empty' "$d/status.json" 2>/dev/null)" = "running" ] && { dir="${d%/}"; break; }
    done < <(_job_dirs_newest_first "$base")
  fi
  [ -n "${dir:-}" ] && [ -d "$dir" ] || { echo "No running $tool job to cancel under $base"; return 0; }

  # Only running jobs are cancellable. Guarding on status (not just `kill -0`)
  # prevents killing an unrelated process that reused a finished job's PID.
  status="$(jq -r '.status // empty' "$dir/status.json" 2>/dev/null)"
  if [ "$status" != "running" ]; then
    echo "Job $(basename "$dir") is '${status:-unknown}', not running — nothing to cancel."
    return 0
  fi

  pid=""
  [ -f "$dir/job.pid" ] && pid="$(cat "$dir/job.pid" 2>/dev/null)"
  if [ -z "$pid" ]; then
    # running but no PID yet → worker is still initializing. Refuse rather than
    # mark cancelled, which would mislabel a worker that is about to come alive.
    echo "Job $(basename "$dir") is still initializing (no pid yet) — retry cancel in a moment."
    return 0
  fi
  # Confirm the PID is actually our runner before killing (defends against PID
  # reuse after a crashed job left status stuck at "running").
  if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q "$tool-run.sh"; then
    kill_tree "$pid"
    echo "Cancelled job $(basename "$dir") (pid $pid)."
  else
    echo "Job $(basename "$dir") has no matching live process (finished or crashed) — cleaning up."
  fi
  # Clean up a workspace the worker never removed (prevents a leaked worktree).
  if [ -f "$dir/workspace.path" ]; then
    IFS=$'\t' read -r ws wskind < "$dir/workspace.path"
    [ -n "$ws" ] && remove_workspace "$ws" "$wskind"
    rm -f "$dir/workspace.path"
  fi
  is_git_repo && git worktree prune >/dev/null 2>&1
  write_status "$dir" "$(jq -r '.command // "?"' "$dir/status.json" 2>/dev/null)" \
    "$(jq -r '.mode // "?"' "$dir/status.json" 2>/dev/null)" 130 "cancelled" \
    "$([ -f "$dir/changes.diff" ] && echo "$dir/changes.diff")"
}

# cmd_setup <tool> <bin> <auth-path...> : report CLI readiness. No network calls,
# no commands that can hang — only PATH lookup, --version, and auth-file existence.
cmd_setup() {
  local tool="$1" bin="$2"; shift 2
  local p found=0
  echo "# $tool setup"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "- CLI: found ($(command -v "$bin"))"
    # Bound `--version` so a CLI that stalls on a startup/update check can't hang
    # setup (some CLIs probe the network on launch). Empty → report unknown.
    local ver; ver="$(_bounded 5 "$bin" --version 2>/dev/null | head -1)"
    echo "- version: ${ver:-(unknown — version check timed out or unavailable)}"
  else
    echo "- CLI: NOT FOUND on PATH — install '$bin', then authenticate."
    return 0
  fi
  for p in "$@"; do
    if [ -e "$p" ]; then echo "- auth: present ($p)"; found=1; break; fi
  done
  [ "$found" -eq 0 ] && echo "- auth: not detected — log in with '$bin' (looked for: $*)"
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
