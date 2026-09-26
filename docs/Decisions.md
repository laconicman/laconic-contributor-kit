# Decisions

What was open when this was built, what was settled, and what remains. The
specification that produced this repository is internal; this file is the public
record of the choices it left open.

## Settled here

### What counts as *answered* for review bodies and issue comments

**An obligation is cleared only by a recorded acknowledgement**, in one of four forms:

| Form | Meaning |
|---|---|
| `comment:<id or permalink>` | I replied here |
| `commit:<sha>` | this commit carries it |
| `pr-body` | the PR description now says it |
| `none:<reason>` | no action needed, and why — the reason is required |

**Shape is always checked. Existence is checked only where it is free** — an id already
present in this run's fetch, a sha the local repository can resolve. Never a network
call: a verifier that needs the network is a verifier that gets skipped offline, and
then `verified` means *we did not look* while reading as *fine*. Each acknowledgement
records its own `verified` flag and note, and the provenance block prints how many went
in unverified.

The rejected alternative, for the record: *"a review body is answered if I posted any
top-level comment after it."* It is a silent false negative — it clears an obligation
whenever you happen to comment about something else in the same window — and it is what
the stopgap audit script used while the asks kept being missed.

### Acknowledgement by the asker

Distinct from acknowledgement by the answerer, and stronger. When the person who raised
a thread replies **after** your reply, the item is `answered-confirmed`: that is the
asker confirming the answer, where your own reply only records a claim.

This is not inference from proximity. The never-infer rule is about inferring
*acceptance from timing*; this is the asker speaking, in their own words, in the thread.
Implemented for inline threads only, since the other two channels have no thread to
reply into.

