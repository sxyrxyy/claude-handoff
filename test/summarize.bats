# test/summarize.bats
load helpers

@test "summarize: degrades to no-op when claude is absent" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'"
    PATH="/usr/bin:/bin"   # no claude on PATH
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    summarize_handoff "main"; echo "rc=$?"
  '
  [[ "$output" == *"rc=0"* ]]
}

@test "summarize: writes narrative + journal into the ref using fake claude" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  cat > "$FAKE_CLAUDE_OUT" <<'MD'
<!-- narrative -->
## Goal
ship handoff v2
## Done
- refstore
## Failed approaches (don't repeat)
- committing to main
## Next
1. wire the hook
<!-- /narrative -->
===JOURNAL===
**Did:** built refstore. **Decided:** dedicated ref to keep history clean. **Failed:** committing to branch.
MD
  fake_claude
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'" FAKE_CLAUDE_OUT="'"$FAKE_CLAUDE_OUT"'"
    export PATH="'"$BATS_TEST_TMPDIR"'/bin:$PATH"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/render.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    summarize_handoff "main"
    echo "=H="; ref_read "main" "HANDOFF.md"
    echo "=L="; ref_read "main" "HANDOFF-LOG.md"
  '
  [[ "$output" == *"ship handoff v2"* ]]
  [[ "$output" == *"Did:** built refstore"* ]]
}

@test "summarize: skips on malformed narrative (no closing tag)" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  cat > "$FAKE_CLAUDE_OUT" <<'MD'
<!-- narrative -->
## Goal
truncated output with no closing tag
===JOURNAL===
**Did:** stuff.
MD
  fake_claude
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'" FAKE_CLAUDE_OUT="'"$FAKE_CLAUDE_OUT"'"
    export PATH="'"$BATS_TEST_TMPDIR"'/bin:$PATH"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    summarize_handoff "main"; echo "rc=$?"
    echo "HANDOFF:"; ref_read "main" "HANDOFF.md"
  '
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" != *"Did:** stuff"* ]]
}

@test "summarize: strips code fences from output" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  cat > "$FAKE_CLAUDE_OUT" <<'MD'
```markdown
<!-- narrative -->
## Goal
fenced goal
<!-- /narrative -->
===JOURNAL===
**Did:** fenced work.
```
MD
  fake_claude
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'" FAKE_CLAUDE_OUT="'"$FAKE_CLAUDE_OUT"'"
    export PATH="'"$BATS_TEST_TMPDIR"'/bin:$PATH"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/render.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    summarize_handoff "main"
    echo "=H="; ref_read "main" "HANDOFF.md"
    echo "=L="; ref_read "main" "HANDOFF-LOG.md"
  '
  [[ "$output" == *"fenced goal"* ]]
  [[ "$output" == *"Did:** fenced work"* ]]
  [[ "$output" != *'```'* ]]
}

@test "summarize: passes HANDOFF_DISABLE=1 to the claude child" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  local bindir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bindir"
  cat > "$bindir/claude" <<'SH'
#!/usr/bin/env bash
echo "CHILD_HANDOFF_DISABLE=$HANDOFF_DISABLE" >&2
printf '<!-- narrative -->\n## Goal\nx\n<!-- /narrative -->\n===JOURNAL===\n**Did:** y.\n'
SH
  chmod +x "$bindir/claude"
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'"
    export PATH="'"$bindir"':$PATH"
    export HANDOFF_LOG_PATH="'"$BATS_TEST_TMPDIR"'/h.log"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    summarize_handoff "main"
    cat "$HANDOFF_LOG_PATH"
  '
  [[ "$output" == *"CHILD_HANDOFF_DISABLE=1"* ]]
}

@test "summarize: skips when another summarizer holds the lock" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  printf '<!-- narrative -->\n## Goal\nlocked-skip\n<!-- /narrative -->\n===JOURNAL===\n**Did:** x.\n' > "$FAKE_CLAUDE_OUT"
  fake_claude
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'" FAKE_CLAUDE_OUT="'"$FAKE_CLAUDE_OUT"'"
    export PATH="'"$BATS_TEST_TMPDIR"'/bin:$PATH"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    export HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/render.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    statedir="$XDG_STATE_HOME/claude-handoff"; mkdir -p "$statedir"
    lkey=$(printf "%s" "$REPO_ROOT/main" | cksum | awk "{print \$1}")
    mkdir "$statedir/$lkey.lock"
    summarize_handoff "main"; echo "rc=$?"
    git -C "$REPO_ROOT" show refs/handoff/tm/main:HANDOFF.md 2>/dev/null || echo "NO-REF"
  '
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" == *"NO-REF"* ]]
  [[ "$output" != *"locked-skip"* ]]
}

@test "summarize: steals a stale lock (older than 3 min)" {
  make_repo
  local tx="$BATS_TEST_TMPDIR/tx.jsonl"; write_transcript "$tx"
  export FAKE_CLAUDE_OUT="$BATS_TEST_TMPDIR/out.md"
  printf '<!-- narrative -->\n## Goal\nstole-lock\n<!-- /narrative -->\n===JOURNAL===\n**Did:** x.\n' > "$FAKE_CLAUDE_OUT"
  fake_claude
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" TRANSCRIPT="'"$tx"'" FAKE_CLAUDE_OUT="'"$FAKE_CLAUDE_OUT"'"
    export PATH="'"$BATS_TEST_TMPDIR"'/bin:$PATH"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    export HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/redact.sh"
    source "'"$PLUGIN_DIR"'/lib/render.sh"
    source "'"$PLUGIN_DIR"'/lib/summarize.sh"
    statedir="$XDG_STATE_HOME/claude-handoff"; mkdir -p "$statedir"
    lkey=$(printf "%s" "$REPO_ROOT/main" | cksum | awk "{print \$1}")
    mkdir "$statedir/$lkey.lock"
    touch -d "10 minutes ago" "$statedir/$lkey.lock"
    summarize_handoff "main"
    git -C "$REPO_ROOT" show refs/handoff/tm/main:HANDOFF.md
  '
  [[ "$output" == *"stole-lock"* ]]
}
