#!/usr/bin/env bash
# Stop hook entry point. Always exits 0; any failure logs and bails.
set -u
set -o pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
mkdir -p "$(dirname "$HANDOFF_LOG_PATH")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }

command -v jq >/dev/null 2>&1 || { log "jq not found, skipping"; exit 0; }

PAYLOAD=$(cat 2>/dev/null || echo '{}')
CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD" 2>/dev/null); [ -z "$CWD" ] && CWD=$PWD
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)
export TRANSCRIPT

source "$PLUGIN_DIR/lib/preflight.sh"
preflight "$CWD"

source "$PLUGIN_DIR/lib/redact.sh"
source "$PLUGIN_DIR/lib/capture.sh"
source "$PLUGIN_DIR/lib/render.sh"
source "$PLUGIN_DIR/lib/refstore.sh"
source "$PLUGIN_DIR/lib/debounce.sh"

capture_state

# Preserve any existing narrative from the ref.
prior=$(ref_read "$CAP_BRANCH" "HANDOFF.md")
narrative=$(printf '%s' "$prior" | extract_narrative)
body=$(render_handoff "$narrative")

# Keep the existing journal as-is (summarizer owns it).
journal=$(ref_read "$CAP_BRANCH" "HANDOFF-LOG.md")

if ref_write "$CAP_BRANCH" "HANDOFF.md" "$body" "HANDOFF-LOG.md" "$journal"; then
  log "wrote refs/handoff/$CAP_BRANCH"
  # Push detached so a slow/unreachable remote never blocks the turn.
  ( nohup bash "$PLUGIN_DIR/lib/run-push.sh" "$REPO_ROOT" "$CAP_BRANCH" \
      >/dev/null 2>&1 & ) || true
fi

# Fire the summarizer detached if the debounce window has elapsed.
if command -v claude >/dev/null 2>&1 && debounce_ok "$REPO_ROOT" "$CAP_BRANCH"; then
  ( nohup bash "$PLUGIN_DIR/lib/run-summarize.sh" "$REPO_ROOT" "$CAP_BRANCH" "$TRANSCRIPT" \
      >/dev/null 2>&1 & ) || true
  log "spawned summarizer for $CAP_BRANCH"
fi

exit 0
