# test/capture.bats
load helpers

run_capture() {
  make_repo
  echo change >> "$REPO/README"
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"
  write_transcript "$tx"
  bash -c '
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'"
    source "'"$PLUGIN_DIR"'/lib/capture.sh"
    capture_state
    echo "---EDITED---"; echo "$CAP_EDITED_FILES"
    echo "---LASTMSG---"; echo "$CAP_LAST_MESSAGE"
  '
}

@test "capture: edited files parsed from transcript" {
  run run_capture
  [[ "$output" == *"src/app.js"* ]]
}

@test "capture: last message keeps ALL lines, not just the last" {
  run run_capture
  [[ "$output" == *"Build complete."* ]]
  [[ "$output" == *"Image built clean."* ]]
}

@test "capture: last message is redacted" {
  run run_capture
  [[ "$output" == *"sk-[REDACTED]"* ]]
  [[ "$output" != *"sk-abcdefghij"* ]]
}
