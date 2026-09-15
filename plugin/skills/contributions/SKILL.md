---
name: contributions
description: Use when working as an outside contributor on someone else's repository — answering a review round, deciding whether a round is finished, recording what was promised upstream, or judging how large a patch really is. Triggers on "did I answer everything", "is this round done", "what do I still owe upstream", "how big is this change", review-round audits, and any use of the `contrib` CLI (`contrib in`, `contrib loc`, `contrib ack`).
---

# Contributions

Two questions, and the discipline that goes with them.

- **What was asked of me that I have not demonstrably absorbed?** → `contrib in`
- **Is what I ship getting more laconic?** → `contrib loc`

The CLI settles everything decidable without reading meaning. It never decides a
meaning question — it hands you the question with exactly the text needed to answer
it. Your job is the column on the right.

## The decision table

Run `contrib in <owner>/<repo> --pr N`. Every item comes back with a `state`. This
table is the whole contract; there is no case where the right response is "ignore it".

| State | What the CLI settled | Your question | Your response |
|---|---|---|---|
| `open-ask` | A root ask from someone else, no reply from me | — | **Answer it, or say why it should be left out.** "Separate PR" is a fine answer. Silence is not. |
| `answered-claimed` | I replied | Is my reply actually *responsive* to the ask, or only adjacent to it? | Re-read both. If the reply dodged, reply again. |
| `answered-confirmed` | The asker replied after my reply | None | Nothing. The asker confirmed it themselves. |
| `edited-after-my-answer` | `lastEditedAt` > my reply | Does the edit change what is being asked? | If it does, answer the new ask. If not, say so once. |
| `obligation-open` | A review body or issue comment from someone else, nothing recorded | Does this need a response, or is it already absorbed? | Either way, **record which**: `contrib ack <id> --with …`. |
| `obligation-acknowledged` | Recorded, body unmoved | None | Nothing. |
| `reopened-by-edit` | Acknowledged, then the body changed | Does the new text ask for something else? | Re-read and re-acknowledge, or answer. |
| `superseded` | The reviewer retracted it | None | Confirm the replacement is in the list. |
| `informational` | The reviewer's own fixed announcement phrase, on a channel with no reply relation | None | Nothing. Counted, not owed. |
| `no-prose` | Badge markup only | None | Nothing. It is counted, not owed. |

**Every state is in this table.** If `contrib` ever prints one that is not, treat it as a
defect and check the item by hand — a state outside the table has no defined response, and
one that quietly sat outside `owed` hid two real asks for a day.

**`informational` is deliberately narrow.** It applies only to review bodies and issue
comments, never to an inline thread, and only on a fixed unambiguous phrase. It once read
a reviewer's declared `kind: "analysis"` as "a receipt, not an ask" — true of thirteen
comments across two repositories and false on the third, where the same kind carried real
findings. A category label cannot carry that decision.

**A review body cannot be replied to. That does not discharge it.** It is implied that
everything goes on after you absorb it in some way; going on as if nothing was posted
is the contributor's mistake. So review bodies are listed first and never auto-cleared.

**`isResolved` is not "answered."** The maintainer sets resolution. A thread can be
resolved with no reply from you, and an open thread can be fully answered. Never
substitute one for the other.

**"No change needed" still needs an acknowledgement.** Filtering out the items that
need no action is how they become the next unanswered thread. Let the reply be one
line; do not let it be no line.

**A zero is a timestamp, not a state.** Acting on a PR *causes* the next review wave, so
`owed 0` has been true at the fetch and false twenty minutes later. The provenance block
stamps `as of <time>` for this reason. **The audit that counts is the one run after the
reviewer's re-run, not after your push.**

## Acknowledging

```bash
contrib ack <id> --with comment:<permalink-or-fragment>   # I replied here
contrib ack <id> --with commit:<sha>                      # this commit carries it
contrib ack <id> --with pr-body                           # the PR description now says it
contrib ack <id> --with none:"pre-existing, not this PR"  # no action needed, and why
```

