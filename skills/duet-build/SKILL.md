---
name: duet-build
description: Run a plan that was already approved. Use when the user says "duet build", or wants to execute what duet plan produced.
---

# duet build

Execute an approved plan. One phase at a time, each with exactly one owner.

## Before anything

Run `duet doctor`. **If it reports the repo is not set up, run the
`duet-setup` skill now, to completion, then carry straight on with what was
asked.** The human asked for something; setup is the questions Duet needs before
it can do it, not a separate errand for them to run.

## Running a stage

Work that writes code goes through a goal, not a prompt. A prompt ends when the
model stops talking; a goal ends when its gate command exits zero.

```bash
duet gate <preset> <n>                       # see the stage's gate command
export DUET_STAGE_LABEL="<n>/<total> <Title>" DUET_GATE_CMD="<the gate>"
duet goal codex  <objective-file> <cwd> <out.jsonl>
duet goal claude <objective-file> <cwd> <out.json> "<gate>"
duet delegate codex <brief> <cwd> <out.jsonl>     # a briefing, not a goal
```

**Call `duet`, never source the shell libraries.** `bin/duet` runs under bash
whatever shell you are in; sourcing `lib/*.sh` from zsh, which is the default on
macOS and what the Bash tool uses, does not work.

The objective is written per `reference/goal-format.md`: one block of prose, no
questions, the gate stated as a command. Read the exit code through
the printed verdict: 75 is a usage limit and must not be retried, 76 wants a
bigger token budget, 77 is blocked and worth reading, 78 hit a time or turn
limit and the work so far stands.

A briefing phase is not a goal. It is one `duet delegate codex` call.

## Per phase

1. **Assemble the briefing.** Standing rules, then the outputs of the phases
   this one declares as inputs. Write it to `phases/<n>/in.md`.
2. **Delegate** to the owner: `duet goal codex` or `duet goal claude` for work
   that writes code, `duet delegate codex` for a briefing. All of them carry the
   safe invocation profile; do not hand-roll the flags, because most of them
   exist to avoid a specific silent failure, and do not source `lib/*.sh`.
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
