import Foundation

/// `contrib in` — *what was asked of me that I have not demonstrably absorbed?*
///
/// Three channels, not one (TASK §12.3 rule 1). Inline review comments, review
/// **bodies**, and issue comments. A run that skips review bodies reproduces the
/// original bug: on #5233 the same ask was raised in review bodies on 09-02, 09-03 and
/// 09-04 and missed every time, because only inline comments were being read — the
/// fourth time by an audit script written specifically to prevent the first failure.
///
/// The set arithmetic in §12.2 applies to channel 1 only, and is deliberately **not**
/// extended to the other two: *"a review body is answered if I posted any top-level
/// comment after it"* is row 1 of §12.10's rejection table, a silent false negative.
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
        /// found. §12.3 rule 4, and the difference between "0 issue comments" as a
        /// fact and as an assumption.
        public var examined: [Channel: Int]
        /// How many of those were **mine**, per channel, and therefore never
        /// obligations against me. Counted rather than silently dropped: an unfiltered
        /// list flags the contributor's own replies as new asks, and printing the
        /// number is what makes the filter visible instead of assumed.
        public var ownAuthored: [Channel: Int]
        public var updatedSnapshot: Snapshot

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

    public func run(_ pr: PullRequestThreads, against previous: Snapshot?) -> Result {
        let closed = pr.isClosed
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
            let askerReplies = replies.filter {
                !isMine($0) && $0.author.caseInsensitiveCompare(root.author) == .orderedSame
            }

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
                if askerReplies.contains(where: { $0.createdAt > lastMine.createdAt }) {
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
            upsert(&snapshot, comment: root, myReply: mine.last, state: state)
            items.append(
                InboundItem(
                    id: root.id, kind: .inlineThread, permalink: root.permalink,
                    state: state, question: state.question,
                    changed: changeDescription(
                        for: root, previous: previous?.entries[root.id],
                        was: before, now: state),
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
        // easily dropped, so it gets the most visible treatment (§12.10).
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
                let prose = stripper.prose(of: comment.body)
                let state: ItemState
                if prose.isEmpty {
                    state = .noProse
                } else if supersession.supersedes(prose) != nil {
                    state = .superseded
                } else if informational.isInformational(raw: comment.body, prose: prose) != nil {
                    state = .informational
                } else if let ack = previous?.entries[comment.id]?.acknowledged {
                    state =
                        ack.bodySha256AtAck == comment.bodySHA256
                        ? .obligationAcknowledged : .reopenedByEdit
                } else {
                    state = .obligationOpen
                }
                let before = previous?.entries[comment.id]?.state
                upsert(&snapshot, comment: comment, myReply: nil, state: state)
                items.append(
                    InboundItem(
                        id: comment.id, kind: channel, permalink: comment.permalink,
                        state: state, question: state.question,
                        changed: changeDescription(
                            for: comment, previous: previous?.entries[comment.id],
                            was: before, now: state),
                        text: .init(ask: prose.isEmpty ? comment.body : prose, reply: nil),
                        roundID: nil, roundAt: comment.createdAt, author: comment.author,
                        previousState: before == state ? nil : before,
                        beyondHorizon: horizon.map { comment.createdAt < $0 } ?? false,
                        isNewToSnapshot: previous?.entries[comment.id] == nil,
                        subjectClosed: closed))
            }
        }

        return Result(
            items: items, examined: examined, ownAuthored: ownAuthored,
            updatedSnapshot: snapshot)
    }

    /// `nil` when the snapshot had it and nothing moved — the majority of items on any
    /// round after the first, and the reason this is a differ and not a reporter.
    ///
    /// **A state transition counts as movement.** Comparing bodies alone means the run
    /// straight after a round of replies reports "nothing moved", which is true of what
    /// the snapshot tracks and false of what a contributor tracks.
    private func changeDescription(
        for comment: RemoteComment, previous: Snapshot.Entry?,
        was: ItemState?, now: ItemState
    ) -> String? {
        guard let previous else { return "new since the last run" }

        var parts: [String] = []
        if let was, was != now {
            parts.append("\(was.rawValue) → \(now.rawValue)")
        }
        if previous.bodySha256 != comment.bodySHA256 {
            let when = comment.lastEditedAt.map { " (edited \(GitHubTime.string($0)))" } ?? ""
            parts.append("body changed since the last run\(when)")
        } else if previous.acknowledged != nil,
            previous.acknowledged?.bodySha256AtAck != comment.bodySHA256
        {
            parts.append("edited after it was acknowledged")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func upsert(
        _ snapshot: inout Snapshot, comment: RemoteComment, myReply: RemoteComment?,
        state: ItemState
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
        entry.myReplyID = myReply?.id ?? entry.myReplyID
        entry.myReplyAt = myReply?.createdAt ?? entry.myReplyAt
        entry.state = state
        snapshot.entries[comment.id] = entry
    }

}
