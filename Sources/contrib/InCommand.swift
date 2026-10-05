import ArgumentParser
import ContributorKit
import Foundation

struct InCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "in",
        abstract: "What was asked of me that I have not demonstrably absorbed?",
        discussion: """
            Three channels, not one: inline review comments, review BODIES, and issue
            comments. A run that skips review bodies reproduces the bug this exists to
            catch — on pjsip/pjproject#5233 the same ask was raised in review bodies
            three times and missed every time, because only inline comments were being
            read.

            A review body and an issue comment cannot be replied to, so they are
            OBLIGATIONS: listed by default, shown first, and never auto-cleared. They
            leave the list when an acknowledgement is recorded with `contrib ack` —
            recorded, never inferred from proximity in time.

            Output is the delta against a local snapshot. On a first run everything is
            new; the snapshot is what makes the second run useful.

            --json emits { provenance, items }, and each item is exactly:
              id, kind, permalink, state, question, changed, text, resolution
            `changed` is null when nothing moved. **`text` is an OBJECT**, not a string:
            { "ask": <the whole ask>, "reply": <my reply, or null> }. `resolution` is
            null off inline threads, else { "isResolved", "resolvedBy", "byAsker",
            "verdictComment" } — reported, never a discharge: a thread is resolved for
            more reasons than the asker's consent. `byAsker` is derived: resolvedBy
            compared with the root's author; `verdictComment` is the permalink of the
            newest asker reply that opened with a verdict phrase, or null.
            `provenance.reviewers[]` is reviewer coverage on the head commit —
            { "channel", "head", "state", "detail", "url", "reviewLogin",
            "lastReviewOn" }, verbatim — so a never-ran review cannot pass for a
            clean round.

            --open prints the queue instead of one subject — one facts line per
            open pull request of mine (owed, to re-read, unexamined, the reviewer
            line on head) — and writes no snapshot, so --pr N stays the run that consumes
            a pull request's delta. Every per-subject run ends with a `verdict`
            line of the same facts; it is a composition, not a judgment, and the
            exit code does not change with it.
            """
    )

    @Argument(help: "<owner>/<repo>")
    var repository: String

    @Option(name: .long, help: "Pull request or issue number. One of --pr and --open is required.")
    var pr: Int?

    @Flag(name: .long, help: "One facts line per open pull request of mine — owed, to re-read, unexamined, the reviewer line on head. Writes no snapshot (--no-snapshot is implied).")
    var open = false

    @Option(name: .long, help: "My login. Only needed when the API does not report authorship.")
    var me: String?

    @Flag(name: .long, help: "List everything examined, not only what is owed or has moved.")
    var all = false

    @Flag(name: .long, help: "Emit the machine contract — every item's full ask and reply text — instead of the table.")
    var json = false

    @Option(name: .long, help: "Where the snapshot lives (default: XDG state dir).")
    var stateDir: String?

    @Flag(name: .long, help: "Do not write the snapshot. The run then cannot inform the next one.")
    var noSnapshot = false

    func validate() throws {
        guard (pr != nil) != open else {
            throw ValidationError("one of --pr and --open is required")
        }
        if open && (json || all) {
            throw ValidationError(
                "--open prints the queue, one line per pull request; --json and --all "
                    + "are per-subject views — use `contrib in <repo> --pr N`")
        }
    }

    func run() async throws {
        if open {
            try await runOpen()
            return
        }
        guard let pr else {
            // validate() already refuses this shape; the guard is for construction
            // paths that skip it.
            throw ValidationError("one of --pr and --open is required")
        }
        var provenance = Provenance(command: "contrib in \(repository) --pr \(pr)")
        let configuration = try Configuration.load(
            directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if let horizon = configuration.inbound.horizon {
            provenance.note("review horizon \(horizon) — earlier items counted, not listed")
        }

        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        let runner = CountingCommandRunner(SystemCommandRunner())
        let client = GHCommandClient(
            runner: runner, queryPath: try GHCommandClient.bundledQueryPath(),
            openPullRequestsQueryPath: try GHCommandClient.bundledQueryPath(
                "OpenPullRequests"))
        let threads = try await client.threads(repository: repository, number: pr)

        let audit = try InboundAudit(configuration: configuration, me: me)

        // Load, audit and save all happen under the repository lock, and the audit is
        // RE-RUN against the snapshot loaded inside it.
        //
        // Merging a result computed from a pre-fetch snapshot was not enough: a
        // concurrent audit of the same subject could record an acknowledgement in that
        // window, and applying our stale entries on top would erase it. The audit is
        // pure given (threads, previous), so re-running it costs microseconds and makes
        // what is saved a function of the state actually on disk. The network fetch
        // stays outside the lock.
        let subject = Subject.format(repository: repository, number: pr)
        var locked = provenance
        let result = try store.withLock(repository: repository) { () -> InboundAudit.Result in
            let previous = try store.load(repository: repository)
            let result = audit.run(threads, against: previous)

            locked.subprocessCalls = runner.count
            InboundReporting.record(
                result, threads, previous: previous,
                reviewerChannels: configuration.inbound.reviewerChannels, into: &locked)
            locked.finish()

            // An anomalous run must not become the next run's baseline: a truncated
            // fetch that saved its partial pages would have the retry treat them as
            // established history.
            if noSnapshot {
                locked.note("--no-snapshot: this run cannot inform the next one")
            } else if locked.hasAnomaly {
                locked.note("snapshot NOT written — this run is anomalous; fix and re-run")
            } else {
                var merged = previous ?? Snapshot(repository: repository)
                merged.merge(result, forSubject: subject)
                try store.save(merged)
                locked.note("snapshot written to \(store.url(for: repository).path)")
            }
            return result
        }
        provenance = locked

        let options = InboundReporting.Options(all: all)
        if json {
            print(
                String(
                    decoding: try InboundReporting.json(
                        result, provenance: provenance, options: options), as: UTF8.self))
        } else {
            print(
                InboundReporting.terminal(
                    threads, result, options: options,
                    reviewerChannels: configuration.inbound.reviewerChannels))
        }

        try Self.emit(provenance)
    }

    /// The queue (issue #12): one facts line per open pull request of mine, over a
    /// full audit per subject — **and no snapshot write**. The queue shows no
    /// items, so it must not consume an item's `changed` signal: `--pr N` stays
    /// the run that advances the snapshot.
    private func runOpen() async throws {
        var provenance = Provenance(command: "contrib in \(repository) --open")
        let configuration = try Configuration.load(
            directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if let horizon = configuration.inbound.horizon {
            provenance.note("review horizon \(horizon) — earlier items counted, not listed")
        }

        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        let runner = CountingCommandRunner(SystemCommandRunner())
        let client = GHCommandClient(
            runner: runner, queryPath: try GHCommandClient.bundledQueryPath(),
            openPullRequestsQueryPath: try GHCommandClient.bundledQueryPath(
                "OpenPullRequests"))
        let list = try await client.openPullRequests(repository: repository)
        provenance.examined("open pull requests", list.totalCount)
        provenance.examined("mine", list.mine.count)
        provenance.examined("queue pages fetched", list.pagesFetched)
        if list.truncated {
            provenance.anomaly(
                "truncatedFetch",
                "pullRequests still had a next page — the queue is incomplete")
        }
        if list.authorshipUnknown > 0 {
            provenance.anomaly(
                "authorshipUnknown",
                "\(list.authorshipUnknown) open pull request(s) carried no "
                    + "viewerDidAuthor — the queue may be short")
        }

        // Every fetch runs before the lock: network outside, the single snapshot
        // read inside it — every row compares against the same previous version.
        let audit = try InboundAudit(configuration: configuration, me: me)
        var subjects: [PullRequestThreads] = []
        for pr in list.mine.sorted(by: { $0.number < $1.number }) {
            subjects.append(
                try await client.threads(repository: repository, number: pr.number))
        }
        // With no snapshot on disk there is nothing to synchronize with — and the
        // lock file itself must not be created, so a read-only queue leaves a
        // fresh state dir untouched. A writer landing mid-sweep just means this
        // run is the baseline it reports.
        let rows: [InboundReporting.SubjectSummary]
        if store.hasSnapshot(repository: repository) {
            rows = try store.withLock(repository: repository) {
                let previous = try store.load(repository: repository)
                return InboundReporting.queueRows(
                    subjects, drafts: Set(list.mine.filter(\.isDraft).map(\.number)),
                    previous: previous, audit: audit,
                    reviewerChannels: configuration.inbound.reviewerChannels,
                    into: &provenance)
            }
        } else {
            rows = InboundReporting.queueRows(
                subjects, drafts: Set(list.mine.filter(\.isDraft).map(\.number)),
                previous: nil, audit: audit,
                reviewerChannels: configuration.inbound.reviewerChannels,
                into: &provenance)
        }

        provenance.note("as of \(GitHubTime.string(Date()))")
        provenance.note(
            "--open writes no snapshot — `contrib in \(repository) --pr N` is the run "
                + "that consumes a pull request's delta")

        print(InboundReporting.queue(repository: repository, list: list, rows: rows))
        provenance.subprocessCalls = runner.count
        try Self.emit(provenance)
    }
}
