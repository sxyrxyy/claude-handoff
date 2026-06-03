# test/weburl.bats
load helpers

_url_for() { # <origin-url>  -> prints ref_web_url for refs/handoff/tm/main
  bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "x" "HANDOFF-LOG.md" ""
    git -C "$REPO_ROOT" remote add origin "'"$1"'" 2>/dev/null || git -C "$REPO_ROOT" remote set-url origin "'"$1"'"
    sha=$(git -C "$REPO_ROOT" rev-parse refs/handoff/tm/main)
    echo "SHA=$sha"
    ref_web_url refs/handoff/tm/main
  '
}

@test "weburl: github ssh remote -> blob url" {
  make_repo
  run _url_for "git@github.com:foo/bar.git"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://github.com/foo/bar/blob/$sha/HANDOFF.md"* ]]
}

@test "weburl: github https remote -> blob url" {
  make_repo
  run _url_for "https://github.com/foo/bar.git"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://github.com/foo/bar/blob/$sha/HANDOFF.md"* ]]
}

@test "weburl: gitlab remote -> dash-blob url" {
  make_repo
  run _url_for "git@gitlab.com:foo/bar.git"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://gitlab.com/foo/bar/-/blob/$sha/HANDOFF.md"* ]]
}

@test "weburl: unknown host falls back to git show command" {
  make_repo
  run _url_for "git@example.com:foo/bar.git"
  [[ "$output" == *"git show refs/handoff/tm/main:HANDOFF.md"* ]]
}

@test "weburl: no origin falls back to git show command" {
  make_repo
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "x" "HANDOFF-LOG.md" ""
    ref_web_url refs/handoff/tm/main
  '
  [[ "$output" == *"git show refs/handoff/tm/main:HANDOFF.md"* ]]
}

@test "weburl: ref_resume_dump includes a url= line" {
  make_repo
  git -C "$REPO" remote add origin "git@github.com:foo/bar.git"
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "body" "HANDOFF-LOG.md" ""
    ref_resume_dump "main"
  '
  [[ "$output" == *"url=https://github.com/foo/bar/blob/"* ]]
}

@test "weburl: github https remote without .git -> blob url" {
  make_repo
  run _url_for "https://github.com/foo/bar"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://github.com/foo/bar/blob/$sha/HANDOFF.md"* ]]
}

@test "weburl: github https remote with trailing slash -> no double slash" {
  make_repo
  run _url_for "https://github.com/foo/bar/"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://github.com/foo/bar/blob/$sha/HANDOFF.md"* ]]
  [[ "$output" != *"bar//blob"* ]]
}

@test "weburl: github ssh remote with port -> blob url" {
  make_repo
  run _url_for "ssh://git@github.com:443/foo/bar.git"
  sha=$(echo "$output" | sed -n 's/^SHA=//p')
  [[ "$output" == *"https://github.com/foo/bar/blob/$sha/HANDOFF.md"* ]]
}
