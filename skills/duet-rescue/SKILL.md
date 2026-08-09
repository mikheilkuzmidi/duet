---
name: duet-rescue
description: Repair an app that already exists and works badly, in 11 fixed stages. Use when the user says "duet rescue", inherited a messy codebase, or has an app that half works and needs fixing or rebuilding.
---

# duet rescue

Eleven stages, fixed, held in `reference/presets/rescue.json`. Banner on every
transition.

```
[1/11] Read it back           what this app appears to do. you correct me
[2/11] Truth audit            what really runs, what is dead, what is unsafe
[3/11] Document reset         may I delete the old markdown and rewrite it
[4/11] Ground-up instructions the correct architecture, written first
[5/11] Repair strategy        fix, rebuild the backend, or start over  <- last question
[6/11] Feature inventory      everything that works today
[7/11] Execute                the chosen strategy
[8/11] Tests                  coverage floor plus one per inventory item
[9/11] Debate                 both agents argue once
[10/11] Polish                reads like a person wrote it
[11/11] Done                  zero outstanding, nothing lost
```

## The order is upside down on purpose

Every instinct says choose the repair strategy first. That is how a rescue goes
wrong, because the strategy gets chosen against the broken app's own idea of
itself. So the correct instructions are written at stage 4, from evidence, and
the strategy is chosen at stage 5 against them.

## Existing documents are evidence, not fact

A broken app is usually built on broken documents. Read the markdown, the
comments and the names to learn what somebody meant. Then verify all of it
against the code and against current documentation before believing any of it.
Cite existing docs as claims. Never as sources.

## Stage 1 states, it does not ask

Read the repo, then say what it looks like this app does and who for. Plain
English, no file paths. Name what you could not work out.

They already built this once. Asking them for the idea from scratch tells them
you did not read it.

## Stage 3 asks before deleting anything

List the exact files. `README.md`, `LICENSE`, `CHANGELOG` and anything under
`.github` are excluded from the ask by default, because they face outward and
are not agent instructions. Never a blanket yes.

If the answer is no, write the new documents alongside the old ones and record
the conflict in `docs/decisions.md`.

## Stage 5, the three strategies, honestly

- **Fix in place.** Cheapest, everything keeps working, and it inherits whatever
  the original structure got wrong. Right when the structure is sound and the
  problems are defects.
- **Rebuild the backend, keep the frontend exactly.** The screens do not change,
  the frontend is copied rather than rewritten, and the new backend connects
  behind it. Right when it looks correct and behaves wrong, which is the most
  common inherited failure.
- **Start over from zero.** Carries across environment variables, integrations
  and data. Slowest, and the only one that removes the original decisions.
  Right when the architecture is the problem or the dependencies cannot be
  brought current.

Present all three against this repo with real cost and real risk. Recommend one.
If two are close, say they are close.

**This is the last question about intent.** After it, questions accumulate for
the final round with recommendations attached.

## Stage 6 is what stops you destroying the app

List every user-visible behaviour that works today, as sentences anyone can test
by hand, including the undocumented ones somebody depends on. Anything already
broken is listed as broken, so it is not mistaken for a regression later.

Without this list, "zero errors" is reachable by deleting whatever errors. With
it, that shortcut fails a check. It is the acceptance list for stage 11.

## Stage 7, and standing rule 9

Repair the defect, never remove the feature. Smallest change that removes the
cause. If a genuine fix needs a feature removed, that goes to the final question
round and the work moves on meanwhile.

On the backend strategy the frontend is copied verbatim. Changing it is a
separate decision taken later, in daylight.

On the rebuild strategy, environment variables, credentials and data migration
are planned before the first line, not discovered at the end.

## Stage 11

`reference/definition-of-done.md`, plus every item in `inventory.md` verified
working. A feature lost to a fix is a failed rescue, not a tidy one.
