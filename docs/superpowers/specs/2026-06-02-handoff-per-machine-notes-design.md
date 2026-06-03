# Per-machine handoff notes + mid-session freshness

Date: 2026-06-02
Status: Design approved, pending implementation plan

## Problem

The handoff is stored in a single per-branch git ref, `refs/handoff/<branch>`,
holding `HANDOFF.md` (a rebuilt snapshot) and `HANDOFF-LOG.md` (a journal,
newest entry prepended, each entry stamped with timestamp + machine name).

Two timing problems:

1. **Clobbering (write side).** The save path (`lib/summarize.sh`) reads the
   *local* ref, rebuilds both files, and pushes. It never fetches first. When
   two machines run sessions on the same branch, the second to push overwrites
   the first's note. `--force-with-lease` does not protect against this: the
   push helper re-reads the remote sha via `ls-remote` immediately before
   pushing and leases against that, so it almost always force-succeeds. Last
   writer wins; the other machine's snapshot and journal entries are lost.

2. **Staleness (read side).** The remote handoff is fetched only once, at
   session start, by the skill (`skills/handoff/SKILL.md`). No hook ever
   fetches. A long-running session, or a session overlapping with another
   machine's session, works off a snapshot of remote taken at start and never
   sees later updates from other machines until a fresh session begins.

These reduce to one job: **a running session should pull other machines'
writes mid-session, and saving must never lose any machine's writes.**

Note: a truly solo long session has nothing newer on remote than itself, so
the staleness problem only bites in combination with another machine writing.
Both reported cases (overlapping sessions; long single session) are covered by
the same fix.

## Goals

- Two machines on the same branch never overwrite each other's handoff.
- A running session keeps its local copy of all machines' notes current in the
  background, without slowing down turns.
- When another machine's note changes, the running session surfaces a brief,
  deduplicated heads-up.
- Graceful rollout: machines on the old version keep working; no data loss
  during the transition.
- Preserve the existing fail-safe philosophy: every hook exits 0, logs to
  `handoff.log`, all network time-boxed.

## Non-goals

- Merging two machines' *snapshots* into one. Each machine keeps its own
  snapshot; the reader presents them side by side.
- Real-time push notification to a running session (OS-level). The heads-up
  rides along with the user's next message as injected context.
- Conflict resolution UI. Per-machine refs make write conflicts impossible, so
  there is nothing to resolve.

## Design

### 1. Ref naming + migration (machine-first)

Each note lives at:

```
refs/handoff/<machine>/<branch>
```

Both segments are sanitized so each stays a single path component (a `/` in a
branch like `feature/x` is encoded, e.g. percent-encoded to `feature%2Fx`).
The encoding does not need to be reversible: when reading, the current branch
and machine are known from context, so we compute the encoded form and match
against it rather than decoding.

**Machine-first is deliberate.** The old ref is `refs/handoff/<branch>` (e.g.
`refs/handoff/main`). Git cannot hold both a ref `refs/handoff/main` and a
directory `refs/handoff/main/` (directory/file conflict). Branch-first
(`refs/handoff/main/laptop`) would collide with the legacy ref. Machine-first
(`refs/handoff/laptop/main`) sits cleanly alongside `refs/handoff/main`.

**Migration: none required.** Because the new refs never collide with the
legacy ref:

- Writers only ever write their own `refs/handoff/<machine>/<branch>`.
- The resume reader also reads the legacy `refs/handoff/<branch>` if it still
  exists, presenting it as one additional, un-attributed note.
- A machine still on the old version keeps updating the legacy ref; a machine
  on the new version writes its own. Resume shows both. No deletion, no race,
  no data loss. The legacy ref naturally stops updating once every machine
  upgrades, and ages out.

**Machine identity:** reuse the existing convention from `summarize.sh` —
`HANDOFF_MACHINE_NAME` if set, else `hostname -s` — sanitized for the ref path.

**Listing all machines for a branch:** enumerate `refs/handoff/*` via
`for-each-ref` and keep refs whose last path segment equals the current
encoded branch. Filtering is done in code, not via glob, to avoid
`wildmatch`/`FNM_PATHNAME` edge cases.

### 2. Write path (clobber fix)

- A helper in `lib/refstore.sh` computes this machine's own ref and does all
  read/write/push against only that ref.
- `lib/summarize.sh` builds `HANDOFF.md` and `HANDOFF-LOG.md` exactly as today,
  but reads its *own* prior note as the base (not the shared ref). The journal
  therefore stays single-machine — clean and short per machine.
- Push targets only the machine's own ref. Only one machine ever writes it, so
  there is no contention; the lease remains as a cheap safety net for the
  pathological same-name-on-two-hosts case but never mediates a real conflict.

