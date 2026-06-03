# test/perref.bats
load helpers

# Write a per-machine note as a specific machine.
_write_as() { # <machine> <branch> <handoff> <log>
  HANDOFF_MACHINE_NAME="$1" bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="'"$1"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "'"$2"'" "HANDOFF.md" "'"$3"'" "HANDOFF-LOG.md" "'"$4"'"
  '
}

@test "perref: two machines on one branch keep separate notes (no clobber)" {
  make_repo
  _write_as laptop  main "laptop-note"  "## 2026-01-01 — laptop — main"
  _write_as desktop main "desktop-note" "## 2026-01-02 — desktop — main"
  run git -C "$REPO" show refs/handoff/laptop/main:HANDOFF.md
  [[ "$output" == *"laptop-note"* ]]
  run git -C "$REPO" show refs/handoff/desktop/main:HANDOFF.md
  [[ "$output" == *"desktop-note"* ]]
}

@test "perref: ref_list_machines lists every machine for the branch" {
  make_repo
  _write_as laptop  main "l" ""
  _write_as desktop main "d" ""
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_list_machines "main" | cut -f1 | sort | tr "\n" " "
  '
  [[ "$output" == *"desktop laptop"* ]]
}

@test "perref: ref_resume_dump includes all machines and a legacy ref" {
  make_repo
  _write_as laptop main "laptop-handoff-body" "## 2026-01-01 — laptop — main"
  # Seed a legacy bare ref the old way (plumbing).
  bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    blob=$(printf "legacy-body" | git -C "$REPO_ROOT" hash-object -w --stdin)
    tree=$(printf "100644 blob %s\tHANDOFF.md\n" "$blob" | git -C "$REPO_ROOT" mktree)
    commit=$(git -C "$REPO_ROOT" commit-tree "$tree" -m legacy)
    git -C "$REPO_ROOT" update-ref refs/handoff/main "$commit"
  '
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_resume_dump "main"
  '
  [[ "$output" == *"machine=laptop"* ]]
  [[ "$output" == *"laptop-handoff-body"* ]]
  [[ "$output" == *"machine=(legacy)"* ]]
  [[ "$output" == *"legacy-body"* ]]
}
