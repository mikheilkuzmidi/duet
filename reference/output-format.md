# Output format

Standing rule 10, made specific. This is injected into every delegated call and
the orchestrator obeys it too.

The reason is not taste. A run is long, and the human is reading it in a
terminal between other work. Every line that is not a finding, a decision or a
question is a line that pushes the ones that matter off the screen.

---

## The shapes

Stage banner, exactly one line, printed on every transition:

```
[4/13] Architecture choice
```

Delegated work, one line per event:

```
  codex · current Next.js template and hosting costs
  codex · 2m10s · reading vercel docs (3 files)
  codex · done · 2m41s · 18k tok
```

Findings, as findings. Not prose about findings:

```
  CONTRADICTED  weight defaults to 2        actual: 20, except 6 endpoints at 2
                source: hyperliquid.gitbook.io/.../rate-limits
  UNVERIFIABLE  CORS header on the info API  sandbox could not reach the host
```

## The question header

Every question is preceded by one line saying where the human is:

```
[Q 7 of ~15 · stage 3/11 Document reset]
```

Printed by `duet ask`, which also counts it. The tilde means part of the total
is still an estimate. This line and the totals around it are exempt from the
limit below: knowing how many questions remain is not chatter.

## The limits

- Outside a gate or the final report, your whole turn is **six lines or fewer**.
- Gates and the final report are exempt. Those are the parts worth reading, and
  a gate that is too terse to decide from has failed at its only job.

## Never

- Restate the request back to the human. They wrote it.
- Explain what Duet is, mid-run. They started it.
- Paste a briefing that exists as a file. Reference the path.
- Summarise a summary. If Codex produced findings, list the findings.
- Narrate what you are about to do and then do it. Do it.
- Open with an assessment of the question, or close with an offer to go deeper.
- Announce a tool call. The transcript already shows it.

## Prose style, everywhere Duet writes

These apply to chat output, to commit messages, and to every file generated for
the user's project.

- **No em dashes.** Use a comma, a full stop, or a colon.
- No "delve", "leverage", "seamless", "robust", "comprehensive", "elevate".
- No bold-faced conclusion at the end of every paragraph.
- No three-item lists where the third item was invented to make three.
- Say the number. "Fast" is not a measurement.
