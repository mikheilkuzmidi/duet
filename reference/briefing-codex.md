# Writing a brief that gets research, not agreement

Standing rule 8, made specific. Claude reads this before commissioning any
Codex fact-finding pass.

The failure this prevents is quiet and expensive. You suspect the rate limit
weight is 2. You write "confirm the weight is 2". Codex reads a page, finds
nothing that contradicts a plausible number, and says yes. You now have a
verified-looking fact that is wrong, and you paid for it.

The fix is not a better model. It is a brief that has no answer in it to agree
with.

---

## Ask the question, withhold the answer

| Do not write | Write |
|---|---|
| Confirm the weight defaults to 2. | List every documented request weight. Give the value for each endpoint class and cite where you read each one. |
| Verify that `createClient` still takes an options object. | What is the current signature of `createClient`? Paste it from the type definitions or the docs, with the version it came from. |
| Check that this approach works on the free tier. | What are the current free tier limits for this service? Quote them and give the URL. |
| Is Postgres the right choice here? | What are the current managed Postgres options at this scale and price point, and what does each cost per month? |

The pattern: **ask for the table, never the yes or no.** A yes or no question is
an invitation to agree, and agreement is cheap. A table has to be read to be
produced.

## Never put your hypothesis in the brief

If a specific claim must be tested, do not attribute it to yourself and do not
say you believe it. Label it as a claim of unknown origin and require an
independent lookup path:

```
A claim of unknown origin says the default weight is 2. Do not evaluate whether
that is plausible. Find the authoritative source for the weight table, read it,
and report what it actually says. If the source does not exist or you cannot
reach it, say UNVERIFIABLE.
```

The instruction not to evaluate plausibility is load bearing. Plausibility is
exactly the check that lets a wrong number through.

## Banned phrasings

`duet_brief_check` warns on these before the brief is sent. It blocks nothing,
because a warning you can override beats a gate you learn to route around.

- "confirm that", "just confirm", "verify that X is Y"
- "as we discussed", "as expected", "as you know"
- "should be", "I believe", "I think", "presumably", "obviously"
- "make sure it's still" anything

## The verdict vocabulary

Every claim comes back with exactly one of these. Require it in the brief.

**VERIFIED** plus the source. A URL, a file path, or the command whose output
you are relying on. No source means not verified.

**CONTRADICTED** plus the correct value plus the source. This is the highest
value output a research pass produces, and it should never be softened into a
hedge.

**UNVERIFIABLE** plus what was tried and what blocked it. Sandbox could not
reach the host. Docs do not cover it. The endpoint requires an account.

UNVERIFIABLE is a respectable answer. It must never be promoted to VERIFIED
because the claim sounded reasonable, and the consumer of the brief must treat
it as an open question, not a soft yes.

## Before you send it

One check, and it takes a second: **does this brief contain a sentence Codex
could agree with instead of investigate?** If yes, rewrite that sentence as a
question and send it again.
