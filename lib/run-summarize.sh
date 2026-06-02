#!/usr/bin/env bash
# Detached wrapper: sources deps and runs summarize_handoff.
# Args: REPO_ROOT BRANCH TRANSCRIPT
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT="${1:-}" TRANSCRIPT="${3:-}"
BRANCH="${2:-}"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }
source "$PLUGIN_DIR/lib/redact.sh"
source "$PLUGIN_DIR/lib/render.sh"
source "$PLUGIN_DIR/lib/refstore.sh"
source "$PLUGIN_DIR/lib/summarize.sh"
summarize_handoff "$BRANCH"
exit 0
