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

    struct Actor: Decodable {
        var login: String?
    }

    struct ReviewRef: Decodable {
        var databaseId: Int?
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
                reviewID: pullRequestReview?.databaseId.map(String.init))
        }
    }
}
