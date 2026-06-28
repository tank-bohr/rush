# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for task/backlog tracking. `bd prime` prints workflow context.

```bash
bd ready                # next available work
bd show <id>            # issue details
bd update <id> --claim  # claim work
bd close <id>           # complete work
```

**Scoped for this project** (see `CLAUDE.md` for the canonical rules): beads holds the
**backlog and forward tasks** only. Narrative and lessons live in `docs/journal.md`; the
record of *why* lives in `git log` and the journal — do not treat `bd remember` as the
sole knowledge store. **Pushing is never mandatory here — push only when the user asks**
(this overrides the default beads session-completion / mandatory-push workflow).
<!-- END BEADS INTEGRATION -->
