# claude-handoff

A Claude Code plugin that hands off work between your own machines without you thinking about it. After every Claude turn a fast bash hook writes a snapshot into a dedicated git ref. At session end (and debounced every ~5 minutes), a headless Haiku call adds a Goal / Done / Failed / Next narrative. Open the same repo on another machine, start a session, and Claude tells you what was happening and proposes the next step — without touching your working tree or branch history.

## How it works

There are two layers and they compose: the mechanical floor guarantees state is never lost; the intelligent ceiling adds the "why" context. Both always exit 0 — nothing the plugin does can break your session.

### Stop hook (`hook.sh`)

Runs after every Claude turn. Fast, no LLM cost.

**Preflight checks** (any failure → silent exit):

- cwd is inside a git repo with a non-detached HEAD
- `HANDOFF_DISABLE=1` is not set
- no `.no-handoff` file at the repo root
- shared-repo detection: if recent history shows more than one committer and the origin URL is not in `HANDOFF_OWN_REMOTES`, the repo is treated as shared and the hook stays off unless a `.handoff-enable` file is present at the repo root

**Capture:** git branch, last commit, `git status -s` (capped at 50 lines), `git diff --stat HEAD` (capped at 30 lines), files edited this session (parsed from the Claude session transcript by looking for `Edit`/`Write`/`NotebookEdit` tool calls), and the last assistant message (all text blocks joined, redacted first, then truncated to `HANDOFF_MAX_MESSAGE_CHARS`).

**Write:** assembles `HANDOFF.md` (auto block + any existing narrative block preserved verbatim from the prior ref state) and writes both `HANDOFF.md` and `HANDOFF-LOG.md` into `refs/handoff/<branch>` using git plumbing (`hash-object` → `mktree` → `commit-tree` → `update-ref`). The working tree and index are never touched.

**Push:** spawns a detached child process (`lib/run-push.sh`) that pushes the ref with `--force-with-lease`. A slow or unreachable remote never blocks the turn.

**Debounce + summarizer:** if `claude` is on PATH and the debounce window has elapsed, spawns a detached child (`lib/run-summarize.sh`) that calls the Haiku summarizer. The hook never waits for it.

### SessionEnd hook (`session-end.sh`)

Runs once at session end, synchronously. Calls `summarize_handoff` directly (ignoring debounce) so the final state of every session is always summarized.

### Summarizer (`lib/summarize.sh`)

Called by the SessionEnd hook and the debounced detached spawn from the Stop hook.

- Reads the transcript and sends it to `claude -p` with model `${HANDOFF_SUMMARY_MODEL:-claude-haiku-4-5}`.
- The prompt asks for a narrative block (Goal / Done / Failed approaches / Next) and one journal line (Did / Decided+why / Failed), separated by `===JOURNAL===`.
- Redacts the model output.
- Strips any code fences the model may have added around the output.
- Validates that `<!-- /narrative -->` is present (guards against a malformed response consuming the journal text).
- Reads the existing `HANDOFF.md` from the ref, replaces the narrative block, and calls `ref_write` + `ref_push`.
- Prepends a timestamped journal entry (newest on top) to `HANDOFF-LOG.md`.
- Degrades silently to a no-op if `claude` is absent, the transcript is missing, or the `claude -p` call fails.
- Runs with `HANDOFF_DISABLE=1` set in the child environment so it does not trigger handoff hooks recursively.

### Resume (`handoff` skill)

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

Each note has a SHA-pinned web permalink. Although the handoff lives in a
non-branch ref, the commit it points to is pushed to the remote, so GitHub
(`/blob/<sha>/HANDOFF.md`) and GitLab (`/-/blob/<sha>/HANDOFF.md`) render it by
SHA. The resume skill shows this link per machine (other remotes get a
`git show <ref>:HANDOFF.md` command instead).

The `/handoff` command lets you trigger a manual rich narrative pass beyond what the summarizer writes automatically.

## What ends up in the ref

