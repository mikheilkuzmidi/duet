---
name: duet-resume
description: Continue a Duet run that stopped, died, or hit its budget, re-running only the phase that failed rather than the whole run. Use when the user says "duet resume", or when a previous run was interrupted.
---

# duet resume

Continue a run that stopped. Re-run the dead phase, not the run.

## Finding the resume point

A phase is complete **if and only if its output file exists**. Outputs are
written atomically, so a partial write is indistinguishable from an absent one.
There is no half-finished state to detect, which is why this is a one-line rule
rather than a recovery subsystem.

`duet_run_resume_point` returns the first phase without a completed output.
Everything before it stands.

## What does not get regenerated

**The plan.** Re-planning would invalidate work that already succeeded, and a
resumed run would silently become a different run.

If the plan is genuinely wrong, that is a new run, not a resume.

## Stale research

If the run directory is older than `resume.researchMaxAgeHours` (24 by default),
**re-run the research phases before continuing**.

Resuming a week-old run against week-old dependency facts would reintroduce
exactly the staleness Duet exists to prevent. A resumed run that quietly uses
stale facts is worse than one that refuses, because it looks like it worked.

## If the repository moved

If the working tree changed since the run stopped, **stop and ask**. This is one
of only two deliberate exceptions to no-questions-after-start, because building
on a moved foundation produces work that is wrong in ways nobody thinks to check.

Show what changed. The human decides whether to continue, re-plan, or start over.

## Across machines

Resume works from another machine, because the plan and briefings are files. But
session ids are host-local, so a resumed phase starts a **fresh** CLI session
with the briefing re-injected rather than trying to reattach to a session that
does not exist there.

## After a budget stop

A hard budget stop checkpoints deliberately, so it is always resumable. Raise
`budget.stopUsd` or clear it, then resume. The ledger continues accumulating
across the resume rather than resetting, or the limit would mean nothing.
