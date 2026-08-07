---
name: duet-research
description: Run a Codex research pass alone, without the rest of the Duet pipeline, to establish current facts about a dependency, API, or version before writing any code. Use when the user says "duet research", or when you need current documentation rather than recalled documentation.
---

# duet research

One phase of the Duet pipeline on its own: **Codex establishes the facts.**

Use it when you need to know what is actually true right now, and your own
recollection is not evidence.

## Run it

```
lib/duet-delegate.sh   # duet_delegate_codex <briefing> <cwd> <out.jsonl>
```

The briefing goes in as a **file**, never as an argument. Codex rejects prompts
over 1,048,576 characters, and the npm shim dies near 1 MB with a Node
`RangeError` that names the wrong cause entirely.

## What a research pass must produce

Not prose about the topic. A **briefing another agent can be grounded on**:

- The exact current version, and where that was read.
- The real API surface for what is being used: signatures, not summaries.
- What changed recently enough to be missing from a model's training data. This
  is the highest-value part of the output.
- Anything that contradicts what a reasonable person would assume.
- Compatibility between the pieces, not just each piece alone.

Every claim names its source (standing rule 3). A claim nobody can check is a
guess wearing a finding's clothes.

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