**Amended 2026-09-26 (issue #7): the asker's verdict confirms whenever it was posted.**
A reviewer that re-reviews on push can confirm a fix before I reply. On
`laconicman/telegram-kb#1` Devin Review did that on twelve threads, and each stayed
`answered-claimed` because its confirmation came first. A reply from the asker's login
whose stripped prose **opens** with a configured phrase (`inbound.verdictPhrases`, seeded
with Devin's `✅ **Resolved**:`) now confirms my reply, before or after it.

- **Opening only.** A reply that mentions the phrase is not a verdict. This is the lesson
  supersession paid for, when a mid-sentence mention retracted a live ask.
- **It needs my reply.** A verdict upgrades my claim to confirmed. It never manufactures a
  reply I did not write, so a verdict-only thread stays `open-ask` until one line clears it.
- **Seeded for one reviewer.** 92 of 92 verdicts carried the phrase, and 0 of 19
  fix-session replies under the same login did. That is one reviewer on one repository;
  see *Reading a reviewer's declared metadata — withdrawn* for what an unverified reading
  of declared structure once cost.

Matching a fixed phrase where the asker puts it is declared structure, not meaning — the
same move supersession makes. The boundary sentence in `ItemState.swift` now says so.

**Amended again, same day: from a bot asker, only the verdict confirms.** A reviewer
bot's login also carries its fix sessions. On `telegram-kb#3` I replied "Fixed", and the
reviewer's login then replied *"Closed the remaining half of this in f7c1a98"*. My fix
had missed a path. Any asker-login reply after mine counted as confirmation, so the one
reply I most needed to read was cleared. The same thing happened on `#6`.

- **Gated to configured bots** (`inbound.botAskers`, seeded with `devin-ai-integration`,
  matched with a GitHub App's `[bot]` suffix ignored). A person's "LGTM, thanks" after my
  reply confirms, as it always has.
- **The asker's latest reply after mine decides.** A verdict confirms. From a bot, anything
  else is the new state `asker-replied`: *confirmation, or correction?* It is listed and
  never owed. A verdict that follows a correction is the reviewer re-checking once the
  rest was closed, so it confirms. A correction that follows a verdict is news the verdict
  predates, so it lists.
- **Cleared by replying, not by `ack`.** A check would judge my reply while the asker's
  later one went unread, and the audit decides `asker-replied` before it reads any check.
  So `ack` refuses and names the remedy: read the reply with `contrib show`, then answer it
  in the thread. That reply makes the thread `answered-claimed` again. The cost is a
  public one-liner even when the bot's reply was harmless; judged worth it over a new
  snapshot field.
- **`contrib show` prints the asker's replies**, each labelled by time, verdict, and
  whether it came after mine. A state whose question is *confirmation or correction?* has
  to arrive with the reply it asks about. That is what made this state legal.

### Resolution is reported, never decided on

Decided 2026-09-26, from issue #7. Every inline item carries GitHub's `isResolved`, the
login that resolved the thread (a GitHub App's `[bot]` suffix removed), and whether that
login is the asker's — in the table, in `contrib show`, and as `resolution`, the eighth
key of the `--json` item.

**No state reads it.** A thread is resolved for more reasons than the asker's consent: I
can resolve my own, a maintainer can, and a reviewer bot's fix session resolves under the
reviewer's own login. So the reader is told *who* resolved it, and keeps the ability to
tell those reasons apart; the audit draws no conclusion from it. `byAsker` exists because
the item carries no author to compare against. It cannot separate a reviewer bot from its
own fix session, which share a login — see *Still open*.

The contract grew a key because the reader needed it. Across seven pull requests the one
unresolved thread was indistinguishable, in `--json`, from the 110 resolved ones.

### Supersession

A reviewer can **retract** an obligation — *"This report is out of date. Scroll down for
the latest report."* Without a concept of supersession, the never-auto-cleared rule
holds open an ask the asker has themselves withdrawn, forever, requiring a human
acknowledgement of something nobody is asking for any more.

Matched case-insensitively against a configurable phrase list, after boilerplate
stripping. Reported and counted; not owed.

### Empty review bodies

Not an edge case — in one observed round, four of six review bodies were badge markup
only. HTML comments, `<picture>` blocks, and lone image or badge lines are stripped
first; a body with no prose left is `no-prose`.

**Counted in the examined total, excluded from the worklist.** The argument for noise
over silence does not extend to noise that is definitionally empty — but a body that
strips to only `[collapsed: …]` markers is not empty, it is *unexamined*: nobody can
tell diagnostics from a hidden ask without reading the section. Those get their own
state, `collapsed-unexamined` — listed until acknowledged, never owed.

### Authorship filtering

GitHub records a reply submitted through the review API as a *review*. On any pull
request where the contributor replies, an unfiltered obligation list is immediately
polluted with their own words.

Measured on `pjsip/pjproject#5233`: **34 review bodies fetched, 24 of them ours.**
Without the filter, that worklist is 34 items of which 24 are the contributor's own
replies flagged as obligations against themselves.

The count of filtered-out items is printed rather than silently dropped, so the filter
is visible instead of assumed.

### CLI surface

`in` / `out` / `loc`, not `scan` / `threads` / `loc`. No aliases — there is no muscle
memory to preserve, and two names for one verb is a cost forever.

### Where the snapshot lives

`~/.local/state/contributorkit/<owner>/<repo>.json` — outside any work tree, honouring
`XDG_STATE_HOME`, overridable with `--state-dir`.

The requirement is that it must never reach an upstream-bound branch. Putting it
outside the tree makes that true **by construction**, rather than by an exclude file
somebody has to maintain and can forget.

The layout is one path component per name. It began as `<owner>__<repo>.json`, which is
**not injective**: `a/b__c` and `a__b/c` are both valid GitHub names and both addressed
`a__b__c.json`, so auditing one could load and then overwrite the other's history.
Snapshots written at the old path are read and merged, never chosen between — both files
can exist holding different pull requests.

### Guards

A provenance block on **every** command, not a separate `contrib check`. A guard you
have to remember to invoke is a guard that does not run — and the miss that motivated
this happened inside a step nobody thought needed guarding.

Non-zero exit on anomaly. A command that examined nothing raises an anomaly by itself.

### Drafting replies

**No.** `contrib in` stops at the worklist. The boundary rule is that the CLI emits the
meaning question rather than answering it; drafting is the natural next step and the
one most likely to produce a confident wrong answer.

### Multi-link register rows

**Several `link=` pairs per row, in one anchor.** Decided 2026-09-13.

```markdown
| A10 | [#5241](…) / [#5240](…) | Fold in `load_cert_direct()`'s early-return leaks | **Trivial** |
<!-- offer id=A10 status=live first-seen=2026-09-05
     link=body:https://github.com/pjsip/pjproject/issues/5241
     link=issue-comment:https://github.com/pjsip/pjproject/pull/5240#issuecomment-5568406534 -->
```

One anchor per row, so there is exactly one `status=` and one `id=`. `link=` repeats,
each carrying its own `<kind>:<url>`; the parser collects them in order and the first is
primary. The alternative — an anchor per link sharing an `id=` — puts each anchor beside
the link it describes but leaves `status=` with no obvious home, and a human editing the
row has to know the anchors group.

Two facts settle the compatibility question, both checked on disk 2026-09-13:

- **The register carries no anchors at all yet.** Nothing to migrate. The `url=`/`kind=`
  pair the specification uses as its example is still accepted on read, as link #1, but
  is never written.
- **`A10` appears on two different rows** — one struck through and delivered, one live
  and unrelated. A reader survives that; a parser keyed on `id=` does not. So ids must be
  unique per anchor, and the first thing the reader should do is report a duplicate
  rather than silently keeping the last one. Fix the register before anchoring it.

### The claim-phrase list

**A hybrid, and the deterministic half comes first.** Decided 2026-09-13.

The check is: my own comment uses a claim phrase with no coverage table or explicit
not-verified list next to it. Over-inclusive by design — whether the claim is *true*
stays with the model.

The list must be seeded from what has actually been written upstream, not from invented
plausible phrases, which is a bootstrapping problem: you need phrases to find phrases. So
the tool **enriches a vocabulary rather than owning one**:

1. `contrib phrases <owner>/<repo> --mine` fetches every comment of ours, splits it into
   sentences, and prints those matching a small seed vocabulary, deduplicated, ranked by
   frequency, each with a permalink.
2. A human — or a model, or later a cheap local one — reads that and picks which are
   genuinely verification claims.
3. The output is a YAML fragment ready to paste into `.contributorkit.yml`. **The tool
   never writes it**, per the rule that the tool advises and never owns.

The seam is the phrase list, so swapping step 2 for a local model later changes nothing
else. A new repository gets a preliminary pass of step 1 before the check is useful there
— stated as a setup step rather than discovered as a silent false negative.

### Fork issues, backlinks, and what counts as delivery

Decided 2026-09-13, from how this actually works in practice rather than from the API.

The original question was whether a fork issue linking to an upstream thread puts a
"referenced" event on that thread's timeline, and whether six live offers would be six
such events on threads a maintainer is reading. The answer reframes it:

> We should definitely keep track of fork issues linking to an upstream thread, but
> generally we do not point maintainers at them and do not assume that maintainers will
> come to see them on their own. Escalating means creating the issue copy in the original
> repository.

Three consequences, and the first two are rules rather than features:

1. **A fork issue never discharges an upstream obligation.** It is not visible to the
   maintainer in any way we rely on. `contrib ack --with` does not accept a fork issue as
   a pointer; the discharge is the upstream comment, or the commit.
2. **A fork *branch* is different, and is a legitimate delivery pointer.** There is one
   recorded case of a maintainer picking commits from our fork to append to another
   contributor's PR, because we could not push there ourselves — which is exactly the
   `D1` row's shape. So `link=fork-branch:` is admissible evidence and `link=fork-issue:`
   is not.
3. **"Filed on the fork, never escalated" becomes a row class in `contrib out`.** A row
   carrying a `link=fork-issue:` and no upstream link, past an age threshold, is an
   escalation candidate: file the copy upstream, or drop it. Deterministic, and it falls
   straight out of the multi-link schema above.

Since we are not relying on the backlink, the `referenceStyle` choice becomes *how quiet
can we be* rather than *how discoverable*. A reference wrapped in backticks is not
auto-linked by GitHub and — as far as we know — creates no cross-reference event, which
would make `quoted` the right default for a mirror nobody is meant to be nudged by.
**That last claim is unverified and must be tested before it is relied on**; it is the
one empirical check the original question asked for, now with a clearer purpose.

## A documentation defect, corrected at the source

The specification's prose said `tests/automated/Makefile` classifies as `build`. It does
not, and never did: the shipped ordered rule list — the same list the 39/33/18/7/1 role
distribution was *measured* with — places `test` ahead of `build`. The rules were right
and the sentence was the error.

**Corrected in place** rather than annotated downthread, which is the rule this kit is
held to. Two things changed beyond the sentence:

- The ordering now has a **stated principle** — *location beats type* — so the
  consequences are derived rather than listed, and cases nobody thought of
  (`tests/run.sh`, `third_party/**/*.yml`) have an answer without a new example.
- The consequences live in the skill's
  [`references/file-roles.md`](../plugin/skills/contributions/references/file-roles.md),
  and **a test reads that table out of the file and asserts every row**. The original
  defect was possible because the example was hand-written prose that nothing checked.
  It is now checked, and the check was verified to fail by flipping a row.

The first version of *that* test silently examined 12 of its 13 rows, because a guard
meant to skip non-path rows also skipped `Makefile` — the same shape of bug, inside the
test written to catch it. It now locates the table by its header and reads it whole.

## Open, raised by the live trial

- **`open-ask`'s question carries no information beyond the state name.** Reported as
  correct but inert. It may be that `open-ask` genuinely has no meaning question — the
  boundary table lists the ask/no-reply test entirely on the deterministic side. If
  anything belongs there it is probably *how many rounds ago it was raised*, since
  "the maintainer had to ask three times" is the whole origin of this tool.
- **Fixes generate the next round's findings at a steady rate.** Three of six round-3
  findings were introduced by round-2 fixes; one round-2 finding was a bug in a round-1
  fix. Nothing notices that a new ask sits on lines a previous fix touched. Recorded
  because it is the most consistent pattern observed, not because it is scoped.

### `answered-claimed` stays listed — until confirmed, checked, or closed

Decided 2026-09-15. A thread I replied to and the asker has not confirmed carries a live
question — *is my reply actually responsive?* — and it used to appear only on the run it
changed, then vanish. A trial session reported that twice: the one item with an unanswered
meaning question was the one hidden by default, whether or not anyone had looked.

It now stays listed until one of three things happens:

- **The asker confirms** → `answered-confirmed`.
- **I record a check** → `contrib ack <id> --with none:"<why it answers>"` gives
  `answered-checked`. The record is keyed to the ask's body hash *and* to the reply it
  judged, so a later reply or an edited ask lists the thread again.
- **The PR or issue closes** → it drops out of the default view, still counted, and is
  listed again if anything about it moves — **unless the thread is still unresolved**
  (amended 2026-09-26, issue #7).

The cost is a longer default list where a reviewer never confirms; judged manageable.

**The amendment.** Across seven pull requests, the only thread the reviewer never resolved
was one whose reply had deferred the finding to tech debt. Its pull request merged, and
the default view hid it among twelve quiet `answered-claimed` threads under
*"merged — 13 answered-claimed item(s) not listed"*. An unresolved thread is the asker's
side disagreeing with the closure, so closure no longer quiets it. It stays listed and
counts in `to re-read`. `contrib ack` still clears it as `answered-checked`, and resolving
the thread quiets it.

This **lists and never clears**: `isResolved` only stops closure from hiding something. It
never marks anything answered, and never makes anything owed.

**Closure quiets only this list.** Owed items stay listed on a closed or merged subject,
because both trials produced counter-examples to "closed means done": a round of six
findings posted on an already-merged PR, and a close carrying a condition addressed to the
contributor. The provenance block reports `to re-read` beside `owed` and never folds one
into the other.

`ack` on an inline thread is therefore allowed in exactly the states where the record is
read — `answered-claimed`, or re-checking `answered-checked` — and refused, with the reason,
in every other.

### The cold start: a horizon, not an era-acknowledgement

**`inbound.horizon` in `.contributorkit.yml`.** Decided 2026-09-15, after a trial hit 44
never-answered threads on a PR whose code a rewrite had since deleted.

```yaml
inbound:
  horizon: "2026-07-01"   # or an ISO timestamp
```

Items raised before it are **counted and not listed**. The rejected alternative was
`contrib ack --era --before <ref>`, writing one reason across every matching item.

The difference is what gets asserted. An era-ack writes dozens of records saying *this was
absorbed*, which did not happen — the bulk-ack the obligation model exists to refuse,
made worse by living in a state directory nobody reads. A horizon asserts something true
and smaller: *this repository is not auditing that era.* One line, in a file a human reads
and git versions.

Three properties make it safe rather than a quiet filter:

- **Nothing is cleared.** The items stay in the snapshot, stay classified, stay counted.
- **The provenance block prints what is held back and how much of it is real** —
  `37 item(s) before the review horizon — not listed (25 of them would otherwise be owed)`.
- **Movement beats the horizon.** An old item surfaces the instant its body changes or its
  state transitions. A reviewer editing a June comment today is today's activity, and a
  horizon that swallowed it would be a check quietly running against the wrong set.

### Reading a reviewer's declared metadata — withdrawn

Briefly, `contrib` read Devin Review's `"kind": "analysis"` marker as *a receipt, not an
ask*, on the reasoning that metadata the asker emits about its own comment is not the CLI
deciding a meaning question — the same move supersession makes.

**The move is sound; the premise was false.** Devin uses `analysis` for both 📝 Info
receipts and 🔍 real findings, and it hid two genuine asks for about ten runs. Withdrawn,
with a regression test built from the two bodies it hid, and `informational` narrowed to
channels with no reply relation and one fixed unambiguous phrase.

The narrower lesson, worth keeping: *read metadata the asker emits about its own intent,
and verify the reading against more than one repository before trusting it to suppress
anything.* A category label is not intent.

## Still open
- **Whether a backticked reference suppresses GitHub's cross-reference event.** Needed to
  choose `referenceStyle`; a write to a public repository, so not tested here.
- **`upstream-commitments.md` has two rows with `id=A10`.** Must be resolved before the
  register is anchored, since the schema keys on that id.
- **An age threshold for the fork-issue escalation row class.** Arbitrary until there is
  more than one data point; the one observed case sat for months.
- **`contrib lint <body-file>`** — an outbound check. A session pasted a comment onto a
  public issue containing the literal token `PASTE_REFERENCE_ID_HERE`. Every guarantee
  this kit makes is about what came *in*; nothing looks at what is about to be sent, and
  the operator will assume it is covered. Should refuse on unresolved template tokens and
  dead links, and — measured the hard way — also diff an edit against the live body and
  render through `POST /markdown` to count the `<br>`s GitHub inserts for every newline.
- **A corpus mode, `contrib in <repo> --mine`.** Every finding in the issue-author trial
  was a *relation between two items*: one issue's close rationale being the principle
  another says is broken; two issues of the same defect class held to different standards.
  Neither is visible from inside either issue.
- **Disposition states** — what *they* did with an item, as opposed to what I owe. A close
  carrying a condition addressed to me, a bot-marked `stale`, and a close with no
  rationale at all are all currently either invisible or flattened into `obligation-open`.
- **Label provenance.** A `bug` label applied by `github-actions` and one applied by a
  person look identical and mean opposite things; a session nearly wrote "they accepted
  this as a bug" into a public comment on the strength of a bot label. Same argument as
  *`isResolved` is not answered*, one layer up.
- **`--with pr-body` acks reopen spuriously** where a bot re-appends a badge to the PR
  description on every edit. Hashing the *stripped* body rather than the raw one would fix
  it, at the cost of re-opening every existing acknowledgement once.
- **`--all` then `--json` turns the second call into a second round**, because the first
  wrote the snapshot. `--no-snapshot` on one of them is the workaround; one invocation
  emitting both would remove the trap.
- **A stray snapshot appeared in a repository work tree once** and could not be
  reproduced. A guard refusing to write a snapshot inside a git work tree unless named
  explicitly is cheap insurance.
