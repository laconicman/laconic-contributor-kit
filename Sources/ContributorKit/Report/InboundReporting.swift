import Foundation

/// `contrib in` output.
///
/// Two rules shape it. **Review bodies come first** — the channel that cannot be
/// replied to is the one most easily dropped, so it gets the most visible treatment
/// rather than a trailing section (<doc:Design>). And **the count examined is printed
/// whether or not anything was found**, because that is the difference between "0
/// issue comments" as a fact and as an assumption (<doc:Design>).
public enum InboundReporting {

    /// One reviewer channel's coverage on the head commit — the fetch's answer to
    /// "did a reviewer actually run on THIS head, and what did it report" (issue
    /// #10). Carried **verbatim**: a `SUCCESS` whose description says "Full review
    /// skipped: trial expired" is a never-ran round, and matching on words to hide
    /// that distinction would be a judgment the kit does not make.
    public struct ReviewerReport: Codable, Sendable, Equatable {
        /// The channel's name — `context` on a legacy status, `name` on a check run.
        public var channel: String
        /// The head commit the report sits on (7-char prefix, GitHub's short form).
        public var head: String?
        /// The reported state verbatim — `state` on a status, `conclusion ?? status`
        /// on a check run.
        public var state: String
        /// The free-text detail verbatim — `description` or `title`.
        public var detail: String?
        public var url: String?
        /// The login `lastReviewOn` refers to.
        public var reviewLogin: String?
        /// The newest review object by `reviewLogin`, as the commit it was left on.
        /// "The last actual review was three heads ago" is coverage the state
        /// string alone cannot carry.
        public var lastReviewOn: String?

        /// `Devin Review @ de08fb5 (head): SUCCESS "Full review skipped: trial
        /// expired" — last review object on f4e3cda`
        public var rendered: String {
            var line = "\(channel) @ \(head ?? "?") (head): \(state)"
            if let detail { line += " \"\(detail)\"" }
            if let lastReviewOn {
                line += " — last review object"
                    + (reviewLogin.map { " by \($0)" } ?? "")
                    + " on \(lastReviewOn)"
            }
            return line
        }
    }

