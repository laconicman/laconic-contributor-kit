# Roadmap

What is built, what is next, and what is deliberately not being built.

## Overview

Priority-ordered. Rationale lives in <doc:Design>; costs and discharges in <doc:TechDebt>.

## Now — shipped and used in anger

- **`contrib in`** — the three-channel audit, obligations, transitions, the re-read list,
  and the review horizon. The subject's own body rides the issue-comments channel — for
  an issue it is the primary ask. Run across three independent trials on `pjsip/pjproject`,
  `laconicman/telegram-kb`, `laconicman/YDelivery`, `laconicman/YandexDeliveryExpress` and
  `anthropics/claude-code`, on both pull requests and issues.
- **`contrib ack`** — recorded acknowledgement by comment, commit, PR body or an explicit
  no-action with a reason. `--refresh` re-fetches the item's subject and rewrites the
  snapshot first, for the reply-then-acknowledge flow.
- **`contrib show`** — one item in full: the ask, your reply, the recorded
  acknowledgement, and a line diff against what the snapshot last saw. Writes only the
  shown entry, so the next `contrib in` no longer reports already-read changes as new.
  `--full` prints the raw body — the retrieval path for `[collapsed: …]` markers.
- **`contrib loc`** — `cloc` orchestration, file roles, per-commit walk, JSONL ledger.
  Offline, and usable on a repository with no GitHub remote at all.

## Next

- **`contrib out`** — *what did I say that is still owed, or has gone stale or false?*
  Offers, promises and claim checking. Specified but not built; it depends on a register
  schema whose multi-link anchor shape is undecided.
- **`contrib lint <body-file>`** — the outbound check. A session pasted a comment onto a
  public issue carrying the literal token `PASTE_REFERENCE_ID_HERE`. Every guarantee here
  is about what came *in*, and the operator will assume the other half is covered. Should
  also diff an edit against the live body and render through `POST /markdown` to count the
  `<br>`s GitHub inserts for every newline.
- **A corpus mode, `contrib in <repo> --mine`.** Every finding in the issue-author trial
  was a relation *between* two items — one issue's close rationale being the principle
  another says is broken. Neither is visible from inside either issue.

## Next — borrow the review skill's discipline, pointed outbound

Recorded 2026-09-20, from three review rounds on this repository's own pull request: 25
findings, zero false positives, every one answered and re-read. The companion
`laconic-code-review` skill has rules for *writing* a finding; a contributor needs the
mirror image for *answering* one, and the round-summary comments written by hand this
week are the evidence of what that shape is.

None of it is implemented. `contrib in` stops at the worklist and does not draft replies
— that stays true; this is guidance for the `contributions` skill, not generation.

### 1. A reply shape, as a decision table

What the three rounds converged on, unprompted, and what the skill should state:

| The reply names | Why |
|---|---|
| The commit that carries the fix | The reviewer can check it without asking |
| The **cause**, not only the fix | *"the local was shadowing the argument"* tells the reviewer whether the class recurs |
| The test that now fails against the old behaviour | Turns a claim into something checkable |
| Any **deviation** from the recommendation, explicitly | A silent deviation reads as a misunderstanding |
| A fix that was **wrong on its first attempt** | One round's fix parsed a commit away entirely; hiding that costs more than admitting it |

### 2. Severity mirroring

A reply that opens by agreeing with the reviewer's own rating — or that says plainly why
it disagrees — is read faster than one that argues the substance first. The review skill
rates findings on one axis; the contributor should answer on the same one.

### 3. A round summary, separate from the per-thread replies

Each round here closed with one comment carrying a table of finding → fix, then the two or
three findings worth calling out beyond their fix. The per-thread replies answer the
reviewer; the summary answers everyone who arrives later, including the author next month.

### 4. Correct the topmost record

Where an earlier reply turns out narrower than it should have been, **edit it** rather
than appending a correction. One reply here cited a CI run on the head that was reviewed
rather than the head that fixed it; the amendment went in place. Edits do not notify, so
anything the reviewer must act on still needs a new comment.

### 5. What the kit needs from the other side

The review skill's `resolve-thread` flips a flag without prose. A resolution that names
the fix — Devin's `✅ **Resolved**: …` — is what lets ``ItemState/answeredConfirmed`` mean
*the asker confirmed it* rather than *the author claimed it*. Filed as TD-3 in the review
package rather than here, because that is where the fix lives.

## Later

- **Disposition states** — what *they* did with an item, as opposed to what I owe. A close
  carrying a condition addressed to me, a bot-marked `stale`, and a close with no rationale
  are currently invisible or flattened into `obligation-open`.
- **Label provenance.** A `bug` label applied by a bot and one applied by a person look
  identical and mean opposite things; a session nearly wrote "they accepted this as a bug"
  into a public comment on the strength of a bot label.
- **Path and line on inline items**, so a code-shaped finding does not need a second fetch
  for its anchor. The one fetch the kit has not absorbed.

## Not being built

Each was considered and rejected with a reason: an MCP server face, a `gh` extension, a
Swift line counter, a commit-type classifier, a second storage engine, a comment-orphan
detector, and a bulk "era" acknowledgement (see <doc:Design> and <doc:TechDebt>).

## See Also

- <doc:Design>
- <doc:TechDebt>
