import Foundation

/// The `ThreadDetail.graphql` response envelope.
///
/// Every field is optional because `issueOrPullRequest` is a union: an Issue carries
/// `issueState` and no reviews, a PullRequest carries `pullRequestState` and all
/// three connections. The two `state` aliases are load-bearing rather than cosmetic —
/// `Issue.state` and `PullRequest.state` return different enums, so the same response
/// key across both fragments is a hard validation error (<doc:Design>).
struct ThreadDetailResponse: Decodable {
    var data: Payload?
    var errors: [GraphQLError]?

    struct GraphQLError: Decodable {
        var message: String
    }

    struct Payload: Decodable {
        var repository: Repository?
    }

    struct Repository: Decodable {
        var issueOrPullRequest: Subject?
    }

    struct Subject: Decodable {
        var __typename: String?
        var number: Int?
        var title: String?
        var url: String?
        var issueState: String?
        var pullRequestState: String?
        var closed: Bool?
        var merged: Bool?
        var body: String?
        var author: Actor?
        var viewerDidAuthor: Bool?
        var createdAt: String?
        var updatedAt: String?
        var lastEditedAt: String?
        var comments: Connection<CommentNode>?
        var reviews: Connection<CommentNode>?
        var reviewThreads: Connection<ThreadNode>?
        /// Head commit + its status/check contexts — pull requests only. `last: 1`
        /// is un-paginated on purpose: the audit's question is "what did the
        /// reviewer report on THIS head", and a deeper history answers a question
        /// nobody asked (issue #10).
        var commits: Connection<CommitNode>?

        /// The subject's own body as a comment-shaped item on the issue-comments
        /// channel.
        ///
        /// For an issue the body IS the ask, and a pull request's description can
        /// carry one too — the fetch unions both through `issueOrPullRequest`, so they
        /// cost the same field. Synthesized rather than modeled as a fourth channel:
        /// GitHub's own timeline treats the body as the thread's first entry, and the
        /// obligation machinery — strip, hash, acknowledge, reopen on edit — then
        /// works unchanged.
        ///
        /// `nil` only when the response carries no body field or the typename is
        /// unknown — an unknown shape must not fabricate an item. An EMPTY body
        /// synthesizes too: skipping it let a body emptied after recording make the
        /// item vanish, and the vanished-item anomaly then blocked every later
        /// snapshot write — the guard that protects the baseline bricked it
        /// permanently. Empty is `no-prose`: counted, not owed, invisible by default.
        func bodyComment() -> RemoteComment? {
            guard let body,
                let number, let url,
                let prefix =
                    __typename == "Issue" ? "issue"
                    : __typename == "PullRequest" ? "pullrequest" : nil
            else { return nil }
            return RemoteComment(
                // Synthesized, not a permalink fragment — the only id in the kit that
                // is not one. It cannot shadow a real one: GitHub's own fragments are
                // `issuecomment-*`, `pullrequestreview-*` and `discussion_r*`, and
                // `Snapshot.entries` is keyed per repository, where subject numbers
                // are unique — the same string can never name two things.
                id: "\(prefix)-\(number)", channel: .issueComment,
                // Same deleted-account rule as `remoteComment`: `ghost` keeps the
                // item in the list rather than dropping it.
                author: author?.login ?? "ghost",
                viewerDidAuthor: viewerDidAuthor ?? false,
                createdAt: GitHubTime.parse(createdAt) ?? .distantPast,
                updatedAt: GitHubTime.parse(updatedAt),
                lastEditedAt: GitHubTime.parse(lastEditedAt),
                body: body, bodyIsExcerpt: false, permalink: url)
        }
    }

    struct Connection<Node: Decodable>: Decodable {
        var pageInfo: PageInfo?
        var nodes: [Node]?
    }

    struct PageInfo: Decodable {
        var hasNextPage: Bool?
        var endCursor: String?
    }

    struct ThreadNode: Decodable {
        var isResolved: Bool?
        var isOutdated: Bool?
        var path: String?
        var resolvedBy: Actor?
        var comments: Connection<CommentNode>?
    }

    /// `commits(last: 1)` wraps the commit object — the node is the edge, the
    /// `commit` field the payload.
    struct CommitNode: Decodable {
        var commit: Commit?
    }

    struct Commit: Decodable {
        var oid: String?
        var statusCheckRollup: StatusCheckRollup?
    }

    struct StatusCheckRollup: Decodable {
        var contexts: Connection<ContextNode>?
    }

    /// A `StatusCheckRollupContext` union member: StatusContext and CheckRun share
    /// no field names, so one flat optional bag decodes either and `__typename`
    /// says which it was. "Legacy status" and "check run" read differently on the
    /// GitHub UI but mean the same thing for coverage — a named channel reporting
    /// a state on this head (issue #10).
    struct ContextNode: Decodable {
        var __typename: String?
        // StatusContext
        var context: String?
        var state: String?
        var description: String?
        var targetUrl: String?
        // CheckRun — `status` while running, `conclusion` once COMPLETED.
        var name: String?
        var status: String?
        var conclusion: String?
        var title: String?
        var detailsUrl: String?

        var isCheckRun: Bool { __typename == "CheckRun" }
        /// What the check calls itself: `context` on a status, `name` on a run.
        var label: String? { isCheckRun ? name : context }
        /// The state worth printing. A completed run's verdict is its conclusion;
        /// mid-flight the status is all there is.
        var reportedState: String? { isCheckRun ? (conclusion ?? status) : state }
        /// Free-text detail verbatim — a check run's `title`, a status's
        /// `description`.
        var detail: String? { isCheckRun ? title : description }
        var link: String? { isCheckRun ? detailsUrl : targetUrl }
    }

    struct Actor: Decodable {
        var login: String?
    }

    struct ReviewRef: Decodable {
        var databaseId: Int?
    }

    /// `commit { oid }` — present on review nodes only: the head the review was
    /// left on (issue #10's "ran on what").
    struct OIDRef: Decodable {
        var oid: String?
    }

    struct CommentNode: Decodable {
        var body: String?
        var url: String?
        var state: String?
        var submittedAt: String?
        var createdAt: String?
        var updatedAt: String?
        var lastEditedAt: String?
        var editor: Actor?
        var viewerDidAuthor: Bool?
        var author: Actor?
        /// Present on inline comments only: the review that carried this one.
        var pullRequestReview: ReviewRef?
        /// Present on review nodes only: the head commit the review was left on.
        var commit: OIDRef?

        /// `nil` when the node carries no permalink — the id is the permalink
        /// fragment, so a node without one cannot be tracked across runs and is worse
        /// than useless in a snapshot.
        func remoteComment(channel: Channel) -> RemoteComment? {
            guard let url, let fragment = url.split(separator: "#").last.map(String.init),
                fragment != url
            else { return nil }
            let created = GitHubTime.parse(submittedAt) ?? GitHubTime.parse(createdAt)
            return RemoteComment(
                id: fragment, channel: channel,
                // A deleted account decodes as a null author; `ghost` is GitHub's own
                // name for it and keeps the item in the list rather than dropping it.
                author: author?.login ?? "ghost",
                viewerDidAuthor: viewerDidAuthor ?? false,
                createdAt: created ?? .distantPast,
                updatedAt: GitHubTime.parse(updatedAt),
                lastEditedAt: GitHubTime.parse(lastEditedAt),
                body: body ?? "", bodyIsExcerpt: false, permalink: url,
                reviewID: pullRequestReview?.databaseId.map(String.init),
                commitOID: commit?.oid)
        }
    }
}
