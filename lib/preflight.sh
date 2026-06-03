# preflight.sh - exit early when this run should be a no-op.
# Sets REPO_ROOT and HANDOFF_SHARED on success. Exits parent shell 0 on bail.

# Is the repo personal? Personal = origin owner in HANDOFF_OWN_REMOTES,
# OR a single committer in the last 90 days. Otherwise shared.
_is_shared_repo() {
  local root=$1 owners="${HANDOFF_OWN_REMOTES:-}" url
  url=$(git -C "$root" remote get-url origin 2>/dev/null || echo "")
  if [ -n "$owners" ] && [ -n "$url" ]; then
    local IFS=,; local o
    for o in $owners; do
      [ -n "$o" ] && [[ "$url" == *"$o"* ]] && { echo 0; return; }
    done
  fi
  local n
  n=$(git -C "$root" shortlog -sne --since="90 days ago" HEAD 2>/dev/null | awk 'END{print NR}')
  [ -z "$n" ] && n=1
  if [ "$n" -le 1 ]; then echo 0; else echo 1; fi
}

preflight() {
  local cwd=$1

  if [ "${HANDOFF_DISABLE:-}" = "1" ]; then
    log "preflight: HANDOFF_DISABLE=1, skipping"; exit 0
  fi

  if ! REPO_ROOT=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
    log "preflight: $cwd not a git repo, skipping"; exit 0
  fi
  export REPO_ROOT

  if [ -e "$REPO_ROOT/.no-handoff" ]; then
    log "preflight: .no-handoff present, skipping"; exit 0
  fi

  if ! git -C "$REPO_ROOT" symbolic-ref -q HEAD >/dev/null; then
    log "preflight: detached HEAD, skipping"; exit 0
  fi

  HANDOFF_SHARED=$(_is_shared_repo "$REPO_ROOT")
  export HANDOFF_SHARED
  if [ "$HANDOFF_SHARED" = "1" ] && [ ! -e "$REPO_ROOT/.handoff-enable" ]; then
    log "preflight: shared repo without .handoff-enable, skipping"; exit 0
  fi
}
