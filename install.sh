#!/usr/bin/env bash
# install.sh - register the plugin (best-effort) and/or self-verify.
# Usage:
#   install.sh            # print install guidance
#   install.sh --verify [REPO]   # run the Stop hook against REPO (default: cwd)
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--verify" ]; then
  repo="${2:-$PWD}"
  tx="$(mktemp)"; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"verify run"}]}}' > "$tx"
  echo "{\"cwd\":\"$repo\",\"transcript_path\":\"$tx\"}" \
    | HANDOFF_SUMMARY_DEBOUNCE_SECS=999999 bash "$PLUGIN_DIR/hook.sh"
  rc=$?
  rm -f "$tx"
  branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  if git -C "$repo" rev-parse -q --verify "refs/handoff/$branch" >/dev/null 2>&1; then
    echo "OK: refs/handoff/$branch written."
    exit 0
  fi
  echo "FAILED: no handoff ref written (rc=$rc). Check ~/.claude/hooks/handoff.log"
  exit 1
fi

for dep in git jq perl bash; do
  command -v "$dep" >/dev/null 2>&1 || echo "WARNING: missing dependency: $dep"
done
cat <<EOF
claude-handoff v2

This is a Claude Code plugin. Install it via the plugin system. The
manifest (.claude-plugin/plugin.json) wires the Stop + SessionEnd hooks;
the handoff skill and /handoff command are auto-discovered from the
skills/ and commands/ directories:

  /plugin install $PLUGIN_DIR

Validate the manifest with:

  claude plugin validate $PLUGIN_DIR

Then verify the hook works in any git repo:

  bash $PLUGIN_DIR/install.sh --verify .

Optional config (export in your shell profile):
  HANDOFF_OWN_REMOTES=github.com/you,git.work.com/you
  HANDOFF_SUMMARY_MODEL=claude-haiku-4-5
  HANDOFF_SUMMARY_DEBOUNCE_SECS=300
EOF
