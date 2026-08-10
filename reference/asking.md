# How to ask

Every gate is a **question with options**. Never a paragraph that ends in a
question mark, and never a list of things you could not work out followed by
"correct me where I am wrong".

The reason is not politeness. A prose question makes the human compose the
answer, which means they do the structuring work, they answer only the parts
they happen to notice, and the parts they skip come back as assumptions nobody
recorded. A question with options is answered in one keystroke and the answer is
unambiguous.

---

## The shape

- **Two to four options.** Each one a real thing somebody would pick.
- **Each option names its consequence**, not just its label. "Experiment that
  grew" is a label. "Experiment that grew, so stage 3 deletes its docs rather
  than rewriting them" is an answer they can judge.
- **One option is recommended**, with the reason, so accepting takes one press.
- **Options come from evidence.** What the code shows, what the research found,
  what they already told you.
- **Free text is always available and never the only path.** The host provides
  it. Your job is to make the options cover the likely answers so it is rarely
  needed.
- **Multi-select when the answers are not exclusive.** Do not force a single
  choice on a question that has several true answers.

## Never invent an option to make three

Two real options beat three where one is filler. If there is genuinely one
sensible answer, present one and say that is why. An option nobody should pick,
included to make another look good, teaches people to stop reading the options.

## A list of unknowns is a list of questions

This is the rule that gets broken most.

When a stage produces several things you could not work out, each one is its own
question with its own options. Not a bulleted list with "correct me" at the
bottom.

**Wrong:**

```
What I could not work out:
  - Whether prediction markets are a real product line or an experiment
  - Whether the Telegram bot was ever a real product
  - Whether the leaderboard is a feature you care about

Correct me where I have got it wrong.
```

**Right:** three questions, each with options drawn from the evidence.

```
Prediction markets: a real product line, or an experiment that grew?
  Real product line     keep them, test them, they get documented as a feature
  Experiment that grew  keep the code, stop treating it as a promise
  Retired               remove the surface and the risk-disclosure text with it
```

If six things are unresolved, ask the two that change what gets built and record
the other four as assumptions with your recommendation. Asking six questions is
better than a paragraph; asking the two that matter is better than either.

## Which unknowns are worth a question

Only ones where a different answer changes what you would build. Everything else
goes to `duet_question_add` with your recommendation and gets resolved in the
final round.

Before asking, finish this sentence: "If they say X I will do this, and if they
say Y I will do that instead." If both branches are the same, do not ask.

## Grouping

Group questions only when they are one decision seen from several sides, and
only up to the host's limit. Otherwise one at a time, and wait for the answer.

Three grouped questions about the same architecture choice is a form worth
filling in. Three grouped questions about unrelated things is a form nobody
finishes.

## Statements are not questions

The read-back at the start of a rescue is a statement: "here is what this app
appears to do." Say it as prose, because it is prose. Then ask about what you
could not work out, in options.

Do not turn a statement into a question by appending "does that sound right?"
That gets "yes" from somebody who skimmed it.
