# test/install.bats
load helpers

@test "install: --verify writes a ref in a throwaway repo" {
  make_repo
  HANDOFF_MACHINE_NAME="tm" run bash "$PLUGIN_DIR/install.sh" --verify "$REPO"
  [ "$status" -eq 0 ]
  run git -C "$REPO" show refs/handoff/tm/main:HANDOFF.md
  [[ "$output" == *"<!-- auto -->"* ]]
}
