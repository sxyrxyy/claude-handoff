# test/preflight.bats
load helpers

run_preflight() {
  # Run preflight in a subshell so its exit doesn't kill bats.
  bash -c '
    log() { :; }
    source "'"$PLUGIN_DIR"'/lib/preflight.sh"
    preflight "$1"
    echo "REPO_ROOT=$REPO_ROOT"
    echo "HANDOFF_SHARED=${HANDOFF_SHARED:-0}"
  ' _ "$1"
}

@test "preflight: bails when not a git repo" {
  run run_preflight "$BATS_TEST_TMPDIR"
  [[ "$output" != *"REPO_ROOT=$BATS_TEST_TMPDIR"* ]]
}

@test "preflight: sets REPO_ROOT inside a repo" {
  make_repo
  run run_preflight "$REPO"
  [[ "$output" == *"REPO_ROOT=$REPO"* ]]
}

@test "preflight: .no-handoff bails" {
  make_repo
  touch "$REPO/.no-handoff"
  run run_preflight "$REPO"
  [[ "$output" != *"REPO_ROOT=$REPO"* ]]
}

@test "preflight: single-committer repo is personal (not shared)" {
  make_repo
  run run_preflight "$REPO"
  [[ "$output" == *"HANDOFF_SHARED=0"* ]]
}

@test "preflight: multi-committer repo is shared and bails without enable marker" {
  make_repo
  git -C "$REPO" -c user.email=a@x -c user.name=a commit -q --allow-empty -m a
  git -C "$REPO" -c user.email=b@x -c user.name=b commit -q --allow-empty -m b
  run run_preflight "$REPO"
  [[ "$output" != *"REPO_ROOT=$REPO"* ]]
}

@test "preflight: shared repo with .handoff-enable proceeds" {
  make_repo
  git -C "$REPO" -c user.email=a@x -c user.name=a commit -q --allow-empty -m a
  git -C "$REPO" -c user.email=b@x -c user.name=b commit -q --allow-empty -m b
  touch "$REPO/.handoff-enable"
  run run_preflight "$REPO"
  [[ "$output" == *"REPO_ROOT=$REPO"* ]]
}
