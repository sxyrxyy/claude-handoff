# Per-machine handoff notes + mid-session freshness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make handoffs per-machine so two machines on the same branch never overwrite each other, and keep a running session current via a throttled background fetch plus a one-line heads-up when another machine updates its note.

**Architecture:** Each machine writes only its own ref `refs/handoff/<machine>/<branch>` (machine-first so it never collides with the legacy `refs/handoff/<branch>`, which is read as a fallback — no migration). The entire write path already routes through `_ref_name` in `lib/refstore.sh`, so namespacing that one function makes every writer per-machine for free. New read-side helpers aggregate all machines for the resume skill. The Stop hook gains a detached, throttled fetch; a new `UserPromptSubmit` hook does pure-local sha diffing to surface a heads-up.

**Tech Stack:** Bash, git plumbing, `jq`, `bats` (bats-core) for tests.

**Spec:** `docs/superpowers/specs/2026-06-02-handoff-per-machine-notes-design.md`

---

## Prerequisite: install bats

`bats` is not on PATH. Install bats-core from the official source before running any test step.

- [ ] **Install bats-core**

Run:
```bash
sudo apt-get update && sudo apt-get install -y bats
bats --version
```
Expected: prints e.g. `Bats 1.x`. (If apt is unavailable, clone the official repo: `git clone https://github.com/bats-core/bats-core.git /tmp/bats-core && sudo /tmp/bats-core/install.sh /usr/local`.)

- [ ] **Confirm the existing suite is green before changes**

Run:
```bash
cd ~/.claude/handoff-plugin && bats test/
```
Expected: all tests PASS. This is the baseline; Task 1 must keep it green.

---

## File Structure

All paths under `~/.claude/handoff-plugin` unless noted.

- `lib/refstore.sh` — MODIFY. Add machine identity + segment encoding; namespace `_ref_name`; add `_ref_legacy_name`, `ref_list_machines`, `ref_resume_dump`, `fetch_due`.
- `lib/run-fetch.sh` — CREATE. Detached wrapper that calls `ref_fetch`.
- `hook.sh` — MODIFY. Spawn the throttled detached fetch after the push block.
- `lib/headsup.sh` — CREATE. Pure-local sibling sha diff → one-line heads-up + seen-state.
- `user-prompt.sh` — CREATE. `UserPromptSubmit` entry point; prints the heads-up line.
- `hooks/hooks.json` — MODIFY. Add the `UserPromptSubmit` hook.
- `install.sh` — MODIFY. `--verify` must check the per-machine ref.
- `skills/handoff/SKILL.md` — MODIFY. Multi-machine resume.
- `README.md` — MODIFY. Document per-machine model + new behavior/env.
- `~/.claude/settings.json` — MODIFY (machine-local, NOT committed). Mirror the `UserPromptSubmit` hook.
- Tests: MODIFY `test/refstore.bats`, `test/hook.bats`, `test/session-end.bats`, `test/install.bats`, `test/summarize.bats`; CREATE `test/perref.bats`, `test/fetch.bats`, `test/headsup.bats`.

---

## Task 1: Per-machine ref scheme + keep existing suite green

**Files:**
- Modify: `lib/refstore.sh` (the `_ref_name` helper near the top)
- Modify: `install.sh` (the `--verify` ref check)
- Modify: `test/refstore.bats`, `test/hook.bats`, `test/session-end.bats`, `test/install.bats`, `test/summarize.bats`

- [ ] **Step 1: Write a failing test for the per-machine ref path**

Add to `test/refstore.bats` (end of file):
```bash
@test "refstore: writes to a per-machine ref, not the bare branch ref" {
  make_repo
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "hello" "HANDOFF-LOG.md" ""
    git -C "$REPO_ROOT" rev-parse -q --verify refs/handoff/tm/main && echo HAVE-PER-MACHINE
    git -C "$REPO_ROOT" rev-parse -q --verify refs/handoff/main || echo NO-BARE
  '
  [[ "$output" == *"HAVE-PER-MACHINE"* ]]
  [[ "$output" == *"NO-BARE"* ]]
}

@test "refstore: encodes a slash in the branch into one segment" {
  make_repo
  run bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="tm"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "feature/x" "HANDOFF.md" "fx" "HANDOFF-LOG.md" ""
    git -C "$REPO_ROOT" rev-parse -q --verify "refs/handoff/tm/feature%2Fx" && echo ENC-OK
    ref_read "feature/x" "HANDOFF.md"
  '
  [[ "$output" == *"ENC-OK"* ]]
  [[ "$output" == *"fx"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/.claude/handoff-plugin && bats test/refstore.bats`
