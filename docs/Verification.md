# What was verified, and how

The discipline this kit is held to says: **state coverage as a table with an explicit
not-verified list, never as a sentence.** Applied here to itself.

Verified on 2026-09-13, macOS 26.0, Swift 6.3.3, `cloc` 2.06, `gh` authenticated as
`laconicman`.

## Executed

| Claim | How | Result |
|---|---|---|
| Package builds clean, debug and release | `swift build`, `swift build -c release` | no errors, no warnings |
| 47 tests pass, entirely offline | `swift test` | 47/47 in 5 suites |
| `contrib loc` reproduces the captured branch total | real run against `pjproject` at `2ba80f1ed..fd5394aed` | added 107/109/21 · removed 82/0/0 · modified 35/8/0 · net +25/+109/+21 — identical to `manifest.json` |
| Comment-to-code ratio | same run | 4.36, matching the manifest |
| `--ignore-whitespace` churn correction | same run | modified code 35 → 20, net unchanged at +25 |
| `--by-role` aggregation | same run | `source: +25/+109/+21`, matching the manifest's `byRole` |
| All 13 cloc fixtures decode exactly as captured | `LocTests` | every section of every document |
| Role classifier agrees with the Python one | `RoleTests` | all 6 fixture paths |
| `contrib in` against a live PR | `contrib in pjsip/pjproject --pr 5233` | 24 inline threads, 34 review bodies, 5 issue comments, 8 owed |
| Authorship filter, live | same run | 24 of 34 review bodies are ours and excluded |
| Empty review bodies, live | `contrib in pjsip/pjproject --pr 5234` | 12 of 22 review bodies are `no-prose` |
| Three-channel coverage, live | same run | 1 owed item, and it is on the issue-comment channel |
| The differ | second `contrib in` run on #5233 | no `changed` lines; only the 8 still-owed items shown |
| `contrib ack`, three forms | real sha, `none:` with reason, malformed sha | verified / verified / refused with exit 1 |
| An acknowledgement clears the item | `contrib in` after two acks | owed 8 → 6 |
| `--json` key set | live run piped through a key check | exactly `id kind permalink state question changed text`, `text` exactly `ask reply` |
| Non-zero exit on anomaly | synthetic repo, config with no catch-all role | `ANOMALY unclassifiedPaths`, exit 2 |
| Non-zero exit on a failed tool | `--cloc /bin/false` | exit 1 |
| Nothing is written outbound | `find` over the state dir after a run | one file: the snapshot |
| GraphQL `Int!` variable passing (`-F` not `-f`) | every live run above | no 422 |
| `reviews()` returns bodies for comment-only reviews | #5234 live | yes — 12 with empty bodies |

## From a live trial, 2026-09-13

An independent session ran `contrib` as the contributor through a real review round on
`laconicman/telegram-kb#1`, with Devin Review as maintainer, and reported back. What that
established, beyond the author's own runs:

| Claim | Evidence |
|---|---|
| The boilerplate stripper handles **real** Devin badge markup | 9 bodies `no-prose`, 4 independently confirmed empty by hand; no misclassification either way |
| Prose survives stripping | `**Devin Review** found 6 new potential issues.` came back `obligation-open` |
| Supersession fires through formatting | 3 real retractions matched, inside a GitHub `[!NOTE]` admonition **and** a blockquote **and** bold |
| A real edited review body | Devin edited a round-1 body to prepend the retraction; classified correctly post-edit |
| Reviewer resolution → `answered-confirmed` | 9 threads, each carrying a real `✅ Resolved:` reply |
| …and it **discriminated** | of 6 threads, Devin confirmed 5; the 6th stayed `answered-claimed` — the exact distinction the state exists for |
| Authorship filter, exact | 10 of 23 bodies ours, then 16 of 29 after 6 replies — the delta is exactly the replies posted |
| It found a round that was missed | A hand-rolled three-channel fetch the day before reported zero new comments; `contrib in` listed 7 owed, of which 3 were regressions introduced by the previous round's fixes |
| False positives | zero, across 7 owed items and 16 findings over three rounds |

**Three defects it found, all now fixed** — see the section below.

## Not verified here — and why

