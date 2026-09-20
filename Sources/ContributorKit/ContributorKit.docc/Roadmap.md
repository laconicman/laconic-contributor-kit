# Roadmap

What is built, what is next, and what is deliberately not being built.

## Overview

Priority-ordered. Rationale lives in <doc:Design>; costs and discharges in <doc:TechDebt>.

## Now — shipped and used in anger

- **`contrib in`** — the three-channel audit, obligations, transitions, the re-read list,
  and the review horizon. Run across three independent trials on `pjsip/pjproject`,
  `laconicman/telegram-kb`, `laconicman/YDelivery`, `laconicman/YandexDeliveryExpress` and
  `anthropics/claude-code`, on both pull requests and issues.
- **`contrib ack`** — recorded acknowledgement by comment, commit, PR body or an explicit
  no-action with a reason.
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
