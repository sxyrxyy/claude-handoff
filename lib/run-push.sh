#!/usr/bin/env bash
# Detached wrapper: push the handoff ref without blocking the hook.
# Args: REPO_ROOT BRANCH
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT="${1:-}"
BRANCH="${2:-}"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }
[ -n "$REPO_ROOT" ] && [ -n "$BRANCH" ] || exit 0
source "$PLUGIN_DIR/lib/refstore.sh"
ref_push "$BRANCH"
exit 0