| Not verified | Why |
|---|---|
| **A PR with more than one reviewer.** | Both ground-truth PRs were reviewed only by `sauwming`; **both live trials also had exactly one reviewer** (the Devin bot), every other participant being the contributor. Three independent attempts, still untested. A root comment from a third party is the gap. |
| **Supersession against a real retraction.** | The phrase list is matched by unit test against a constructed body. No captured GitHub review body in this workspace contains a retraction. |
| **`answered-confirmed` against real data.** | No fixture and neither live PR contains a thread where the asker replied after our reply. Tested against a constructed thread only. |
| **Pagination past one page.** | Every live subject fitted in one page of 100 — the largest across both trials carried 88 items on one page. The cursor loop, the `hasNextPage` ceiling and the `truncatedFetch` anomaly are exercised by unit test and by construction, never by a real oversized PR. |
| ~~`lastEditedAt` on a real edited comment~~ | **Now verified** — six live instances in the second trial, plus an edited *review body* in the first. Moved to the executed table. |
| ~~Issues, as opposed to pull requests~~ | **Now verified** — a third session ran `contrib in` over five authored issues on `anthropics/claude-code`; the query serves both through `issueOrPullRequest` and needed no change. It found a maintainer's conditional close that a hand-applied reading of the same model had missed. |
| **`commenter:` missing an inline-only PR.** | Requires `Candidates.graphql` and the enumeration union, which belong to `contrib out`. Not built. |
| **Whether a fork issue backlinks onto an upstream thread.** | A write to a public repository. Not attempted. |
| **Any platform other than macOS.** | `platforms: [.macOS(.v14)]`; CryptoKit and the XDG state path are the only platform-specific pieces. |

## From a second live trial, 2026-09-13 (Devin Desktop)

A second session ran `contrib` as the contributor across 17 PRs in two repositories
(`laconicman/YDelivery` ×11, `laconicman/YandexDeliveryExpress` ×6), processing a real
review day. What it established:

| Claim | Evidence |
|---|---|
| **`edited-after-my-answer` — a previously untested row** | Fired on **six live instances** across four PRs. On two the edit genuinely changed the ask and produced code fixes; on two it did not and was said so once. The state's question was the right fork every time |
| It found work a careful manual pass had missed — again | A hand audit with raw `gh api` on 09-09 believed the repo current; the first sweep found 18 action-state items across nine "done" PRs, including a same-day edit at 12:02 that would have shipped past |
| Transitions are load-bearing | `6 × open-ask → answered-claimed`, `1 × edited-after-my-answer → answered-claimed`, `1 × obligation-open → obligation-acknowledged` — reported as "the most load-bearing line in the output" |
| Supersession, authorship, `no-prose` | Confirmed incidentally at volume: 3 retractions, `23 of those review bodies are mine` on one PR and 24/50 on another, 18 empty bodies absorbed |
| Day's outcome | 21 thread replies, 17 recorded acks, 3 code fixes, 2 docs fixes. **`owed 0` on every PR except one deliberate archaeology pile** |

**Two defects and one wart it found, all now fixed** — see below. One gap was left open
by decision rather than by oversight: see `Decisions.md` on era acknowledgement.

## Three defects the live trial found

1. **The differ could not see state transitions.** The run straight after answering six
   threads and acknowledging one obligation said *"nothing moved since the last run"* —
   true of what the snapshot tracked, false of what a contributor tracks, because the
   snapshot stored no state at all. It now stores `state` per entry, reports transitions
   in `changed` (`open-ask → answered-claimed`), counts them in the provenance block, and
   the empty case now names what was compared instead of asserting silence.

   This also answers the report's separate complaint that `answered-claimed` vanishes
   after the cold start: the run in which a thread *becomes* `answered-claimed` is
   exactly the run where *"is my reply actually responsive?"* is worth asking, and it now
   surfaces there.

2. **`--json` sliced the ask at 400 characters.** Every round-3 ask ended mid-sentence and
   the session had to re-fetch bodies with `gh api` — the re-enumeration the machine
   contract exists to eliminate. The ask is now carried whole; only terminal display
   truncates. Measured after the fix on the same PR: asks of 2248, 2026, 892 and 876
   characters, all previously cut.

3. **`contrib ack` on an inline thread was a silent no-op.** It reported success, wrote a
   field nothing reads, and left `owed` unchanged — which is the single failure class this
   tool refuses everywhere else. It is now refused with an explanation of why an inline
   thread does not need one. Found by testing the report's own suggested workflow rather
   than by reading the code.

The provenance block also now states body completeness **positively** (`bodies: full text,
not excerpts`). The trial could not tell whether the `excerptBodies` check had passed or
had failed to run, which is the same absence-of-evidence shape as the rest of this file.

## Three more, from the second trial

