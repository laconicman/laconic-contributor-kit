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

    // MARK: - Helpers

    private func thread(pr: Int, _ rootID: String) async throws -> RemoteThread? {
        try await Fixtures.resolution(pr: pr).threads.first { $0.root?.id == rootID }
    }
}
