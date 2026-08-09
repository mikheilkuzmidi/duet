---
name: duet-research
description: Have Codex check what is currently true about a dependency, API or version. No code written. Use when the user says "duet research", or when recalled documentation is not good enough.
---

# duet research

One phase of the Duet pipeline on its own: **Codex establishes the facts.**

## Before anything

Run `duet doctor`. **If it reports the repo is not set up, run the
`duet-setup` skill now, to completion, then carry straight on with what was
asked.** The human asked for something; setup is the questions Duet needs before
it can do it, not a separate errand for them to run.

Use it when you need to know what is actually true right now, and your own
recollection is not evidence.

## Run it

```bash
duet delegate codex <briefing> <cwd> <out.jsonl>
```

Call `duet`, never source `lib/*.sh`. `bin/duet` runs under bash whatever shell
you are in; the libraries do not survive being sourced from zsh, which is the
default on macOS.

The briefing goes in as a **file**, never as an argument. Codex rejects prompts
over 1,048,576 characters, and the npm shim dies near 1 MB with a Node
`RangeError` that names the wrong cause entirely.

## Write the brief so it cannot be agreed with

`reference/briefing-codex.md`, in full, before writing a word of it.

**Ask the question, withhold the answer.** "Confirm the weight defaults to 2"
gets you a yes. "List every documented request weight and cite where you read
each one" gets you the table, and the table is where the wrong number shows up.

Ask for the table, never the yes or no. Never put your hypothesis in the brief.
If a specific claim must be tested, label it a claim of unknown origin, say
explicitly not to evaluate whether it is plausible, and require an independent
lookup path. Plausibility is exactly the check that lets a wrong number through.

`duet_brief_check` runs automatically and warns on leading phrasings. It blocks
nothing. Rewrite what it flags anyway.

## What a research pass must produce

Not prose about the topic. A **briefing another agent can be grounded on**:

- The exact current version, and where that was read.
- The real API surface for what is being used: signatures, not summaries.
- What changed recently enough to be missing from a model's training data. This
  is the highest-value part of the output.
- Anything that contradicts what a reasonable person would assume.
- Compatibility between the pieces, not just each piece alone.

Every claim comes back with exactly one verdict and a source (standing rule 3):

- **VERIFIED** plus the URL, file path or command whose output it rests on.
- **CONTRADICTED** plus the correct value plus the source. This is the highest
  value output a research pass produces. Never soften it into a hedge.
- **UNVERIFIABLE** plus what was tried and what blocked it.

UNVERIFIABLE is a respectable answer. It must never be promoted to VERIFIED
because the claim sounded reasonable, and whoever consumes the briefing treats
it as an open question rather than a soft yes.

## Stack advisory

Research is not only lookup. If the proposed approach is a poor fit and
something current would serve better, **say so, with reasons**. That judgement
is part of establishing the facts, not an overstep.

Do not force it. If the chosen stack is reasonable, say that and move on.

## Model

The research pass must run on a strong reasoning model. `duet-models.sh`
discovers one at runtime and ranks effort by position in the model's own
advertised list, never by a hardcoded name.

**If only a weak model is available, fail loudly.** A quietly downgraded
research pass is worse than no research pass, because it produces confident
output that nobody thinks to check.

## Where it goes

Into the run directory as a briefing file, then into the next phase via
`--append-system-prompt-file`. Not into a chat message that compaction will eat
before the phase that needs it has started.