### `HANDOFF.md` — current snapshot

```markdown
<!-- auto -->
# Handoff
**Machine:** ghost-thinkpad
**Branch:** main · last commit: `bc9622d Embed severity model`
**Updated:** 2026-06-02T07:56:53Z

## Working tree
```
 M docs/design.md
```

## Diff stat
```
 docs/design.md | 12 +++---
 1 file changed, 6 insertions(+), 6 deletions(-)
```

## Files touched this session
- worker/docker/run-scan.sh

## Last action (Claude)
> Build complete. Image `recon-scanner:latest` built clean.
<!-- /auto -->

<!-- narrative -->
## Goal
Wire pentest-pro into the scan worker.
## Done
- recon-scanner image builds clean
## Failed approaches (don't repeat)
- `--privileged` — too permissive; NET_ADMIN + NET_RAW + /dev/net/tun is enough.
## Next
1. Add `--cap-add NET_RAW` to runner.py
<!-- /narrative -->
```

The `<!-- auto -->` block is rewritten every turn by the Stop hook. The `<!-- narrative -->` block is written by the Haiku summarizer (or the `/handoff` command) and is preserved verbatim by the hook between summarizer runs.

### `HANDOFF-LOG.md` — append-only rationale journal

Newest entry on top. One entry per summarizer run:

```markdown
## 2026-06-02T07:56Z — ghost-thinkpad — main
**Did:** wired pentest-pro into the scan worker; image builds clean.
**Decided:** NET_ADMIN + NET_RAW + /dev/net/tun instead of --privileged — why: least privilege that still lets raw sockets work.
**Failed:** --privileged (too permissive).
```

Uncapped by default. Set `HANDOFF_LOG_MAX_ENTRIES` to trim to N newest entries.

## Install

This is a Claude Code plugin. The manifest (`.claude-plugin/plugin.json`) wires the Stop + SessionEnd hooks; the `handoff` skill and `/handoff` command are auto-discovered from the `skills/` and `commands/` directories.

```bash
# Register the plugin
/plugin install /path/to/claude-handoff

# Validate the manifest
claude plugin validate /path/to/claude-handoff

# Verify the hook works in any git repo
bash /path/to/claude-handoff/install.sh --verify .
```

`install.sh` without `--verify` prints the same guidance above along with a dependency check.

**Dependencies:** `git`, `bash` >= 5, `jq`, `perl`. The `claude` CLI is required for the Haiku summarizer; without it the plugin degrades to the mechanical snapshot only (still fully functional as a state sync tool).

## Config

| Env var / marker | Default | What it does |
|---|---|---|
| `HANDOFF_DISABLE=1` | unset | No-op the hook and summarizer for the current shell. |
| `.no-handoff` (file at repo root) | absent | Force-disable handoff for that repo. |
| `.handoff-enable` (file at repo root) | absent | Opt a shared repo in. Required when the repo is detected as shared. |
| `HANDOFF_OWN_REMOTES` | unset | Comma-separated list of account/org/host substrings. If the origin URL matches any entry, the repo is treated as personal (no `.handoff-enable` needed). |
| `HANDOFF_MACHINE_NAME` | `hostname -s` | Friendly machine name shown in `HANDOFF.md`. Useful if two machines have the same hostname. |
| `HANDOFF_SUMMARY_MODEL` | `claude-haiku-4-5` | Model used by the Haiku summarizer. |
| `HANDOFF_SUMMARY_DEBOUNCE_SECS` | `300` | Minimum seconds between mid-session summarizer runs from the Stop hook. |
| `HANDOFF_FETCH_THROTTLE_SECS` | `60` | Minimum seconds between background fetches of other machines' notes (Stop hook). |
| `HANDOFF_MAX_MESSAGE_CHARS` | `2000` | Truncation length for the captured last assistant message (applied after redaction). |
| `HANDOFF_LOG_MAX_ENTRIES` | unset (unlimited) | Trim `HANDOFF-LOG.md` to N newest entries. |
| `HANDOFF_LOG_PATH` | `~/.claude/hooks/handoff.log` | Where the hook's own debug log goes. |

