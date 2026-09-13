import Foundation

/// The `ThreadDetail.graphql` response envelope.
///
/// Every field is optional because `issueOrPullRequest` is a union: an Issue carries
/// `issueState` and no reviews, a PullRequest carries `pullRequestState` and all
/// three connections. The two `state` aliases are load-bearing rather than cosmetic —
/// `Issue.state` and `PullRequest.state` return different enums, so the same response
/// key across both fragments is a hard validation error (TASK §4.3).
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
        var comments: Connection<CommentNode>?
        var reviews: Connection<CommentNode>?
        var reviewThreads: Connection<ThreadNode>?
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
                reviewID: nil)
        }
    }
}
