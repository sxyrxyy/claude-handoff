# test/helpers.bash - shared setup for bats tests.

# Path to the plugin root (one level up from test/).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_DIR

# Create a throwaway git repo in $BATS_TEST_TMPDIR/repo (exported as $REPO).
# Makes one initial commit so HEAD exists.
make_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@e.st
  git -C "$REPO" config user.name tester
  echo init > "$REPO/README"
  git -C "$REPO" add README
  git -C "$REPO" commit -q -m init
  export REPO
}

# Add a bare repo as 'origin' so push paths can be tested.
add_origin() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$ORIGIN"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  export ORIGIN
}

# Put a fake `claude` on PATH that prints $FAKE_CLAUDE_OUT (a file path).
fake_claude() {
  local bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  cat > "$bindir/claude" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_CLAUDE_OUT"
SH
  chmod +x "$bindir/claude"
  PATH="$bindir:$PATH"
  export PATH
}

# Write a minimal Claude Code transcript JSONL to $1.
# Includes two assistant turns; the last has a multi-line text block
# and an Edit tool_use.
write_transcript() {
  cat > "$1" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"first message"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/app.js"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Build complete.\nImage built clean.\nAPI key sk-abcdefghijklmnopqrstuvwxyz123 leaked."}]}}
JSONL
}
