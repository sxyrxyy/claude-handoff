# test/install.bats
load helpers

@test "install: --verify writes a ref in a throwaway repo" {
  make_repo
  run bash "$PLUGIN_DIR/install.sh" --verify "$REPO"
  [ "$status" -eq 0 ]
  run git -C "$REPO" show refs/handoff/main:HANDOFF.md
  [[ "$output" == *"<!-- auto -->"* ]]
}
