# ``ContributorKit``

What was asked of me that I have not demonstrably absorbed, and is what I ship getting
more laconic?

## Overview

Two questions, for anyone contributing to somebody else's repository. `ContributorKit` is
the library; `contrib` is the command-line tool built on it.

The kit **diffs the world against a local snapshot and reports the delta.** It decides
everything decidable without reading meaning, and hands the meaning question back with
exactly the text needed to answer it.

```swift
let audit = InboundAudit(
    me: nil,
    stripper: try BoilerplateStripper(settings: configuration.inbound),
    supersession: SupersessionDetector(phrases: configuration.inbound.supersessionPhrases),
    informational: try InformationalDetector(patterns: configuration.inbound.informationalPatterns),
    verdicts: VerdictDetector(phrases: configuration.inbound.verdictPhrases),
    botAskers: configuration.inbound.botAskers,
    horizon: try configuration.inbound.horizonDate())

let result = audit.run(threads, against: previousSnapshot)
for item in result.owed {
    print(item.permalink, item.state.rawValue, item.question)
}
```

Every command ends with a ``Provenance`` block it cannot be run without, printing the
count examined whether or not anything was found, and exits non-zero on an anomaly.

## Topics

### Project Direction

- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>

### The inbound audit

- ``InboundAudit``
- ``InboundItem``
- ``ItemState``
- ``Snapshot``
- ``SnapshotStore``
- ``Acknowledgement``
- ``AcknowledgementEligibility``

### Reading a reviewer's markup

- ``BoilerplateStripper``
- ``SupersessionDetector``
- ``InformationalDetector``
- ``VerdictDetector``

### Reaching GitHub

- ``GitHubClient``
- ``GHCommandClient``
- ``PullRequestThreads``
- ``RemoteComment``
- ``Channel``

### Counting lines

- ``Cloc``
- ``RangeWalker``
- ``Counts``
- ``DiffStats``
- ``FileRoleClassifier``

### The spine

- ``CommandRunner``
- ``Configuration``
- ``Provenance``
