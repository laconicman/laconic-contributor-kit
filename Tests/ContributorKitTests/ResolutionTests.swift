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

    // MARK: - Helpers

    private func thread(pr: Int, _ rootID: String) async throws -> RemoteThread? {
        try await Fixtures.resolution(pr: pr).threads.first { $0.root?.id == rootID }
    }
}
