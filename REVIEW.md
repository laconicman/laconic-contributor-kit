# Review Guidelines

This kit audits review rounds. Every rule below came from a defect that shipped in it, or
from a failure on a real upstream pull request. Generic Swift advice is not wanted here —
`swift-format` and the test suite already cover that ground.

## Critical Areas

- Require `Sources/ContributorKit/Inbound/InboundAudit.swift` to keep covering all three
  channels: inline threads, review bodies, issue comments. Dropping review bodies
  reproduces the bug this kit was built after.
- Flag any call site passing a `Channel.inlineThread` comment to `InformationalDetector`.
  Suppressing an inline thread on a marker can only hide a real ask; it did, for ten runs.
- Reject any `informationalPatterns` entry in
  `Sources/ContributorKit/Resources/inbound.default.yml` that is not a fixed, unambiguous
  phrase. A reviewer's category label is not a statement of intent.
- Require every new stored property on `Snapshot`, `Snapshot.Entry` or `Acknowledgement`
  to decode when absent: `Optional`, or `decodeIfPresent` in `Snapshot.init(from:)`. A
  non-optional property with a default breaks every existing state directory on upgrade.
- Require a matching fixture in `Tests/ContributorKitTests/Fixtures/snapshots/` whenever
  the snapshot schema gains a field.
- Require a new `Sources/ContributorKit/Inbound/ItemState.swift` case to add a row to
  `plugin/skills/contributions/SKILL.md`. A state outside that table has no defined
  response. Reject any PR that disables the test enforcing it.

## Conventions

- Flag any key added to `InboundItem.encode(to:)` beyond the eight in the contract, unless
  the PR also updates `Sources/ContributorKit/ContributorKit.docc/Design.md` and
  `ContractTests.jsonContractIsExact`.
- `Counts` must never gain a `total`, and no code may sum `code + comment + blank`. LOC is
  three columns; one summed figure is what this half exists not to produce.
- Require every `Sources/contrib/*Command.swift` return path to end at
  `Self.emit(provenance)`.
- Require each to record at least one `provenance.examined(…)`: a command that examines
  nothing cannot tell "found nothing" from "did not run".
- Figures in tests come from `Tests/ContributorKitTests/Fixtures/manifest.json` or another captured fixture — never
  retyped into Swift. Flag a literal expected count with no fixture behind it.
- Role globs live in `Sources/ContributorKit/Resources/contributorkit.default.yml`, which
  is byte-identical to the fixtures' copy. Flag any role rule transcribed into Swift.

## Anti-patterns to Flag

- Flag any merge of stdout into stderr, or exit 0 with empty output treated as success.
  `cloc` and `gh` both exit 0 on an empty result; require `runExpectingOutput`.
- Require evidence of execution — an exit status, a count, a non-empty `CommandOutput` —
  before any assertion in `Tests/ContributorKitTests/**` whose passing condition is an
  absence (zero hits, no output, no diff).
- Flag a test in `Tests/ContributorKitTests/**` whose assertions restate the
  implementation. "9 of 9 items carried the marker" confirms a regex, not the premise that
  the marker means what the author assumed.
- Reject any inference that an obligation was discharged from timing, proximity,
  `isResolved`, or a closed state. Only a recorded `Acknowledgement` or the asker's own
  reply clears one.
- Flag any code path that stores state no reader consults. `AcknowledgementEligibility`
  exists because `ack` on an inline thread once reported success and changed nothing.
- Reject `Bundle.module` used outside `Sources/ContributorKit/Support/Configuration.swift` and
  `Sources/ContributorKit/GitHub/GHCommandClient.swift`.
  Its accessor calls `fatalError` and falls back to an absolute build path.

## Security

- No credential is ever read, stored, or invented. `gh` holds the token; flag any code that
  reads `GITHUB_TOKEN`, shells `gh auth token`, or writes a token anywhere.
- Nothing leaves the workspace without an explicit flag — not a LOC figure, not a drafted
  reply, not a register row. Flag any new network write, or any `gh` invocation that is not
  a read.
- Snapshots must stay outside the work tree (see `SnapshotStore`). Flag a default path that
  could land inside a repository and reach an upstream-bound branch.

## Performance

- `contrib loc --range` must never touch the network; it has to stay usable offline and on
  a repository with no GitHub remote. Flag any `gh` call reachable from `LocCommand`.
- Both pipes in `SystemCommandRunner` must be drained concurrently. Reading them serially
  deadlocks against `waitUntilExit` once output exceeds the 64 KB pipe buffer, which
  `cloc --by-file` does on a large range.

## Ignore

- Skip `.build/`, `.swiftpm/` and `Package.resolved` entirely.
- Skip `Tests/ContributorKitTests/Fixtures/**` — captured ground truth, regenerated rather
  than authored. Comment only if one appears hand-edited.
- Skip `Sources/ContributorKit/Resources/*.graphql` — validated against GitHub's published
  schema by an external validator, not by review.
- `scripts/loc-heuristic.awk` — kept as documentation of a superseded method, not a code
  path. Skip it.
