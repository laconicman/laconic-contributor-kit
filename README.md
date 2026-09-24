# ContributorKit

[![CI](https://github.com/laconicman/laconic-contributor-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/laconicman/laconic-contributor-kit/actions/workflows/ci.yml)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/laconicman/laconic-contributor-kit)


Two questions, for anyone contributing to somebody else's repository.

**What was asked of me that I have not demonstrably absorbed?**

```bash
contrib in pjsip/pjproject --pr 5233
```

**Is what I ship getting more laconic?**

```bash
contrib loc --range upstream/master..my-branch --by-role
```

That is the whole tool. Everything below is how it answers them, and what it refuses
to do.

---

## Direction docs

The architecture, the decisions and the register of known debt live in the DocC catalogue
and are authoritative over anything said here or in code comments:

- **Design** — every decision, why it was taken, and what was rejected.
- **Roadmap** — what is built, what is next, what is deliberately not being built.
- **TechDebt** — a numbered register, each item with its cost and its discharge.

```bash
swift package generate-documentation --target ContributorKit
```

They render on the [Swift Package Index](https://swiftpackageindex.com) too — `.spi.yml`
names the documentation target.

## Why it exists

On one upstream pull request, **two separate asks each had to be made three times.**

- *"apply this to `sip_transport_tcp.c` too"* — raised in review bodies on three
  consecutive days, missed every time, because only inline comments were being read.
- *"add a regression test"* — raised in review bodies twice more, missed again. This
  time by an audit script written specifically to prevent the first failure, which
  enumerated only inline comments and so reported "all threads answered" every round.

Every code point the maintainer raised was fixed in the round it was raised. What
failed was **response completeness** — which a tool can check and a human reliably
cannot.

> A checker that quietly checks the wrong set is worse than no checker.

## What `contrib in` actually does

It reads **three channels**, not one:

| Channel | Can you reply to it? | How it is cleared |
|---|---|---|
| Inline review comments | Yes | A reply from you in the thread |
| **Review bodies** | **No** | A *recorded* acknowledgement |
| Issue comments — **including the subject's own body** | No | A *recorded* acknowledgement |

There is no repo-wide endpoint for review bodies — they are reachable only per pull
request, which is exactly why they go missing.

A review body cannot be replied to. **That does not discharge it.** It is a contributor's
mistake to go on as if nothing was posted, so review bodies are listed first and never
auto-cleared. They leave the list when you record where the content was absorbed:

```bash
contrib ack pullrequestreview-5130977763 --with commit:e02b93e1
contrib ack pullrequestreview-5095816383 --with none:"pre-existing, not this PR"
```

Recorded, never inferred from proximity in time. The record is keyed by comment id
**and** body hash, so if the reviewer edits the ask after you acknowledge it, the item
re-opens by itself.

## What "owed" means

The provenance block ends with a count of items **owed**. It is not a backlog estimate
and not a judgement about your work — it is one deterministic question per item:

> *Is there something here that nothing in the record answers?*

Four states are owed, and five are not:

| Owed | Not owed |
|---|---|
| `open-ask` — a root ask from someone else, no reply from me | `answered-claimed` — I replied |
| `obligation-open` — a review body or issue comment with nothing recorded | `answered-confirmed` — the asker replied after me |
| `reopened-by-edit` — acknowledged, then the body changed | `obligation-acknowledged` — recorded, body unmoved |
| `edited-after-my-answer` — the ask moved after I answered | `superseded` — the reviewer retracted it |
| | `no-prose` — badge markup only |

**The two halves have opposite defaults, and that is the whole design.** On an inline
thread "answered" is decidable — did I post a reply in this thread? — so the default
flips to *not owed* as soon as I reply. On a review body or an issue comment there is no
reply relation to check, so nothing can ever make it *not* owed except a record. The
channel that cannot be replied to is the one that goes missing, so it is the one that
defaults to owed.

### The cold start

A repository you adopt this on mid-flight will show a pile on the first run. On
`pjsip/pjproject#5233` that was **eight** — one per review round the maintainer ever
posted — even though every one had been absorbed months earlier across eight rounds of
back-and-forth.

That is correct, not a bug: the tool has no memory of rounds that happened before it
existed, and inferring "these are probably fine because they are old" is precisely the
inference the obligation model exists to refuse. But it is a once-per-repository cost,
and the honest way to pay it is to record it as what it is:

```bash
contrib ack pullrequestreview-5095816383 --with none:"pre-adoption; absorbed in round 3"
```

Those acknowledgements are real records with real reasons, and they re-open by
themselves if the reviewer ever edits the body. After the first pass, every later run
shows only what actually moved.

**How big the pile is depends on the reviewer, not on you.** A reviewer that marks its
own superseded reports *"out of date"* — Devin Review does — has every historical body
classified `superseded` or `no-prose`, and the pile clears itself. Measured on one such
PR: 37 review bodies, 16 ours, 16 no-prose, 4 superseded, **5 owed**. A human maintainer
who never retracts produces the full pile instead. Two first runs looking nothing alike
is this, not inconsistency.

## It is a differ, not a reporter

Every run compares the world against a local snapshot and reports the delta. A
reporter re-derives the same list every round and hands you a wall of text; a differ
hands you three items and says what changed about each.

The first run on a repository is the baseline, and says so. On a second round, a run
*without* prior state is not a weaker version of this — it is actively misleading,
because it cannot tell a new finding from a reviewer's resolution from your own reply.

The snapshot lives in `~/.local/state/contributorkit/`, outside any work tree, so it
cannot reach an upstream-bound branch. `--state-dir` moves it.

## The boundary

> The CLI decides everything decidable **without reading meaning**. It never decides a
> meaning question. It emits the meaning question, pre-loaded with exactly the text
> needed to answer it, and marks everything it already settled.

| The tool decides | Only you decide |
|---|---|
| Is there a root ask from someone else with no reply from me? | Is my reply actually *responsive* to the ask? |
| Has this item's body hash or `lastEditedAt` changed since my snapshot? | Does the edit change what is being asked? |
| Was the ask edited *after* my answer was posted? | Is my answer now wrong, or merely older? |
| Did I paginate to the end? Do the counts agree with last run? | — |

## Every command ends with a provenance block

```
— provenance —
command        contrib in pjsip/pjproject --pr 5233
inline threads 24
review bodies  34
issue comments 5
owed           8
pages fetched  1
note           24 of those review bodies are mine — not obligations
note           2 item(s) no-prose — counted, not owed
subprocesses   1
anomalies      none
```

It prints **the count examined**, whether or not anything was found. That is the
difference between "0 issue comments" as a fact and as an assumption. A guard you have
to remember to invoke is a guard that does not run, so this is not a separate
`contrib check` — it is attached to every command, and an anomaly exits non-zero.

A command that recorded no examined counts at all raises an anomaly by itself, because
a check that cannot distinguish *ran and passed* from *did not run* reports success in
both cases.

## `contrib loc`

**LOC is a trend, never a quality score.** Tests legitimately add lines and comments
are programmer's politeness. Code, comment and blank are reported separately and
**never summed** — there is deliberately no `total` field anywhere in the type.

```
                 code   comment   blank
added             107       109      21
removed            82         0       0
modified           35         8       0   (code 20 excluding whitespace)
net               +25      +109     +21

comment/code   4.36
```

- `cloc` is the classifier. This package contains no line counter, and should not.
- Roles are ordered, first match wins: `vendor` → `test` → `build` → `docs` → `source`.
  `vendor` is a third of a typical C project, and folding it into `source` makes an
  upstream dependency bump read as your own bloat.
- Per-commit figures **do not sum to the branch total** and are not a check on it:
  commits re-touch the same lines. Both views are correct; the report says which it is
  showing.
- The comment-to-code ratio is **suppressed when net code ≤ 0**. A deduplication commit
  at `code −33 / comment +21` would otherwise print `−0.64`, which is worse than
  printing nothing.
- `--range` never touches the network, and must stay that way.

**The figures are internal by default.** They are an input to your judgement about how
large a patch really is — not an output to anyone else.

## Nothing leaves the workspace without an explicit flag

Not a LOC figure, not a register row, not a drafted reply. Default is read, compare,
report locally. `contrib in` stops at the worklist and does not draft replies: that is
the natural next step and the one most likely to produce a confident wrong answer.

No credential is ever read, stored or invented. `gh` holds the token; this shells out
to it and never asks what it is.

## Install

Needs `gh` (authenticated) for `contrib in`, and `cloc` for `contrib loc`. Neither is
bundled and neither path is hardcoded.

```bash
git clone https://github.com/laconicman/laconic-contributor-kit
cd laconic-contributor-kit
swift build -c release
./scripts/install.sh          # or: ./scripts/install.sh ~/.local/bin
```

**Use the script rather than copying the binary.** `contrib` needs its resource bundle
beside it, and a binary copied alone keeps working — by falling back to the absolute
path of the build directory — right up until someone runs `swift package clean`, at
which point it dies with an internal `fatalError` rather than a diagnosable message.
The script copies both.

`contrib loc` needs no network and no GitHub remote at all, so it works on a repository
that has neither.

As a Claude Code plugin, `plugin/` carries the `contributions` skill — the policy half,
as a decision table. Point your plugin config at this repository's `plugin/` directory.

## Configuration

`.contributorkit.yml` in the repository root overrides the shipped defaults, per
top-level key. The role list is replaced whole rather than merged, because the
**order** is the contract and a merged order is nobody's.

Shipped defaults live in `Sources/ContributorKit/Resources/`, in two files on purpose:
`contributorkit.default.yml` is generated from the script that measured the role
distribution over 3,435 files, and `inbound.default.yml` is reasoned from one field
report and says so. Provenance is stated per claim, not per project.

## Tests

```bash
swift test
```

Entirely offline. The tests assert against captured `cloc` documents and real
captured GitHub threads rather than against numbers retyped into Swift — if a figure
drifts it shows up as a comparison against a measured document.

## What this deliberately does not do

No MCP server. No `gh` extension. No Swift line counter. No commit-type classifier. No
second storage engine. No comment-orphan detector. No bulk "era" acknowledgement. Each was
considered and the reason is in the Design article.

`contrib out` — *what did I say that is still owed, or has gone stale or false?* — is
specified and not yet built. It depends on a register schema with one genuinely
undecided piece.
