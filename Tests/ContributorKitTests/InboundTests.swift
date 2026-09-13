import Foundation
import Testing

@testable import ContributorKit

/// `contrib in` against the thread fixtures — TASK §12, and the four gaps two live
/// review rounds exposed in the field report.
@Suite("contrib in — three channels, obligations, and the differ")
struct InboundTests {

    // MARK: - The positive and negative cases the definition of done names

    /// #5233 is the positive case. Its two open inline threads — `3948887913` and
    /// `3948887920` — are a use-after-free on OpenSSL below 3.0 that was taking down
    /// two Windows CI jobs, and a doc gap on ownership. Neither was known beforehand;
    /// nothing about the diff would have surfaced either.
    @Test("#5233 positive: two open inline asks, by id")
    func positiveCaseInline() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        let open = result.items.filter { $0.kind == .inlineThread && $0.state == .openAsk }
        #expect(
            open.map(\.id).sorted() == ["discussion_r3948887913", "discussion_r3948887920"])
        #expect(result.examined[.inlineThread] == 24)
        #expect(result.count(of: .answeredClaimed, in: .inlineThread) == 22)
    }

    /// **All three channels, on one PR.** The inline channel is 2 open; the review-body
    /// channel is 8 open obligations, because a review body cannot be replied to and
    /// none of them carries a recorded acknowledgement yet (§12.10). That is the
    /// capability working, not a false positive: the two historical #5233 misses were
    /// both review bodies, and an inline-only run reports this PR as two items rather
    /// than ten.
    @Test("#5233 positive: three channels give ten owed items, not two")
    func positiveCaseAllChannels() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.inlineThread] == 24)
        #expect(result.examined[.reviewBody] == 8)
        #expect(result.examined[.issueComment] == 5)

        #expect(result.count(of: .openAsk, in: .inlineThread) == 2)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 8)
        // Every issue comment on #5233 is ours, so none is an obligation against us.
        #expect(result.ownAuthored[.issueComment] == 5)
        #expect(result.count(of: .obligationOpen, in: .issueComment) == 0)

        #expect(result.owed.count == 10)
    }

    /// #5234 is the negative case in the two channels §12.7 measured — and a real one:
    /// every review there carried inline comments with an empty body, so
    /// `pr-5234.reviews.json` is `[]`. A tool that only read review bodies would report
    /// nothing at all for this PR.
    @Test("#5234 negative: no open inline asks, and no review bodies at all")
    func negativeCase() throws {
        let pr = try Fixtures.threads(pr: 5234)
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.inlineThread] == 10)
        #expect(result.count(of: .openAsk, in: .inlineThread) == 0)
        #expect(result.examined[.reviewBody] == 0)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 0)
    }

    /// The third channel is not empty on #5234, and saying so is the point. One of its
    /// two issue comments is the maintainer's; under §12.10 that is an obligation until
    /// something is recorded against it, and the CLI does not get to decide whether it
    /// is "really" an ask — that is the meaning question it hands to the model.
    @Test("#5234: the issue-comment channel carries one obligation, ours excluded")
    func negativeCaseIssueComments() throws {
        let pr = try Fixtures.threads(pr: 5234)
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.issueComment] == 2)
        #expect(result.ownAuthored[.issueComment] == 1)
        let open = result.items.filter {
            $0.kind == .issueComment && $0.state == .obligationOpen
        }
        #expect(open.count == 1)
        #expect(open.first?.author == "sauwming")
        #expect(result.owed.count == 1)
    }

    // MARK: - Gap 2.1: authorship filtering

    /// GitHub records a reply submitted through the review API as a review, so on any
    /// PR where the contributor replies, an unfiltered obligation list is immediately
    /// polluted with their own words. `pr-5233.selfreply.reviews.json` is the captured
    /// eight plus one derived record authored by us.
    @Test("a review body I wrote is never an obligation against me")
    func ownReviewBodyIsNotAnObligation() throws {
        let pr = try Fixtures.threads(
            pr: 5233, comments: "pr-5233.positive.comments.json",
            reviews: "pr-5233.selfreply.reviews.json")
        let result = try Fixtures.audit().run(pr, against: nil)

        #expect(result.examined[.reviewBody] == 9, "all nine are examined and counted")
        #expect(result.ownAuthored[.reviewBody] == 1, "one of them is mine")
        #expect(
            result.count(of: .obligationOpen, in: .reviewBody) == 8,
            "and only the other eight are owed")
        #expect(!result.items.contains { $0.id == "pullrequestreview-5130977999" })
    }

    /// The same filter, with no `--me` and no `viewerDidAuthor`: nothing is mine, so
    /// everything is owed. This is what the unfiltered list looks like, pinned so the
    /// filter cannot quietly stop working.
    @Test("without an author filter the same fixture yields nine obligations")
    func withoutAuthorFilterEverythingIsOwed() throws {
        let pr = try Fixtures.threads(
            pr: 5233, comments: "pr-5233.positive.comments.json",
            reviews: "pr-5233.selfreply.reviews.json", me: "nobody")
        let result = try Fixtures.audit(me: nil).run(pr, against: nil)
        #expect(result.count(of: .obligationOpen, in: .reviewBody) == 9)
    }

    // MARK: - Gap 2.2: empty review bodies are the common case

    /// Four of six bodies in the field round were badge markup only. Counted in the
    /// examined total so the count stays honest; excluded from the worklist, because
    /// §12.3 rule 4's argument for noise over silence does not extend to noise that is
    /// definitionally empty.
    @Test("a badge-only review body is counted but not owed")
    func boilerplateOnlyBodyIsNotOwed() throws {
        let config = try Configuration.builtInDefaults()
        let stripper = try BoilerplateStripper(settings: config.inbound)

        let badgeOnly = """
            <!-- devin-review-badge -->
            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="https://example.invalid/d.svg">
              <img src="https://example.invalid/l.svg">
            </picture>

            ---
            """
        #expect(stripper.prose(of: badgeOnly).isEmpty)
        #expect(!stripper.prose(of: badgeOnly + "\nOne real sentence.").isEmpty)
    }

    @Test("an unclosed boilerplate opener swallows the rest rather than leaking it")
    func unclosedBoilerplateBlock() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        #expect(stripper.prose(of: "Real prose.\n<!-- never closed").trimmed == "Real prose.")
    }

    // MARK: - The reviewer's own kind marker

    /// **Reading the asker's declared `kind` is not deciding a meaning question.** Devin
    /// Review opens every inline body with a machine-readable marker, and the two kinds
    /// it emits are `bug` (a finding) and `analysis` (a 📝 Info receipt). Taking the
    /// asker at their word is the same move supersession makes.
    ///
    /// The markers below are the real thing, copied from
    /// `laconicman/YandexDeliveryExpress#3`.
    @Test("a reviewer-declared analysis note is not owed; a declared bug is")
    func declaredKindIsHonoured() throws {
        let config = try Configuration.builtInDefaults()
        let detector = try InformationalDetector(
            patterns: config.inbound.informationalPatterns)
        let stripper = try BoilerplateStripper(settings: config.inbound)

        let analysis = """
            <!-- devin-review-comment {"id": "ANALYSIS_pr-review-job-8092f8_0001",             "file_path": "Tests/SampleData.swift", "kind": "analysis"} -->

            📝 **Info: Bridge init field/order match verified**

            The test-side init forwards all 17 fields.
            """
        let bug = analysis
            .replacingOccurrences(of: "\"kind\": \"analysis\"", with: "\"kind\": \"bug\"")

        #expect(detector.isInformational(raw: analysis, prose: stripper.prose(of: analysis)) != nil)
        #expect(detector.isInformational(raw: bug, prose: stripper.prose(of: bug)) == nil)
        #expect(ItemState.informational.isOwed == false)
    }

    /// A bot's run announcement is a fixed phrase, and the only prose left once the
    /// badge is stripped. Matched against the stripped prose rather than the raw body.
    @Test("a bot run announcement is informational, not an obligation")
    func botAnnouncementIsInformational() throws {
        let config = try Configuration.builtInDefaults()
        let detector = try InformationalDetector(
            patterns: config.inbound.informationalPatterns)
        let stripper = try BoilerplateStripper(settings: config.inbound)

        let announcement = """
            Starting Devin Review.

            <!-- devin-review-badge-begin -->
            <a href="https://app.devin.ai/review/o/r/pull/3" target="_blank">
              <picture>
                <img src="https://static.devin.ai/assets/gh-devin-review-light.svg?v=3">
              </picture>
            </a>
            <!-- devin-review-badge-end -->
            """
        let prose = stripper.prose(of: announcement)
        #expect(prose == "Starting Devin Review.")
        #expect(detector.isInformational(raw: announcement, prose: prose) != nil)
    }

    /// **Paired markers must be stripped before generic HTML comments.** Removing
    /// `<!--…-->` first destroys the begin/end pairing and leaves the wrapped block
    /// behind — a bare `<a href=…>` / `</a>` trailing every excerpt, which is what sent
    /// a trial session through `--json` for every single triage.
    @Test("the badge block is removed whole, leaving no anchor residue")
    func badgeBlockLeavesNoResidue() throws {
        let stripper = try BoilerplateStripper(
            settings: try Configuration.builtInDefaults().inbound)
        let body = """
            **Devin Review** found 1 new potential issue.

            <!-- devin-review-badge-begin -->
            <a href="https://app.devin.ai/review/o/r/pull/3" target="_blank">
              <picture>
                <source media="(prefers-color-scheme: dark)" srcset="https://x/d.svg">
                <img src="https://x/l.svg" alt="Devin Review">
              </picture>
            </a>
            <!-- devin-review-badge-end -->
            """
        #expect(stripper.prose(of: body) == "**Devin Review** found 1 new potential issue.")
    }

    /// The finding title must lead the excerpt. An inline Devin body opens with its
    /// marker, so the raw slice showed an invisible HTML comment and pushed the title
    /// out of view.
    @Test("an inline ask's text leads with the finding, not the marker")
    func inlineAskLeadsWithTheFinding() throws {
        let raw = """
            <!-- devin-review-comment {"id": "BUG_pr-review-job-295bbd", "kind": "bug"} -->

            🔴 **Interrupted sync skips new pages**

            After one incremental page, `commitPage` clears `backfillComplete`.
            """
        let root = RemoteComment(
            id: "discussion_r1", channel: .inlineThread, author: "devin-ai-integration",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: raw, permalink: "https://github.com/o/r/pull/1#discussion_r1")

        let result = try Fixtures.audit().run(
            pullRequest(threads: [RemoteThread(comments: [root])]), against: nil)
        let ask = try #require(result.items.first?.text.ask)
        #expect(ask.hasPrefix("🔴 **Interrupted sync skips new pages**"))
        #expect(!ask.contains("devin-review-comment"))
        #expect(result.items.first?.state == .openAsk, "a declared bug is still owed")
    }

    // MARK: - Gap 2.3: supersession

    /// A reviewer can retract an obligation. Without this, §12.10's never-auto-cleared
    /// rule holds open an ask the asker has themselves withdrawn — forever.
    @Test("a retracted review body is superseded, not owed")
    func supersededBodyIsNotOwed() throws {
        let config = try Configuration.builtInDefaults()
        let detector = SupersessionDetector(phrases: config.inbound.supersessionPhrases)
        let retraction =
            "**This report is out of date.** Scroll down for the latest report on this PR."
        #expect(detector.supersedes(retraction) == "this report is out of date")
        #expect(detector.supersedes("Please apply this to sip_transport_tcp.c too.") == nil)
        #expect(ItemState.superseded.isOwed == false)
    }

    // MARK: - Gap 2.4: acknowledgement by the asker

    /// The asker replying in the thread, describing the fix in their own words, is
    /// better evidence than our own claim to have fixed something — it is the asker
    /// confirming the answer. Not an inference from proximity: §4.6's rule is about
    /// inferring acceptance from *timing*, and this is the asker speaking.
    ///
    /// No current fixture contains one, so this is constructed. Said plainly rather
    /// than left to be discovered.
    @Test("the asker's own reply after mine clears the thread; mine alone only claims")
    func askerConfirmationBeatsMyClaim() throws {
        func thread(withAskerReply: Bool) -> RemoteThread {
            var comments = [
                comment("discussion_r1", "sauwming", at: 0),
                comment("discussion_r2", "laconicman", at: 10),
            ]
            if withAskerReply {
                comments.append(comment("discussion_r3", "sauwming", at: 20))
            }
            return RemoteThread(comments: comments)
        }

        let claimed = try Fixtures.audit().run(
            pullRequest(threads: [thread(withAskerReply: false)]), against: nil)
        #expect(claimed.items.first?.state == .answeredClaimed)
        #expect(claimed.items.first?.state.isOwed == false)

        let confirmed = try Fixtures.audit().run(
            pullRequest(threads: [thread(withAskerReply: true)]), against: nil)
        #expect(confirmed.items.first?.state == .answeredConfirmed)
    }

    /// §13.4's sharpest check, and free given the snapshot:
    /// `lastEditedAt > myReplyAt` means the ask was edited after I answered it.
    @Test("an ask edited after my answer re-opens as its own state")
    func editedAfterMyAnswer() throws {
        var root = comment("discussion_r1", "sauwming", at: 0)
        root.lastEditedAt = Date(timeIntervalSince1970: 30)
        let thread = RemoteThread(comments: [root, comment("discussion_r2", "laconicman", at: 10)])

        let result = try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
        #expect(result.items.first?.state == .editedAfterMyAnswer)
        #expect(result.items.first?.state.isOwed == true)
    }

    // MARK: - The differ

    /// §13's "since the last iteration" is the load-bearing piece. Without
    /// round-over-round state, a second round re-lists everything already answered.
    @Test("a second run reports only what moved")
    func secondRunReportsOnlyTheDelta() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let first = try Fixtures.audit().run(pr, against: nil)
        #expect(first.items.allSatisfy { $0.changed == "new since the last run" })

        let second = try Fixtures.audit().run(pr, against: first.updatedSnapshot)
        #expect(second.items.allSatisfy { $0.changed == nil })
        // The worklist is unchanged — a differ reports the delta, it does not forget
        // what is still owed.
        #expect(second.owed.count == first.owed.count)
    }

    /// **A state transition is movement.** Comparing bodies alone means the run straight
    /// after a round of replies reports "nothing moved" — true of what the snapshot
    /// tracks, false of what a contributor tracks. Reported from a live trial: six
    /// threads answered and one obligation acknowledged, and the next run said nothing
    /// had changed.
    @Test("answering a thread shows up as a transition on the next run")
    func stateTransitionsAreMovement() throws {
        let root = comment("discussion_r1", "sauwming", at: 0)
        let unanswered = RemoteThread(comments: [root])
        let answered = RemoteThread(
            comments: [root, comment("discussion_r2", "laconicman", at: 10)])

        let first = try Fixtures.audit().run(
            pullRequest(threads: [unanswered]), against: nil)
        #expect(first.items.first?.state == .openAsk)

        // Nothing changed at all: no transition, no movement.
        let stable = try Fixtures.audit().run(
            pullRequest(threads: [unanswered]), against: first.updatedSnapshot)
        #expect(stable.items.first?.changed == nil)
        #expect(stable.items.first?.previousState == nil)

        // Now I reply. The body did not change; the state did.
        let moved = try Fixtures.audit().run(
            pullRequest(threads: [answered]), against: first.updatedSnapshot)
        #expect(moved.items.first?.state == .answeredClaimed)
        #expect(moved.items.first?.previousState == .openAsk)
        #expect(moved.items.first?.changed == "open-ask → answered-claimed")
        // And it is visible, even though it is no longer owed — which is the run in
        // which "is my reply actually responsive?" is worth asking.
        #expect(moved.items.first?.state.isOwed == false)
        #expect(moved.items.contains { $0.changed != nil })
    }

    /// An acknowledgement is a transition too, and it was the other half of the same
    /// silent run.
    @Test("acknowledging an obligation shows up as a transition")
    func acknowledgementIsATransition() throws {
        let body = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "devin",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        var snapshot = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: nil
        ).updatedSnapshot
        snapshot.entries["pullrequestreview-1"]?.acknowledged = Acknowledgement(
            kind: .commit, pointer: "1da04eb", bodySha256AtAck: body.bodySHA256,
            verified: true, verificationNote: "test")

        let after = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: snapshot)
        #expect(after.items.first?.state == .obligationAcknowledged)
        #expect(after.items.first?.changed == "obligation-open → obligation-acknowledged")
    }

    /// **The `--json` ask must be answerable from the JSON.** It was truncated at 400
    /// characters, so every round-3 ask in the live trial ended mid-sentence and the
    /// session had to re-fetch bodies with `gh api` — which is the re-enumeration the
    /// machine contract exists to eliminate. Terminal display still truncates; the
    /// contract does not.
    @Test("the ask is carried whole, not sliced")
    func askIsNotTruncated() throws {
        let long = String(repeating: "A resumed backfill loses the newest watermark. ", count: 40)
        #expect(long.count > 400)
        let body = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "devin",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: long, permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        let result = try Fixtures.audit().run(
            pullRequest(reviewBodies: [body]), against: nil)
        // A review body's ask is the *stripped* prose — badge markup should not pad the
        // contract — so it is trimmed, but never sliced.
        #expect(result.items.first?.text.ask == long.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(result.items.first?.text.ask.hasSuffix("…") == false)
        #expect((result.items.first?.text.ask.count ?? 0) > 400)
    }

    /// The record is keyed by comment id **and** body hash, so an edit after
    /// acknowledgement re-opens the item by itself. For review bodies the hash is not
    /// an optimisation — it is the only mechanism REST leaves available.
    @Test("an acknowledged review body re-opens when its body is edited")
    func acknowledgementIsKeyedByHash() throws {
        let original = RemoteComment(
            id: "pullrequestreview-1", channel: .reviewBody, author: "sauwming",
            viewerDidAuthor: false, createdAt: Date(timeIntervalSince1970: 0),
            body: "Please add a regression test.",
            permalink: "https://github.com/o/r/pull/1#pullrequestreview-1")

        var snapshot = try Fixtures.audit().run(
            pullRequest(reviewBodies: [original]), against: nil
        ).updatedSnapshot
        snapshot.entries["pullrequestreview-1"]?.acknowledged = Acknowledgement(
            kind: .commit, pointer: "e02b93e1", bodySha256AtAck: original.bodySHA256,
            verified: true, verificationNote: "test")

        let unchanged = try Fixtures.audit().run(
            pullRequest(reviewBodies: [original]), against: snapshot)
        #expect(unchanged.items.first?.state == .obligationAcknowledged)
        #expect(unchanged.owed.isEmpty)

        var edited = original
        edited.body = "Please add a regression test — and one for the TCP path too."
        let reopened = try Fixtures.audit().run(
            pullRequest(reviewBodies: [edited]), against: snapshot)
        #expect(reopened.items.first?.state == .reopenedByEdit)
        #expect(reopened.owed.count == 1)
    }

    /// Root comments only — a reply inside a thread is not a new ask (§12.2).
    @Test("replies inside a thread are never counted as roots")
    func repliesAreNotRoots() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        #expect(pr.threads.count == 24)
        #expect(pr.threads.reduce(0) { $0 + $1.comments.count } == 46)
        #expect(pr.threads.allSatisfy { $0.root?.author == "sauwming" })
    }

    /// Rounds are unevenly sized — #5233's carry 2, 4, 5, 5, 3, 2, 2 and 1 threads.
    /// Grouping by review is therefore not cosmetic; a flat list of 24 loses which
    /// round is open (§12.4).
    @Test("threads group into the rounds that carried them")
    func roundGrouping() throws {
        let pr = try Fixtures.threads(pr: 5233, comments: "pr-5233.positive.comments.json")
        let result = try Fixtures.audit().run(pr, against: nil)
        let rounds = Dictionary(grouping: result.items.filter { $0.kind == .inlineThread }) {
            $0.roundID ?? "—"
        }
        let expected = try Fixtures.threadsManifest().prs["5233"]?.rounds
        #expect(rounds.count == expected?.count)
        for (review, size) in expected ?? [:] {
            #expect(rounds[review]?.count == size, "round \(review)")
        }
    }

    // MARK: - Helpers

    private func comment(_ id: String, _ author: String, at seconds: TimeInterval)
        -> RemoteComment
    {
        RemoteComment(
            id: id, channel: .inlineThread, author: author, viewerDidAuthor: false,
            createdAt: Date(timeIntervalSince1970: seconds),
            body: "body of \(id)", permalink: "https://github.com/o/r/pull/1#\(id)")
    }

    private func pullRequest(
        threads: [RemoteThread] = [], reviewBodies: [RemoteComment] = []
    ) -> PullRequestThreads {
        PullRequestThreads(
            repository: "o/r", number: 1, title: "t", url: "u", state: "OPEN",
            isMerged: false, threads: threads, reviewBodies: reviewBodies,
            issueComments: [], pagesFetched: 1)
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
