#!/usr/bin/env bash
# install.sh — register the grok bridge as a local marketplace and enable it.
#
#   ./install.sh --dry-run   # show what would happen, change nothing
#   ./install.sh --apply     # register + enable via the official `claude` CLI
#
# Uses the official `claude plugin` CLI, which edits ~/.claude config safely
# (atomic, validated). We do not hand-edit settings.json.
set -uo pipefail

MARKET_NAME="grok-local"
PLUGIN_NAME="grok"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:---dry-run}"

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found on PATH." >&2
  exit 127
fi

echo "Plugin path : $HERE"
echo "Marketplace : $MARKET_NAME"
echo "Plugin      : $PLUGIN_NAME@$MARKET_NAME"
echo

case "$MODE" in
  --dry-run)
    echo "[dry-run] Would run:"
    echo "  claude plugin marketplace add \"$HERE\""
    echo "  claude plugin install $PLUGIN_NAME@$MARKET_NAME"
    echo
    echo "Re-run with --apply to perform these steps."
    ;;
  --apply)
    echo "==> claude plugin marketplace add"
    claude plugin marketplace add "$HERE" || {
      echo "marketplace add failed (may already exist — continuing)" >&2
    }
    echo "==> claude plugin install"
    claude plugin install "$PLUGIN_NAME@$MARKET_NAME" || {
      echo "ERROR: plugin install failed." >&2; exit 1
    }
    echo
    echo "Done. Start a new Claude Code session and try /grok:review."
    ;;
  *)
    echo "Usage: $0 [--dry-run|--apply]" >&2
    exit 2
    ;;
esac
