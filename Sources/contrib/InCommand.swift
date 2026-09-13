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
        if let previous {
            provenance.note(
                "snapshot age \(Int(previous.age / 3600))h, \(previous.entries.count) known item(s)")
        } else {
            // Said out loud rather than treated as "nothing changed": a first run has no
            // baseline, and on a second round a run without prior state is actively
            // misleading rather than merely weaker.
            provenance.note("no snapshot for \(repository) — this run is the baseline")
        }

        let runner = CountingCommandRunner(SystemCommandRunner())
        let client = GHCommandClient(
            runner: runner, queryPath: try GHCommandClient.bundledQueryPath())
        let threads = try await client.threads(repository: repository, number: pr)

        let audit = InboundAudit(
            me: me,
            stripper: try BoilerplateStripper(settings: configuration.inbound),
            supersession: SupersessionDetector(phrases: configuration.inbound.supersessionPhrases))
        let result = audit.run(threads, against: previous)

        provenance.subprocessCalls = runner.count
        InboundReporting.record(result, threads, into: &provenance)
        if let previous, result.updatedSnapshot.entries.count < previous.entries.count {
            provenance.anomaly(
                "itemsVanished",
                "\(previous.entries.count - result.updatedSnapshot.entries.count) item(s) "
                    + "in the snapshot were not in this fetch")
        }

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

        if !noSnapshot {
            try store.save(result.updatedSnapshot)
            provenance.note("snapshot written to \(store.url(for: repository).path)")
        }

        try Self.emit(provenance)
    }
}
