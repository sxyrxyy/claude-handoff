# test/fetch.bats
load helpers

@test "fetch_due: true first call, false within window, true after window" {
  make_repo
  run bash -c '
    export REPO_ROOT="'"$REPO"'"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    export HANDOFF_FETCH_THROTTLE_SECS=60
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    fetch_due && echo "first=due"
    fetch_due || echo "second=throttled"
    # Backdate the stamp beyond the window.
    dir="$XDG_STATE_HOME/claude-handoff"
    hash=$(printf "%s" "$REPO_ROOT" | cksum | awk "{print \$1}")
    echo $(( $(date +%s) - 120 )) > "$dir/$hash.fetch"
    fetch_due && echo "third=due"
  '
  [[ "$output" == *"first=due"* ]]
  [[ "$output" == *"second=throttled"* ]]
  [[ "$output" == *"third=due"* ]]
}

@test "run-fetch.sh: pulls handoff refs from origin" {
  make_repo; add_origin
  # Push a per-machine note from a "remote" clone so origin has a handoff ref.
  CLONE="$BATS_TEST_TMPDIR/clone"
  git clone -q "$ORIGIN" "$CLONE"
  HANDOFF_MACHINE_NAME="other" bash -c '
    log() { :; }
    export REPO_ROOT="'"$CLONE"'" HANDOFF_MACHINE_NAME="other"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "from-other" "HANDOFF-LOG.md" ""
    ref_push "main"
  '
  HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" run bash "$PLUGIN_DIR/lib/run-fetch.sh" "$REPO"
  [ "$status" -eq 0 ]
  run git -C "$REPO" show refs/handoff/other/main:HANDOFF.md
  [[ "$output" == *"from-other"* ]]
}

@test "fetch_due: zero window always allows" {
  make_repo
  run bash -c '
    export REPO_ROOT="'"$REPO"'"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    export HANDOFF_FETCH_THROTTLE_SECS=0
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    fetch_due && echo "a=due"
    fetch_due && echo "b=due"
  '
  [[ "$output" == *"a=due"* ]]
  [[ "$output" == *"b=due"* ]]
}
