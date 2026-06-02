# test/smoke.bats
load helpers

@test "helpers: make_repo creates a repo with HEAD" {
  make_repo
  run git -C "$REPO" rev-parse HEAD
  [ "$status" -eq 0 ]
}
