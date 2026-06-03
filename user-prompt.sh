#!/usr/bin/env bash
# UserPromptSubmit hook: emit a one-line heads-up if another machine updated its
# handoff. Pure local reads (no network). Always exits 0 so it never blocks a
# prompt; prints at most one line of context to stdout.
set -u
set -o pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
mkdir -p "$(dirname "$HANDOFF_LOG_PATH")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null || echo '{}')
CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD" 2>/dev/null); [ -z "$CWD" ] && CWD=$PWD

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
export REPO_ROOT
BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null) || exit 0

source "$PLUGIN_DIR/lib/refstore.sh"
source "$PLUGIN_DIR/lib/headsup.sh"
headsup_line "$BRANCH" 2>>"$HANDOFF_LOG_PATH" || true
exit 0
