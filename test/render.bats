# test/render.bats
load helpers

# render_handoff writes to stdout (not a file) so it can target a ref tree.
run_render() {
  bash -c '
    export CAP_HOST=mybox CAP_NOW=2026-06-02T00:00:00Z CAP_BRANCH=main
    export CAP_LAST_COMMIT="abc123 do thing" CAP_STATUS=" M a.txt"
    export CAP_DIFFSTAT=" a.txt | 2 +-" CAP_EDITED_FILES="a.txt"
    export CAP_LAST_MESSAGE="did the thing"
    source "'"$PLUGIN_DIR"'/lib/render.sh"
    render_handoff "$1"
  ' _ "$1"
}

@test "render: includes header and last action" {
  run run_render ""
  [[ "$output" == *"**Machine:** mybox"* ]]
  [[ "$output" == *"> did the thing"* ]]
  [[ "$output" == *"<!-- auto -->"* ]]
}

@test "render: preserves an existing narrative block" {
  local prior="<!-- narrative -->
## Goal
ship it
<!-- /narrative -->"
  run run_render "$prior"
  [[ "$output" == *"## Goal"* ]]
  [[ "$output" == *"ship it"* ]]
}

@test "render: missing narrative end marker does not run to EOF" {
  # A malformed prior with no end marker must not swallow everything.
  local prior="<!-- narrative -->
## Goal
ship it
TRAILING GARBAGE"
  run run_render "$prior"
  # Output must still be well-formed: contains auto block.
  [[ "$output" == *"<!-- auto -->"* ]]
}

@test "extract_narrative: emits block when both markers present" {
  run bash -c 'printf "<!-- narrative -->\n## Goal\nx\n<!-- /narrative -->\n" | { source "'"$PLUGIN_DIR"'/lib/render.sh"; extract_narrative; }'
  [[ "$output" == *"<!-- narrative -->"* ]]
  [[ "$output" == *"## Goal"* ]]
  [[ "$output" == *"<!-- /narrative -->"* ]]
}

@test "extract_narrative: emits nothing when end marker missing" {
  run bash -c 'printf "<!-- narrative -->\n## Goal\nx\nTRAILING\n" | { source "'"$PLUGIN_DIR"'/lib/render.sh"; extract_narrative; }'
  [ -z "$output" ]
}