Expected: the two new tests FAIL (ref still written at `refs/handoff/main`); the bare-ref check finds the old ref.

- [ ] **Step 3: Implement the per-machine ref scheme in `lib/refstore.sh`**

Replace the existing `_ref_name` definition:
```bash
_ref_name() { echo "refs/handoff/$1"; }
```
with:
```bash
# Machine name for ref namespacing — matches capture.sh CAP_HOST.
ref_machine() {
  printf '%s' "${HANDOFF_MACHINE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
}

# Percent-encode anything outside [A-Za-z0-9._-] so a branch or machine name
# becomes a single git-ref-safe path segment. Reversible via _ref_dec.
_ref_enc() {
  local s=$1 out= i c
  for (( i=0; i<${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._-]) out+=$c ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# Reverse _ref_enc for display (%2F -> /).
_ref_dec() { printf '%b' "${1//%/\\x}"; }

# This machine's ref for a branch: refs/handoff/<enc-machine>/<enc-branch>.
_ref_name() {
  printf 'refs/handoff/%s/%s' "$(_ref_enc "$(ref_machine)")" "$(_ref_enc "$1")"
}

# Legacy (pre-per-machine) ref, branch unencoded: refs/handoff/<branch>.
_ref_legacy_name() { printf 'refs/handoff/%s' "$1"; }
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd ~/.claude/handoff-plugin && bats test/refstore.bats`
Expected: the two new tests PASS. The three existing tests that hard-code `refs/handoff/main` (lines ~39, ~52, ~67) now FAIL — fix them in the next step.

- [ ] **Step 5: Update the existing `test/refstore.bats` assertions to the per-machine path**

In the test `"refstore: subsequent writes chain as parents"`, set the machine name and update the rev-list path. Change the `run bash -c '...'` body so it begins with `export REPO_ROOT="..." HANDOFF_MACHINE_NAME="tm"` and the last line reads:
```bash
    git -C "$REPO_ROOT" rev-list --count refs/handoff/tm/main
```
In `"refstore: push to origin succeeds when remote exists"`, add `HANDOFF_MACHINE_NAME="tm"` to the exports and change the final line to:
```bash
    git -C "'"$ORIGIN"'" rev-parse refs/handoff/tm/main
```
In `"refstore: push advances remote on subsequent pushes"`, add `HANDOFF_MACHINE_NAME="tm"` to the exports and change the final line to:
```bash
    git -C "'"$ORIGIN"'" show refs/handoff/tm/main:HANDOFF.md
```

- [ ] **Step 6: Update `test/hook.bats`**

In `run_hook()`, add the machine name to the env list so the ref is deterministic:
```bash
run_hook() {
  echo "{\"hook_event_name\":\"Stop\",\"cwd\":\"$REPO\",\"transcript_path\":\"$1\"}" \
    | HANDOFF_SUMMARY_DEBOUNCE_SECS=999999 \
      HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" \
      HANDOFF_MACHINE_NAME="tm" \
      bash "$PLUGIN_DIR/hook.sh"
}
```
In the test `"hook: writes the auto block into the ref, not the working tree"`, change the assertion line to:
```bash
  run git -C "$REPO" show refs/handoff/tm/main:HANDOFF.md
```

- [ ] **Step 7: Update `test/session-end.bats`**

Add `HANDOFF_MACHINE_NAME="tm"` to the env on the `session-end.sh` invocation and update the assertion. The invocation becomes:
```bash
  echo "{\"cwd\":\"$REPO\",\"transcript_path\":\"$tx\"}" \
    | HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      FAKE_CLAUDE_OUT="$FAKE_CLAUDE_OUT" HANDOFF_MACHINE_NAME="tm" \
      bash "$PLUGIN_DIR/session-end.sh"
  run git -C "$REPO" show refs/handoff/tm/main:HANDOFF.md
```

