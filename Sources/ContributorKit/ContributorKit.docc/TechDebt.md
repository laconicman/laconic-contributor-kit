# Tech debt

Numbered register. Each item carries what it costs and the change that retires it.

## Overview

Status legend: **open** (accepted, unscheduled) · **deferred** (a decision was taken not to
fix it yet, with the reason) · **watch** (observed once, cause not established).

Reference an item from code as `// TODO(TD-3): …`.

### TD-1 — `contrib out` does not exist · open

The kit audits only what came *in*. A contributor's outbound side — offers made, promises
owed, claims that outran their evidence — is specified and unbuilt.

**Cost.** Half the kit's own thesis is unenforced, and the operator will assume otherwise.
A comment carrying an unresolved template token reached a public issue during a trial.

**Discharge.** Build `contrib out` plus `contrib lint`; see <doc:Roadmap>.

### TD-2 — the register's multi-link anchor schema is undecided · open

A register row can carry more than one permalink. Whether that is several `link=` pairs in
one HTML-comment anchor or an anchor per link with a shared `id=` was never settled.

**Cost.** Blocks TD-1. Deciding it after the first multi-link row exists is the expensive
order, and that row already exists.

**Discharge.** Pick one, write it into <doc:Design>, and parse only anchors — never prose.

### TD-3 — no path or line on an inline item · open

``InboundItem`` carries a permalink, not an anchor. A code-shaped finding therefore needs
one extra `gh api pulls/N/comments` call to locate it in the diff.

**Cost.** One avoidable fetch per round. Measured as small, but it is the only fetch the
kit has not absorbed, and `reviewThreads.path` is already in the GraphQL response.

**Discharge.** Add `path` to the item — which widens the seven-key `--json` contract, so it
needs the contract's rationale revisited in <doc:Design>, not just a field.

### TD-4 — `edited-after-my-answer` fires on markup-only edits · deferred

A reviewer that appends its badge to a superseded body re-opens every acknowledged item in
that round. Observed twice in one morning on one thread.

**Cost.** A public reply nobody needed, each time.

**Deferred deliberately.** Hashing the stripped prose instead would let a genuinely edited
ask be acknowledged privately — wrong in the expensive direction, where today's behaviour
is wrong in the cheap one. The item now reports *"markup only, prose unchanged"* so the
contributor knows which kind of edit it was, and the refusal stands.

**Discharge.** Only if the cheap direction proves costlier in practice than the expensive
one; revisit with counts, not impressions.

### TD-5 — two review bodies can share a body hash · watch

Two distinct rounds produced bodies reading exactly `**Devin Review** found 6 new potential
issues.`, hashing identically.

**Cost.** None today: records are keyed by id *and* hash. Anything later keyed on the hash
alone would merge two distinct obligations.

**Discharge.** Keep the composite key. If a hash-only index is ever introduced, this is the
case that breaks it.

### TD-6 — an `ack` failed and then succeeded minutes later · watch

Five items refused an acknowledgement, then accepted the same one after a `contrib in`
refreshed the snapshot.

**Cost.** Unknown. The reporting session's shell helper discarded stderr, so the message
does not exist.

**Discharge.** Reproduce with stderr captured, or close it as unreproducible. It is
recorded as a thing to watch, not as a defect — the evidence for it is gone.

### TD-7 — pagination past one page has never run · open

Every live subject across four trials fitted in one page of 100; the largest carried 88
items. The cursor loop, the page ceiling and the `truncatedFetch` anomaly are exercised by
unit test and by construction only.

**Cost.** The one untested path whose failure mode is a silently short list — the exact
class this kit exists to catch.

**Discharge.** Run against a pull request with more than 100 comments, or synthesise one.

### TD-8 — a second human reviewer is untested · open

Every trial had exactly one reviewer. A root comment from a third party — neither the
contributor nor the maintainer — has never been classified.

**Cost.** Unknown behaviour on multi-reviewer projects, which is most large ones.

**Discharge.** One run against a pull request with two or more reviewers.

### TD-9 — recording a responsiveness check has no dedicated verb · open

``ItemState/answeredChecked`` is reached through `contrib ack`, whose vocabulary is about
absorbing an obligation rather than judging one's own reply.

**Cost.** The command reads oddly for the inline case, and its refusal messages carry the
explanation the naming should.

**Discharge.** Either a distinct verb, or a documented statement that one record kind
covers both.

### TD-10 — a stray snapshot appeared once in a work tree · watch

A file named like the state snapshot appeared untracked in a repository root during a
trial; every reconstructable invocation passed `--state-dir`, and it did not reproduce.

**Cost.** A snapshot inside a work tree can reach an upstream-bound branch, which the state
directory's location exists to make impossible.

**Discharge.** Refuse to write a snapshot inside a git work tree unless the path was named
explicitly.

## See Also

- <doc:Design>
- <doc:Roadmap>