Recorded, **never inferred from proximity in time**. The record is keyed by comment id
*and* body hash, so if the reviewer edits the ask after you acknowledge it, it re-opens
by itself. Shape is always checked; existence only where it is free, and the provenance
block prints how many acknowledgements went in unverified.

## Five rules that were each paid for

1. **A review round is complete when the audit says so, never when you believe it is.**
   On `pjsip/pjproject#5233` two separate asks each had to be made three times. Every
   code point raised was fixed in the round it was raised; what failed was response
   completeness — which a tool can check and a human reliably cannot.

2. **Never trust a truncated fetch.** One miss was literally `sort | tail -6` over a
   seven-event batch: the earliest comment fell off, its id was hard-coded into the
   follow-up fetch, and the truncation propagated silently into "the round is done".
   The provenance block prints the count examined for this reason. Read it.

3. **Never trust an unexecuted check.** A verification that cannot distinguish "ran and
   passed" from "did not run" reports success in both cases. Assert on the *evidence of
   execution* — an exit status, a count, a non-empty result — before asserting on the
   outcome. When a check's passing condition is an absence (zero hits, no output, no
   diff), it is at its most dangerous, because every failure mode produces that absence
   too. A non-zero exit from `contrib` means an anomaly, not a finding.

4. **Verifying a conditionally-compiled change against one configuration is not
   verification.** A release paired with a `>= 3.0` up-ref was checked against OpenSSL
   3.6.3 — the only version where it is correct — and shipped a use-after-free that took
   down two Windows CI jobs on 1.1.1. Enumerate the configurations the guard selects
   between, build the ones you can, and **name the ones you cannot** rather than letting
   silence imply coverage.

5. **State coverage as a table, not as a sentence.** "Verified with `-Wall` across the
   backends" cannot be checked by a reader; a row per backend plus an explicit
   *not verified here* list can. This is what a maintainer needs from a contributor who
   cannot run their CI.

6. **Correct the topmost record.** Where a claim in an existing comment turns out
   narrower or wrong, **edit that comment** rather than appending a correction
   downthread. GitHub preserves the edit history behind the "edited" marker, so nothing
   is concealed. The tradeoff to know: an edit does not notify, so anything the
   maintainer must *act* on still needs a new comment.

## LOC

**LOC is a trend, never a quality score.** Tests legitimately add lines and comments are
programmer's politeness. `contrib loc` reports code, comment and blank separately and
never sums them; neither should you. Never quote a single summed "LOC" figure.

**The figures are internal by default.** They are an input to your judgement — how large
the patch really is, whether it wants splitting, whether the comment-to-code ratio is
worth mentioning at all — not an output to anyone else. Before asking which counter
produced a number, ask *should it leave at all?*

**Per-commit figures do not sum to the branch total** and are not a check on it:
commits re-touch the same lines. Both views are correct; say which one you are showing.

**Any figure that does leave the workspace comes from `cloc`**, never from an awk
heuristic. `scripts/loc-heuristic.awk` is kept as documentation of where the original
numbers came from, not as a second code path.

Roles are ordered and **location beats type**, so a Makefile inside `tests/` is `test`,
not `build`. When a path lands in a bucket that looks wrong, read
[`references/file-roles.md`](references/file-roles.md) — you do not need it otherwise.

## The default posture

**Nothing leaves the workspace without an explicit flag.** Not a LOC figure, not a
register row, not a drafted reply. Default is read, compare, report locally. A LOC
figure appearing in an outbound comment without the flag having been set is itself a
finding.

**Acceptance of an offer is a human reply**, never inferred by a matcher. When
`contrib` marks something an acceptance candidate, that means *go read the thread* — it
does not mean *update the row*.

## Phrasing the next offer

Spotting a defect and offering to fix it costs a maintainer nothing to accept. "Sure,
please do" is one word for them and days for you, and declining after offering reads as
impolite. So: know the exposure before adding to it, and phrase new offers so that
saying yes is bounded — name the size, and name what it depends on.