Result: each machine grows its own note; nothing one machine writes can
overwrite another's.

### 3. Read / resume (multi-machine view)

`skills/handoff/SKILL.md` changes from reading one ref to gathering all:

1. Fetch `refs/handoff/*` (unchanged).
2. Collect every `refs/handoff/<machine>/<branch>` for the current branch, plus
   the legacy `refs/handoff/<branch>` if present.
3. Sort notes by last-commit time.
4. Present, still propose-don't-act:
   > "Last on **laptop**, 12m ago. **Goal:** … **Next:** … Avoid: … Want me to pick this up?"
   > "Also has notes: desktop (3h ago), ci (1d ago)."
5. Drift detection (recorded last commit vs current HEAD) runs against the most
   recent note, as today.
6. If only one machine has a note, the output reads identically to today's
   single-machine experience.

### 4. Freshness: passive refresh + active heads-up

Both pieces stay off the turn's critical path.

**Passive refresh — addition to the existing Stop hook (`hook.sh`).**
The Stop hook already fires every turn and spawns a detached push. Add a
detached, throttled fetch of `refs/handoff/*` alongside it:

- Detached (`nohup … &`) — never blocks the turn.
- Throttled via a timestamp file in `$XDG_STATE_HOME/claude-handoff/` — at most
  one fetch per ~60s regardless of turn rate.
- Time-boxed (`timeout`) and fail-silent.

This keeps the local copy of every machine's note current in the background and
fixes long-session staleness on its own: re-asking "where was I" reads fresh
data.

**Active heads-up — new `UserPromptSubmit` hook (`user-prompt.sh` +
`lib/headsup.sh`).**
Fires when the user submits a message. Does **no network** — reads only the
already-fetched local refs:

1. Read the current sha of each sibling machine's note (every machine except
   this one).
2. Compare against a per-key "last seen" file in
   `$XDG_STATE_HOME/claude-handoff/seen/`.
3. If a sibling changed, inject one line of `additionalContext` for this turn:
   *"note: desktop updated its handoff ~2m ago."* Then update the seen file.
4. Dedup by sha: a given change announces once and never repeats. This machine
   never notifies about itself.

Because it is pure local reads, it adds no latency, and it is hardened to emit
nothing and exit 0 on any error, so it can never block prompt submission.

**Wiring:** both go into the plugin's `hooks/hooks.json` (the Stop fetch is an
addition to the existing Stop entry; `UserPromptSubmit` is new). The local
`~/.claude/settings.json` is updated to mirror the `UserPromptSubmit` entry so
it is live on this machine (same approach used for `SessionEnd`). The
`settings.json` change is machine-local and not committed to the repo.

### End-to-end flow

1. Turn ends → Stop: summarize → push own ref + detached throttled fetch of all
   refs.
2. User submits → UserPromptSubmit: diff local siblings vs seen → maybe inject
   one-line heads-up.
3. User asks "where was I" → skill: fetch + aggregate all machines + legacy →
   propose.
4. Session ends → SessionEnd: final summarize + push own ref.

## Files touched

All in `~/.claude/handoff-plugin` unless noted:

- `lib/refstore.sh` — machine/branch sanitize + encode, own-ref helper,
  list-siblings-for-branch, legacy-ref read, throttled-fetch helper.
- `lib/summarize.sh` — base rebuild on this machine's own prior note; write/push
  own ref.
- `hook.sh` (Stop) — add detached throttled fetch.
- `lib/headsup.sh` + `user-prompt.sh` — UserPromptSubmit entry point +
  diff-and-inject logic.
- `hooks/hooks.json` — add UserPromptSubmit; append fetch to Stop.
- `skills/handoff/SKILL.md` — multi-machine resume.
- `README.md` — document per-machine model + new behavior/env.
- `~/.claude/settings.json` (local only, not committed) — mirror UserPromptSubmit.

## Testing (`test/*.bats`, extending the existing suite)

- Ref encoding round-trips a slashed branch (`feature/x`).
- Two different `HANDOFF_MACHINE_NAME` values writing the same branch produce
  two separate refs, each with its own content — assert no clobber.
- Read aggregation lists both machines for a branch; single-machine case reads
  like today.
- Legacy `refs/handoff/<branch>` is still read as a fallback note.
- Throttle: a second fetch inside the window is skipped.
- Heads-up: a changed sibling emits exactly one notice; unchanged emits none;
  same sha twice does not re-emit; own machine never self-notifies.
- UserPromptSubmit hook always exits 0 even on malformed state (never blocks a
  prompt).

## Error handling

Unchanged philosophy: every hook is fail-silent, exits 0, and logs to
`handoff.log`; all network is time-boxed. The UserPromptSubmit path does zero
network and is hardened to never block submission.
