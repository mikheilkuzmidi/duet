---
name: duet
description: Run any task through Claude and Codex together, where Codex establishes current facts and Claude owns judgement. Use when the user says "duet", wants two AIs to check each other's work, or wants a build that must not use stale API knowledge.
---

# Duet

You orchestrate. Codex is your counterpart, not your subordinate: it is better
than you at one specific thing, and this pipeline exists to stop you doing that
thing badly.

Run `duet doctor` first. If it refuses, offer to install what is
missing. Do not proceed on one agent.

**If it reports the repo is not set up, run the `duet-setup` skill right now,
to completion, then carry straight on with what was asked.** Not a suggestion
for later and not a second invocation for the human: they asked for something,
and this is the questions Duet needs before it can do it.

## The premise, so you can reason from it rather than obey

Your training data is older than this project's dependencies. You will produce a
method signature that looks exactly right and does not exist. That is a date
problem, not a character flaw, and trying harder cannot fix it.

So: **the model that reads current documentation establishes the facts, then the
model that reasons about structure writes the code.** You are the second one.
Claude always orchestrates; Codex is the fact-finder, the backend and the tests.

## Is there a preset for this?

Four jobs have fixed stages, because their shape is known in advance and
inventing it fresh each run only means nobody can say where they are.

| If the task is | Use |
|---|---|
| build an app, site or product from nothing | `duet-app` |
| repair something that exists and works badly | `duet-rescue` |
| add to a working project | `duet-feature` |
| build a skill or slash command | `duet-skill` |

Anything else: generate phases here.

## What gets injected

`reference/standing-rules.md`, `reference/output-format.md` and
`reference/definition-of-done.md` go into every delegated call via
`--append-system-prompt-file`, re-injected at every phase boundary because
prompt text does not survive compaction and a system-prompt file does.

The rules are **advisory**. Nothing enforces them. Depart from one when the task
genuinely calls for it, say so, and it appears on the plan's coverage line.
Departing is allowed. Departing silently is not.

## Phases

Generated per task. No fixed pipeline to fill in. A typical shape is grill,
research, dependency selection, implement, verify, debate, ship, but produce
what the task actually needs.

**One shared plan.** Every phase carries an owner, its inputs, its outputs and
its done-condition. Codex does not plan separately; it executes assigned phases
and may propose amendments back.

### Routing

`reference/capability-table.json` is data, not prose, so a user can override a
row in `.duet/config.json` without touching this skill.

**A phase needing both current facts and structural judgement splits into two: a
Codex brief, then a Claude phase that consumes it.** Never one phase with two
owners. The brief is not overhead, it is the mechanism that keeps the second
phase honest.

Skip the brief only when the phase needs nothing outside the working directory:
pure logic, naming, structural refactors. Briefs are cached within a run.

### Ownership inside a build phase

Claude owns everything the user sees and every word they read. Codex owns
everything underneath: backend, data, integrations, environment, tests.

Codex raises a wording or interface concern by filing it with the exact string
and the reason. It does not edit it. Claude decides, and an intentional choice
stands.

### Delegate work as a goal, briefs as a call

This is the difference between work that comes back finished and work that comes
back at eighty percent.

| The phase | How to run it |
|---|---|
| produces a briefing, and nothing else | `duet delegate codex <brief> <cwd> <out>` |
| writes code, or must satisfy a command | `duet goal codex` / `duet goal claude` |

A goal ends when its gate command exits zero. A prompt ends when the model stops
talking, which is a different thing and is why half-built results happen.

Before delegating a stage:

1. Resolve its gate: `duet gate <preset> <n>`. A resolver
   that returns non-zero means a command is not configured; record that as
   outstanding rather than treating the stage as passed.
2. Export `DUET_STAGE_LABEL` and `DUET_GATE_CMD` so the run context injected
   into the call tells the agent where it is and what it is measured by.
3. Write the objective per `reference/goal-format.md`: one block of prose, no
   headings, no questions, constraints folded in, and the gate stated as the
   command.
4. Call the runner. `duet goal claude` takes the gate as its fourth argument
   and loops until it passes.

`duet goal` prints what the exit code means, because these are not all
failures:

- **75** usage limited. **Stop. Do not retry.** Resume after the reset.
- **76** token budget spent. Raise `goal.tokenBudget` and resume.
- **77** blocked. It needs something it does not have; read what it said.
- **78** hit `goal.maxMinutes` or `goal.maxTurns`. The work so far stands.

### Approval

Show the plan before running anything: phases, owners, and a **coverage line**
naming which standing rules this plan honours, which it skips, and why. Then
wait.

If fast mode is on, say plainly that the gate is not stopping anything in this
mode. It is information, not a checkpoint.

## Grilling comes first, research runs beside it

Grill to a near-complete spec **before** implementation, at the depth
`grill.depth` was set to. One question at a time. Codex research runs
**concurrently** in the background, so the facts are ready when the spec is.

Once implementation starts, stop asking about intent. Two exceptions, both of
which reshape the project: a dependency violates the researched supply-chain
standard, or the repository changed underneath a resumed run.

## Briefing Codex

Read `reference/briefing-codex.md` before writing any research brief.

**Ask the question, withhold the answer.** A brief containing its own conclusion
gets that conclusion back, and you will have paid for agreement and filed it as
verification. Ask for the table, never the yes or no. Require VERIFIED,
CONTRADICTED or UNVERIFIABLE with a source on every claim.

`duet_brief_check` warns on leading phrasings before a brief is sent. It blocks
nothing, because a gate people learn to route around protects nothing.

## When something is unclear mid-run

- **A factual gap** goes to Codex. Which API, what version, does this method
  exist. Never interrupt the human for something a document can answer.
- **An intent gap** accumulates for the single final round. Record it with
  `duet_question_add` along with what you would do and why, proceed on that
  recommendation, and mark the work provisional.

## The debate

When implementation is done, Codex reviews it and sends a **list** of concerns.
Never one at a time; a running argument is unreadable and never terminates.

1. Codex sends the whole list.
2. Claude answers the whole list in one pass.
3. Codex agrees or pushes back **once**.
4. Claude fixes what was genuinely wrong. **Correct and intentional choices
   stand** (standing rule 5). Conceding a point you believe is right in order to
   end the argument makes the whole exercise worthless.

Anything still disputed goes to the human with **both positions and their
reasoning inline**. Those join the final round rather than interrupting.

## The final round

Every question ships with your **recommended answer already selected** and the
reasoning inline. That is what makes one pass sufficient: the project completes
whether the human answers all of them, some, or none. Skipping takes the
recommendation.

If an answer opens a new question, resolve it yourself with the same standard
you would have used autonomously and record the assumption. **There is no second
round.**

Then fix and verify against the answers, and finish against
`reference/definition-of-done.md`.

## State

Everything lives in `.duet/runs/<run-id>/`, which is excluded locally. Files are
the source of truth; GitHub is a batched projection of milestones only. Write
phase outputs atomically via `duet_write_atomic`, so a partial write is
indistinguishable from an absent one and resume stays a two-line rule.

## Limits

Never more than `duet_max_agents_for claude` Claude agents or
`duet_max_agents_for codex` Codex agents at once, and never more than 10 in
total. This protects rate limits you cannot see. On a 429 or a session limit,
**stop spawning. Do not retry.**

Report spend at each phase boundary. You can measure what Duet spent. You cannot
see what the human spent elsewhere, and you must not pretend otherwise.

## Output

`reference/output-format.md`. Six lines or fewer per turn outside a gate or the
final report. Findings, not prose about findings. No em dashes.
