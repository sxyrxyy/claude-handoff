# test/session-end.bats
load helpers

@test "session-end: runs summarizer once with fake claude" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  printf '<!-- narrative -->\n## Goal\ndone-test\n<!-- /narrative -->\n===JOURNAL===\n**Did:** x.\n' > "$FAKE_CLAUDE_OUT"
  fake_claude
  echo "{\"cwd\":\"$REPO\",\"transcript_path\":\"$tx\"}" \
    | HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      FAKE_CLAUDE_OUT="$FAKE_CLAUDE_OUT" \
      bash "$PLUGIN_DIR/session-end.sh"
  run git -C "$REPO" show refs/handoff/main:HANDOFF.md
  [[ "$output" == *"done-test"* ]]
}
