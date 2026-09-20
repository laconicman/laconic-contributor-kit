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
              id, kind, permalink, state, question, changed, text
            `changed` is null when nothing moved. **`text` is an OBJECT**, not a string:
            { "ask": <the whole ask>, "reply": <my reply, or null> }.
            """
    )

    @Argument(help: "<owner>/<repo>")
    var repository: String

    @Option(name: .long, help: "Pull request or issue number.")
    var pr: Int

    @Option(name: .long, help: "My login. Only needed when the API does not report authorship.")
    var me: String?

    @Flag(name: .long, help: "List everything examined, not only what is owed or has moved.")
    var all = false

    @Flag(name: .long, help: "Emit the machine contract instead of the table.")
    var json = false

    @Option(name: .long, help: "Where the snapshot lives (default: XDG state dir).")
    var stateDir: String?

    @Flag(name: .long, help: "Do not write the snapshot. The run then cannot inform the next one.")
    var noSnapshot = false

    func run() async throws {
        var provenance = Provenance(command: "contrib in \(repository) --pr \(pr)")
        let configuration = try Configuration.load(
            directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if let horizon = configuration.inbound.horizon {
            provenance.note("review horizon \(horizon) — earlier items counted, not listed")
        }

        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        let runner = CountingCommandRunner(SystemCommandRunner())
        let client = GHCommandClient(
            runner: runner, queryPath: try GHCommandClient.bundledQueryPath())
        let threads = try await client.threads(repository: repository, number: pr)

        let audit = InboundAudit(
            me: me,
            stripper: try BoilerplateStripper(settings: configuration.inbound),
            supersession: SupersessionDetector(phrases: configuration.inbound.supersessionPhrases),
            informational: try InformationalDetector(
                patterns: configuration.inbound.informationalPatterns),
            horizon: try configuration.inbound.horizonDate())

        // Load, audit and save all happen under the repository lock, and the audit is
        // RE-RUN against the snapshot loaded inside it.
        //
        // Merging a result computed from a pre-fetch snapshot was not enough: a
        // concurrent audit of the same subject could record an acknowledgement in that
        // window, and applying our stale entries on top would erase it. The audit is
        // pure given (threads, previous), so re-running it costs microseconds and makes
        // what is saved a function of the state actually on disk. The network fetch
        // stays outside the lock.
        let subject = "\(repository)#\(pr)"
        var locked = provenance
        let result = try store.withLock(repository: repository) { () -> InboundAudit.Result in
            let previous = try store.load(repository: repository)
            let result = audit.run(threads, against: previous)

            locked.subprocessCalls = runner.count
            InboundReporting.record(result, threads, previous: previous, into: &locked)
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
                for (id, entry) in result.updatedSnapshot.entries where entry.subject == subject {
                    merged.entries[id] = entry
                }
                merged.authored.formUnion(result.updatedSnapshot.authored)
                merged.updatedAt = Date()
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
            print(InboundReporting.terminal(threads, result, options: options))
        }

        try Self.emit(provenance)
    }
}
