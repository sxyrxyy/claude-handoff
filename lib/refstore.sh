# refstore.sh - read/write/push handoff content to refs/handoff/<machine>/<branch>
# WITHOUT touching the working tree or index, via git plumbing.
# Requires REPO_ROOT and a log() function in scope.

# Machine name for ref namespacing -- matches capture.sh CAP_HOST.
ref_machine() {
  printf '%s' "${HANDOFF_MACHINE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
}

# Percent-encode anything outside [A-Za-z0-9._-] so a branch or machine name
# becomes a single git-ref-safe path segment. Reversible via _ref_dec.
_ref_enc() {
  local s=$1 out= i c
  for (( i=0; i<${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._-]) out+=$c ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# Reverse _ref_enc for display (%2F -> /).
_ref_dec() { printf '%b' "${1//%/\\x}"; }

# This machine's ref for a branch: refs/handoff/<enc-machine>/<enc-branch>.
_ref_name() {
  printf 'refs/handoff/%s/%s' "$(_ref_enc "$(ref_machine)")" "$(_ref_enc "$1")"
}

# Legacy (pre-per-machine) ref, branch unencoded: refs/handoff/<branch>.
_ref_legacy_name() { printf 'refs/handoff/%s' "$1"; }

# ref_write <branch> <fileA> <contentA> <fileB> <contentB>
# Builds a tree of the two files and commits it to the handoff ref,
# parented on the previous handoff commit if one exists.
ref_write() {
  if [ $# -lt 5 ]; then log "ref_write: requires 5 args, got $#"; return 1; fi
  local branch=$1 fa=$2 ca=$3 fb=$4 cb=$5
  local ref; ref=$(_ref_name "$branch")
  local g=(git -C "$REPO_ROOT")

  # Fallback identity so commit-tree never fails in an identity-less repo.
  # Only affects objects in refs/handoff/*, never the user's history.
  local -x GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Claude Handoff}"
  local -x GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-handoff@localhost}"
  local -x GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Claude Handoff}"
  local -x GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-handoff@localhost}"

  local blob_a blob_b
  blob_a=$(printf '%s' "$ca" | "${g[@]}" hash-object -w --stdin) || { log "ref_write: hash a failed"; return 1; }
  blob_b=$(printf '%s' "$cb" | "${g[@]}" hash-object -w --stdin) || { log "ref_write: hash b failed"; return 1; }

  local tree
  tree=$(printf '100644 blob %s\t%s\n100644 blob %s\t%s\n' "$blob_a" "$fa" "$blob_b" "$fb" \
    | "${g[@]}" mktree) || { log "ref_write: mktree failed"; return 1; }

  local parent commit
  parent=$("${g[@]}" rev-parse -q --verify "$ref" 2>/dev/null || echo "")
  if [ -n "$parent" ]; then
    commit=$("${g[@]}" commit-tree "$tree" -p "$parent" -m "handoff $branch") || { log "ref_write: commit-tree failed (identity?)"; return 1; }
  else
    commit=$("${g[@]}" commit-tree "$tree" -m "handoff $branch") || { log "ref_write: commit-tree failed (identity?)"; return 1; }
  fi
  "${g[@]}" update-ref "$ref" "$commit" || { log "ref_write: update-ref failed"; return 1; }
}

# ref_read <branch> <file> -> prints content (empty if missing).
ref_read() {
  local branch=$1 file=$2 ref; ref=$(_ref_name "$branch")
  git -C "$REPO_ROOT" show "$ref:$file" 2>/dev/null || true
}

# ref_push <branch> - push the ref with an explicit lease; no-op if no origin.
ref_push() {
  local branch=$1 ref; ref=$(_ref_name "$branch")
  git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1 || { log "ref_push: no origin"; return 0; }
  local old_sha lease
  old_sha=$(git -C "$REPO_ROOT" ls-remote origin "$ref" 2>/dev/null | awk '{print $1}')
  if [ -n "$old_sha" ]; then
    lease="--force-with-lease=$ref:$old_sha"
  else
    lease="--force-with-lease"
  fi
  if ! timeout 30s git -C "$REPO_ROOT" push -q "$lease" origin "$ref:$ref" 2>>"${HANDOFF_LOG_PATH:-/dev/null}"; then
    log "ref_push: push failed (will retry next turn)"; return 0
  fi
}

# ref_fetch <branch> - fetch all handoff refs from origin (best-effort).
ref_fetch() {
  git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1 || return 0
  timeout 30s git -C "$REPO_ROOT" fetch -q origin 'refs/handoff/*:refs/handoff/*' 2>>"${HANDOFF_LOG_PATH:-/dev/null}" || true
}
