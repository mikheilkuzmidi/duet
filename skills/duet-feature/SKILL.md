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
