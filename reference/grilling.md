# Grilling

"Ask until nothing important is left to guess" is a target, not a method. This
is the method: the question shapes that actually find holes, in the order they
usually find them.

The test for whether to ask a question at all: **would any answer change what
gets built?** If not, it is conversation, and conversation costs the human's
patience, which is the scarcest thing in the room.

One question per turn. Wait for the answer. A list of six questions gets one
answer to the easiest one.

---

## The archetypes

**What happens when two people do this at the same time?**
Finds the entire class of bug nobody designs for and everybody ships. Bookings,
carts, counters, uploads, anything with a balance. The answer is usually "I had
not thought about that", and it usually changes the data model.

**What does the user see when this fails?**
Not what is logged. What appears on their screen. Most specs describe the happy
path in detail and leave every failure as an implicit blank screen. This is also
the question that surfaces whether they care about the product or only the
feature.

**What are you assuming somebody else handles?**
Payments, email delivery, auth, moderation, backups, GDPR. Every project has a
line where the person assumes something outside it is taken care of, and half
the time nothing is on the other side of that line.

**What does this look like in month two?**
A hundred times the data, real users, and someone on holiday. Finds the design
that only works while it is empty, and the one that needs an admin screen nobody
has scoped.

**What would make you throw this away and start again?**
Finds the actual requirement, the one they did not say because it felt too
obvious. If the answer is "if it is slow" you have just learned that performance
is the spec.

**What is the thing that is obvious to you and nobody else?**
Domain knowledge. The regulation, the way their industry does invoices, the
customer who accounts for half of revenue. They will not volunteer it, because
to them it is not information, it is just how the world is.

**Who else touches this?**
Other systems, other teams, a spreadsheet somebody maintains by hand. Integration
requirements arrive late and expensively when this is not asked early.

**What is out of scope, deliberately?**
The most useful question in the set and the least asked. A written no is what
stops a project growing sideways every time somebody has an idea.

## Depth

`grill.depth` decides how far this runs. **There is no cap**, because a spec
with a hole in it is more expensive than one more question.

What there is instead is a promise. Work out how many of the archetypes this
task actually needs, **say that number before asking any of them**, and revise
it out loud if it changes:

```
Six questions before I build. The spec is missing failure behaviour, the
concurrency story, and who else touches this.
```

Uncapped and announced is honest. Uncapped and silent is what produced a run
that reached question 17 with no end in sight.

**`off`** builds what was asked. Record the assumptions you had to make, in one
line each, and move on. Legitimate: sometimes the person knows exactly what they
want and questions are friction.

**`normal`** asks only the archetypes that would change what gets built for
this specific task. Usually three to five questions. Stop when the next one
would not change anything.

**`hard`** asks all of them, and argues with the idea itself. Is this the right
thing to build? Is there a smaller version that tests the same assumption? What
is the evidence anybody wants this? Hard mode is allowed to conclude that the
project should not be built, and saying so is the most valuable output it has.

## What grilling is not

**Not a form.** Do not read the archetypes out in order. Pick the ones this task
actually needs, in the words this person uses.

**Not an interrogation.** If they do not know, that is an answer. Record it as
an assumption with your recommendation and move on. "I do not know yet" is
frequently the honest state of a real project.

**Not a rewrite of their idea.** You are finding holes in the spec, not
replacing their judgement with yours. Hard mode argues; it does not override.

**Not after implementation starts.** Everything here happens before the last
intent gate. Afterwards, questions accumulate for the single final round with a
recommendation attached, and the build continues.
