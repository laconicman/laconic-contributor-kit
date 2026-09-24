import ArgumentParser
import ContributorKit
import Foundation

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Re-read one item in full — body, your reply, and what moved.",
        discussion: """
            The table truncates, and `gh api … --jq '.body'` is the road back to
            hand-rolled fetches. `show` prints one item whole: the stripped ask as the
            audit sees it, your last reply for an inline thread, the recorded
            acknowledgement, and a line diff against the last recorded read — or the
            acknowledged text, when the record kept its prose.

            The snapshot records what was shown: the item's fresh entry is written
            under the repository lock, so the next `contrib in` no longer reports
            this item's already-read changes as new. Only the shown entry is
            written — items nobody was shown keep their `changed` signal — and an
            anomalous fetch writes nothing.
            """
    )

    @Argument(help: "The item id, as printed by `contrib in`.")
    var id: String

    @Argument(help: "<owner>/<repo>")
    var repository: String

    @Option(name: .long, help: "Pull request or issue number — only needed when the item is not in the snapshot.")
    var pr: Int?

    @Option(name: .long, help: "My login. Only needed when the API does not report authorship.")
    var me: String?

    @Option(name: .long, help: "Repository path for the inbound configuration.")
    var repo: String = "."

    @Option(name: .long, help: "Where the snapshot lives (default: XDG state dir).")
    var stateDir: String?

    enum ShowError: Error, CustomStringConvertible {
        case refused(String)

        var description: String {
            switch self {
            case .refused(let why): return why
            }
        }
    }

    func run() async throws {
        var provenance = Provenance(command: "contrib show \(id)")
        let store = SnapshotStore(directory: stateDir.map { URL(fileURLWithPath: $0) })
        let snapshot = try store.load(repository: repository)
        let entry = snapshot?.entries[id]

        // Same validation as `ack`: a --pr that disagrees with the recorded subject
        // almost always means the id was typed for one pull request and --pr for another.
        if let pr, let entry, let subject = entry.subject,
            !entry.isFromSubject(repository: repository, pr: pr)
        {
            throw ShowError.refused("\(id) belongs to \(subject), not \(repository)#\(pr)")
        }

        let subject =
            entry?.subject ?? pr.map { Subject.format(repository: repository, number: $0) }
        guard let subject, let number = Subject.number(in: subject, repository: repository)
        else {
            throw ShowError.refused(
                "no item `\(id)` in the snapshot and no --pr to fetch it from — "
                    + "run `contrib in \(repository) --pr N` first, or pass --pr N")
        }

        let workingCopy = URL(fileURLWithPath: repo).standardizedFileURL
        let configuration = try Configuration.load(directory: workingCopy)
        let runner = CountingCommandRunner(SystemCommandRunner())
        let client = GHCommandClient(
            runner: runner, queryPath: try GHCommandClient.bundledQueryPath())
        let fetched = try await client.threads(repository: repository, number: number)

        let audit = try InboundAudit(configuration: configuration, me: me)

        // Load, audit and write inside the repository lock, exactly as `contrib in`
        // does: the audit is re-run against the snapshot on disk, so an `in` or `ack`
        // landing between the fetch and the write is seen rather than overwritten.
        // What differs is the write — only the shown entry, not the whole subject —
        // so items nobody was shown keep their "changed" signal.
        struct Shown {
            var result: InboundAudit.Result
            var previous: Snapshot.Entry?
            var wrote: Bool
        }
        let shown = try store.withLock(repository: repository) { () -> Shown in
            var current =
                (try store.load(repository: repository)) ?? Snapshot(repository: repository)
            let previous = current.entries[id]
            let result = audit.run(fetched, against: current)
            // Same trust rule as `contrib in`: a fetch that lost items cannot be the
            // next run's baseline — here it would also erase this item's signal.
            let anomalous =
                !fetched.truncatedConnections.isEmpty || !result.vanished.isEmpty
            var wrote = false
            if !anomalous, let fresh = result.updatedSnapshot.entries[id] {
                current.entries[id] = fresh
                current.authored.formUnion(result.updatedSnapshot.authored)
                current.updatedAt = Date()
                try store.save(current)
                wrote = true
            }
            return Shown(result: result, previous: previous, wrote: wrote)
        }
        let result = shown.result
        let previous = shown.previous

        for connection in fetched.truncatedConnections {
            provenance.anomaly("truncatedFetch", "\(connection) still had a next page")
        }
        if !result.vanished.isEmpty {
            provenance.anomaly(
                "itemsVanished",
                "\(result.vanished.count) item(s) \(subject) carried last run were not in "
                    + "this fetch: \(result.vanished.prefix(5).joined(separator: ", "))")
        }
        guard let item = result.items.first(where: { $0.id == id }) else {
            throw ShowError.refused(
                "\(id) was not in the fetch for \(subject) — "
                    + "deleted upstream, or the wrong --pr")
        }
        let comment = fetched.allComments.first { $0.id == id }

        print(render(item, pr: fetched))
        print("")
        print("── ask " + String(repeating: "─", count: 60))
        print(item.text.ask)
        if item.kind == .inlineThread {
            print("")
            print("── my reply " + String(repeating: "─", count: 54))
            print(item.text.reply ?? "(no reply from you yet)")
        }
        if let ack = previous?.acknowledged {
            print("")
            print("── acknowledged " + String(repeating: "─", count: 50))
            print(
                "\(ack.rendered) at \(GitHubTime.string(ack.at)) — "
                    + "\(ack.verified ? "verified" : "UNVERIFIED"): \(ack.verificationNote)")
            if let replyID = ack.replyIDAtAck { print("judged reply: \(replyID)") }
            if let previous {
                print(
                    previous.bodySha256 == ack.bodySha256AtAck
                        ? "body unchanged since acknowledgement"
                        : "body CHANGED since acknowledgement — that is why it re-opened")
            }
        }

        // The diff anchor is the best recorded earlier text: the acknowledged prose
        // when the record kept it, else the last read's. `nil` means this snapshot
        // predates prose tracking — say so rather than diffing against nothing.
        let ackedProse = previous?.acknowledged?.proseAtAck
        let anchor = ackedProse ?? previous?.prose
        print("")
        if let anchor, let comment {
            let anchorName = ackedProse != nil ? "acknowledgement" : "the last read"
            print("── diff: since \(anchorName) " + String(repeating: "─", count: 40))
            let diff = LineDiff.lines(from: anchor, to: audit.stripper.prose(of: comment.body))
            print(diff.isEmpty ? "(prose unchanged)" : diff.joined(separator: "\n"))
        } else if previous == nil {
            print("── diff " + String(repeating: "─", count: 58))
            print("(item was not in the snapshot — no earlier text to diff against)")
        } else {
            print("── diff " + String(repeating: "─", count: 58))
            print("(snapshot predates prose tracking — no earlier text to diff against)")
        }

        if shown.wrote {
            provenance.note("snapshot updated for \(id) — other items untouched")
        } else {
            provenance.note("snapshot NOT written — anomalous fetch; fix and re-run")
        }

        provenance.subprocessCalls = runner.count
        for channel in Channel.allCases {
            provenance.examined(channel.plural, result.examined[channel] ?? 0)
        }
        provenance.note("as of \(GitHubTime.string(Date()))")
        try Self.emit(provenance)
    }

    private func render(_ item: InboundItem, pr: PullRequestThreads) -> String {
        var lines: [String] = []
        let title = pr.title.isEmpty ? "" : " — \(pr.title)"
        lines.append("\(pr.repository)#\(pr.number)\(title)")
        lines.append("")
        let marker = item.state.isOwed ? "●" : "·"
        let author = item.author.map { " \($0)" } ?? ""
        lines.append("\(marker) \(item.id)  [\(item.state.rawValue)]\(author)")
        if let round = item.roundID, let at = item.roundAt {
            lines.append("  round \(round), \(String(GitHubTime.string(at).prefix(10)))")
        }
        if let changed = item.changed {
            lines.append("  changed: \(changed)")
        }
        if item.state.isOwed || item.state.needsLook {
            lines.append("  → \(item.question)")
        }
        lines.append("  \(item.permalink)")
        return lines.joined(separator: "\n")
    }
}
