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

## Say how many, before the first one

A person answering questions needs to know how many there are. Duet used to open
with "ten questions", which was true of setup and of nothing else, and a real
run reached question 17 of an unknown total.

State the total before the first question. The preset is already known, because
invoking `duet-rescue` named it, so `duet questions <preset>` gives the run's
share and setup adds its own.

```
duet-rescue. 15 questions in total.
  10 now, to set up Duet in this repo. About two minutes.
   5 during the run, at stages 1, 3 and 5 of 11.
  Stage 1 may add a few if the read-back finds things worth asking about.
  Nothing asks you after stage 5 until the final round.
```

## Then keep saying where they are

Every question carries its position, printed by `duet ask <stage> <title>`:

```
[Q 7 of ~15 · stage 3/11 Document reset]
```

The tilde means part of the total is still an estimate. Its absence means
nothing further can surprise them, which is worth as much as the number.

## Revise out loud, in both directions

The moment a variable part becomes knowable, restate the total with the delta
and the reason:

```
Revised: 19 questions, 4 more than I said.
The read-back found four unknowns worth asking. Stages 5 to 11 still ask nothing.
```

Finishing under the estimate is announced too, because a total that only ever
grows is one nobody believes.

**Never revise silently.** A number quietly replaced is worse than never having
given one, and it is the failure this section exists to prevent.

The final round is stated separately and not counted. Every answer in it arrives
pre-selected and the run completes whether it is answered or not, so folding it
in would present an optional round as a required one.

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
