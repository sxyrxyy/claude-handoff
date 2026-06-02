#!/usr/bin/env bash
# SessionEnd hook: run the summarizer one final time (synchronous, ignores debounce).
set -u
set -o pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
mkdir -p "$(dirname "$HANDOFF_LOG_PATH")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }

command -v jq >/dev/null 2>&1 || exit 0
PAYLOAD=$(cat 2>/dev/null || echo '{}')
CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD" 2>/dev/null); [ -z "$CWD" ] && CWD=$PWD
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)
export TRANSCRIPT

source "$PLUGIN_DIR/lib/preflight.sh"
preflight "$CWD"
BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null) || exit 0

source "$PLUGIN_DIR/lib/redact.sh"
source "$PLUGIN_DIR/lib/render.sh"
source "$PLUGIN_DIR/lib/refstore.sh"
source "$PLUGIN_DIR/lib/summarize.sh"
summarize_handoff "$BRANCH"
exit 0
