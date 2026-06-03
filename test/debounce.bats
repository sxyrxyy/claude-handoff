# test/debounce.bats
load helpers

@test "debounce: first call allowed, immediate second call blocked" {
  run bash -c '
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    source "'"$PLUGIN_DIR"'/lib/debounce.sh"
    debounce_ok "repoX" "main" && echo FIRST=yes || echo FIRST=no
    debounce_ok "repoX" "main" && echo SECOND=yes || echo SECOND=no
  '
  [[ "$output" == *"FIRST=yes"* ]]
  [[ "$output" == *"SECOND=no"* ]]
}

@test "debounce: zero window always allows" {
  run bash -c '
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state" HANDOFF_SUMMARY_DEBOUNCE_SECS=0
    source "'"$PLUGIN_DIR"'/lib/debounce.sh"
    debounce_ok "r" "main" && echo A=yes
    debounce_ok "r" "main" && echo B=yes
  '
  [[ "$output" == *"A=yes"* ]]
  [[ "$output" == *"B=yes"* ]]
}

@test "debounce: corrupt stamp does not crash under set -u" {
  run bash -c '
    set -u
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    source "'"$PLUGIN_DIR"'/lib/debounce.sh"
    debounce_ok "ck" "main"
    dir="$XDG_STATE_HOME/claude-handoff"
    for f in "$dir"/*.last; do echo "GARBAGE" > "$f"; done
    HANDOFF_SUMMARY_DEBOUNCE_SECS=300 debounce_ok "ck" "main" && echo OK=yes || echo OK=no
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK=yes"* ]]
}
