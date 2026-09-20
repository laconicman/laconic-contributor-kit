# Design

The decisions this kit rests on, why each was taken, and what was rejected.

## Overview

Authoritative over code comments where they disagree. Every entry below was paid for by a
specific failure on a real pull request; none is a preference.

The origin: on one upstream PR, **two separate asks each had to be made three times.**
*"Apply this to the TCP transport too"* was raised in review bodies on three consecutive
days and missed every time, because only inline comments were being read. *"Add a
regression test"* was missed twice more — the second time by an audit script written
specifically to prevent the first failure, which enumerated only inline comments and so
reported "all threads answered" every round.

> A checker that quietly checks the wrong set is worse than no checker.

## Three channels, not one

Review feedback arrives on three surfaces: inline review comments, **review bodies**, and
issue comments. There is no repo-wide endpoint for review bodies — they are reachable only
per pull request, which is exactly why they go missing.

Set arithmetic over `in_reply_to_id` answers "is this thread answered?" for inline threads
only. It is deliberately **not** extended to the other two.

**Rejected:** *"a review body is answered if I posted any top-level comment after it."*
It is a silent false negative — it clears an obligation whenever you happen to comment
about something else in the same window — and it is what the stopgap audit used while the
asks kept being missed.

## Review bodies and issue comments are obligations

Neither can be replied to. That moves the burden onto the contributor; it does not
discharge it. So they are listed first, never auto-cleared, and leave the list only when
an acknowledgement is **recorded** — a pointer to where the content was absorbed.

The record is keyed by comment id **and** body hash, so an edit after acknowledgement
re-opens the item by itself. For review bodies the hash is not an optimisation: REST's
review schema carries `submitted_at` and nothing else, so the channel with no reply
mechanism is also the one REST cannot diff. That is why the per-thread fetch is GraphQL.

See ``Acknowledgement`` and ``AcknowledgementEligibility``.

## A differ, not a reporter

A reporter re-derives the same list every run and hands the reader a wall of text. A
differ compares against a ``Snapshot`` and reports what moved.

**A state transition counts as movement.** Comparing bodies alone meant the run
immediately after a round of replies reported "nothing moved" — true of what the snapshot
tracked and false of what a contributor tracks, because the snapshot stored no state at
all. Entries carry ``ItemState`` for this reason.

Measured: roughly 2,300 tokens per audit against ~24,900 for a hand-rolled `jq` fetch of
the same three endpoints, and ~193,000 raw.

## The boundary

> The CLI decides everything decidable **without reading meaning**. It never decides a
> meaning question. It emits the meaning question, pre-loaded with exactly the text needed
> to answer it, and marks everything it already settled.

Both failure modes cost the same thing. If the tool judges meaning it will be wrong and
the reader re-derives anyway; if it dumps raw comments the reader re-enumerates, which is
the waste being eliminated. Hence ``InboundItem``'s seven-key contract: `id`, `kind`,
`permalink`, `state`, `question`, `changed`, `text`, and nothing else.

## Reading a reviewer's declared metadata — the limit

Supersession is allowed: a reviewer writing *"This report is out of date"* has retracted
the ask, and taking the asker at their word is not judging meaning.

**A category label is not intent, and this line was drawn the hard way.** The kit briefly
read one reviewer's `kind: "analysis"` marker as "a receipt, not an ask", on 13 confirming
comments across two repositories. On a third, the same kind carried real findings, and two
genuine asks were hidden for about ten runs.

The verification that let it through — *"9 of 9 reclassified items carried the marker"* —
confirmed a regex, not the premise. ``InformationalDetector`` is now narrow by
construction: it never applies to an inline thread, because an inline thread's lifecycle is
decidable from ids alone and suppressing one can only ever hide a real ask.

## Nothing leaves the workspace without an explicit flag

Not a LOC figure, not a register row, not a drafted reply. `contrib in` stops at the
worklist and does not draft replies — the natural next step, and the one most likely to
produce a confident wrong answer.

No credential is ever read, stored or invented: `gh` holds the token.

## LOC is a trend, never a quality score

Tests legitimately add lines and comments are programmer's politeness. ``Counts`` has
three fields and deliberately **no** `total` property; a single summed figure is the thing
this half exists not to produce.

`cloc` is the classifier. **Rejected:** writing a Swift line counter, which means
re-deriving a 300-language comment table to arrive at the same numbers.

## See Also

- <doc:Roadmap>
- <doc:TechDebt>
