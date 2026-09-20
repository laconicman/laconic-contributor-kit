import ArgumentParser
import ContributorKit
import Foundation

struct AckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ack",
        abstract: "Record where an obligation was absorbed.",
        discussion: """
            A review body and an issue comment cannot be replied to, so nothing about
            them says "answered" on its own. They leave the worklist only when an
            acknowledgement is RECORDED — a pointer to where the content was absorbed:

              --with comment:<id>        a comment of mine, by permalink or fragment
              --with commit:<sha>        a commit that carries the change
              --with pr-body             the PR description was edited
              --with none:"<reason>"     no action needed, and why

            Shape is always checked. Existence is checked only where it is free — an id
            already in this run's fetch, a sha the local repository resolves — and the
            result is recorded per acknowledgement, so an unverified one reads as
            unverified rather than as fine.

            The record is keyed by comment id AND body hash, so an edit after
            acknowledgement re-opens the item by itself.
            """
    )

    @Argument(help: "The item id, as printed by `contrib in`.")
    var id: String

    @Option(name: .long, help: "Where the content was absorbed.")
    var with: String

    @Argument(help: "<owner>/<repo>")
    var repository: String

    @Option(name: .long, help: "Repository path for resolving a commit sha.")
    var repo: String = "."

    @Option(name: .long, help: "Where the snapshot lives (default: XDG state dir).")
    var stateDir: String?

    enum AckError: Error, CustomStringConvertible {
        case refused(String)

        var description: String {
            switch self {
            case .refused(let why): return why
            }
        }
    }

    func run() async throws {
        var provenance = Provenance(command: "contrib ack \(id)")
        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        guard var snapshot = try store.load(repository: repository) else {
            throw SnapshotError.unknownItem(id)
        }
        guard let entry = snapshot.entries[id] else {
            throw SnapshotError.unknownItem(id)
        }
        if let refusal = AcknowledgementEligibility.refusal(for: entry, id: id) {
            throw AckError.refused(refusal)
        }

        let repository = URL(fileURLWithPath: repo).standardizedFileURL
        let runner = CountingCommandRunner(SystemCommandRunner())
        // Both what others wrote and what I wrote: a `comment:` pointer almost always
        // names one of my own replies, which are authored rather than items.
        let parser = AcknowledgementParser(
            knownCommentIDs: Set(snapshot.entries.keys).union(snapshot.authored),
            resolveCommit: { sha in
                let out = try? await runner.run(
                    ["git", "cat-file", "-e", "\(sha)^{commit}"], cwd: repository)
                return out?.status == 0
            })

        var acknowledgement = try await parser.parse(with, bodySha256: entry.bodySha256)
        let configuration = try Configuration.load(
            directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if let refusal = AcknowledgementEligibility.refusal(
            forKind: acknowledgement.kind,
            allowed: configuration.inbound.acknowledgementKinds, id: id)
        {
            throw AckError.refused(refusal)
        }
        if entry.kind == .inlineThread {
            // A responsiveness check judges one reply. Remember which, so a later reply
            // lists the thread again instead of inheriting a check it never had.
            acknowledgement.replyIDAtAck = entry.myReplyID
        }
        snapshot.entries[id]?.acknowledged = acknowledgement
        try store.save(snapshot)

        print("\(id) acknowledged with \(acknowledgement.rendered)")
        print("  \(acknowledgement.verified ? "verified" : "UNVERIFIED"): \(acknowledgement.verificationNote)")
        print("  it re-opens by itself if the body changes (sha256 \(entry.bodySha256.prefix(12)))")

        provenance.subprocessCalls = runner.count
        provenance.examined("items in snapshot", snapshot.entries.count)
        provenance.examined("acknowledged now", 1)
        if !acknowledgement.verified {
            provenance.note("recorded unverified — \(acknowledgement.verificationNote)")
        }
        try Self.emit(provenance)
    }
}
