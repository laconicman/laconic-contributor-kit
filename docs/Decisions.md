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

### Supersession

A reviewer can **retract** an obligation — *"This report is out of date. Scroll down for
the latest report."* Without a concept of supersession, the never-auto-cleared rule
holds open an ask the asker has themselves withdrawn, forever, requiring a human
acknowledgement of something nobody is asking for any more.

Matched case-insensitively against a configurable phrase list, after boilerplate
stripping. Reported and counted; not owed.

### Empty review bodies

Not an edge case — in one observed round, four of six review bodies were badge markup
only. HTML comments, `<picture>` and `<details>` blocks, and lone image or badge lines
are stripped first; a body with no prose left is `no-prose`.

**Counted in the examined total, excluded from the worklist.** The argument for noise
over silence does not extend to noise that is definitionally empty.

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

`~/.local/state/contributorkit/<owner>__<repo>.json` — outside any work tree, honouring
`XDG_STATE_HOME`, overridable with `--state-dir`.

The requirement is that it must never reach an upstream-bound branch. Putting it
outside the tree makes that true **by construction**, rather than by an exclude file
somebody has to maintain and can forget.

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

## Still open
- **Whether a backticked reference suppresses GitHub's cross-reference event.** Needed to
  choose `referenceStyle`; a write to a public repository, so not tested here.
- **`upstream-commitments.md` has two rows with `id=A10`.** Must be resolved before the
  register is anchored, since the schema keys on that id.
- **An age threshold for the fork-issue escalation row class.** Arbitrary until there is
  more than one data point; the one observed case sat for months.
