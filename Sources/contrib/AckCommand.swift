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

    @Option(name: .long, help: "Pull request or issue number — checked against the item's recorded subject, and required by --refresh when it has none.")
    var pr: Int?

    @Flag(name: .long, help: "Re-fetch the item's subject and update the snapshot before writing — reply → `in` → ack in one step.")
    var refresh = false

    @Option(name: .long, help: "My login. Only needed when the API does not report authorship.")
    var me: String?

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
        guard var entry = snapshot.entries[id] else {
            throw SnapshotError.unknownItem(id)
        }
        // Accepted for symmetry with `contrib in`, and validated rather than ignored:
        // a number that disagrees with the recorded subject almost always means the id
        // was typed for one pull request and --pr for another.
        if let pr, let subject = entry.subject,
            !entry.isFromSubject(repository: repository, pr: pr)
        {
            throw AckError.refused("\(id) belongs to \(subject), not \(repository)#\(pr)")
        }

        let workingCopy = URL(fileURLWithPath: repo).standardizedFileURL
        let runner = CountingCommandRunner(SystemCommandRunner())
        // The target repository's rules, not the one this shell happens to sit in.
        let configuration = try Configuration.load(directory: workingCopy)

        if refresh {
            let subject =
                entry.subject ?? pr.map { Subject.format(repository: repository, number: $0) }
            guard let subject,
                let number = Subject.number(in: subject, repository: repository)
            else {
                throw AckError.refused(
                    "\(id) has no recorded pull request — pass --pr N, or run `contrib in` first")
            }
            let client = GHCommandClient(
                runner: runner, queryPath: try GHCommandClient.bundledQueryPath())
            let fetched = try await client.threads(repository: repository, number: number)
            // Same rule as `contrib in`: a truncated fetch must not become the next
            // run's baseline — and here it would also legitimise a stale eligibility check.
            guard fetched.truncatedConnections.isEmpty else {
                throw AckError.refused(
                    "the refresh fetch was truncated (\(fetched.truncatedConnections.joined(separator: ", "))) "
                        + "— refusing to acknowledge against a partial read")
            }
            let audit = try InboundAudit(configuration: configuration, me: me)
            // The same read-modify-write discipline as `contrib in`: the audit is
            // re-run under the lock against the state actually on disk, and merged
            // subject-scoped so a concurrent audit of another PR is not overwritten.
            try store.withLock(repository: repository) {
                var current = try store.load(repository: repository) ?? snapshot
                let result = audit.run(fetched, against: current)
                // Same rule as `contrib in`: an anomalous fetch must not become the next
                // run's baseline — and here it would also legitimise a stale eligibility
                // check. Throwing skips the save entirely.
                guard result.vanished.isEmpty else {
                    throw AckError.refused(
                        "the refresh fetch dropped \(result.vanished.count) item(s) \(subject) "
                            + "carried last run — refusing to acknowledge against a partial read: "
                            + result.vanished.prefix(5).joined(separator: ", "))
                }
                current.merge(result, forSubject: subject)
                try store.save(current)
                snapshot = current
            }
            guard let fresh = snapshot.entries[id] else {
                throw AckError.refused(
                    "\(id) was not in the refresh fetch — it may have been deleted upstream")
            }
            entry = fresh
            provenance.examined("refresh items", fetched.allComments.count)
            provenance.note("snapshot refreshed from \(subject)")
        }

        if let refusal = AcknowledgementEligibility.refusal(for: entry, id: id) {
            throw AckError.refused(refusal)
        }

        // **Only what I wrote.** `snapshot.entries` holds the reviewers' comments — the
        // asks themselves — so including them let an ask verify its own
        // acknowledgement. Authored ids are the replies a `comment:` pointer means.
        let parser = AcknowledgementParser(
            knownCommentIDs: snapshot.authored,
            resolveCommit: { sha in
                let out = try? await runner.run(
                    ["git", "cat-file", "-e", "\(sha)^{commit}"], cwd: workingCopy)
                return out?.status == 0
            })

        var acknowledgement = try await parser.parse(with, bodySha256: entry.bodySha256)
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
        // Same transaction rule as `contrib in`: re-read under the lock and apply only
        // this one entry, so an audit running alongside is not overwritten.
        //
        // Eligibility is checked AGAIN here, against the state actually being written.
        // The check above ran before the lock, so an audit landing in between could have
        // moved the item — the asker confirming it, or an edit arriving — and the
        // acknowledgement would be recorded against state that no longer permits it.
        try store.withLock(repository: repository) {
            var current = try store.load(repository: repository) ?? snapshot
            guard let fresh = current.entries[id] else {
                throw SnapshotError.unknownItem(id)
            }
            if let refusal = AcknowledgementEligibility.refusal(for: fresh, id: id) {
                throw AckError.refused(refusal)
            }
            if fresh.bodySha256 != entry.bodySha256 {
                throw AckError.refused(
                    """
                    \(id) changed while this acknowledgement was being prepared. \
                    Re-read it and run the command again.
                    """)
            }
            acknowledgement.bodySha256AtAck = fresh.bodySha256
            if fresh.kind == .inlineThread { acknowledgement.replyIDAtAck = fresh.myReplyID }
            // The prose the record judged, kept so `contrib show` can diff the ask as
            // absorbed against the ask as it stands — the hash says *that* it moved,
            // not *what* moved.
            acknowledgement.proseAtAck = fresh.prose
            current.entries[id]?.acknowledged = acknowledgement
            current.updatedAt = Date()
            try store.save(current)
        }

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
