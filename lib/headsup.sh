# headsup.sh - detect sibling machines' handoff updates and emit a one-line
# heads-up. No network. Requires REPO_ROOT and a sourced refstore.sh.

# Humanize a duration in seconds to "Nm" / "Nh" / "Nd".
_ago() {
  local s=$1
  [ "$s" -lt 0 ] && s=0
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' $(( s / 60 ))
  elif [ "$s" -lt 86400 ]; then printf '%dh' $(( s / 3600 ))
  else printf '%dd' $(( s / 86400 )); fi
}

# Write "<ref> <sha>" for every sibling (not this machine) to the seen-file.
_headsup_write_seen() { # <branch> <enc-self> <seen-file>
  local branch=$1 self=$2 seen=$3 m r sha tmp
  tmp="$seen.tmp.$$"
  : > "$tmp" 2>/dev/null || return 0
  while IFS=$'\t' read -r m r; do
    [ -n "$r" ] || continue
    case "$r" in refs/handoff/"$self"/*) continue ;; esac
    sha=$(git -C "$REPO_ROOT" rev-parse "$r" 2>/dev/null) || continue
    printf '%s %s\n' "$r" "$sha" >> "$tmp"
  done < <(ref_list_machines "$branch")
  mv "$tmp" "$seen" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

# Print one heads-up line if any OTHER machine's note changed since last seen;
# otherwise print nothing. Updates the seen-state either way.
headsup_line() {
  local branch=$1
  local self; self=$(_ref_enc "$(ref_machine)")
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-handoff/seen"
  mkdir -p "$dir" 2>/dev/null || return 0
  local key; key=$(printf '%s' "$REPO_ROOT/$branch" | cksum | awk '{print $1}')
  local seen="$dir/$key"
  local now; now=$(date +%s)

  local changed_m="" changed_age="" newest=-1
  local m r sha prev ct
  while IFS=$'\t' read -r m r; do
    [ -n "$r" ] || continue
    case "$r" in refs/handoff/"$self"/*) continue ;; esac
    sha=$(git -C "$REPO_ROOT" rev-parse "$r" 2>/dev/null) || continue
    prev=$(grep -F "$r " "$seen" 2>/dev/null | awk '{print $2}' | head -n1)
    if [ "$sha" != "$prev" ]; then
      ct=$(git -C "$REPO_ROOT" log -1 --format='%ct' "$r" 2>/dev/null || echo "$now")
      if [ "$ct" -ge "$newest" ]; then newest=$ct; changed_m="$m"; changed_age="$(_ago $(( now - ct )))"; fi
    fi
  done < <(ref_list_machines "$branch")

  _headsup_write_seen "$branch" "$self" "$seen"

  [ -n "$changed_m" ] || return 0
  printf 'note: %s updated its handoff ~%s ago\n' "$changed_m" "$changed_age"
}
