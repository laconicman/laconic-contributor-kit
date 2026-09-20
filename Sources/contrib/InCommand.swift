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

        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        let previous = try store.load(repository: repository)
        if let horizon = configuration.inbound.horizon {
            provenance.note("review horizon \(horizon) — earlier items counted, not listed")
        }


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
        let result = audit.run(threads, against: previous)

        provenance.subprocessCalls = runner.count
        InboundReporting.record(result, threads, previous: previous, into: &provenance)
        let options = InboundReporting.Options(all: all)
        if json {
            var forJSON = provenance
            forJSON.finish()
            print(
                String(
                    decoding: try InboundReporting.json(
                        result, provenance: forJSON, options: options), as: UTF8.self))
        } else {
            print(InboundReporting.terminal(threads, result, options: options))
        }

        // An anomalous run must not become the next run's baseline. A truncated fetch
        // that saved its partial pages would have the retry treat them as established
        // history, and the items it never saw would look like nothing had changed —
        // the differ silently built on a fetch it had already declared untrustworthy.
        provenance.finish()
        if noSnapshot {
            provenance.note("--no-snapshot: this run cannot inform the next one")
        } else if provenance.hasAnomaly {
            provenance.note("snapshot NOT written — this run is anomalous; fix and re-run")
        } else {
            // Locked read-modify-write, and only our own subject's entries are applied.
            // The snapshot holds every PR and issue in the repository, so a plain save
            // of `updatedSnapshot` would drop whatever another audit wrote between our
            // load and our save. The lock is held for the file transaction only, never
            // across the network fetch.
            let subject = "\(repository)#\(pr)"
            try store.withLock(repository: repository) {
                var merged =
                    try store.load(repository: repository)
                    ?? Snapshot(repository: repository)
                for (id, entry) in result.updatedSnapshot.entries where entry.subject == subject {
                    merged.entries[id] = entry
                }
                merged.authored.formUnion(result.updatedSnapshot.authored)
                merged.updatedAt = Date()
                try store.save(merged)
            }
            provenance.note("snapshot written to \(store.url(for: repository).path)")
        }

        try Self.emit(provenance)
    }
}
