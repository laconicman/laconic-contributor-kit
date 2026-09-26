import Foundation
import Testing

@testable import ContributorKit

/// Issue #7: 111 Devin Review threads on `laconicman/telegram-kb`, read twice — by
/// `contrib in` and by an independent GraphQL walk — and the cases where they disagreed.
///
/// Every thread here is a real one, cut verbatim into `Fixtures/resolution/` from the
/// capture that issue was written from. The shapes the data never produced are
/// constructed, and each says so.
@Suite("resolution — issue #7")
struct ResolutionTests {

    // MARK: - C: the asker's replies travel with the state

    /// Case 3: I replied "Fixed", and the reviewer's login then replied "Closed the
    /// remaining half of this in f7c1a98" — my fix had missed a path. `contrib show`
    /// printed my side only, so the reply the thread's state rested on was the one it
    /// left out.
    @Test("the asker's replies are read in order and placed against my last reply")
    func askerRepliesArePlaced() async throws {
        let correction = try #require(try await thread(pr: 3, "discussion_r4095575834"))
        let replies = try Fixtures.audit().askerReplies(in: correction)
        let late = try #require(replies.last)
        #expect(late.comment.body.hasPrefix("Closed the remaining half of this"))
        #expect(late.isAfterMyLastReply)
        #expect(!replies.contains { $0.comment.author == "laconicman" }, "mine are not the asker's")

        // Case 1: the verdict came first and my reply after it.
        let early = try #require(try await thread(pr: 1, "discussion_r4025099437"))
        let verdict = try #require(try Fixtures.audit().askerReplies(in: early).first)
        #expect(verdict.comment.body.hasPrefix("✅ **Resolved**:"))
        #expect(!verdict.isAfterMyLastReply)

        // Case 2: the asker's login replied and I never did — nothing is "after" mine.
        let session = try #require(try await thread(pr: 5, "discussion_r4098761481"))
        let sessionReplies = try Fixtures.audit().askerReplies(in: session)
        #expect(!sessionReplies.isEmpty)
        #expect(sessionReplies.allSatisfy { !$0.isAfterMyLastReply })
    }

    // MARK: - Resolution, reported and never decided on

    /// `ThreadDetail.graphql` fetched `resolvedBy` and the decode dropped it. The
    /// reviewer resolves as `devin-ai-integration[bot]` and comments as
    /// `devin-ai-integration`, so it is carried with the suffix removed — the one
    /// spelling that compares with the asker.
    @Test("resolvedBy survives decode with [bot] removed, and reaches the item")
    func resolvedByIsCarried() async throws {
        let raw = try JSONDecoder().decode(
            ThreadDetailResponse.self,
            from: try Fixtures.data("resolution/telegram-kb-pr-5.json"))
        let rawLogin = try #require(
            raw.data?.repository?.issueOrPullRequest?.reviewThreads?.nodes?.first?
                .resolvedBy?.login)
        #expect(rawLogin.hasSuffix("[bot]"), "the premise: the capture carries the suffix")

        let pr = try await Fixtures.resolution(pr: 5)
        let thread = try #require(pr.threads.first)
        let root = try #require(thread.root)
        #expect(thread.isResolved)
        #expect(thread.resolvedBy == Login.normalised(rawLogin))
        #expect(thread.resolvedBy == root.author)

