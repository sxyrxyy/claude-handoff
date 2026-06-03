# test/hook.bats
load helpers

setup() {
  fake_claude
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/claude-out.md"
  printf '<!-- narrative -->\n## Goal\nx\n<!-- /narrative -->\n===JOURNAL===\n**Did:** y.\n' > "$FAKE_CLAUDE_OUT"
}

run_hook() {
  echo "{\"hook_event_name\":\"Stop\",\"cwd\":\"$REPO\",\"transcript_path\":\"$1\"}" \
    | HANDOFF_SUMMARY_DEBOUNCE_SECS=999999 \
      HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" \
      HANDOFF_MACHINE_NAME="tm" \
      bash "$PLUGIN_DIR/hook.sh"
}

@test "hook: writes the auto block into the ref, not the working tree" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  run run_hook "$tx"
  [ "$status" -eq 0 ]
  [ ! -f "$REPO/HANDOFF.md" ]
  run git -C "$REPO" show refs/handoff/tm/main:HANDOFF.md
  [[ "$output" == *"<!-- auto -->"* ]]
  [[ "$output" == *"Build complete."* ]]
}

@test "hook: exits 0 outside a git repo" {
  echo "{\"cwd\":\"$BATS_TEST_TMPDIR\",\"transcript_path\":\"/dev/null\"}" \
    | bash "$PLUGIN_DIR/hook.sh"
  [ "$?" -eq 0 ]
}
