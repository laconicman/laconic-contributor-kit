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

## Known documentation defect in the source specification

The spec's prose states that `tests/automated/Makefile` classifies as `build`. It does
not: the shipped ordered rule list — which is the same list the 39/33/18/7/1 role
distribution was measured with — places `test` ahead of `build`, so it classifies as
`test`. **The rules are authoritative and the sentence is the error.** Pinned by a test
so the next reader finds the answer rather than the claim.

## Still open

- **Multi-link register rows.** A register row can carry more than one permalink. The
  anchor schema must allow several `link=` pairs per row, or an anchor per link with a
  shared `id=`. Belongs to `contrib out`, which is not built.
- **The claim-phrase list** for checking our own outbound comments. Should be seeded
  from what has actually been written upstream, the way the offer phrases were, rather
  than from invented plausible phrases.
- **Whether a fork issue linking to an upstream thread puts a "referenced" event on
  that thread's timeline.** Six live offers would be six such events on threads the
  maintainer is reading. It is a write to a public repository, so it is not tested here.
