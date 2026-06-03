#!/usr/bin/env bash
# Detached wrapper: fetch handoff refs without blocking the hook.
# Args: REPO_ROOT
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT="${1:-}"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }
[ -n "$REPO_ROOT" ] || exit 0
source "$PLUGIN_DIR/lib/refstore.sh"
ref_fetch
exit 0
