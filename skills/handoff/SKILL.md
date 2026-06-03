---
name: handoff
description: Use when starting a session, when the user mentions handoff/resume/"where was I"/"pick up where I left off", or when switching machines. Aggregates every machine's handoff note for the branch and offers a propose-don't-act resume. Coexists with Stop/SessionEnd/UserPromptSubmit hooks that maintain the handoff automatically.
---

# Handoff

Handoffs are stored in a dedicated git ref (`refs/handoff/<branch>`), not in
the working tree. The Stop and SessionEnd hooks maintain them automatically —
you never create them by hand.

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
   Each note is a block headed `===HANDOFF machine=<name> ref=<ref>===`,
   followed by a `url=<link>` line (a SHA-pinned GitHub/GitLab permalink to that
   machine's `HANDOFF.md`, or a `git show …` command if the remote is not
   GitHub/GitLab), then the machine's `HANDOFF.md`, then its top
   `HANDOFF-LOG.md` entry. A block headed `machine=(legacy)` is a pre-upgrade
   note from the old single-ref layout — treat it as one more machine. If the
   dump is empty, do nothing and continue normally.
4. Detect drift: compare the recorded last commit in the most recent note
   against `git log -1 --format=%h` and check `git status -s`.

## What to present (propose, don't act)

One short paragraph for the most recent machine, then wait:

> "Last on `<machine>`, `<age>` ago. **Goal:** `<goal>`. **Next:** `<the single next step>`. Avoid: `<top failed approach>`. Want me to pick this up?"

If other machines also have notes, add one line:
> "Also has notes: `<machine>` (`<age>`), `<machine>` (`<age>`)."

Surface the `url=` value for the chosen note so the user can open the raw
handoff directly:
> "View: `<url>`"

If drift was detected, add:
> "Note: repo has moved since the handoff (handoff at `<sha>`, now at `<sha>`)."

**Do not** auto-read files, auto-run tests, or start work until the user confirms.

## On confirmation

1. Read the files listed under "Files touched this session" in the chosen note.
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