        let item = try #require(
            try Fixtures.audit().run(pr, against: nil).items.first { $0.id == root.id })
        #expect(
            item.resolution
                == .init(isResolved: true, resolvedBy: root.author, byAsker: true))
    }

    /// A thread is resolved for more reasons than the asker's consent, so the flag is
    /// shown to the reader and read by no state. Flipping it on every captured thread
    /// must move nothing.
    @Test("no state reads the resolution")
    func resolutionDecidesNoState() async throws {
        for number in [1, 2, 3, 5, 6] {
            let pr = try await Fixtures.resolution(pr: number)
            var flipped = pr
            flipped.threads = pr.threads.map { thread in
                var thread = thread
                thread.isResolved.toggle()
                thread.resolvedBy = thread.isResolved ? "someone-else" : nil
                return thread
            }
            let states = try Fixtures.audit().run(pr, against: nil).items.map(\.state)
            let flippedStates = try Fixtures.audit().run(flipped, against: nil).items.map(\.state)
            #expect(!states.isEmpty, "#\(number) examined something")
            #expect(states == flippedStates, "#\(number)")
        }
    }

    /// The table names who resolved a thread, so a resolution by the asker reads
    /// differently from one by me or by a maintainer.
    @Test("the table says whether, and by whom, a thread was resolved")
    func resolutionNote() {
        func item(_ resolution: InboundItem.Resolution?) -> InboundItem {
            InboundItem(
                id: "x", kind: resolution == nil ? .reviewBody : .inlineThread, permalink: "u",
                state: .answeredClaimed, question: "q", changed: nil,
                text: .init(ask: "a", reply: "r"), resolution: resolution)
        }
        #expect(InboundReporting.resolutionNote(item(nil)) == "")
        #expect(
            InboundReporting.resolutionNote(
                item(.init(isResolved: false, resolvedBy: nil, byAsker: false)))
                == " — unresolved")
        #expect(
            InboundReporting.resolutionNote(
                item(.init(isResolved: true, resolvedBy: "reviewer", byAsker: true)))
                == " — resolved by the asker")
        #expect(
            InboundReporting.resolutionNote(
                item(.init(isResolved: true, resolvedBy: "laconicman", byAsker: false)))
                == " — resolved by laconicman")
    }

    // MARK: - B: closure does not quiet an unresolved thread

    /// Case 4: my reply deferred the finding to tech debt, so nothing ever made the
    /// reviewer's claim false and it never resolved the thread. It was the only
    /// unresolved thread across seven pull requests, and the merge hid it among twelve
    /// quiet `answered-claimed` ones. The same thread resolved is the control: closure
    /// still quiets that — the mutant for dropping the exception.
    @Test("a merged PR keeps an unresolved answered-claimed thread listed, and only that")
    func unresolvedThreadOutlivesTheMerge() async throws {
        let id = "discussion_r4024609952"
        var pr = try await Fixtures.resolution(pr: 1)
        #expect(pr.isClosed, "the premise: #1 is merged")
        // This thread alone, so the provenance note counts nothing else.
        pr.threads = pr.threads.filter { $0.root?.id == id }
        let open = try #require(pr.threads.first)
        #expect(!open.isResolved, "the premise: the reviewer never resolved it")

        var resolved = pr
        resolved.threads = pr.threads.map { thread in
            guard thread.root?.id == id else { return thread }
            var thread = thread
            thread.isResolved = true
            thread.resolvedBy = thread.root?.author
            return thread
        }

        for (fetched, listed) in [(pr, true), (resolved, false)] {
            // A second run, so nothing reads as moved.
            let first = try Fixtures.audit().run(fetched, against: nil)
            let second = try Fixtures.audit().run(fetched, against: first.updatedSnapshot)
            let item = try #require(second.items.first { $0.id == id })
            #expect(item.state == .answeredClaimed)
            #expect(item.changed == nil)
            #expect(item.isListedByDefault == listed, "listed: \(listed)")
            #expect(second.toReRead.map(\.id) == (listed ? [id] : []))
            #expect(second.owed.isEmpty, "listed is not owed")

            var provenance = Provenance(command: "contrib in")
            InboundReporting.record(second, fetched, previous: first.updatedSnapshot, into: &provenance)
            let quiet = provenance.notes.contains { $0.contains("not listed") && $0.contains("answered-claimed") }
            #expect(quiet == !listed, "the quiet count names only what is really unlisted")
        }
    }

    // MARK: - A: the asker's verdict confirms, whenever it was posted

    /// Case 1: the reviewer re-reviewed on push, posted `✅ **Resolved**:`, and *then* I
    /// replied. Only an asker reply after mine used to confirm, so a confirmation that
    /// arrived first counted for nothing — twelve such threads on one pull request.
    @Test("a verdict before my reply confirms it")
    func verdictBeforeMyReplyConfirms() async throws {
        let pr = try await Fixtures.resolution(pr: 1)
        let item = try #require(
            try Fixtures.audit().run(pr, against: nil).items.first {
                $0.id == "discussion_r4025099437"
            })
        #expect(item.state == .answeredConfirmed)
    }

    /// The phrase upgrades my claim to confirmed; it never manufactures a reply I did
    /// not write. Case 2's verdict-only threads stay owed — one line of reply clears
    /// each, which is honest.
    @Test("a verdict with no reply of mine leaves the ask open")
    func verdictWithoutMyReplyStaysOpen() async throws {
        let pr = try await Fixtures.resolution(pr: 5)
        let id = "discussion_r4097237099"
        let thread = try #require(pr.threads.first { $0.root?.id == id })
        #expect(
            try Fixtures.audit().askerReplies(in: thread).contains(where: \.isVerdict),
            "the premise: the asker's verdict is there")
        let item = try #require(try Fixtures.audit().run(pr, against: nil).items.first { $0.id == id })
        #expect(item.state == .openAsk)
    }

    /// The shape that always worked — my reply, then the verdict — still does.
    @Test("a verdict after my reply still confirms it")
    func verdictAfterMyReplyConfirms() async throws {
        let pr = try await Fixtures.resolution(pr: 2)
        let item = try #require(try Fixtures.audit().run(pr, against: nil).items.first)
        #expect(item.id == "discussion_r4058500969")
        #expect(item.state == .answeredConfirmed)
    }

    /// **A verdict opens the reply.** Matching anywhere is how supersession once
    /// retracted a live ask; here it would confirm a thread on a reply that only talks
    /// about the phrase. No capture holds such a reply, so this is constructed — the
    /// mutant for dropping the opening-lines restriction.
    @Test("the verdict phrase mid-reply, or quoted, is not a verdict")
    func verdictMustOpenTheReply() throws {
        let detector = VerdictDetector(
            phrases: try Configuration.builtInDefaults().inbound.verdictPhrases)
        #expect(detector.isVerdict("✅ **Resolved**: the crawler now rejects the redirect."))
        #expect(detector.isVerdict("\n  ✅ **resolved**: case and leading space do not matter"))
        #expect(!detector.isVerdict("I would not call this ✅ **Resolved**: the second path still writes."))
        #expect(!detector.isVerdict("> ✅ **Resolved**: quoted from the thread above\n\nThis is not fixed."))
        #expect(!VerdictDetector(phrases: [""]).isVerdict("anything"), "an empty phrase confirms nothing")

        // Through the audit: the asker mentions the phrase before my reply.
        let reviewer = "devin-ai-integration"
        let thread = RemoteThread(comments: [
            comment("discussion_r1", reviewer, at: 0, "🔴 **A finding**"),
            comment(
                "discussion_r2", reviewer, at: 5,
                "Not yet — a reply opening ✅ **Resolved**: would mean it is."),
            comment("discussion_r3", "laconicman", at: 10, "Fixed in abc1234."),
        ])
        let result = try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
        #expect(result.items.first?.state == .answeredClaimed)
    }

    // MARK: - A′: a bot asker's non-verdict reply is a question

    /// Case 3, twice: I replied "Fixed", then the reviewer's login — its fix session —
    /// replied that my fix had missed a path and it had closed the rest. Any asker-login
    /// reply after mine used to confirm, so the one reply I most needed to read was
    /// cleared. It is now listed, not owed, with the question it raises.
    @Test("a bot asker's correction after my reply is asker-replied, listed and not owed")
    func correctionIsAQuestion() async throws {
        for (number, id) in [(3, "discussion_r4095575834"), (6, "discussion_r4097650348")] {
            let pr = try await Fixtures.resolution(pr: number)
            let result = try Fixtures.audit().run(pr, against: nil)
            let item = try #require(result.items.first { $0.id == id })
            #expect(item.state == .askerReplied, "#\(number)")
            #expect(!item.state.isOwed)
            #expect(item.isListedByDefault, "#\(number) is open, and nobody has looked")
            #expect(result.toReRead.map(\.id).contains(id))
        }
    }

    /// The bot gate. A person's "LGTM, thanks" after my reply is the asker confirming,
    /// exactly as before; only a configured bot's login is suspected of speaking for a
    /// fix session. No capture holds a human asker at all, so this is constructed — the
    /// mutant for dropping the gate.
    @Test("a human asker's plain reply after mine still confirms")
    func humanReplyStillConfirms() throws {
        let thread = RemoteThread(comments: [
            comment("discussion_r1", "sauwming", at: 0, "Please free this on the error path."),
            comment("discussion_r2", "laconicman", at: 10, "Fixed in abc1234."),
            comment("discussion_r3", "sauwming", at: 20, "LGTM, thanks."),
        ])
        let result = try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
        #expect(result.items.first?.state == .answeredConfirmed)
    }

    /// The asker's **latest** reply after mine decides. A verdict after a correction is
    /// the reviewer re-checking once the fix session closed the rest; a correction
    /// after a verdict is news the verdict predates. Neither order occurs in the
    /// captures, so both are constructed.
    @Test("the bot asker's latest reply after mine decides")
    func latestAskerReplyDecides() throws {
        let bot = "devin-ai-integration"
        let verdict = "✅ **Resolved**: both paths now check the id."
        let correction = "Closed the remaining half of this in f7c1a98."
        func state(_ first: String, _ second: String) throws -> ItemState? {
            let thread = RemoteThread(comments: [
                comment("discussion_r1", bot, at: 0, "🔴 **A finding**"),
                comment("discussion_r2", "laconicman", at: 10, "Fixed."),
                comment("discussion_r3", bot, at: 20, first),
                comment("discussion_r4", bot, at: 30, second),
            ])
            return try Fixtures.audit().run(pullRequest(threads: [thread]), against: nil)
                .items.first?.state
        }
        #expect(try state(correction, verdict) == .answeredConfirmed)
        #expect(try state(verdict, correction) == .askerReplied)
    }

    /// A check recorded on `asker-replied` would judge my reply while the asker's later
    /// one went unread, and the audit decides the state before it reads any check — a
    /// record nobody reads. The refusal names the remedy instead.
    @Test("ack is refused on asker-replied, and the refusal names the way out")
    func askerRepliedTakesNoAcknowledgement() {
        let entry = Snapshot.Entry(
            kind: .inlineThread, url: "u", author: "devin-ai-integration", createdAt: Date(),
            updatedAt: nil, lastEditedAt: nil, bodySha256: "h", state: .askerReplied,
            firstSeen: Date(), myReplyID: "discussion_r2", myReplyAt: Date(), acknowledged: nil)
        let refusal = AcknowledgementEligibility.refusal(for: entry, id: "discussion_r1")
        #expect(refusal?.contains("contrib show discussion_r1") == true)
        #expect(refusal?.contains("--refresh") == true)
    }

    // MARK: - D: one login, two roles — a documented limit

    /// Case 2: the fix session replied under the reviewer's own login, and I never
    /// replied. Nothing the kit can read tells that reply from the reviewer's, so the
    /// thread stays an open ask — pinned here so that any future "delegate" fix shows
    /// up as a visible diff rather than a silent one.
    @Test("a fix session's reply under the asker's login leaves the ask open")
    func oneLoginTwoRolesStaysOpen() async throws {
        let pr = try await Fixtures.resolution(pr: 5)
        let id = "discussion_r4098761481"
        let thread = try #require(pr.threads.first { $0.root?.id == id })
        let replies = try Fixtures.audit().askerReplies(in: thread)
        #expect(!replies.isEmpty && replies.allSatisfy { !$0.isVerdict }, "the premise")
        let item = try #require(try Fixtures.audit().run(pr, against: nil).items.first { $0.id == id })
        #expect(item.state == .openAsk)
    }

    // MARK: - Helpers

    private func comment(
        _ id: String, _ author: String, at seconds: TimeInterval, _ body: String
    ) -> RemoteComment {
        RemoteComment(
            id: id, channel: .inlineThread, author: author, viewerDidAuthor: false,
            createdAt: Date(timeIntervalSince1970: seconds), body: body,
            permalink: "https://github.com/o/r/pull/1#\(id)")
    }

    private func pullRequest(threads: [RemoteThread], state: String = "OPEN") -> PullRequestThreads {
        PullRequestThreads(
            repository: "o/r", number: 1, title: "t", url: "u", state: state,
            isMerged: state == "MERGED", threads: threads, reviewBodies: [], issueComments: [],
            pagesFetched: 1)
    }

    private func thread(pr: Int, _ rootID: String) async throws -> RemoteThread? {
        try await Fixtures.resolution(pr: pr).threads.first { $0.root?.id == rootID }
    }
}
