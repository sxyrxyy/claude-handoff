---
name: handoff
description: Use when starting a session, when the user mentions handoff/resume/"where was I"/"pick up where I left off", or when switching machines. Fetches the handoff ref and offers a propose-don't-act resume. Coexists with Stop/SessionEnd hooks that maintain the handoff automatically.
---

# Handoff

Handoffs are stored in a dedicated git ref (`refs/handoff/<branch>`), not in
the working tree. The Stop and SessionEnd hooks maintain them automatically —
you never create them by hand.

## On session start

1. Confirm cwd is a git repo. If not, do nothing.
2. Fetch handoff refs (silent, non-fatal):
   `git fetch -q origin 'refs/handoff/*:refs/handoff/*' 2>/dev/null || true`
3. Read the snapshot for the current branch:
   `git show refs/handoff/<branch>:HANDOFF.md 2>/dev/null`
   If it does not exist, do nothing and continue normally.
4. Read recent rationale: `git show refs/handoff/<branch>:HANDOFF-LOG.md` (top entry).
5. Detect drift: compare the recorded last commit against `git log -1 --format=%h`
   and check `git status -s`. If the recorded commit differs from HEAD, note it.

## What to present (propose, don't act)

One short paragraph, then wait:

> "Last on `<machine>`, `<age>` ago. **Goal:** `<goal>`. **Next:** `<the single next step>`. Avoid: `<top failed approach>`. Want me to pick this up?"

If drift was detected, add:
> "Note: repo has moved since the handoff (handoff at `<sha>`, now at `<sha>`)."

**Do not** auto-read files, auto-run tests, or start work until the user confirms.

## On confirmation

1. Read the files listed under "Files touched this session".
2. Summarize the current state and the proposed next step concretely.
3. Ask the user to confirm the next step before executing it.

## Trigger words

Activate when the user says: "handoff", "hand off", "where was I",
"pick up where I left off", "continue from last time", "what was I doing",
"resume", "switching machines".

## The `/handoff` command

For a manual rich narrative pass beyond what the summarizer writes, the user
runs `/handoff`. See `commands/handoff.md`.

## What this skill does NOT do

- Auto-resume without asking.
- Write or push the handoff (the hooks do that).
- Modify state on the other machine.