4. **The reviewer's own `kind` marker was ignored.** Devin Review opens every inline body
   with `<!-- devin-review-comment {… "kind": "bug" | "analysis"} -->`, and `analysis`
   notes are 📝 Info receipts, not requests. They classified `open-ask` and demanded
   answers; a session answered three with one-liners to reach zero.

   Reading a kind the *asker* declared is not the CLI deciding a meaning question — it is
   the same move supersession makes. New `informational` state, driven by configurable
   patterns rather than hardcoded, shipped with the Devin markers and a bot's fixed
   announcement phrase. **Verified on `laconicman/telegram-kb#1`: 9 of 9 items reclassified
   were reviewer-declared `analysis`; no `bug` was touched.** `owed` 5 → 3.

   Measured first: across two repositories the only kinds Devin emits are `analysis` (13)
   and `bug` (11).

5. **Excerpts led with an invisible HTML comment.** An inline body opens with the marker,
   so the visible slice showed `<!-- devin-review-comment {"id": "BUG_pr-review-job…` and
   pushed the finding title out of view. A trial session routed **every** triage through
   `--json` because of it. Ask text is now the stripped prose on all three channels —
   `🔴 **Interrupted sync skips new pages** …` leads.

6. **Paired markers were being destroyed before they could be used.** Stripping `<!--…-->`
   generically removed Devin's `badge-begin` / `badge-end` delimiters first and left the
   wrapped `<a href=…>` / `</a>` behind, trailing every excerpt. Paired blocks are now
   stripped first. Not a classification bug — `no-prose` was always reached by genuinely
   empty bodies — but it was the noise in exactly the place the complaint was about.

**And one non-defect worth recording:** the trial's `--json` parser broke because `text`
is an object, not a string. The shape was right and undocumented; `--help` now states it.

## The first true miss — a false negative this kit introduced

**An `informational` state I added hid two real asks for about ten runs**, and a human
found them in the GitHub UI instead. This is the failure class the whole tool exists to
prevent, and it is worth recording in full because the mistake was in the *verification*,
not only the code.

The premise was that Devin Review's declared `"kind": "analysis"` marks a receipt rather
than a request. Measured across `laconicman/YandexDeliveryExpress` and
`laconicman/telegram-kb`: 13 analysis comments, every one a 📝 Info verification note.
That looked conclusive. On `laconicman/YDelivery#28` the same kind carries 🔍 findings —
*"Redirect refusal loses its reason"*, *"Dismissal leaves other work running"* — both
genuine and both fix-producing.

**Devin uses one kind for two purposes.** The marker cannot carry the decision.

The verification that let it through said: *"9 of 9 items reclassified were
reviewer-declared analysis; no bug was touched."* That is true, and it confirms the regex
matched what it claimed to match. **It does not test the premise.** Checking that a
mechanism works is not checking that the rule it implements is right — the distinction
the field report's rule 5 draws between *ran and passed* and *tested the right thing*, one
level up from where that rule usually bites.

Withdrawn. What remains:

- `informational` applies **only to review bodies and issue comments** — channels with no
  reply relation. An inline thread's lifecycle is decidable from ids alone, so suppressing
  one on a marker can only ever hide a real ask. This also removes the stickiness the
  report found: the state sat outside the answered lifecycle, surviving replies that
  should have moved it to `answered-claimed`.
- The only shipped pattern is a bot's fixed announcement phrase.
- The state is now **in the skill's decision table**, with its question and its response.
  It was not, which is the deeper defect the report named: the table says it is the whole
  contract, and an item outside it has no defined response.

Regression test built from the two real bodies that were hidden.

**The same failure mode was recorded independently the same week**, in a sibling tool in
this workspace: a connector's 400 errors were blamed on a stale session because fresh
processes worked, when every "fresh process" success had also changed the input or the
time; the real cause was an unindexed repository. That report kept its post-mortem on the
grounds that *"the failure mode (a mechanism story outrunning its evidence) is more
reusable than the bug"* — and then it recurred here, in a different tool, from a different
session, within a week. It is now rule 7 in the skill.

## The review horizon, and what it deliberately is not

A second trial hit 44 never-answered threads on a June-era PR whose code a rewrite had
deleted, and proposed an `ack --era` that would write one reason across all of them.

Rejected in favour of `inbound.horizon` in `.contributorkit.yml`: items raised before it
are **counted and not listed**. Nothing is cleared, nothing is claimed absorbed, and the
declaration lives in a versioned file a human reads rather than as dozens of fabricated
acknowledgements in a state directory.

Measured on that PR: `owed` 53 → 28, with `37 item(s) before the review horizon — not
listed (25 of them would otherwise be owed)`. The count of what is being held back, and
how much of it is real, is printed every run.

An item beyond the horizon still surfaces **the moment anything about it moves**. A
reviewer editing an old comment today is today's activity, and a horizon that swallowed
that would be the same wrong-set failure in a new place.

## Six more defects, from two further trials

