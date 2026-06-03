# test/headsup.bats
load helpers

_write_as() { # <machine> <branch> <body>
  HANDOFF_MACHINE_NAME="$1" bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="'"$1"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "'"$2"'" "HANDOFF.md" "'"$3"'" "HANDOFF-LOG.md" ""
  '
}

_headsup() { # runs headsup_line as machine "me"
  bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="me"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/headsup.sh"
    headsup_line "main"
  '
}

@test "headsup: announces a changed sibling exactly once" {
  make_repo
  _write_as desktop main "d1"
  run _headsup
  [ "$status" -eq 0 ]
  [[ "$output" == *"desktop updated its handoff"* ]]
  # Second call with no change: silent (deduped by sha).
  run _headsup
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "headsup: re-announces when the sibling changes again" {
  make_repo
  _write_as desktop main "d1"
  _headsup >/dev/null            # prime the seen-state
  _write_as desktop main "d2"    # sibling advances
  run _headsup
  [ "$status" -eq 0 ]
  [[ "$output" == *"desktop updated its handoff"* ]]
}

@test "headsup: never announces this machine's own note" {
  make_repo
  _write_as me main "mine"
  run _headsup
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "user-prompt.sh: exits 0 and is silent outside a git repo" {
  run bash -c 'echo "{\"cwd\":\"'"$BATS_TEST_TMPDIR"'\"}" | bash "'"$PLUGIN_DIR"'/user-prompt.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "headsup: two changed siblings announce once, then both dedupe" {
  make_repo
  _write_as desktop main "d1"
  _write_as laptop  main "l1"
  run _headsup
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated its handoff"* ]]
  # Both siblings recorded in seen-state -> next call is silent.
  run _headsup
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
