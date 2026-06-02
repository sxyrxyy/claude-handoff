# capture.sh - read git + transcript into CAP_* state variables.
# Expects REPO_ROOT. Exports CAP_* for the renderer.

source "$(dirname "${BASH_SOURCE[0]}")/redact.sh"

capture_state() {
  CAP_HOST=${HANDOFF_MACHINE_NAME:-$(hostname -s 2>/dev/null || hostname)}
  CAP_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  CAP_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD)
  CAP_LAST_COMMIT=$(git -C "$REPO_ROOT" log -1 --format='%h %s' 2>/dev/null || echo '(no commits)')
  CAP_STATUS=$(git -C "$REPO_ROOT" status -s 2>/dev/null | head -n 50)
  CAP_DIFFSTAT=$(git -C "$REPO_ROOT" diff --stat HEAD 2>/dev/null | head -n 30)
  CAP_EDITED_FILES=""
  CAP_LAST_MESSAGE=""
  export CAP_HOST CAP_NOW CAP_BRANCH CAP_LAST_COMMIT CAP_STATUS CAP_DIFFSTAT CAP_EDITED_FILES CAP_LAST_MESSAGE
  _capture_from_transcript "${TRANSCRIPT:-}"
}

_capture_from_transcript() {
  local transcript=$1
  local max_chars=${HANDOFF_MAX_MESSAGE_CHARS:-2000}
  { [ -z "$transcript" ] || [ ! -f "$transcript" ]; } && return 0

  CAP_EDITED_FILES=$(
    jq -r '
      select(.type=="assistant")
      | .message.content[]?
      | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="NotebookEdit"))
      | .input.file_path // .input.notebook_path // empty
    ' "$transcript" 2>/dev/null | awk 'NF' | sort -u | head -n 50
  )

  # Last assistant message: slurp, take the last assistant entry, join its
  # text blocks (preserves multi-line). Redact FIRST, then truncate.
  CAP_LAST_MESSAGE=$(
    jq -rs '
      map(select(.type=="assistant")) | last
      | (.message.content // [])
      | map(select(.type=="text") | .text) | join("\n")
    ' "$transcript" 2>/dev/null | redact | head -c "$max_chars"
  )
}
