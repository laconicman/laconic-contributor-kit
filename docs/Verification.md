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
| **A PR with more than one reviewer.** | Both ground-truth PRs were reviewed only by `sauwming`. A root comment from a third party — someone who is neither us nor the maintainer — is untested in both the fixtures and the live runs. |
| **Supersession against a real retraction.** | The phrase list is matched by unit test against a constructed body. No captured GitHub review body in this workspace contains a retraction. |
| **`answered-confirmed` against real data.** | No fixture and neither live PR contains a thread where the asker replied after our reply. Tested against a constructed thread only. |
| **Pagination past one page.** | Every live subject fitted in one page of 100. The cursor loop, the `hasNextPage` ceiling and the `truncatedFetch` anomaly are exercised by unit test and by construction, not by a real oversized PR. |
| **`lastEditedAt` on a real edited comment.** | Edit detection is tested through the body hash, which is the API-independent backstop. No live comment in these runs had been edited. |
| **Issues, as opposed to pull requests.** | The query serves both through `issueOrPullRequest`, and the decoder treats every connection as optional, but no live run targeted an issue. |
| **`commenter:` missing an inline-only PR.** | Requires `Candidates.graphql` and the enumeration union, which belong to `contrib out`. Not built. |
| **Whether a fork issue backlinks onto an upstream thread.** | A write to a public repository. Not attempted. |
| **Any platform other than macOS.** | `platforms: [.macOS(.v14)]`; CryptoKit and the XDG state path are the only platform-specific pieces. |

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
