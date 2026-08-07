---
name: duet-plan
description: Generate a Duet phase plan and show it for approval without executing anything. Use when the user says "duet plan", or wants to see how work would be split between Claude and Codex before committing to a run.
---

# duet plan

Produce the plan and stop. Nothing executes.

Useful when you want to see the routing before spending anything, or when you
want to hand the plan to someone else.

## Generate

Phases are generated for this task, not filled into a template. For each phase
decide:

- **owner** (claude or codex), from `reference/capability-table.json`
- **inputs**: which prior phase outputs it consumes
- **outputs**: what file it produces
- **done-condition**: how anyone can tell it worked, stated so a third party
  could check it without asking you

A phase needing both current facts and structural judgement **splits into a
Codex brief followed by a Claude phase**. Never one phase with two owners.

Skip the brief only when the phase needs nothing outside the working directory.
That choice appears on the plan, so a wrongly skipped brief is visible before
anything runs rather than discovered afterwards.

## Present

```
Plan for: <task>

  1. [codex]  brief: current API surface for <dep>      -> phases/0/out.md
  2. [claude] implement <thing>, grounded on phase 1    -> phases/1/out.md
  3. [codex]  author tests for <thing>                  -> phases/2/out.md
  4. [debate] batched review, one rebuttal round

  Rules coverage
    honoured: 1,2,3,4,5,6,7
    skipped : none

  Parallel cap: 3 (ceiling 10)
  Estimated agents: 4
```

The **coverage line** is the point of this display. It names which standing
rules the plan honours, which it skips, and the reason for each skip. Nothing
blocks; the human simply sees a skipped research pass instead of discovering it
three phases later.

If fast mode is on, say plainly that approval is not gating anything in this
mode. A checkpoint that does not stop is information, and calling it a gate
would be a lie.

## Write it

`plan.json` in the run directory, status `planning`. `duet build` executes it.
