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

## A note on the fixtures

The thread fixtures store **no full message bodies** — 120 characters per comment, 160
per review body. That is right for id arithmetic and it is why the pair is ~19 KB
rather than 254 KB, but it means the boilerplate stripper and the supersession detector
see a fragment when run against them. `contrib in` raises an `excerptBodies` anomaly
whenever bodies are excerpts, so this reads as a stated limit rather than a silent one.

The live GraphQL path fetches whole bodies and does not have this limitation.