- [ ] **Step 8: Update `test/summarize.bats` (the two raw-path assertions)**

In the locked-skip test, add `HANDOFF_MACHINE_NAME="tm"` to the `export ...` line inside `run bash -c '...'` and change the final git line to:
```bash
    git -C "$REPO_ROOT" show refs/handoff/tm/main:HANDOFF.md 2>/dev/null || echo "NO-REF"
```
In the stale-lock test, add `HANDOFF_MACHINE_NAME="tm"` to the `export ...` line and change the final git line to:
```bash
    git -C "$REPO_ROOT" show refs/handoff/tm/main:HANDOFF.md
```

- [ ] **Step 9: Update `install.sh --verify` to check the per-machine ref**

In `install.sh`, the `--verify` branch currently computes `branch` then checks `refs/handoff/$branch`. Source refstore and check the per-machine ref. Replace this block:
```bash
  branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  if git -C "$repo" rev-parse -q --verify "refs/handoff/$branch" >/dev/null 2>&1; then
    echo "OK: refs/handoff/$branch written."
    exit 0
  fi
  echo "FAILED: no handoff ref written (rc=$rc). Check ~/.claude/hooks/handoff.log"
  exit 1
```
with:
```bash
  branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  source "$PLUGIN_DIR/lib/refstore.sh"
  ref="$(_ref_name "$branch")"
  if git -C "$repo" rev-parse -q --verify "$ref" >/dev/null 2>&1; then
    echo "OK: $ref written."
    exit 0
  fi
  echo "FAILED: no handoff ref written (rc=$rc). Check ~/.claude/hooks/handoff.log"
  exit 1
```

- [ ] **Step 10: Update `test/install.bats`**

Make the machine name deterministic and check the per-machine ref:
```bash
@test "install: --verify writes a ref in a throwaway repo" {
  make_repo
  HANDOFF_MACHINE_NAME="tm" run bash "$PLUGIN_DIR/install.sh" --verify "$REPO"
  [ "$status" -eq 0 ]
  run git -C "$REPO" show refs/handoff/tm/main:HANDOFF.md
  [[ "$output" == *"<!-- auto -->"* ]]
}
```

- [ ] **Step 11: Run the full suite — must be green**

Run: `cd ~/.claude/handoff-plugin && bats test/`
Expected: all tests PASS (existing behavior preserved, now on per-machine refs).

- [ ] **Step 12: Commit**

```bash
cd ~/.claude/handoff-plugin
git add lib/refstore.sh install.sh test/
git commit -m "feat: namespace handoff refs per machine (refs/handoff/<machine>/<branch>)"
```

---

## Task 2: Read-side aggregation helpers

**Files:**
- Modify: `lib/refstore.sh`
- Test: `test/perref.bats` (create)

- [ ] **Step 1: Write the failing test**

