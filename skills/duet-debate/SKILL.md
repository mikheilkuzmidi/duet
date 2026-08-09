---
name: duet-debate
description: Have both AIs review existing work and argue about it once. Use when the user says "duet debate", or wants a branch challenged before it ships, including work they wrote themselves.
---

# duet debate

The review exchange, runnable on its own. It works on any branch, including work
neither agent wrote, which is most of its value outside a full pipeline.

## The protocol

**Batched, never one concern at a time.** A running argument is unreadable and
never terminates.

1. **Codex sends the whole list.** Each concern: what is wrong, where, why it
   matters, and the source that establishes it. Concerns without a source are
   opinions and should be labelled as such.
2. **Claude answers the whole list in one pass.** For each: fix it, or explain
   why it is correct as written.
3. **Codex agrees or pushes back once.** One round. Not until someone tires.
4. **Claude fixes what was genuinely wrong.**

## The part that makes it worth doing

**Correct and intentional choices stand** (standing rule 5).

Review that overwrites deliberate decisions teaches everyone to ignore review.
If a choice was made on purpose and the reasoning holds, defend it and leave it.
Conceding a point you believe is right in order to end the argument is the
failure mode that makes review theatre, and it is more common than being wrong.

Equally: if a concern lands, fix it without ceremony. Both outcomes are good.

## Deadlock

Anything still disputed after the rebuttal round **goes to the human**, with
**both positions and their reasoning inline**:

```
Unresolved: retry strategy in fetchUser

  Codex:  exponential backoff with jitter. The API docs specify
          retry-after and this ignores it. [source: api docs, rate limits]
  Claude: fixed 3 retries. The call sits behind a user-facing spinner;
          backoff past ~2s reads as a hang. [reason: UX, not correctness]

  Recommend: Codex. Honouring retry-after is a correctness issue; the
             spinner problem is better solved by a timeout than by
             ignoring the header.
```

The human decides with the argument in front of them, not a bare choice. These
join the single final question round rather than interrupting, each with a
recommendation pre-selected, so a deadlock nobody cares about resolves itself.

## Why the human arbitrates

Letting Claude win as orchestrator was considered and rejected: it would let the
judgement model overrule the facts model on a documentation fact, which is
precisely the failure Duet exists to eliminate.

After the human decides, **fix and verify everything** against those decisions
before finishing.
