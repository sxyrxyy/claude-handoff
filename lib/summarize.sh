# summarize.sh - run headless Haiku to produce narrative + journal entry,
# merge into the handoff ref, push. Degrades to no-op if claude missing.
# Requires REPO_ROOT, TRANSCRIPT, and sourced refstore.sh / redact.sh.

_summary_prompt() {
  cat <<'P'
You are summarizing a coding session transcript for a handoff to another machine.
Output EXACTLY two parts separated by a line containing only ===JOURNAL===.

Part 1: a narrative block, verbatim format:
<!-- narrative -->
## Goal
<1-2 sentences: what the user is trying to achieve>
## Done
- <completed items>
## Failed approaches (don't repeat)
- <what was tried and abandoned, with why; omit bullet if none>
## Next
1. <the single most important next step>
2. <follow-on if any>
<!-- /narrative -->

Part 2 (after ===JOURNAL===): one line:
**Did:** ... **Decided:** ... (with why) **Failed:** ...

Be terse. Reference real file paths. No preamble, no code fences around the output.
P
}

summarize_handoff() {
  local branch=$1
  command -v claude >/dev/null 2>&1 || { log "summarize: claude not found, skipping"; return 0; }
  { [ -n "${TRANSCRIPT:-}" ] && [ -f "$TRANSCRIPT" ]; } || { log "summarize: no transcript"; return 0; }

  # Single-flight lock per repo+branch so the debounced Stop-spawn and the
  # synchronous SessionEnd run can't race on the same ref. A lock older than
  # 3 minutes (a hung/killed run) is treated as stale and stolen.
  local statedir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-handoff"
  mkdir -p "$statedir" 2>/dev/null || true
  local lkey; lkey=$(printf '%s' "$REPO_ROOT/$branch" | cksum | awk '{print $1}')
  local lock="$statedir/$lkey.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +3 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null && mkdir "$lock" 2>/dev/null; then
      log "summarize: stole stale lock"
    else
      log "summarize: another summarizer running, skipping"; return 0
    fi
  fi
  trap 'rmdir "'"$lock"'" 2>/dev/null || true' RETURN

  local model="${HANDOFF_SUMMARY_MODEL:-claude-haiku-4-5}"
  local raw
  raw=$(HANDOFF_DISABLE=1 timeout 90s claude -p \
        --model "$model" \
        "$(_summary_prompt)

TRANSCRIPT (JSONL):
$(jq -rs 'map(select(.type=="assistant" or .type=="user"))
          | map(.message.content // [] | map(.text? // .input? // "") | join(" ")) | join("\n")' \
          "$TRANSCRIPT" 2>/dev/null | tail -c 20000)" \
        2>>"${HANDOFF_LOG_PATH:-/dev/null}") || { log "summarize: claude call failed"; return 0; }

  [ -z "$raw" ] && { log "summarize: empty model output"; return 0; }
  raw=$(printf '%s' "$raw" | redact)

  # Strip any code-fence lines the model may have wrapped the output in.
  local clean
  clean=$(printf '%s' "$raw" | grep -vE '^```')

  # Require a well-formed narrative: both opening and closing tags must be
  # present. Without this, awk's range match runs to EOF and folds the
  # journal text into the narrative, corrupting HANDOFF.md.
  if ! printf '%s' "$clean" | grep -qF '<!-- /narrative -->'; then
    log "summarize: malformed narrative (no closing tag), skipping"; return 0
  fi

  local narrative journal
  narrative=$(printf '%s' "$clean" | awk '/<!-- narrative -->/,/<!-- \/narrative -->/')
  journal=$(printf '%s' "$clean" | awk 'f{print} /===JOURNAL===/{f=1}' | awk 'NF' | head -n 5)
  [ -z "$narrative" ] && { log "summarize: no narrative parsed"; return 0; }

  # Rebuild HANDOFF.md = existing auto block + new narrative.
  local cur auto
  cur=$(ref_read "$branch" "HANDOFF.md")
  auto=$(printf '%s' "$cur" | awk '/<!-- auto -->/,/<!-- \/auto -->/')
  [ -z "$auto" ] && auto="<!-- auto -->
# Handoff
<!-- /auto -->"
  local new_handoff="$auto

$narrative"

  # Prepend journal entry (newest on top), then optional trim.
  local stamp; stamp=$(date -u +%Y-%m-%dT%H:%MZ)
  local host="${HANDOFF_MACHINE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
  local cur_log new_log
  cur_log=$(ref_read "$branch" "HANDOFF-LOG.md")
  new_log="## $stamp — $host — $branch
$journal

$cur_log"
  if [ -n "${HANDOFF_LOG_MAX_ENTRIES:-}" ]; then
    new_log=$(printf '%s' "$new_log" | awk -v n="$HANDOFF_LOG_MAX_ENTRIES" '
      /^## [0-9][0-9][0-9][0-9]-/ { c++ } c<=n { print }')
  fi

  ref_write "$branch" "HANDOFF.md" "$new_handoff" "HANDOFF-LOG.md" "$new_log" || return 0
  ref_push "$branch"
  log "summarize: updated narrative + journal for $branch"
}
