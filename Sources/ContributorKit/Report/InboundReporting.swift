import Foundation

/// `contrib in` output.
///
/// Two rules shape it. **Review bodies come first** — the channel that cannot be
/// replied to is the one most easily dropped, so it gets the most visible treatment
/// rather than a trailing section (<doc:Design>). And **the count examined is printed
/// whether or not anything was found**, because that is the difference between "0
/// issue comments" as a fact and as an assumption (<doc:Design>).
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

        let shown = result.items.filter {
            options.all ? $0.isVisible : $0.isListedByDefault
        }
        if shown.isEmpty {
            lines.append("")
            // Say what was compared. "Nothing moved" on its own cannot be told apart
            // from "this check cannot see what would have moved".
            lines.append(
                "Nothing owed. No item changed state, body or acknowledgement since the "
                    + "last run — \(result.items.count) compared.")
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
                // it is how the maintainer experiences it (the Design article).
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
    /// else** (<doc:Design>).
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
        let items = result.items.filter {
            options.all ? $0.isVisible : $0.isListedByDefault
        }
        return try encoder.encode(Document(provenance: provenance, items: items))
    }

    /// Fold the audit's counts into the provenance block. Called for every run, found
    /// or not.
    public static func record(
        _ result: InboundAudit.Result, _ pr: PullRequestThreads,
        previous: Snapshot?, into provenance: inout Provenance
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
        // Reported beside `owed`, never folded into it: nothing is owed on these, but
        // each carries a question no one has recorded an answer to.
        provenance.examined("to re-read", result.toReRead.count)
        if pr.isClosed {
            let quiet = result.items.filter {
                $0.isVisible && $0.state.needsLook && $0.changed == nil
            }.count
            if quiet > 0 {
                provenance.note(
                    "\(pr.state.lowercased()) — \(quiet) answered-claimed item(s) not listed; "
                        + "owed items are listed regardless")
            }
        }
        provenance.examined("pages fetched", pr.pagesFetched)
        // A zero is a timestamp, not a state: acting on a PR *causes* the next review
        // wave, and an `owed 0` has twice been true at the fetch and false twenty
        // minutes later. Stamping the fetch makes a quoted zero carry its own expiry.
        provenance.note("as of \(GitHubTime.string(Date()))")

        if !result.beyondHorizon.isEmpty {
            let owed = result.beyondHorizon.filter(\.state.isOwed).count
            provenance.note(
                "\(result.beyondHorizon.count) item(s) before the review horizon — "
                    + "not listed (\(owed) of them would otherwise be owed)")
        }

        // Transitions, named. The run straight after a round of replies is the one most
        // likely to be read, and "nothing moved" was the wrong answer to it.
        let moved = result.items.filter { $0.previousState != nil }
        if !moved.isEmpty {
            provenance.examined("changed state", moved.count)
            let byTransition = Dictionary(grouping: moved) {
                "\($0.previousState!.rawValue) → \($0.state.rawValue)"
            }
            for transition in byTransition.keys.sorted() {
                provenance.note("\(byTransition[transition]!.count) × \(transition)")
            }
        }

        for state in [ItemState.noProse, .superseded, .informational] {
            let count = Channel.allCases.reduce(0) { $0 + result.count(of: state, in: $1) }
            if count > 0 {
                provenance.note("\(count) item(s) \(state.rawValue) — counted, not owed")
            }
        }
        // A marker-only body is flagged, not empty — name it or the
        // "collapsed content exists" promise never reaches default output.
        // `text.ask` is prose-or-raw-body, so the test is shape, not prefix:
        // every non-empty line is a generated marker. A raw body carrying the
        // literal text `[collapsed:` inside a comment does not match.
        let collapsedOnly = result.items.filter { item in
            guard item.state == .noProse else { return false }
            let lines = item.text.ask.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return !lines.isEmpty && lines.allSatisfy(BoilerplateStripper.isCollapsedMarker)
        }
        if !collapsedOnly.isEmpty {
            provenance.note(
                "\(collapsedOnly.count) item(s) are collapsed sections only — "
                    + "`contrib show <id> \(pr.repository) --full` retrieves them: "
                    + collapsedOnly.map(\.id).joined(separator: ", "))
        }
        // Scoped to what THIS run examined. Both of these counted over the whole
        // repository, which is a different question: sweeping five issues in one repo,
        // only the first announced a baseline while each of the others was also its own
        // first run, and an unverified acknowledgement from one issue was reported
        // against another.
        let examinedIDs = Set(result.items.map(\.id))
        let unverified = result.updatedSnapshot.entries
            .filter { examinedIDs.contains($0.key) && $0.value.acknowledged?.verified == false }
            .count
        if unverified > 0 {
            provenance.note(
                "\(unverified) acknowledgement(s) on this item recorded but unverified")
        }
        let subject = "\(pr.repository)#\(pr.number)"
        let knownHere = (previous?.entries.values ?? [:].values)
            .filter { $0.subject == subject }.count
        if knownHere == 0 {
            // Said per subject, not per repository: sweeping five issues in one repo,
            // only the first announced a baseline while each of the others was also its
            // own first run.
            provenance.note("no prior items for \(subject) — this run is its baseline")
        }
        if let previous {
            let newHere = result.items.filter(\.isNewToSnapshot).count
            provenance.note(
                "snapshot: \(previous.entries.count) item(s) known for this repository, "
                    + "age \(Int(previous.age / 3600))h; \(newHere) new this run")
        }
        if !result.vanished.isEmpty {
            provenance.anomaly(
                "itemsVanished",
                "\(result.vanished.count) item(s) this subject carried last run were not in "
                    + "this fetch: \(result.vanished.prefix(5).joined(separator: ", "))")
        }
        for connection in pr.truncatedConnections {
            provenance.anomaly("truncatedFetch", "\(connection) still had a next page")
        }
        // Stated positively as well as negatively: an observer cannot tell a check that
        // passed from one that did not run, and "no excerptBodies anomaly" is exactly
        // that shape.
        if pr.bodiesAreExcerpts {
            provenance.anomaly(
                "excerptBodies",
                "bodies are truncated excerpts — boilerplate and supersession checks saw a fragment")
        } else {
            provenance.note("bodies: full text, not excerpts")
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
        if item.state.isOwed || item.state.needsLook {
            lines.append("\(indent)  → \(item.question)")
            if item.kind != .inlineThread || item.state.needsLook {
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
