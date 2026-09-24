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

The subject's own body rides the issue-comments channel as a synthesized item — for an
issue it is the primary ask, and a pull request's description can carry one. GitHub's
own timeline treats the body as the thread's first entry; `viewerDidAuthor` filters the
contributor's own, so on self-authored subjects it is never listed.

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

## The nuance inventory

GitHub's threads carry more signal than the audit reads, and issue threads have their
own shapes — simpler than pull request threads (no outdated marks, no resolved state)
but not empty of nuance. Parked here so the probing is not re-done: each entry is a
real option, none is adopted, and the *reason it waits* is as much the content as the
field.

- **`isMinimized` on comments.** A maintainer minimizing a comment is closer to
  retraction than to resolution — but it is a *semantic* judgement about intent, and
  semantic judgement is the boundary this kit does not cross. Parked, not adopted.
- **`stateReason` (`COMPLETED` / `NOT_PLANNED` / `DUPLICATE`).** Real disposition
  signal — the issue-side analog of the `closed`/`merged` distinction, and the same
  question the Roadmap's "disposition states" entry asks. Parked with it.
- **`locked` conversations.** An `obligation-open` on a locked thread cannot be
  discharged by comment — only `ack` closes it. Worth surfacing before it surprises,
  not before it occurs.
- **Cross-references.** "Closes #N" links and timeline events are how an issue learns
  something addresses it — a distinct channel of evidence, not a comment. Later, with
  disposition states.
- **Reactions.** A 👍 from the asker looks like confirmation, but `reactionGroups`
  carries no per-user attribution, and inferring confirmation from non-verbal signal
  is the rejected direction twice over.
- **`authorAssociation`.** Could let an issue author's follow-up weigh like an
  asker-confirmation — but weakening the conservative model is the cost, not the win.
- **A real HTML parser for the stripper.** `BoilerplateStripper` hand-rolls tag
  scanning — boundary checks, depth counting, comment-aware skipping, a recursion
  cap — and each review round has found another shape the hand-rolled version
  missed (commented tags, borrowed summaries). A structured parser would retire
  that class. Questionable, parked: the corpus is comment *fragments*, not
  documents — a parser must still answer "is this line prose or boilerplate",
  which is a policy question markup structure alone does not settle; and a
  dependency for ~150 lines of scan is a trade that wants evidence the missed
  shapes keep coming, not a principle. If the next round finds yet another legal
  form, that is the evidence.

Two lessons the review rounds on #5 paid for, recorded here because they generalise:

- **Canonicalise the whole form, never a suffix of it.** "One referent, many legal
  spellings" is the class a reviewer keeps finding — a subject-URL check matching the
  last four path segments still verified a `blob` path in a *foreign* repository.
  `subjectBodyID` parses the URL and requires the complete path shape; anything less
  is another instance of the same bug.
- **`prose` serves two readers, and the split must be explicit.** A
  `[collapsed: "Title" ·hash]` marker is display text for the contributor *and* input
  to the emptiness check — `hasSubstantiveProse` exists because conflating the two is
  exactly how badge-only bodies once became obligations. The marker's hash covers the
  collapsed content, so an edit inside a `<details>` section moves `prose` and can
  never be mislabeled "markup only". Three corollaries the as-built review paid for:
  markers are generated metadata, not the asker's words, so supersession and
  informational matching read `substantiveProse` — a collapsed section *titled* like
  a retraction cannot retract the body it rides with; a `<summary>` titles only its
  own `<details>`, so the title search stops at the first nested opener rather than
  borrowing a child's legend; and kept-section recursion is capped, because nested
  kept summaries are constructible inside one comment body. A body of *only* markers
  is `collapsed-unexamined`, not `no-prose` — unexamined is not empty, so the flag
  lists until acknowledged rather than vanishing into the examined count. And marker
  presence is *provenance, not shape*: `strip(_:)` returns the markers the details
  pass emitted that survived the later boilerplate passes, so a marker-shaped line an
  author wrote — quoting the format — stays prose, a marker erased with its block
  flags nothing, and only real emissions flag unexamined content or block a
  suppression verdict. Shape has one remaining job: suppression classifiers read
  prose minus marker-shaped lines regardless of provenance, because a line quoting
  the format is never the reviewer's own opening statement — a retraction embedded
  in a quoted marker title cannot withdraw the ask it rides with.

And one clarification worth stating plainly: a reviewer's collapsible section —
"Learn more", fix instructions, diagnostics — is part of the comment `body`, not a
separate API field. The fetch always carried it; what `prose` does with it is a
stripping decision, which is why the answer was configuration (`keptDetailsSummaries`)
and a flag (`show --full`), not a fetch change.

## See Also

- <doc:Roadmap>
- <doc:TechDebt>
