# debounce.sh - rate-limit the summarizer per repo+branch.
# debounce_ok <repo_key> <branch> returns 0 if enough time has passed
# (and records "now"), 1 otherwise.

debounce_ok() {
  local key=$1 branch=$2
  local win=${HANDOFF_SUMMARY_DEBOUNCE_SECS:-300}
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-handoff"
  mkdir -p "$dir" 2>/dev/null || return 0
  local hash; hash=$(printf '%s' "$key/$branch" | cksum | awk '{print $1}')
  local stamp="$dir/$hash.last"
  local now; now=$(date +%s)
  if [ "$win" -gt 0 ] && [ -f "$stamp" ]; then
    local prev; prev=$(cat "$stamp" 2>/dev/null || echo 0)
    if [[ "$prev" =~ ^[0-9]+$ ]] && [ $(( now - prev )) -lt "$win" ]; then
      return 1
    fi
  fi
  echo "$now" > "$stamp" 2>/dev/null || true
  return 0
}
