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

    public init(
        me: String?, stripper: BoilerplateStripper, supersession: SupersessionDetector
    ) {
        self.me = me
        self.stripper = stripper
        self.supersession = supersession
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

        public var owed: [InboundItem] { items.filter(\.state.isOwed) }

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
                continue
            }
            let replies = Array(thread.replies)
            let mine = replies.filter(isMine)
            let askerReplies = replies.filter {
                !isMine($0) && $0.author.caseInsensitiveCompare(root.author) == .orderedSame
            }

            let state: ItemState
            if let lastMine = mine.last {
                if askerReplies.contains(where: { $0.createdAt > lastMine.createdAt }) {
                    state = .answeredConfirmed
                } else if let edited = root.lastEditedAt, edited > lastMine.createdAt {
                    state = .editedAfterMyAnswer
                } else {
                    state = .answeredClaimed
                }
            } else {
                state = .openAsk
            }

            upsert(&snapshot, comment: root, myReply: mine.last)
            items.append(
                InboundItem(
                    id: root.id, kind: .inlineThread, permalink: root.permalink,
                    state: state, question: state.question,
                    changed: changeDescription(for: root, previous: previous?.entries[root.id]),
                    text: .init(ask: excerpt(root.body), reply: mine.last.map { excerpt($0.body) }),
                    roundID: root.reviewID, roundAt: root.createdAt, author: root.author))
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
                    continue
                }
                let prose = stripper.prose(of: comment.body)
                let state: ItemState
                if prose.isEmpty {
                    state = .noProse
                } else if supersession.supersedes(prose) != nil {
                    state = .superseded
                } else if let ack = previous?.entries[comment.id]?.acknowledged {
                    state =
                        ack.bodySha256AtAck == comment.bodySHA256
                        ? .obligationAcknowledged : .reopenedByEdit
                } else {
                    state = .obligationOpen
                }
                upsert(&snapshot, comment: comment, myReply: nil)
                items.append(
                    InboundItem(
                        id: comment.id, kind: channel, permalink: comment.permalink,
                        state: state, question: state.question,
                        changed: changeDescription(
                            for: comment, previous: previous?.entries[comment.id]),
                        text: .init(ask: excerpt(prose.isEmpty ? comment.body : prose), reply: nil),
                        roundID: nil, roundAt: comment.createdAt, author: comment.author))
            }
        }

        return Result(
            items: items, examined: examined, ownAuthored: ownAuthored,
            updatedSnapshot: snapshot)
    }

    /// `nil` when the snapshot had it and nothing moved — the majority of items on any
    /// round after the first, and the reason this is a differ and not a reporter.
    private func changeDescription(for comment: RemoteComment, previous: Snapshot.Entry?)
        -> String?
    {
        guard let previous else { return "new since the last run" }
        if previous.bodySha256 != comment.bodySHA256 {
            let when = comment.lastEditedAt.map { " (edited \(GitHubTime.string($0)))" } ?? ""
            return "body changed since the last run\(when)"
        }
        if previous.acknowledged != nil, previous.acknowledged?.bodySha256AtAck != comment.bodySHA256
        {
            return "edited after it was acknowledged"
        }
        return nil
    }

    private func upsert(
        _ snapshot: inout Snapshot, comment: RemoteComment, myReply: RemoteComment?
    ) {
        var entry =
            snapshot.entries[comment.id]
            ?? Snapshot.Entry(
                kind: comment.channel, url: comment.permalink, author: comment.author,
                createdAt: comment.createdAt, updatedAt: comment.updatedAt,
                lastEditedAt: comment.lastEditedAt, bodySha256: comment.bodySHA256,
                firstSeen: Date(), myReplyID: nil, myReplyAt: nil, acknowledged: nil)
        entry.updatedAt = comment.updatedAt
        entry.lastEditedAt = comment.lastEditedAt
        entry.bodySha256 = comment.bodySHA256
        entry.myReplyID = myReply?.id ?? entry.myReplyID
        entry.myReplyAt = myReply?.createdAt ?? entry.myReplyAt
        snapshot.entries[comment.id] = entry
    }

    /// The minimum text §13.3 allows: enough to answer the question, not enough to
    /// re-enumerate from.
    private func excerpt(_ body: String, limit: Int = 400) -> String {
        let collapsed = body.replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
