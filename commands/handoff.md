---
description: Write a rich narrative (Goal / Done / Failed / Next) into the handoff ref. The mechanical state and auto-summary are maintained by the hooks.
---

Write or refresh the `<!-- narrative -->` block for the current branch's handoff.
The handoff lives in this machine's `refs/handoff/<machine>/<branch>` ref, not the
working tree.

## Gather context

- `git status` and `git diff --stat HEAD`.
- The conversation so far for what was tried and why.
- Existing narrative (read via the refstore helper, which resolves this
  machine's ref): `bash -c 'export REPO_ROOT=$(git rev-parse --show-toplevel); log() { :; }; source "<plugin_dir>/lib/refstore.sh"; ref_read "$(git symbolic-ref --short HEAD)" HANDOFF.md'` (if present).

## Produce the narrative block

```markdown
<!-- narrative -->
## Goal
[1-2 sentences: what the user is trying to achieve]
## Done
- [completed item]
## Failed approaches (don't repeat)
- [what was tried and why it failed — omit if none]
## Next
1. [single most important next step]
2. [follow-on, if any]
<!-- /narrative -->
```

Guidelines:
- Failed approaches are the highest-value section.
- Be terse; reference real file paths and commands.
- Do not duplicate the auto block (machine/branch/status/last message).

## Apply it

You cannot edit the ref by hand easily. Instead, write the block to a temp file
and apply it directly with the refstore helper:

```bash
bash -c '
  export REPO_ROOT="$(git rev-parse --show-toplevel)"
  HANDOFF_LOG_PATH=/dev/null; log() { :; }
  source "<plugin_dir>/lib/refstore.sh"
  branch="$(git symbolic-ref --short HEAD)"
  cur="$(ref_read "$branch" HANDOFF.md)"
  auto="$(printf "%s" "$cur" | awk "/<!-- auto -->/,/<!-- \/auto -->/")"
  narrative="$(cat /tmp/handoff-narrative.md)"
  journal="$(ref_read "$branch" HANDOFF-LOG.md)"
  ref_write "$branch" HANDOFF.md "$auto

$narrative" HANDOFF-LOG.md "$journal"
  ref_push "$branch"
'
```

Write your narrative block to `/tmp/handoff-narrative.md` first, then run the
above (substituting the real plugin dir). Tell the user it is saved; the next
session on any machine will see it.
