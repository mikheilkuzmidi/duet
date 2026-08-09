# Writing a goal

A prompt ends when the model stops talking. A goal ends when its exit gate
passes. That is the whole difference, and it is the difference between an app
and most of an app.

Codex has this natively: `thread/goal/set` carries an objective and a status,
and the status stays `active` until the work is genuinely done. Duet drives it
through `lib/duet-goal.sh`. What this file governs is the objective you hand it,
because a goal with a vague objective is a prompt with extra machinery.

---

## The shape

**Under 4000 characters.** Not a style preference: `thread/goal/set` rejects
anything longer, and Duet refuses rather than truncating, because the gate lives
at the end of the block and a truncated objective loses it silently. Briefings,
research findings and file listings do not go in the objective; they go in the
developer instructions, which have no such cap.

**One block of prose. No headings, no checklists, no sections.** A structured
document invites the agent to treat each section as separately satisfiable and
report on progress through them. A block invites it to do the work.

```
Rebuild the booking API against docs/architecture.md. Postgres on Supabase,
no new dependencies outside the approved set in docs/decisions.md. Keep the
existing route paths exactly; the frontend is not yours to change. Work
autonomously, pick the option best serving the constraints, state assumptions
in one line and continue. Never stop to ask. Solve blockers rather than
reporting them.

Gate: npm test -- --coverage green AND tsc --noEmit clean AND POST /bookings
returns 201 in tests/api.test.ts
```

Five things, folded into prose rather than listed:

1. **What to build**, in one sentence, naming the document that governs it.
2. **The constraints that would otherwise be guessed**: the stack, the budget,
   what may not change.
3. **Autonomy**: work alone, choose, state assumptions in one line, continue.
4. **Never stop to ask.** A goal that stops to ask is a prompt.
5. **The gate.**

## The gate is a command

This is the part that decides whether the work comes back finished.

**Good:** `npm test -- --coverage green AND tsc --noEmit clean`
**Useless:** "the booking flow works end to end"

A subjective gate is satisfied by an agent that believes it is satisfied, which
is exactly the failure this is meant to prevent. A command gate is satisfied by
a process exiting zero, and nobody's opinion enters into it.

The commands come from `commands.*` in `.duet/config.json`, detected once by
`lib/duet-detect.sh` and confirmed by the human, so every goal in a project
shares the same definition of working.

Where a phase genuinely has no command gate, say so in the objective and give
the nearest checkable thing: a file that must exist, a string that must appear
in output, an endpoint that must answer. "A third party could check this without
asking you" is the standard.

## What not to put in a goal

- **Questions.** Any question, however small. The agent will answer it itself
  and the answer will be worse than yours, or it will stop, and a goal that
  stops is a prompt.
- **Progress reporting instructions.** "Report back when you finish stage two"
  turns one goal into three prompts.
- **A plan.** The goal states the destination and the constraints. If you have
  already worked out the steps, you did the interesting part and hired an
  expensive agent to type.
- **Politeness.** It costs tokens and changes nothing.

## One goal, one branch, one PR

Never combine a deletion goal with a build goal. When something goes wrong, the
unit you revert is the goal, and a goal that did two things cannot be half
reverted.

`git.mode` enforces the branch side of this.

## Budget

`goal.tokenBudget` sets `tokenBudget` on the goal. Reaching it moves the status
to `budgetLimited`, which Duet reports as a stop rather than a failure: the work
so far stands, and resuming continues it.

`goal.maxMinutes` and `goal.maxTurns` are Duet's own limits, because a goal that
is not converging will not converge, and burning an afternoon proving it is a
waste of somebody's money.

## When a goal cannot finish

Four states that are not failure, and each is reported as itself:

- `usageLimited`, the plan's rate limit. **Do not retry.** Resume after reset.
- `budgetLimited`, the token budget. Raise it and resume.
- `blocked`, it needs something it does not have. This one is worth reading.
- timed out on `maxMinutes` or `maxTurns`. The work so far stands.
