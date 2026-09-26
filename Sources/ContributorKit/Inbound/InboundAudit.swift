import Foundation

/// `contrib in` — *what was asked of me that I have not demonstrably absorbed?*
///
/// Three channels, not one (<doc:Design>). Inline review comments, review
/// **bodies**, and issue comments. A run that skips review bodies reproduces the
/// original bug: on #5233 the same ask was raised in review bodies on 09-02, 09-03 and
/// 09-04 and missed every time, because only inline comments were being read — the
/// fourth time by an audit script written specifically to prevent the first failure.
///
/// The set arithmetic in <doc:Design> applies to channel 1 only, and is deliberately **not**
/// extended to the other two: *"a review body is answered if I posted any top-level
/// comment after it"* is row 1 of <doc:Design>'s rejection table, a silent false negative.
public struct InboundAudit: Sendable {
    public let me: String?
    public let stripper: BoilerplateStripper
    public let supersession: SupersessionDetector
    public let informational: InformationalDetector
    /// Items raised before this are counted and not listed (`inbound.horizon`).
    public let horizon: Date?

    public init(
        me: String?, stripper: BoilerplateStripper, supersession: SupersessionDetector,
        informational: InformationalDetector, horizon: Date? = nil
    ) {
        self.horizon = horizon
        self.me = me
        self.stripper = stripper
        self.supersession = supersession
        self.informational = informational
    }

    public struct Result: Sendable {
        /// Every item examined, in every state — the reporter filters, not the audit.
        public var items: [InboundItem]
        /// Everything examined, per channel — printed whether or not anything was
        /// found. <doc:Design>, and the difference between "0 issue comments" as a
        /// fact and as an assumption.
        public var examined: [Channel: Int]
        /// How many of those were **mine**, per channel, and therefore never
        /// obligations against me. Counted rather than silently dropped: an unfiltered
        /// list flags the contributor's own replies as new asks, and printing the
        /// number is what makes the filter visible instead of assumed.
        public var ownAuthored: [Channel: Int]
        public var updatedSnapshot: Snapshot
        /// Ids this subject carried last run and does not carry now.
        ///
        /// A disappearance is an anomaly, not a quiet omission: an item that leaves the
        /// fetch leaves the worklist, and the one thing this kit must never do is drop
        /// an ask silently. Counting snapshot entries could not detect this — the
        /// snapshot only ever grows — so the comparison is over ids actually fetched.
        public var vanished: [String]

        /// Owed **and** in scope. An item beyond the declared horizon is not owed
        /// until something about it moves; the provenance block reports how many were
        /// held back and by which boundary, so the number is never silently smaller.
        public var owed: [InboundItem] { items.filter { $0.state.isOwed && $0.isVisible } }
        /// Answered but unconfirmed and unchecked, on an open subject — the list that
        /// asks *is my reply actually responsive?*
        public var toReRead: [InboundItem] {
            items.filter { $0.isVisible && $0.state.needsLook && !$0.subjectClosed }
        }
        /// Items the horizon is holding back this run.
        public var beyondHorizon: [InboundItem] { items.filter { !$0.isVisible } }

        public func count(of state: ItemState, in channel: Channel) -> Int {
            items.filter { $0.kind == channel && $0.state == state }.count
        }
    }

    /// Is this comment mine? `viewerDidAuthor` when the source supplied it (the live
    /// GraphQL path always does), else a login comparison.
    ///
    /// **Authorship filtering is not a detail.** GitHub records a reply submitted
    /// through the review API as a review, so on any PR where the contributor replies,
    /// an unfiltered obligation list is immediately polluted with their own words —
    /// four of them, in the field round that found this.
    private func isMine(_ comment: RemoteComment) -> Bool {
        if comment.viewerDidAuthor { return true }
        if let me { return comment.author.caseInsensitiveCompare(me) == .orderedSame }
        return false
    }

    /// One reply from the asker's own login in an inline thread.
    public struct AskerReply: Sendable {
        public var comment: RemoteComment
        /// Posted after my last reply. `false` when I have not replied at all.
        public var isAfterMyLastReply: Bool
    }

