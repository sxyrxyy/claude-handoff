# test/refstore.bats
load helpers

@test "refstore: write then read round-trips a file in the ref" {
  make_repo
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "hello world" "HANDOFF-LOG.md" "log line"
    echo "=H="; ref_read "main" "HANDOFF.md"
    echo "=L="; ref_read "main" "HANDOFF-LOG.md"
  '
  [[ "$output" == *"hello world"* ]]
  [[ "$output" == *"log line"* ]]
}

@test "refstore: write does NOT touch the working tree" {
  make_repo
  bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "hello" "HANDOFF-LOG.md" ""
  '
  [ ! -f "$REPO/HANDOFF.md" ]
  run git -C "$REPO" status --porcelain
  [ -z "$output" ]
}

@test "refstore: subsequent writes chain as parents" {
  make_repo
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "v1" "HANDOFF-LOG.md" ""
    ref_write "main" "HANDOFF.md" "v2" "HANDOFF-LOG.md" ""
    git -C "$REPO_ROOT" rev-list --count refs/handoff/main
  '
  [[ "$output" == *"2"* ]]
}

@test "refstore: push to origin succeeds when remote exists" {
  make_repo; add_origin
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "x" "HANDOFF-LOG.md" ""
    ref_push "main"
    git -C "'"$ORIGIN"'" rev-parse refs/handoff/main
  '
  [ "$status" -eq 0 ]
}

@test "refstore: push advances remote on subsequent pushes" {
  make_repo; add_origin
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "v1" "HANDOFF-LOG.md" ""
    ref_push "main"
    ref_write "main" "HANDOFF.md" "v2" "HANDOFF-LOG.md" ""
    ref_push "main"
    git -C "'"$ORIGIN"'" show refs/handoff/main:HANDOFF.md
  '
  [[ "$output" == *"v2"* ]]
}

@test "refstore: ref_write works without configured git identity" {
  make_repo
  git -C "$REPO" config --unset user.name || true
  git -C "$REPO" config --unset user.email || true
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "noident" "HANDOFF-LOG.md" "" && echo OK
    ref_read "main" "HANDOFF.md"
  '
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"noident"* ]]
}
