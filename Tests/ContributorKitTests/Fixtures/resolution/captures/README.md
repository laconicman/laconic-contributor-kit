# Issue #7 captures

The raw evidence that issue #7 and PR #8 were built on, kept so that the figures in
`docs/Verification.md` can be derived again offline. No test reads these files. The
threads the tests use are cut verbatim from them into `../telegram-kb-pr-*.json`.

| File | What it is |
|---|---|
| `pr-N.threads.graphql.json` | Every `reviewThreads` page for `laconicman/telegram-kb#N`, from the oracle's own GraphQL query (`scripts/resolution-crosscheck.py`), including `isResolved` and `resolvedBy` |
| `pr-N.contrib.json` | `contrib in laconicman/telegram-kb --pr N --all --json --no-snapshot` from a build before PR #8. The build that was installed then; its exact commit was not recorded |
| `crosscheck-2026-09-26-before.txt` | The oracle's report on those captures, the one issue #7 quotes |
| `crosscheck-2026-09-27-after.txt` | The oracle, re-run live against the consolidated PR #8 build |

Captured 2026-09-26 at 18:01–18:02 UTC. Each `contrib.json` carries its own `as of` stamp.
The data is public review traffic on a public repository.

The live threads have moved on, or will: the case-4 thread (`discussion_r4024609952`) is due
to be answered and resolved. Do not refresh these files from a later fetch. A new capture
is new evidence, and belongs in a new folder with its own date.