7. **The baseline was announced per repository, not per item.** Sweeping five issues in
   one repository, only the first printed `no snapshot … this run is the baseline` while
   each of the others was also its own first run. Now reported after the audit, where the
   per-item facts are known: `N known for this repository, age Xh; M new this run`.
8. **The unverified-acknowledgement count had the same scope leak** — it counted
   repository-wide, so an unverified ack on one issue was reported against another. Now
   scoped to what the run examined.
9. **A `comment:` pointer at my own comment could never verify.** The audit skips my
   comments before recording anything, so the one comment worth pointing an
   acknowledgement at was the one kind that always recorded `UNVERIFIED` — with a note
   that repeated itself and named a fetch `ack` never makes. Authored ids are now
   recorded as authored; verified live, 34 of them on one PR.
10. **Setting one `inbound` key demanded restating the whole block**, failing with a
    decoding error naming an unrelated key. `inbound:` now merges per sub-key. The
    whole-key rule stays for `roles:`, where the *order* is the contract.
11. **`owed 0` carried no expiry.** Acting on a PR causes the next review wave, so a zero
    was twice true at the fetch and false twenty minutes later. The provenance block now
    stamps `as of <time>`, and the skill carries the workflow rule: the audit that counts
    is the one run after the reviewer's re-run, not after your push.
12. **`contrib in` works unchanged on issues** — the first run against issues rather than
    pull requests, five of them. Moved out of the not-verified list.

## An upgrade crash, and a correction that corrected the wrong thing

13. **Upgrading broke every existing state dir.** `authored` was added to `Snapshot` as a
    non-optional property with a default. Synthesized `Decodable` ignores property
    defaults, so a snapshot written by the previous build threw `keyNotFound 'authored'` —
    before the schema-version guard could produce its own message, so it read like a
    corrupt file. The only workaround was a new `--state-dir`, discarding the round history
    the snapshot exists to keep. Reported by a trial session on its real state dir.

    `Snapshot` now decodes by hand, with every post-release field `decodeIfPresent`.
    `SnapshotCompatibilityTests` holds one fixture per historical shape — before per-entry
    `state`, and before `authored` — and all three of its tests failed with the exact
    reported error before the fix. Verified against a **copy** of the file that crashed:
    it loads as a 56-hour-old previous round and reports five real transitions.

    Adding a field to `Snapshot` now means adding a fixture, not only a property.

**The trial session then retracted a claim that was true.** Its first report said the
snapshot stored no `state` values; its later correction said the preserved file showed a
`state` on every entry, and struck the original through. The preserved file was not
written by the build that session trialled. It was written by the author of this kit,
running a freshly installed build against *that session's* state dir to check a fix —
**nine seconds after committing `66576ab`**, the commit that added per-entry `state`, and
about half an hour after the report was filed. The file's own `updatedAt`
(`2026-09-13T11:49:50Z`) and the commit time (`11:49:41Z`) pin it; `Snapshot.Entry` at the
trialled build, `2709164`, has no `state` field, so nothing that build wrote could carry one.

The original claim was correct, the gap was real, and `66576ab` is what closed it — which
answers the question the correction left explicitly open. It is rule 7 a third time: the
file differed in a variable nobody had isolated, and the variable was a second writer.

The lesson for this document's own practice: **verify against a copy of another session's
state, never the state itself.** The trial brief told every session to use its own state
dir so they could not clobber each other, and the one that clobbered one was the author.

## A sharp edge, found while preparing a handoff

**The binary is not portable on its own, and it hides that fact.** SwiftPM's generated
`Bundle.module` accessor falls back to the *absolute path of the build directory*, so a
binary copied alone to `/usr/local/bin` keeps working — until someone runs
`swift package clean`, at which point it dies with an internal `fatalError` naming two
paths and no remedy.

The README previously gave `cp .build/release/contrib /usr/local/bin/` as the install
step, which produces exactly that latent trap. Corrected: `scripts/install.sh` copies the
binary and the bundle together, and was verified by installing to a prefix and then
removing the bundle from the build tree — the installed copy still runs.

The deeper fix, not taken: embed the three resources as generated Swift constants and
drop `Bundle.module` entirely, which would make the binary genuinely single-file. Left
for when distribution matters; the drift-test mechanism to keep the generated copies
honest already exists twice in this package.

## A note on the fixtures

The thread fixtures store **no full message bodies** — 120 characters per comment, 160
per review body. That is right for id arithmetic and it is why the pair is ~19 KB
rather than 254 KB, but it means the boilerplate stripper and the supersession detector
see a fragment when run against them. `contrib in` raises an `excerptBodies` anomaly
whenever bodies are excerpts, so this reads as a stated limit rather than a silent one.

The live GraphQL path fetches whole bodies and does not have this limitation.
