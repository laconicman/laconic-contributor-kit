import Foundation

/// `contrib in` output.
///
/// Two rules shape it. **Review bodies come first** — the channel that cannot be
/// replied to is the one most easily dropped, so it gets the most visible treatment
/// rather than a trailing section (TASK §12.10). And **the count examined is printed
/// whether or not anything was found**, because that is the difference between "0
/// issue comments" as a fact and as an assumption (§12.3 rule 4).
public enum InboundReporting {

    public struct Options: Sendable {
        /// Show everything examined, not only what is owed or has moved. Off by
        /// default: a reporter re-derives the same list every run and hands the model
        /// a wall of text; a differ hands it three items and says what changed.
        public var all: Bool

        public init(all: Bool = false) {
            self.all = all
        }
    }

    public static func terminal(
        _ pr: PullRequestThreads, _ result: InboundAudit.Result, options: Options = .init()
    ) -> String {
        var lines: [String] = []
        let title = pr.title.isEmpty ? "" : " — \(pr.title)"
        lines.append("\(pr.repository)#\(pr.number)\(title)")

        let shown = result.items.filter { options.all || $0.state.isOwed || $0.changed != nil }
        if shown.isEmpty {
            lines.append("")
            lines.append("Nothing owed and nothing moved since the last run.")
            return lines.joined(separator: "\n")
        }

        for channel in [Channel.reviewBody, .issueComment, .inlineThread] {
            let items = shown.filter { $0.kind == channel }
            guard !items.isEmpty else { continue }
            lines.append("")
            lines.append(header(for: channel))

            if channel == .inlineThread {
                // Grouped by the review that carried them: "two threads open from the
                // round three days ago" is actionable in a way a flat list is not, and
                // it is how the maintainer experiences it (§12.4).
                let rounds = Dictionary(grouping: items) { $0.roundID ?? "—" }
                for round in rounds.keys.sorted(by: { roundOrder(rounds, $0, $1) }) {
                    let group = rounds[round]!
                    let when = group.compactMap(\.roundAt).min().map(dayString) ?? "?"
                    lines.append("  round \(round), \(when) — \(group.count) thread(s)")
                    lines.append(contentsOf: group.flatMap { render($0, indent: "    ") })
                }
            } else {
                lines.append(contentsOf: items.flatMap { render($0, indent: "  ") })
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The `--json` contract, exactly: a provenance block, and per item `id`, `kind`,
    /// `permalink`, `state`, `question`, `changed` and the minimum text. **Nothing
    /// else** (TASK §13.3).
    public static func json(
        _ result: InboundAudit.Result, provenance: Provenance, options: Options = .init()
    ) throws -> Data {
        struct Document: Encodable {
            var provenance: Provenance
            var items: [InboundItem]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let items = result.items.filter { options.all || $0.state.isOwed || $0.changed != nil }
        return try encoder.encode(Document(provenance: provenance, items: items))
    }

    /// Fold the audit's counts into the provenance block. Called for every run, found
    /// or not.
    public static func record(
        _ result: InboundAudit.Result, _ pr: PullRequestThreads, into provenance: inout Provenance
    ) {
        for channel in Channel.allCases {
            let examined = result.examined[channel] ?? 0
            let mine = result.ownAuthored[channel] ?? 0
            provenance.examined(channel.plural, examined)
            if mine > 0 {
                provenance.note("\(mine) of those \(channel.plural) are mine — not obligations")
            }
        }
        provenance.examined("owed", result.owed.count)
        provenance.examined("pages fetched", pr.pagesFetched)

        for state in [ItemState.noProse, .superseded] {
            let count = Channel.allCases.reduce(0) { $0 + result.count(of: state, in: $1) }
            if count > 0 {
                provenance.note("\(count) item(s) \(state.rawValue) — counted, not owed")
            }
        }
        let unverified = result.updatedSnapshot.entries.values.filter {
            $0.acknowledged?.verified == false
        }.count
        if unverified > 0 {
            provenance.note("\(unverified) acknowledgement(s) recorded but unverified")
        }
        for connection in pr.truncatedConnections {
            provenance.anomaly("truncatedFetch", "\(connection) still had a next page")
        }
        if pr.bodiesAreExcerpts {
            provenance.anomaly(
                "excerptBodies",
                "bodies are truncated excerpts — boilerplate and supersession checks saw a fragment")
        }
    }

    private static func header(for channel: Channel) -> String {
        switch channel {
        case .reviewBody:
            return "REVIEW BODIES — no reply mechanism; listed until acknowledged"
        case .issueComment:
            return "ISSUE COMMENTS — no reply mechanism; listed until acknowledged"
        case .inlineThread:
            return "INLINE THREADS"
        }
    }

    private static func render(_ item: InboundItem, indent: String) -> [String] {
        var lines: [String] = []
        let marker = item.state.isOwed ? "●" : "·"
        let author = item.author.map { " \($0)" } ?? ""
        lines.append("\(indent)\(marker) \(item.id)  [\(item.state.rawValue)]\(author)")
        if let changed = item.changed {
            lines.append("\(indent)  changed: \(changed)")
        }
        lines.append("\(indent)  \(oneLine(item.text.ask))")
        if let reply = item.text.reply {
            lines.append("\(indent)  my reply: \(oneLine(reply))")
        }
        if item.state.isOwed {
            lines.append("\(indent)  → \(item.question)")
            if item.kind != .inlineThread {
                lines.append("\(indent)    contrib ack \(item.id) --with none:\"…\"")
            }
        }
        lines.append("\(indent)  \(item.permalink)")
        return lines
    }

    private static func oneLine(_ text: String, limit: Int = 150) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    private static func dayString(_ date: Date) -> String {
        String(GitHubTime.string(date).prefix(10))
    }

    private static func roundOrder(
        _ rounds: [String: [InboundItem]], _ a: String, _ b: String
    ) -> Bool {
        let left = rounds[a]?.compactMap(\.roundAt).min() ?? .distantPast
        let right = rounds[b]?.compactMap(\.roundAt).min() ?? .distantPast
        return left < right
    }
}
