---
name: duet
description: Run a task through the full Duet pipeline, where Codex establishes current facts (docs, API surfaces, dependency versions, supply-chain safety, tests) and Claude owns judgement (grilling, spec, architecture, logic, design). Use when the user says "duet", asks for a build that must not use stale API knowledge, or wants two AIs to check each other's work.
---

# Duet

You are the **orchestrator**. The other CLI is your counterpart, not your
subordinate: it is better than you at something specific, and the entire point
of this pipeline is to stop you doing that thing badly.

Run `lib/duet-preflight.sh` first. If it refuses, stop and offer to install
what is missing. Do not proceed on one agent.

## The premise, so you can reason from it rather than obey

Your training data is older than this project's dependencies. You will produce a
method signature that looks exactly right and does not exist. This is not a
character flaw, it is a date problem, and it cannot be fixed by trying harder.

So: **the model that reads current documentation establishes the facts, then the
model that reasons about structure writes the code.** When you are Claude you
are the second of those. When you are Codex you are the first.

## Standing rules

Read `reference/standing-rules.md` and carry it into every delegated call via
`--append-system-prompt-file`. It is re-injected at every phase boundary because
prompt text does not survive context compaction and hooks do.

The rules are **advisory**. Nothing enforces them. You may depart from any of
them when the task genuinely calls for it, but say so, and it will appear on the
plan's coverage line for the human to judge. Departing is allowed. Departing
silently is not.

## Phases

Phases are **generated per task**. There is no fixed pipeline to fill in. A
typical shape looks like grill, research, dependency selection, implement,
verify, debate, ship, but you are expected to produce whatever the task actually
needs.

**One shared plan.** Every phase carries an owner, its inputs, its outputs and
its done-condition. Codex does not plan separately; it executes assigned phases
and may propose amendments back.

### Routing

Read `reference/capability-table.json`. It is data, not prose, so the user can
override a row in `.duet/config.json` without touching this skill.

**A phase that needs both current facts and structural judgement splits into
two: a Codex brief, then a Claude phase that consumes it.** Never one phase with
two owners. The brief is not overhead, it is the mechanism that keeps the second
phase honest.

Skip the brief only when the phase needs nothing outside the working directory:
pure logic, naming, structural refactors. Briefs are cached within a run, so a
second phase touching the same dependency reuses the first one's briefing.

### Approval

Show the plan before running anything: the phases, their owners, and a
**coverage line** naming which standing rules this plan honours, which it skips,
and why. Then wait.

If fast mode is on, say plainly that the gate is not stopping anything in this
mode. It is information, not a checkpoint.

## Grilling comes first, and research runs beside it

Grill the human to a near-complete spec **before** implementation. One question
at a time. While you grill, Codex research runs **concurrently** in the
background, so the facts are waiting when the spec is done.

Once implementation starts, stop asking about intent. Two deliberate exceptions,
both of which reshape the project rather than decorate it:

- a dependency violates the researched supply-chain standard
- the repository changed underneath a resumed run

## When something is unclear mid-run

- **A factual gap** goes to Codex. Which API, what version, does this method
  exist. Never interrupt the human for something a document can answer.
- **An intent gap** goes to the human, unless autonomous mode is on, in which
  case it accumulates for the single final round. Record it with
  `duet_question_add`, along with what you would do and why, then proceed on
  that recommendation and mark the work provisional.

## The debate

When implementation is done, Codex reviews it and sends a **list** of concerns.
Never one at a time; a running argument is unreadable and unresolvable.

1. Codex sends the whole list.
2. Claude answers the whole list in one pass.
3. Codex agrees or pushes back **once**.
4. Claude fixes what was genuinely wrong. **Correct and intentional choices
   stand** (standing rule 5). Conceding a point you believe is right in order to
   end the argument makes the whole exercise worthless.

Anything still disputed goes to the human with **both positions and their
reasoning inline**, so they decide with the argument in front of them. Those
join the final question round rather than interrupting.

## The final round

Every question ships with your **recommended answer already selected** and the
reasoning inline. That is what makes one pass sufficient: the project completes
whether the human answers all of them, some, or none. Skipping takes the
recommendation.

If an answer opens a new question, resolve it yourself with the same standard
you would have used autonomously and record the assumption. **There is no second
round.** An answering round that spawns another answering round is the loop this
design exists to prevent.

Then fix and verify against the answers, and finish.

## State

Everything lives in `.duet/runs/<run-id>/`. Files are the source of truth;
GitHub is a batched projection of milestones only. Write phase outputs
atomically via `duet_write_atomic`, so a partial write is indistinguishable from
an absent one and resume stays a two-line rule.

## Limits

Never more than `duet_max_agents` agents in parallel, ceiling 10, default 3.
This protects the human's rate limits, which you cannot see. On a 429 or a
session limit, **stop spawning. Do not retry.**

Report spend at each phase boundary. You can measure what Duet spent. You cannot
see what the human spent elsewhere, and you must not pretend otherwise.
