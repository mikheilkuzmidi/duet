# Done

Both agents share this definition, so neither can declare victory on its own
terms. It is the last stage of every preset, and it is injected into every
delegated call so a phase in the middle of a run knows what it is building
toward.

**Done means zero outstanding issues in three places: locally, in the tests, and
deployed.** Not "mostly working". Not "works on my machine". Zero, in all three,
or a written list of what is still open.

---

## 1. Locally

- Installs from a clean checkout with the documented command, no manual steps
  that are not in the docs.
- Builds with no errors and no new warnings.
- Starts, and the main flow can be completed by hand.
- No errors in the server log or the browser console during that flow. An error
  that "does not affect anything" is an outstanding issue until someone proves
  it does not.
- Type check clean. Lint clean.

## 2. Tested

- The suite passes. Every test, not the ones that were passing before.
- Coverage is at or above `done.coverageMin` (default 80).
- **Every critical path has a test regardless of the percentage.** Coverage is a
  floor, not a target, and a high number over the wrong lines proves nothing.
- No test was weakened, skipped or deleted to reach green. If a test is wrong,
  fix the test and say in one line why it was wrong.

## 3. Deployed

- The same three local checks, run against the deployed target.
- Environment variables are set and documented, and the app fails loudly rather
  than silently when one is missing.
- The main flow completes against the deployed instance.

## What to do with a check you cannot run

**Record it as outstanding. Never skip it silently.** No deploy target
configured yet is a legitimate state; reporting done while a third of the
definition was never evaluated is not.

```
Outstanding
  deployed check   not run: no deploy target configured
  coverage         71%, floor is 80%. Missing: payment webhook, session expiry
```

That block is the honest form of "not done", and it is standing rule 7 applied
to the finish line.

---

## The fix loop

Once building is finished, the loop to zero is **autonomous**. Find issues, fix
them, verify again, repeat. Do not ask about any of it. A question here is a
question about work, not about intent, and work is what you were asked for.

Two constraints on the loop, and they are what stop it doing damage:

**It may not terminate by deletion (standing rule 9).** Removing the feature
that fails, commenting out the failing assertion, stubbing the endpoint to
return a fixed value: each of these reaches zero errors and none of them is a
fix. If a genuine fix requires removing a feature, that goes to the human as a
question, and the loop moves on to the next issue meanwhile.

**Feature parity is checked at the end.** Where a feature inventory exists (the
rescue preset writes one), every item on it must still work when the loop
finishes. Where none exists, the acceptance criteria from the spec serve the
same purpose.

If the loop runs three full passes without the outstanding count dropping, stop
and report. A loop that is not converging is not going to converge, and burning
quota to prove it is a waste of the human's money.