    /// The replies in `thread` from the root's login that are not mine, oldest first.
    ///
    /// One definition for the audit, which decides on them, and for `contrib show`,
    /// which prints them: a state that rests on the asker's reply has to arrive with
    /// that reply, and two readings of "the asker" would let the two disagree.
    public func askerReplies(in thread: RemoteThread) -> [AskerReply] {
        guard let root = thread.root else { return [] }
        let lastMine = thread.replies.last(where: isMine)
        return thread.replies
            .filter { !isMine($0) && $0.author.caseInsensitiveCompare(root.author) == .orderedSame }
            .map { reply in
                AskerReply(
                    comment: reply,
                    isAfterMyLastReply: lastMine.map { reply.createdAt > $0.createdAt } ?? false)
            }
    }

    public func run(_ pr: PullRequestThreads, against previous: Snapshot?) -> Result {
        let closed = pr.isClosed
        let subject = Subject.format(repository: pr.repository, number: pr.number)
        var items: [InboundItem] = []
        var examined: [Channel: Int] = [:]
        var ownAuthored: [Channel: Int] = [:]
        var snapshot = previous ?? Snapshot(repository: pr.repository)
        snapshot.updatedAt = Date()

        // ---- channel 1: inline review threads -------------------------------------
        examined[.inlineThread] = pr.threads.count
        ownAuthored[.inlineThread] = 0
        for thread in pr.threads {
            guard let root = thread.root else { continue }
            guard !isMine(root) else {
                ownAuthored[.inlineThread, default: 0] += 1
                snapshot.authored.insert(root.id)
                continue
            }
            let replies = Array(thread.replies)
            let mine = replies.filter(isMine)
            for reply in mine { snapshot.authored.insert(reply.id) }
            let askerReplies = askerReplies(in: thread)

            // Display text is the stripped prose on every channel. An inline Devin
            // body opens with its marker and closes with a badge block, so the raw
            // slice led with an invisible HTML comment and pushed the finding title out
            // of view — a trial session routed every triage through `--json` because of
            // it.
            let rootProse = stripper.prose(of: root.body)

            // `informational` is deliberately NOT consulted here. An inline thread has
            // a reply relation, so its lifecycle is decidable without reading anything;
            // suppressing one on a marker can only ever hide a real ask, and did.
            let state: ItemState
            if let lastMine = mine.last {
                if askerReplies.contains(where: \.isAfterMyLastReply) {
                    state = .answeredConfirmed
                } else if let edited = root.lastEditedAt, edited > lastMine.createdAt {
                    state = .editedAfterMyAnswer
                } else if let check = previous?.entries[root.id]?.acknowledged,
                    check.bodySha256AtAck == root.bodySHA256,
                    check.replyIDAtAck == lastMine.id
                {
                    // Current only while it judged this ask and this reply. A new reply
                    // or an edited ask lists the thread again.
                    state = .answeredChecked
                } else {
                    state = .answeredClaimed
                }
            } else {
                state = .openAsk
            }

            let before = previous?.entries[root.id]?.state
            upsert(&snapshot, comment: root, myReply: mine.last, state: state, subject: subject)
            items.append(
                InboundItem(
                    id: root.id, kind: .inlineThread, permalink: root.permalink,
                    state: state, question: state.question,
                    changed: changeDescription(
                        for: root, previous: previous?.entries[root.id],
                        was: before, now: state,
                        previousProse: previous?.entries[root.id]?.prose),
                    text: .init(
                        ask: rootProse.isEmpty ? root.body : rootProse,
                        reply: mine.last.map { stripper.prose(of: $0.body) }),
                    roundID: root.reviewID, roundAt: root.createdAt, author: root.author,
                    previousState: before == state ? nil : before,
                    beyondHorizon: horizon.map { root.createdAt < $0 } ?? false,
                    isNewToSnapshot: previous?.entries[root.id] == nil,
                    subjectClosed: closed))
        }

        // ---- channels 2 and 3: review bodies, then issue comments -----------------
        // Review bodies go first: the channel that cannot be replied to is the one most
        // easily dropped, so it gets the most visible treatment (the Design article).
        for (channel, comments) in [
            (Channel.reviewBody, pr.reviewBodies), (Channel.issueComment, pr.issueComments),
        ] {
            examined[channel] = comments.count
            ownAuthored[channel] = 0
            for comment in comments {
                guard !isMine(comment) else {
                    ownAuthored[channel, default: 0] += 1
                    snapshot.authored.insert(comment.id)
                    continue
                }
                let stripped = stripper.strip(comment.body)
                let prose = stripped.prose
                // Marker lines flag collapsed sections for retrieval — they are
                // generated metadata, not the asker's words, and a marker's
                // embedded title can neither carry an ask nor retract one, so
                // the classifiers judge the substantive prose only. The marker
                // set is *provenance*: lines the author wrote in marker shape
                // stay prose, and markers a later boilerplate pass erased count
                // for nothing. A body of only surviving emitted markers is not
                // `no-prose` — that means *empty*; this is unexamined.
                let substantive = stripper.substantiveProse(
                    prose, markers: stripped.collapsedMarkers)
                let suppressible = stripped.collapsedMarkers.isEmpty
                // A line in marker SHAPE — literal ones survive
                // `substantiveProse` — is quoting the format: its embedded
                // title is never the reviewer's own opening statement, so it
                // cannot supply a retraction. But it IS authored text, so it
                // still counts for wholeness — dropping it must not leave a
                // fragment that whole-matches an informational announcement.
                // Hence: supersedes reads prose minus marker-shaped lines
                // (`contains` on opening lines — removal can only remove a
                // phrase), while informational reads `substantive` whole.
                let classifierProse = substantive
                    .components(separatedBy: .newlines)
                    .filter {
                        !BoilerplateStripper.isCollapsedMarker(
                            $0.trimmingCharacters(in: .whitespaces))
                    }
                    .joined(separator: "\n")
                let state: ItemState
                if substantive.isEmpty {
                    if stripped.collapsedMarkers.isEmpty {
                        state = .noProse
                    } else if let ack = previous?.entries[comment.id]?.acknowledged,
                        ack.bodySha256AtAck == comment.bodySHA256
                    {
                        state = .obligationAcknowledged
                    } else {
                        state = .collapsedUnexamined
                    }
                } else if suppressible, supersession.supersedes(classifierProse) != nil {
                    state = .superseded
                } else if suppressible,
                    informational.isInformational(raw: comment.body, prose: substantive) != nil
                {
                    state = .informational
                } else if let ack = previous?.entries[comment.id]?.acknowledged {
                    state =
                        ack.bodySha256AtAck == comment.bodySHA256
                        ? .obligationAcknowledged : .reopenedByEdit
                } else {
                    state = .obligationOpen
                }
                let before = previous?.entries[comment.id]?.state
                upsert(&snapshot, comment: comment, myReply: nil, state: state, subject: subject)
                items.append(
                    InboundItem(
                        id: comment.id, kind: channel, permalink: comment.permalink,
                        state: state, question: state.question,
                        changed: changeDescription(
                            for: comment, previous: previous?.entries[comment.id],
                            was: before, now: state,
                            previousProse: previous?.entries[comment.id]?.prose),
                        text: .init(ask: prose.isEmpty ? comment.body : prose, reply: nil),
                        roundID: nil, roundAt: comment.createdAt, author: comment.author,
                        previousState: before == state ? nil : before,
                        beyondHorizon: horizon.map { comment.createdAt < $0 } ?? false,
                        isNewToSnapshot: previous?.entries[comment.id] == nil,
                        subjectClosed: closed))
            }
        }

        // Ids this subject had last run, minus the ones it still has. Authored ids are
        // excluded: our own comments are recorded as authored, never as items.
        let seen = Set(items.map(\.id)).union(snapshot.authored)
        let vanished =
            (previous?.entries ?? [:])
            .filter { $0.value.subject == subject && !seen.contains($0.key) }
            .keys.sorted()

        return Result(
            items: items, examined: examined, ownAuthored: ownAuthored,
            updatedSnapshot: snapshot, vanished: vanished)
    }