Create `test/perref.bats`:
```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/.claude/handoff-plugin && bats test/perref.bats`
Expected: the `ref_list_machines` and `ref_resume_dump` tests FAIL with "command not found" (helpers don't exist yet). The no-clobber test should already PASS (Task 1 gave us per-machine refs).

- [ ] **Step 3: Implement the helpers in `lib/refstore.sh`**

Append to `lib/refstore.sh`:
```bash
# List every machine with a note for <branch> (excludes the legacy bare ref).
# Prints one line per machine: "<machine><TAB><refname>".
ref_list_machines() {
  local branch=$1 eb; eb=$(_ref_enc "$branch")
  local r rest m
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$r" in
      refs/handoff/*/"$eb")
        rest=${r#refs/handoff/}
        m=${rest%/*}
        case "$m" in */*) continue ;; esac   # skip deeper nesting
        printf '%s\t%s\n' "$(_ref_dec "$m")" "$r"
        ;;
    esac
  done < <(git -C "$REPO_ROOT" for-each-ref --format='%(refname)' refs/handoff/ 2>/dev/null)
}

# Dump every machine's note for <branch> (newest first), plus the legacy ref if
# present, as delimited blocks for the resume skill to narrate.
ref_resume_dump() {
  local branch=$1 ct m r lr
  {
    while IFS=$'\t' read -r m r; do
      [ -n "$r" ] || continue
      ct=$(git -C "$REPO_ROOT" log -1 --format='%ct' "$r" 2>/dev/null || echo 0)
      printf '%s\t%s\t%s\n' "$ct" "$m" "$r"
    done < <(ref_list_machines "$branch")
    lr=$(_ref_legacy_name "$branch")
    if git -C "$REPO_ROOT" rev-parse -q --verify "$lr" >/dev/null 2>&1; then
      ct=$(git -C "$REPO_ROOT" log -1 --format='%ct' "$lr" 2>/dev/null || echo 0)
      printf '%s\t%s\t%s\n' "$ct" "(legacy)" "$lr"
    fi
  } | sort -rn | while IFS=$'\t' read -r ct m r; do
    [ -n "$r" ] || continue
    printf '===HANDOFF machine=%s ref=%s===\n' "$m" "$r"
    git -C "$REPO_ROOT" show "$r:HANDOFF.md" 2>/dev/null || true
    printf '\n---LOG (top entry)---\n'
    git -C "$REPO_ROOT" show "$r:HANDOFF-LOG.md" 2>/dev/null \
      | awk 'BEGIN{n=0} /^## /{n++} n>=2{exit} {print}'
    printf '\n'
  done
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ~/.claude/handoff-plugin && bats test/perref.bats`
Expected: all three tests PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/handoff-plugin
git add lib/refstore.sh test/perref.bats
git commit -m "feat: ref_list_machines + ref_resume_dump for multi-machine resume"
```

---

## Task 3: Throttled background fetch in the Stop hook

**Files:**
- Modify: `lib/refstore.sh` (add `fetch_due`)
- Create: `lib/run-fetch.sh`
- Modify: `hook.sh`
- Test: `test/fetch.bats` (create)

- [ ] **Step 1: Write the failing test**

Create `test/fetch.bats`:
```bash
# test/fetch.bats
load helpers

@test "fetch_due: true first call, false within window, true after window" {
  make_repo
  run bash -c '
    export REPO_ROOT="'"$REPO"'"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    export HANDOFF_FETCH_THROTTLE_SECS=60
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    fetch_due && echo "first=due"
    fetch_due || echo "second=throttled"
    # Backdate the stamp beyond the window.
    dir="$XDG_STATE_HOME/claude-handoff"
    hash=$(printf "%s" "$REPO_ROOT" | cksum | awk "{print \$1}")
    echo $(( $(date +%s) - 120 )) > "$dir/$hash.fetch"
    fetch_due && echo "third=due"
  '
  [[ "$output" == *"first=due"* ]]
  [[ "$output" == *"second=throttled"* ]]
  [[ "$output" == *"third=due"* ]]
}

@test "run-fetch.sh: pulls handoff refs from origin" {
  make_repo; add_origin
  # Push a per-machine note from a "remote" clone so origin has a handoff ref.
  CLONE="$BATS_TEST_TMPDIR/clone"
  git clone -q "$ORIGIN" "$CLONE"
  HANDOFF_MACHINE_NAME="other" bash -c '
    log() { :; }
    export REPO_ROOT="'"$CLONE"'" HANDOFF_MACHINE_NAME="other"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "main" "HANDOFF.md" "from-other" "HANDOFF-LOG.md" ""
    ref_push "main"
  '
  HANDOFF_LOG_PATH="$BATS_TEST_TMPDIR/h.log" bash "$PLUGIN_DIR/lib/run-fetch.sh" "$REPO"
  run git -C "$REPO" show refs/handoff/other/main:HANDOFF.md
  [[ "$output" == *"from-other"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/.claude/handoff-plugin && bats test/fetch.bats`
Expected: FAIL — `fetch_due` not defined and `lib/run-fetch.sh` does not exist.

- [ ] **Step 3: Add `fetch_due` to `lib/refstore.sh`**

Append to `lib/refstore.sh`:
```bash
# Returns 0 if a background fetch is due for this repo (and records "now"),
# 1 if throttled. Window via HANDOFF_FETCH_THROTTLE_SECS (default 60s).
fetch_due() {
  local win=${HANDOFF_FETCH_THROTTLE_SECS:-60}
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-handoff"
  mkdir -p "$dir" 2>/dev/null || return 0
  local hash; hash=$(printf '%s' "$REPO_ROOT" | cksum | awk '{print $1}')
  local stamp="$dir/$hash.fetch"
  local now; now=$(date +%s)
  if [ "$win" -gt 0 ] && [ -f "$stamp" ]; then
    local prev; prev=$(cat "$stamp" 2>/dev/null || echo 0)
    if [[ "$prev" =~ ^[0-9]+$ ]] && [ $(( now - prev )) -lt "$win" ]; then
      return 1
    fi
  fi
  echo "$now" > "$stamp" 2>/dev/null || true
  return 0
}
```

- [ ] **Step 4: Create `lib/run-fetch.sh`**

```bash
#!/usr/bin/env bash
# Detached wrapper: fetch handoff refs without blocking the hook.
# Args: REPO_ROOT
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT="${1:-}"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }
[ -n "$REPO_ROOT" ] || exit 0
source "$PLUGIN_DIR/lib/refstore.sh"
ref_fetch
exit 0
```
Then make it executable:
```bash
chmod +x ~/.claude/handoff-plugin/lib/run-fetch.sh
```

- [ ] **Step 5: Wire the throttled fetch into `hook.sh`**

In `hook.sh`, immediately AFTER the `if ref_write ... fi` block (the one ending at the line with the closing `fi` after the detached push, around line 42) and BEFORE the summarizer block, insert:
```bash
# Pull other machines' notes in the background (throttled) so a long-running
# session stays current. Detached so the network never blocks the turn.
if fetch_due; then
  ( nohup bash "$PLUGIN_DIR/lib/run-fetch.sh" "$REPO_ROOT" >/dev/null 2>&1 & ) || true
fi
```
(`refstore.sh` is already sourced at the top of `hook.sh`, and `REPO_ROOT` is exported by `preflight`.)

- [ ] **Step 6: Run to verify it passes**

Run: `cd ~/.claude/handoff-plugin && bats test/fetch.bats`
Expected: both tests PASS.

- [ ] **Step 7: Run the full suite (hook.sh changed)**

Run: `cd ~/.claude/handoff-plugin && bats test/`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
cd ~/.claude/handoff-plugin
git add lib/refstore.sh lib/run-fetch.sh hook.sh test/fetch.bats
git commit -m "feat: throttled background fetch of handoff refs in the Stop hook"
```

---

## Task 4: Heads-up on sibling updates

**Files:**
- Create: `lib/headsup.sh`
- Create: `user-prompt.sh`
- Test: `test/headsup.bats` (create)

- [ ] **Step 1: Write the failing test**

Create `test/headsup.bats`:
```bash
# test/headsup.bats
load helpers

_write_as() { # <machine> <branch> <body>
  HANDOFF_MACHINE_NAME="$1" bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="'"$1"'"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    ref_write "'"$2"'" "HANDOFF.md" "'"$3"'" "HANDOFF-LOG.md" ""
  '
}

_headsup() { # runs headsup_line as machine "me"
  bash -c '
    log() { :; }
    export REPO_ROOT="'"$REPO"'" HANDOFF_MACHINE_NAME="me"
    export XDG_STATE_HOME="'"$BATS_TEST_TMPDIR"'/state"
    source "'"$PLUGIN_DIR"'/lib/refstore.sh"
    source "'"$PLUGIN_DIR"'/lib/headsup.sh"
    headsup_line "main"
  '
}

@test "headsup: announces a changed sibling exactly once" {
  make_repo
  _write_as desktop main "d1"
  run _headsup
  [[ "$output" == *"desktop updated its handoff"* ]]
  # Second call with no change: silent (deduped by sha).
  run _headsup
  [ -z "$output" ]
}

@test "headsup: re-announces when the sibling changes again" {
  make_repo
  _write_as desktop main "d1"
  _headsup >/dev/null            # prime the seen-state
  _write_as desktop main "d2"    # sibling advances
  run _headsup
  [[ "$output" == *"desktop updated its handoff"* ]]
}

@test "headsup: never announces this machine's own note" {
  make_repo
  _write_as me main "mine"
  run _headsup
  [ -z "$output" ]
}

@test "user-prompt.sh: exits 0 and is silent outside a git repo" {
  run bash -c 'echo "{\"cwd\":\"'"$BATS_TEST_TMPDIR"'\"}" | bash "'"$PLUGIN_DIR"'/user-prompt.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/.claude/handoff-plugin && bats test/headsup.bats`
Expected: FAIL — `headsup_line` undefined and `user-prompt.sh` missing.

- [ ] **Step 3: Create `lib/headsup.sh`**

```bash
# headsup.sh - detect sibling machines' handoff updates and emit a one-line
# heads-up. No network. Requires REPO_ROOT and a sourced refstore.sh.

# Humanize a duration in seconds to "Nm" / "Nh" / "Nd".
_ago() {
  local s=$1
  [ "$s" -lt 0 ] && s=0
  if [ "$s" -lt 3600 ]; then printf '%dm' $(( s / 60 ))
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

  local changed="" newest=-1
  local m r sha prev ct
  while IFS=$'\t' read -r m r; do
    [ -n "$r" ] || continue
    case "$r" in refs/handoff/"$self"/*) continue ;; esac
    sha=$(git -C "$REPO_ROOT" rev-parse "$r" 2>/dev/null) || continue
    prev=$(grep -F "$r " "$seen" 2>/dev/null | awk '{print $2}' | head -n1)
    if [ "$sha" != "$prev" ]; then
      ct=$(git -C "$REPO_ROOT" log -1 --format='%ct' "$r" 2>/dev/null || echo "$now")
      if [ "$ct" -ge "$newest" ]; then newest=$ct; changed="$m|$(_ago $(( now - ct )))"; fi
    fi
  done < <(ref_list_machines "$branch")

  _headsup_write_seen "$branch" "$self" "$seen"

  [ -n "$changed" ] || return 0
  printf 'note: %s updated its handoff ~%s ago\n' "${changed%%|*}" "${changed##*|}"
}
```

- [ ] **Step 4: Create `user-prompt.sh`**

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook: emit a one-line heads-up if another machine updated its
# handoff. Pure local reads (no network). Always exits 0 so it never blocks a
# prompt; prints at most one line of context to stdout.
set -u
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_LOG_PATH="${HANDOFF_LOG_PATH:-$HOME/.claude/hooks/handoff.log}"
mkdir -p "$(dirname "$HANDOFF_LOG_PATH")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$HANDOFF_LOG_PATH" 2>/dev/null || true; }

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null || echo '{}')
CWD=$(jq -r '.cwd // empty' <<<"$PAYLOAD" 2>/dev/null); [ -z "$CWD" ] && CWD=$PWD

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
export REPO_ROOT
BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null) || exit 0