    /// The head commit's contexts as coverage lines.
    ///
    /// Every `StatusContext` is listed — legacy statuses are few and each one is
    /// somebody's report. A `CheckRun` is listed only when `channels` names it,
    /// because CI produces dozens and coverage answers a different question than
    /// "did the build pass". `channels` also maps a check name to the login whose
    /// latest review object supplies `lastReviewOn`.
    public static func reviewerCoverage(
        _ pr: PullRequestThreads, channels: [String: String]
    ) -> [ReviewerReport] {
        pr.headContexts
            .filter { !$0.isCheckRun || channels[$0.name] != nil }
            // One name can appear twice (a status and a run under the same
            // app) — a tiebreak keeps the line order deterministic.
            .sorted { $0.name != $1.name ? $0.name < $1.name : !$0.isCheckRun }
            .map { context in
                var report = ReviewerReport(
                    channel: context.name,
                    head: pr.headCommitOID.map { String($0.prefix(7)) },
                    state: context.state, detail: context.detail, url: context.url)
                if let login = channels[context.name],
                    let latest = pr.reviewBodies
                        .filter({ Login.same($0.author, login) && $0.commitOID != nil })
                        .max(by: { $0.createdAt < $1.createdAt })
                {
                    report.reviewLogin = login
                    report.lastReviewOn = latest.commitOID.map { String($0.prefix(7)) }
                }
                return report
            }
    }

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
        _ pr: PullRequestThreads, _ result: InboundAudit.Result, options: Options = .init(),
        reviewerChannels: [String: String]
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
            // A clean ledger and a never-ran review are the same absence: when the
            // head carries reviewer contexts the verdict travels with the zero —
            // verbatim, so "Full review skipped" cannot pass for a clean round
            // (issue #10).
            for reviewer in reviewerCoverage(pr, channels: reviewerChannels) {
                lines.append("reviewer       \(reviewer.rendered)")
            }
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
                    lines.append(
                        contentsOf: group.flatMap {
                            render(
                                $0, indent: "    ", repository: pr.repository,
                                number: pr.number)
                        })
                }
            } else {
                lines.append(
                    contentsOf: items.flatMap {
                        render(
                            $0, indent: "  ", repository: pr.repository,
                            number: pr.number)
                    })
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One subject's facts for the `verdict` line and the `--open` queue (issue
    /// #12): the two counts, whether the subject was a cold start, and the head's
    /// reviewer coverage verbatim.
    public struct SubjectSummary: Sendable {
        public var number: Int
        public var title: String
        public var isDraft: Bool
        public var owed: Int
        public var toReRead: Int
        /// Collapsed sections nobody has read — work `owed` and `to re-read`
        /// cannot see (PR #15).
        public var unexamined: Int
        public var isBaseline: Bool
        public var hasHead: Bool
        public var reviewers: [ReviewerReport]

        public init(
            number: Int, title: String, isDraft: Bool, owed: Int, toReRead: Int,
            unexamined: Int, isBaseline: Bool, hasHead: Bool,
            reviewers: [ReviewerReport]
        ) {
            self.number = number
            self.title = title
            self.isDraft = isDraft
            self.owed = owed
            self.toReRead = toReRead
            self.unexamined = unexamined
            self.isBaseline = isBaseline
            self.hasHead = hasHead
            self.reviewers = reviewers
        }
    }

    /// `owed 0 · to re-read 0 · unexamined 0 · baseline · <reviewer line verbatim> · …`
    ///
    /// A composition of facts, not a judgment (issue #12): the reviewer detail is
    /// carried verbatim, so `SUCCESS "Full review skipped"` still cannot pass for a
    /// clean round. On a subject with no head commit (an issue) the line stops after
    /// the counts — absence of coverage is a fetch fact, not a claim.
    public static func facts(
        owed: Int, toReRead: Int, unexamined: Int, isBaseline: Bool, hasHead: Bool,
        reviewers: [ReviewerReport]
    ) -> String {
        var line = "owed \(owed) · to re-read \(toReRead) · unexamined \(unexamined)"
        if isBaseline { line += " · baseline" }
        if hasHead {
            // One line is the contract: a check-run `title` or a status
            // `description` can carry a newline, and the row must not wrap into
            // the next subject. `rendered` itself stays verbatim for the
            // provenance block, which is free to span lines.
            line += reviewers.isEmpty
                ? " · no reviewer context on head"
                : " · " + reviewers.map {
                    $0.rendered
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
                }.joined(separator: " · ")
        }
        return line
    }

    /// The `--open` queue (issue #12): a header counting every open pull request
    /// against the ones that are mine, then one facts line per mine. No items —
    /// the queue shows no item's `changed` signal, so it writes nothing.
    public static func queue(
        repository: String, list: OpenPullRequestList, rows: [SubjectSummary]
    ) -> String {
        var lines = [
            "\(repository) — \(list.mine.count) of \(list.totalCount) "
                + "open pull request(s) are mine"
        ]
        if list.mine.isEmpty {
            lines.append("")
            lines.append("Nothing to audit.")
            return lines.joined(separator: "\n")
        }
        for row in rows.sorted(by: { $0.number < $1.number }) {
            lines.append("")
            let label = "#\(row.number)  "
            lines.append("\(label)\(row.title)\(row.isDraft ? " (draft)" : "")")
            lines.append(
                String(repeating: " ", count: label.count) + facts(
                    owed: row.owed, toReRead: row.toReRead, unexamined: row.unexamined,
                    isBaseline: row.isBaseline,
                    hasHead: row.hasHead, reviewers: row.reviewers))
        }
        return lines.joined(separator: "\n")
    }

    /// The queue's per-subject work (issue #12): audit each fetched pull request
    /// against ONE snapshot version — every subject's baseline and every `changed`
    /// comparison reads the same previous — and fold the fetch anomalies, the
    /// counters and the rows out of it.
    ///
    /// Called inside the repository lock after all fetches: the audits are pure
    /// and the snapshot they compare against must be the version on disk, not one
    /// loaded before another run could write.
    public static func queueRows(
        _ subjects: [PullRequestThreads], drafts: Set<Int>, previous: Snapshot?,
        audit: InboundAudit, reviewerChannels: [String: String],
        into provenance: inout Provenance
    ) -> [SubjectSummary] {
        var rows: [SubjectSummary] = []
        var examined: [Channel: Int] = [:]
        var owed = 0
        var toReRead = 0
        var unexamined = 0
        var pagesFetched = 0
        var baselines: [Int] = []
        var allFullText = true
        for subject in subjects.sorted(by: { $0.number < $1.number }) {
            let result = audit.run(subject, against: previous)
            recordFetchAnomalies(
                result, subject, label: "#\(subject.number)", into: &provenance)
            for channel in Channel.allCases {
                examined[channel, default: 0] += result.examined[channel] ?? 0
            }
            let isBaseline = knownBefore(subject, previous: previous) == 0
            if isBaseline { baselines.append(subject.number) }
            rows.append(
                SubjectSummary(
                    number: subject.number, title: subject.title,
                    isDraft: drafts.contains(subject.number),
                    owed: result.owed.count, toReRead: result.toReRead.count,
                    unexamined: result.unexamined.count, isBaseline: isBaseline,
                    hasHead: subject.headCommitOID != nil,
                    reviewers: reviewerCoverage(subject, channels: reviewerChannels)))
            owed += result.owed.count
            toReRead += result.toReRead.count
            unexamined += result.unexamined.count
            pagesFetched += subject.pagesFetched
            if subject.bodiesAreExcerpts { allFullText = false }
        }

        provenance.examined("pull requests audited", subjects.count)
        for channel in Channel.allCases {
            provenance.examined(channel.plural, examined[channel] ?? 0)
        }
        provenance.examined("owed", owed)
        provenance.examined("to re-read", toReRead)
        provenance.examined("unexamined", unexamined)
        provenance.examined("pages fetched", pagesFetched)
        if allFullText, !subjects.isEmpty {
            provenance.note(
                "bodies: full text, not excerpts — all \(subjects.count) pull request(s)")
        }
        if !baselines.isEmpty {
            provenance.note(
                "\(baselines.count) pull request(s) have no prior items — their "
                    + "counts are a cold start, not a round: "
                    + baselines.map { "#\($0)" }.joined(separator: ", "))
        }
        return rows
    }

    /// How many entries the previous snapshot already knew for this subject — the
    /// one definition of "baseline", shared by `record()`'s note and the `--open`
    /// queue's row flag.
    ///
    /// Entries written before `subject` existed carry no `subject` key; they are
    /// identified by their permalink, the one field they always carried — matched
    /// the way `AcknowledgementParser.subjectBodyID` parses it (owner/repo
    /// case-insensitive, host unchecked, path before the `#`).
    public static func knownBefore(_ pr: PullRequestThreads, previous: Snapshot?) -> Int {
        let subject = "\(pr.repository)#\(pr.number)"
        let paths = [
            "/\(pr.repository)/pull/\(pr.number)",
            "/\(pr.repository)/pulls/\(pr.number)",
            "/\(pr.repository)/issues/\(pr.number)",
        ]
        return (previous?.entries.values ?? [:].values).filter { entry in
            if entry.subject == subject { return true }
            guard entry.subject == nil,
                let url = URL(string: entry.url)
            else { return false }
            return paths.contains {
                url.path.caseInsensitiveCompare($0) == .orderedSame
            }
        }.count
    }

    /// The `--json` contract, exactly: a provenance block, and per item `id`, `kind`,
    /// `permalink`, `state`, `question`, `changed`, the minimum text and `resolution`.
    /// **Nothing else** (<doc:Design>).
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
        previous: Snapshot?, reviewerChannels: [String: String],
        into provenance: inout Provenance
    ) {
        // Reviewer coverage is recorded, not examined-counted: the contexts are
        // what the head commit carries, and the verdict is what a "Nothing owed"
        // reads beside the zero (issue #10).
        provenance.reviewers = reviewerCoverage(pr, channels: reviewerChannels)
        recordFetchAnomalies(result, pr, label: nil, into: &provenance)
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
        // A collapsed section nobody has read is work the first two counts cannot
        // see — a zero is a statement, an absent segment is not.
        provenance.examined("unexamined", result.unexamined.count)
        if pr.isClosed {
            let quiet = result.items.filter {
                $0.isVisible && $0.state.needsLook && !$0.isListedByDefault
            }.count
            if quiet > 0 {
                provenance.note(
                    "\(pr.state.lowercased()) — \(quiet) answered-claimed or asker-replied "
                        + "item(s) on resolved threads not listed; owed items and unresolved "
                        + "threads are listed regardless")
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
        if knownBefore(pr, previous: previous) == 0 {
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
        // Stated positively as well as negatively: an observer cannot tell a check that
        // passed from one that did not run, and "no excerptBodies anomaly" is exactly
        // that shape.
        if !pr.bodiesAreExcerpts {
            provenance.note("bodies: full text, not excerpts")
        }
    }

    /// The fetch's own anomalies, in one place so `--open` cannot drift from
    /// `--pr` (issue #12): a vanished item, a truncated connection and an excerpt
    /// body are the same three failures on every subject, and a truncated head
    /// context list is a note for the same reason `record()` treats it as one —
    /// a busy CI PR must not hold the ledger hostage. `label` prefixes each line
    /// (`"#3: reviews still had a next page"`) when one run covers many subjects.
    static func recordFetchAnomalies(
        _ result: InboundAudit.Result, _ pr: PullRequestThreads, label: String?,
        into provenance: inout Provenance
    ) {
        let prefix = label.map { "\($0): " } ?? ""
        if !result.vanished.isEmpty {
            provenance.anomaly(
                "itemsVanished",
                "\(prefix)\(result.vanished.count) item(s) this subject carried last "
                    + "run were not in this fetch: "
                    + "\(result.vanished.prefix(5).joined(separator: ", "))")
        }
        for connection in pr.truncatedConnections {
            provenance.anomaly(
                "truncatedFetch", "\(prefix)\(connection) still had a next page")
        }
        if pr.bodiesAreExcerpts {
            provenance.anomaly(
                "excerptBodies",
                "\(prefix)bodies are truncated excerpts — boilerplate and supersession "
                    + "checks saw a fragment")
        }
        // Only when the source said "pull request": an absent head is then a
        // missing fetch fact, not an issue-shaped subject — and a pre-field
        // capture (`isPullRequest` nil) must not read as anomalous.
        if pr.isPullRequest == true && pr.headCommitOID == nil {
            provenance.anomaly(
                "noHeadCommit",
                "\(prefix)the fetch reported no head commit — "
                    + "reviewer coverage cannot be read")
        }
        if pr.headContextsTruncated {
            provenance.note(
                "\(prefix)head check-context list truncated — "
                    + "reviewer coverage may be incomplete")
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

    private static func render(
        _ item: InboundItem, indent: String, repository: String, number: Int
    ) -> [String]
    {
        var lines: [String] = []
        let marker = item.state.isOwed ? "●" : "·"
        let author = item.author.map { " \($0)" } ?? ""
        lines.append(
            "\(indent)\(marker) \(item.id)  [\(item.state.rawValue)]\(author)\(resolutionNote(item))")
        if let changed = item.changed {
            lines.append("\(indent)  changed: \(changed)")
        }
        let excerpt = oneLine(item.text.ask)
        lines.append("\(indent)  \(excerpt)")
        // A marker past the excerpt's cut would leave no flag at all — name the
        // sections the excerpt could not show.
        let hidden = item.text.ask.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { BoilerplateStripper.isCollapsedMarker($0) && !excerpt.contains($0) }
        for markerLine in hidden {
            lines.append(
                "\(indent)  + \(markerLine) — `contrib show \(item.id) \(repository) --full`")
        }
        if let reply = item.text.reply {
            lines.append("\(indent)  my reply: \(oneLine(reply))")
        }
        if item.state.isOwed || item.state.needsLook || item.state == .collapsedUnexamined {
            lines.append("\(indent)  → \(item.question)")
            if item.state == .askerReplied {
                lines.append("\(indent)    contrib show \(item.id) \(repository)")
            } else if item.kind != .inlineThread || item.state == .answeredClaimed {
                // The id's subject is known here, so the printed line is the
                // runnable form — repository and --pr filled in (issue #13).
                lines.append(
                    "\(indent)    contrib ack \(item.id) --with none:\"…\""
                        + " \(repository) --pr \(number)")
            }
        }
        lines.append("\(indent)  \(item.permalink)")
        return lines
    }

    /// ` — unresolved`, ` — resolved by the asker`, or ` — resolved by <login>`; empty
    /// off inline threads. Who resolved a thread is evidence for the reader — a thread
    /// is resolved for more reasons than the asker's consent — never for the audit.
    public static func resolutionNote(_ item: InboundItem) -> String {
        guard let resolution = item.resolution else { return "" }
        guard resolution.isResolved else { return " — unresolved" }
        if resolution.byAsker { return " — resolved by the asker" }
        return resolution.resolvedBy.map { " — resolved by \($0)" } ?? " — resolved"
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
