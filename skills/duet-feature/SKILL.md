---
name: duet-feature
description: Add a feature to a repo that already exists, in 8 fixed stages. Use when the user says "duet feature", or wants something added to a working project rather than built from scratch.
---

# duet feature

Eight stages, fixed, held in `reference/presets/feature.json`.

```
[1/8] Read the project   load the documents, check they still match the code
[2/8] Scope              what it does, what it deliberately does not  <- last question
[3/8] Research           Codex checks anything new this touches
[4/8] Plan               which files, in what order, and how to tell it worked
[5/8] Build              Claude the surface, Codex underneath
[6/8] Tests              at the project's level plus the new paths
[7/8] Debate             both agents argue once
[8/8] Done               zero outstanding, no regression
```

## Before anything

Run `duet doctor`. **If it reports the repo is not set up, run the
`duet-setup` skill now, to completion, then carry straight on with what was
asked.** The human asked for something; setup is the questions Duet needs before
it can do it, not a separate errand for them to run.

## Every gate is a question with options

Not a paragraph that ends in a question mark. Two to four options, each naming
its consequence, one recommended so accepting takes a single press. Free text
stays available and is never the only path.

**A list of things you could not work out is a list of questions.** Never a
bulleted list of unknowns followed by "correct me where I am wrong": that makes
the human compose the answer, and whatever they skip becomes an assumption
nobody recorded. Ask the ones where a different answer changes what you build,
and record the rest with `duet_question_add`.

Full rules in `reference/asking.md`.

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

## Stage 1 decides whether this is the right skill

Read `CLAUDE.md`, `AGENTS.md` and `docs/` first. That is what they are for.
Then spot-check them against the code.

- Documents match: continue, one line saying so.
- Documents have drifted badly: **stop and recommend `duet-rescue`**. Building
  on a map that no longer describes the territory produces work that is wrong in
  ways nobody thinks to check.
- No documents at all: offer `duet-app` for a project that never had any, or
  `duet-rescue` to reconstruct them.

## Stage 3 can be skipped, visibly

If the feature uses nothing outside the existing dependency set and touches no
external API, skip the research pass and **say that you skipped it and why**.
A skipped brief that appears on the plan is a decision. One that does not is a
gap discovered three stages later.

## Match the project, not your defaults

A feature that works but looks imported from another codebase is a defect. Use
the patterns already here. If the right implementation requires departing from
`docs/architecture.md`, that is a decision, and it goes in `docs/decisions.md`
before the code, not after.

## Stage 8

`reference/definition-of-done.md`, plus nothing that worked before works worse.