source "$PLUGIN_DIR/lib/refstore.sh"
source "$PLUGIN_DIR/lib/headsup.sh"
headsup_line "$BRANCH" 2>>"$HANDOFF_LOG_PATH" || true
exit 0
```
Then:
```bash
chmod +x ~/.claude/handoff-plugin/user-prompt.sh
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd ~/.claude/handoff-plugin && bats test/headsup.bats`
Expected: all four tests PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/.claude/handoff-plugin
git add lib/headsup.sh user-prompt.sh test/headsup.bats
git commit -m "feat: UserPromptSubmit heads-up when a sibling machine updates its handoff"
```

---

## Task 5: Wire the UserPromptSubmit hook

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `~/.claude/settings.json` (machine-local, NOT committed)

- [ ] **Step 1: Add the hook to `hooks/hooks.json`**

Replace the file contents with (adds `UserPromptSubmit`; Stop/SessionEnd unchanged):
```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hook.sh\"", "timeout": 45 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/session-end.sh\"", "timeout": 120 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/user-prompt.sh\"", "timeout": 10 } ] }
    ]
  }
}
```

- [ ] **Step 2: Validate the manifest**

Run: `claude plugin validate ~/.claude/handoff-plugin`
Expected: reports the manifest as valid (no errors).

- [ ] **Step 3: Mirror the hook into local `~/.claude/settings.json`**

