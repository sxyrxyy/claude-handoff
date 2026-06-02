# render.sh - assemble HANDOFF.md text to STDOUT from CAP_* vars.
# render_handoff "<prior_narrative_or_empty>" prints the full file body.
# Narrative is extracted by the caller (refstore) and passed in.

# Extract a well-formed narrative block from prior content on stdin.
# Returns nothing if start or end marker is missing (no run-to-EOF).
extract_narrative() {
  awk '
    /<!-- narrative -->/ { capturing=1 }
    capturing { buf = buf $0 "\n" }
    /<!-- \/narrative -->/ { if (capturing) { printf "%s", buf }; capturing=0; buf="" }
  '
}

render_handoff() {
  local narrative=${1:-}
  echo "<!-- auto -->"
  echo "# Handoff"
  echo
  echo "**Machine:** $CAP_HOST"
  echo "**Branch:** $CAP_BRANCH · last commit: \`$CAP_LAST_COMMIT\`"
  echo "**Updated:** $CAP_NOW"
  echo
  echo "## Working tree"
  echo '```'
  [ -n "$CAP_STATUS" ] && echo "$CAP_STATUS" || echo "(clean)"
  echo '```'
  echo
  echo "## Diff stat"
  echo '```'
  [ -n "$CAP_DIFFSTAT" ] && echo "$CAP_DIFFSTAT" || echo "(no changes)"
  echo '```'
  echo
  if [ -n "$CAP_EDITED_FILES" ]; then
    echo "## Files touched this session"
    echo "$CAP_EDITED_FILES" | sed 's/^/- /'
    echo
  fi
  if [ -n "$CAP_LAST_MESSAGE" ]; then
    echo "## Last action (Claude)"
    echo "$CAP_LAST_MESSAGE" | sed 's/^/> /'
    echo
  fi
  echo "<!-- /auto -->"
  if [ -n "$narrative" ]; then
    echo
    echo "$narrative"
  fi
}
