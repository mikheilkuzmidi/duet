---
name: duet-build
description: Run a plan that was already approved. Use when the user says "duet build", or wants to execute what duet plan produced.
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

Two pools, one ceiling: `duet_max_agents_for claude` and
`duet_max_agents_for codex`, never more than 10 in total. The pools are separate
because the accounts and their rate limits are separate, so a single shared
number could only ever be wrong for one of them. Every spawn goes through the
gate; a phase may not quietly raise its own budget.

**On a 429 or a session limit, stop spawning. Do not retry.** Retrying into a
rate limit turns a pause into a ban risk.

## Ownership inside a phase

Claude owns everything the user sees and every word they read. Codex owns
everything underneath. Codex files wording and interface concerns with the exact
string and the reason; it does not edit them. Claude decides.
`reference/capability-table.json` holds the full boundary.

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