This machine uses the manual settings.json wiring (not a marketplace plugin). Add a `UserPromptSubmit` entry alongside the existing `Stop` and `SessionEnd` hooks, pointing at the absolute path. The `hooks` object should contain:
```json
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/handoff-plugin/user-prompt.sh",
            "timeout": 10
          }
        ]
      }
    ]
```

- [ ] **Step 4: Verify settings.json is valid JSON**

Run: `jq -e . ~/.claude/settings.json >/dev/null && echo valid`
Expected: `valid`.

- [ ] **Step 5: Commit (repo manifest only; settings.json is machine-local)**

```bash
cd ~/.claude/handoff-plugin
git add hooks/hooks.json
git commit -m "feat: register UserPromptSubmit hook in plugin manifest"
```

---

## Task 6: Multi-machine resume in the skill

**Files:**
- Modify: `skills/handoff/SKILL.md`

- [ ] **Step 1: Rewrite the "On session start" and "What to present" sections**

Replace the body between the `# Handoff` intro and the `## Trigger words` section so it reads:
```markdown
## On session start

1. Confirm cwd is a git repo. If not, do nothing.
2. Fetch handoff refs (silent, non-fatal):
   `git fetch -q origin 'refs/handoff/*:refs/handoff/*' 2>/dev/null || true`
3. Dump every machine's note for the current branch. Run:
   ```
   bash -c 'source ~/.claude/handoff-plugin/lib/refstore.sh; \
     export REPO_ROOT=$(git rev-parse --show-toplevel); \
     ref_resume_dump "$(git symbolic-ref --short HEAD)"'
   ```
   Each note is a block headed `===HANDOFF machine=<name> ref=<ref>===` with the
   machine's `HANDOFF.md` then its top `HANDOFF-LOG.md` entry. A block headed
   `machine=(legacy)` is a pre-upgrade note from the old single-ref layout —
   treat it as one more machine. If the dump is empty, do nothing and continue
   normally.
4. Detect drift: compare the recorded last commit in the most recent note
   against `git log -1 --format=%h` and check `git status -s`.

## What to present (propose, don't act)

One short paragraph for the most recent machine, then wait:

> "Last on `<machine>`, `<age>` ago. **Goal:** `<goal>`. **Next:** `<the single next step>`. Avoid: `<top failed approach>`. Want me to pick this up?"

If other machines also have notes, add one line:
> "Also has notes: `<machine>` (`<age>`), `<machine>` (`<age>`)."

If drift was detected, add:
> "Note: repo has moved since the handoff (handoff at `<sha>`, now at `<sha>`)."

**Do not** auto-read files, auto-run tests, or start work until the user confirms.

## On confirmation

1. Read the files listed under "Files touched this session" in the chosen note.
2. Summarize the current state and the proposed next step concretely.
3. Ask the user to confirm the next step before executing it.
```

