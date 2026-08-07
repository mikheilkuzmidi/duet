---
name: duet-build
description: Execute an approved Duet plan, running each phase with its assigned owner and grounding every Claude phase on the preceding Codex brief. Use when the user says "duet build", or wants to run a plan that duet plan already produced.
---

# duet build

Execute an approved plan. One phase at a time, each with exactly one owner.

## Per phase

1. **Assemble the briefing.** Standing rules, then the outputs of the phases
   this one declares as inputs. Write it to `phases/<n>/in.md`.
2. **Delegate** to the owner via `duet_delegate_codex` or
   `duet_delegate_claude`. Both carry the safe invocation profile; do not
   hand-roll the flags, because most of them exist to avoid a specific silent
   failure.
3. **Verify the served model** with `duet_require_strong`. Both platforms
   silently downgrade, so selecting a strong model is not the same as getting
   one.
4. **Write the output atomically.** Partial writes must be indistinguishable
   from absent ones, which is what keeps resume simple.
5. **Record spend**, then `duet_ledger_guard`. On a hard stop, checkpoint and
   exit cleanly. Dying mid-phase is the one thing that makes a run
   unrecoverable.

## Long phases

Claude Code's Bash tool caps at **600 seconds** and neither CLI has a timeout
flag. Anything that may exceed it is spawned **detached** with output redirected
into the run directory and polled with `duet_poll`, not awaited.

## Parallelism

Never exceed `duet_max_agents`, ceiling 10, default 3, one shared pool across
both CLIs. Every spawn goes through the single gate; a phase may not quietly
raise its own budget.

**On a 429 or a session limit, stop spawning. Do not retry.** Retrying into a
rate limit turns a pause into a ban risk.

## Questions

Do not interrupt for intent. Record with `duet_question_add`, including what you
would do and why, then proceed on that recommendation and mark the work
provisional so a different answer causes a targeted redo rather than a restart.

Two exceptions, both of which change the project rather than decorate it:

- **A dependency violates the researched safety standard.** Stop. Report the
  dependency, the standard, why it exists, and the nearest safe alternative that
  research already found. Then ask. Do not substitute on your own; a silent
  dependency swap can reshape an architecture.
- **The repository changed underneath a resumed run.** Stop and ask rather than
  building on a moved foundation.

## Failure

Report what happened, not what was meant to happen (standing rule 7). A phase
that half worked is a phase that failed, and saying so now is cheaper for
everyone than being discovered three phases later.