    /// `nil` when the snapshot had it and nothing moved — the majority of items on any
    /// round after the first, and the reason this is a differ and not a reporter.
    ///
    /// **A state transition counts as movement.** Comparing bodies alone means the run
    /// straight after a round of replies reports "nothing moved", which is true of what
    /// the snapshot tracks and false of what a contributor tracks.
    private func changeDescription(
        for comment: RemoteComment, previous: Snapshot.Entry?,
        was: ItemState?, now: ItemState, previousProse: String?
    ) -> String? {
        guard let previous else { return "new since the last run" }

        var parts: [String] = []
        if let was, was != now {
            parts.append("\(was.rawValue) → \(now.rawValue)")
        }
        if previous.bodySha256 != comment.bodySHA256 {
            let when = comment.lastEditedAt.map { " (edited \(GitHubTime.string($0)))" } ?? ""
            // Whether the *prose* moved is decidable, and worth saying: this reviewer
            // appends its badge to a body when a later round supersedes it, so a whole
            // round's threads can re-open at once for no semantic reason. Observed twice
            // in one morning on one thread. The item is still re-opened and a stale
            // check is still refused — today's behaviour is wrong in the cheap
            // direction, and hashing stripped prose instead would be wrong in the
            // expensive one — but the contributor is told which kind of edit it was.
            let proseMoved = stripper.prose(of: comment.body) != previousProse
            parts.append(
                "body changed since the last run\(when)"
                    + (proseMoved ? "" : " — markup only, prose unchanged"))
        } else if previous.acknowledged != nil,
            previous.acknowledged?.bodySha256AtAck != comment.bodySHA256
        {
            // Same annotation as the branch above: a reviewer that re-appends its badge
            // re-opens an acknowledged item for no semantic reason, and the contributor
            // should be told which kind of edit it was before re-reading.
            let proseMoved = stripper.prose(of: comment.body) != previousProse
            parts.append(
                "edited after it was acknowledged"
                    + (proseMoved ? "" : " — markup only, prose unchanged"))
        } else if now == .editedAfterMyAnswer {
            // `lastEditedAt` bumped and the body is byte-identical — the strongest
            // form of the same signal: not even markup moved. Without this the line
            // reads as a plain `→ edited-after-my-answer` transition, which is the
            // urgent-looking version of a no-op.
            parts.append("edited after your reply — body unchanged")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func upsert(
        _ snapshot: inout Snapshot, comment: RemoteComment, myReply: RemoteComment?,
        state: ItemState, subject: String
    ) {
        var entry =
            snapshot.entries[comment.id]
            ?? Snapshot.Entry(
                kind: comment.channel, url: comment.permalink, author: comment.author,
                createdAt: comment.createdAt, updatedAt: comment.updatedAt,
                lastEditedAt: comment.lastEditedAt, bodySha256: comment.bodySHA256,
                state: nil, firstSeen: Date(), myReplyID: nil, myReplyAt: nil,
                acknowledged: nil)
        entry.updatedAt = comment.updatedAt
        entry.lastEditedAt = comment.lastEditedAt
        entry.bodySha256 = comment.bodySHA256
        entry.prose = stripper.prose(of: comment.body)
        entry.myReplyID = myReply?.id ?? entry.myReplyID
        entry.myReplyAt = myReply?.createdAt ?? entry.myReplyAt
        entry.state = state
        entry.subject = subject
        snapshot.entries[comment.id] = entry
    }

}

extension InboundAudit {
    /// The audit every command builds the same way: this repository's inbound rules,
    /// no more and no less. One construction site means `in`, `ack --refresh` and
    /// `show` cannot quietly disagree on what an item means.
    public init(configuration: Configuration, me: String?) throws {
        self.init(
            me: me,
            stripper: try BoilerplateStripper(settings: configuration.inbound),
            supersession: SupersessionDetector(
                phrases: configuration.inbound.supersessionPhrases),
            informational: try InformationalDetector(
                patterns: configuration.inbound.informationalPatterns),
            horizon: try configuration.inbound.horizonDate())
    }
}

extension Snapshot {
    /// Apply one audit's subject to this snapshot, leaving every other subject alone.
    ///
    /// The snapshot is per repository and the audit is per subject: `entries` in the
    /// result covers the fetched subject plus a stale copy of everything else, so the
    /// subject filter is the load-bearing line — an unscoped write would erase the
    /// other pull requests' state. Shared by `contrib in` and `ack --refresh` so the
    /// two cannot drift.
    public mutating func merge(_ result: InboundAudit.Result, forSubject subject: String) {
        for (id, entry) in result.updatedSnapshot.entries where entry.subject == subject {
            entries[id] = entry
        }
        authored.formUnion(result.updatedSnapshot.authored)
        updatedAt = Date()
    }
}