- [ ] **Step 2: Update the front-matter description**

Change the `description:` line in the YAML front-matter to:
```yaml
description: Use when starting a session, when the user mentions handoff/resume/"where was I"/"pick up where I left off", or when switching machines. Aggregates every machine's handoff note for the branch and offers a propose-don't-act resume. Coexists with Stop/SessionEnd/UserPromptSubmit hooks that maintain the handoff automatically.
```

- [ ] **Step 3: Manually verify the dump command works end to end**

Run (in a repo that has a handoff ref written by Task 1+):
```bash
cd ~/.claude/handoff-plugin
bash -c 'source ~/.claude/handoff-plugin/lib/refstore.sh; export REPO_ROOT=$(git rev-parse --show-toplevel); ref_resume_dump "$(git symbolic-ref --short HEAD)"'
```
Expected: at least one `===HANDOFF machine=... ===` block prints with HANDOFF.md content. (If none yet, write one first via `bash install.sh --verify .`.)

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/handoff-plugin
git add skills/handoff/SKILL.md
git commit -m "feat: multi-machine resume in the handoff skill"
```

---

## Task 7: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the per-machine model + freshness**

Update the README's behavior section (around line 48, the "On session start ... fetches `refs/handoff/*`" paragraph). Replace that paragraph with:
```markdown
Handoffs are stored per machine in `refs/handoff/<machine>/<branch>` (machine
name from `HANDOFF_MACHINE_NAME`, else `hostname -s`). Two machines on the same
branch never overwrite each other. On session start the skill fetches
`refs/handoff/*`, aggregates every machine's note for the branch (plus a legacy
`refs/handoff/<branch>` ref if one predates the upgrade), detects drift between
the recorded commit and current HEAD, and presents a one-paragraph resume
proposal — then **waits for confirmation**.

While a session runs, the Stop hook also pulls other machines' notes in the
background (throttled by `HANDOFF_FETCH_THROTTLE_SECS`, default 60s), and a
`UserPromptSubmit` hook surfaces a one-line heads-up the first time another
machine's note changes.
```
Add the new env vars to any existing "Optional config" list:
```markdown
  HANDOFF_FETCH_THROTTLE_SECS=60   # min seconds between background fetches
```
Add `lib/headsup.sh`, `lib/run-fetch.sh`, and `user-prompt.sh` to the file-tree
listing, and `fetch.bats`, `headsup.bats`, `perref.bats` to the `test/` listing.

- [ ] **Step 2: Commit**

```bash
cd ~/.claude/handoff-plugin
git add README.md
git commit -m "docs: per-machine handoff notes + mid-session freshness"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run the entire test suite**

Run: `cd ~/.claude/handoff-plugin && bats test/`
Expected: every test PASSES (existing + new: perref, fetch, headsup).

- [ ] **Step 2: End-to-end smoke against a throwaway repo**

Run:
```bash
tmp=$(mktemp -d); git -C "$tmp" init -q -b main
git -C "$tmp" config user.email t@e.st; git -C "$tmp" config user.name t
git -C "$tmp" commit -q --allow-empty -m init
HANDOFF_MACHINE_NAME=alpha bash ~/.claude/handoff-plugin/install.sh --verify "$tmp"
HANDOFF_MACHINE_NAME=beta  bash ~/.claude/handoff-plugin/install.sh --verify "$tmp"
echo '--- refs ---'; git -C "$tmp" for-each-ref refs/handoff/
echo '--- dump ---'
bash -c 'source ~/.claude/handoff-plugin/lib/refstore.sh; export REPO_ROOT="'"$tmp"'"; ref_resume_dump main'
rm -rf "$tmp"
```
Expected: two refs `refs/handoff/alpha/main` and `refs/handoff/beta/main`; the dump prints both machines' blocks. No `refs/handoff/main` bare ref.

- [ ] **Step 3: Confirm the live wiring is valid**

Run:
```bash
claude plugin validate ~/.claude/handoff-plugin
jq -e '.hooks.UserPromptSubmit' ~/.claude/settings.json >/dev/null && echo "settings wired"
```
Expected: manifest valid; `settings wired`.

- [ ] **Step 4: Final commit if anything is uncommitted**

```bash
cd ~/.claude/handoff-plugin && git status --short
```
Expected: clean (all work committed). The `~/.claude/settings.json` change is intentionally outside the repo and not shown here.

---

## Notes / risks

- **UserPromptSubmit context injection:** the heads-up relies on `UserPromptSubmit` stdout (exit 0) being added to the turn's context. The unit tests verify the script's stdout behavior directly, which is independent of how Claude Code consumes it. If a future CC version stops injecting plain stdout, switch `user-prompt.sh` to emit `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<line>"}}` instead — the heads-up logic in `lib/headsup.sh` is unchanged.
- **`for-each-ref` pattern matching** is deliberately avoided for branch filtering; `ref_list_machines` enumerates all `refs/handoff/` and filters in shell to dodge `wildmatch`/`FNM_PATHNAME` ambiguity across `/`.
- **Multibyte branch/machine names:** `_ref_enc` encodes per character; exotic UTF-8 names may not round-trip byte-perfectly. Out of scope (YAGNI) — git branch and host names are ASCII in practice.