## Safety

**History stays clean.** Handoff data lives only in `refs/handoff/<branch>` — never committed to your working branch, never in `git log`, never in `git status`, never visible to CI.

**Force pushes are bounded.** The ref is pushed with `--force-with-lease` using an explicit lease on the remote SHA. If another machine has pushed in the meantime, the push aborts and logs; the next turn retries cleanly. Last-writer-wins is intentional for a single-user tool.

**Secret redaction.** The last assistant message and the Haiku summary output are both run through `lib/redact.sh` before being stored. Redaction happens before truncation so a secret cannot straddle the cut boundary. Categories scrubbed (ordered, most-specific first):

- PEM private key blocks (`-----BEGIN ... PRIVATE KEY-----`)
- API keys: `sk-...` (OpenAI / Anthropic style)
- GitHub tokens: `gh[pousar]_...`
- AWS access keys: `AKIA[A-Z0-9]{16}`
- Slack tokens: `xox[baprs]-...`
- JWTs: `eyJ....eyJ....`
- Bearer auth headers
- Uppercase env assignments ending in `_KEY`, `_TOKEN`, `_SECRET`, `_PASSWORD`, `_PASS`
- Lowercase assignments: `api_key=` / `apikey=` / `api-key=`, `token=`, `secret=`, `password=`, `passwd=`, `pass=` (case-insensitive)

Documented as best-effort. Do not paste production credentials into Claude.

**Hooks always exit 0.** Any failure (missing tool, unreachable remote, corrupt transcript, failed LLM call) is logged to `HANDOFF_LOG_PATH` and the hook bails silently. Your session is never interrupted.

**Shared-repo detection.** A repo is personal (handoff auto-on) when the origin URL matches `HANDOFF_OWN_REMOTES` or when only one committer appears in the last 90 days of history. Otherwise it is treated as shared and handoff stays off until you drop `.handoff-enable` at the repo root.

## Layout

```
claude-handoff/
├── .claude-plugin/
│   └── plugin.json          # plugin manifest: hooks, skill, command
├── hooks/
│   └── hooks.json           # Stop + SessionEnd + UserPromptSubmit hook declarations
├── hook.sh                  # Stop hook entrypoint
├── session-end.sh           # SessionEnd hook entrypoint
├── user-prompt.sh           # UserPromptSubmit hook: other-machine heads-up
├── lib/
│   ├── preflight.sh         # bail checks + shared-repo detection
│   ├── capture.sh           # git + transcript → CAP_* vars
│   ├── redact.sh            # ordered secret scrubbing
│   ├── render.sh            # assemble HANDOFF.md, preserve narrative
│   ├── refstore.sh          # git plumbing: read/write/push handoff ref
│   ├── debounce.sh          # rate-limit summarizer per repo+branch
│   ├── headsup.sh           # diff other machines' notes; emit heads-up line
│   ├── summarize.sh         # claude -p Haiku → narrative + journal
│   ├── run-fetch.sh         # detached wrapper: throttled fetch of remote refs
│   ├── run-push.sh          # detached wrapper: push ref
│   └── run-summarize.sh     # detached wrapper: run summarizer
├── skills/handoff/
│   └── SKILL.md             # session-start fetch + propose-don't-act resume
├── commands/
│   └── handoff.md           # /handoff manual narrative command
├── install.sh               # print guidance + --verify self-check
└── test/
    ├── helpers.bash
    ├── capture.bats
    ├── debounce.bats
    ├── fetch.bats
    ├── headsup.bats
    ├── hook.bats
    ├── install.bats
    ├── perref.bats
    ├── preflight.bats
    ├── redact.bats
    ├── refstore.bats
    ├── render.bats
    ├── session-end.bats
    ├── smoke.bats
    ├── summarize.bats
    └── weburl.bats
```
