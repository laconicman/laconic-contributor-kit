import Foundation

/// One row of the `--open` queue (issue #12): just enough of a pull request to say
/// whether it is mine and what to call it.
public struct OpenPullRequest: Sendable, Equatable {
    public var number: Int
    public var title: String
    public var isDraft: Bool
    public var viewerDidAuthor: Bool

    public init(number: Int, title: String, isDraft: Bool, viewerDidAuthor: Bool) {
        self.number = number
        self.title = title
        self.isDraft = isDraft
        self.viewerDidAuthor = viewerDidAuthor
    }
}

/// The repository's open pull requests as fetched, plus the three facts that keep
/// the list honest: `totalCount` is what GitHub says is open, `pagesFetched` how
/// many round trips it took, and `truncated` is set when a `hasNextPage` outlived
/// the page ceiling — a cut list cannot say it was cut on its own.
public struct OpenPullRequestList: Sendable {
    public var all: [OpenPullRequest]
    public var totalCount: Int
    public var pagesFetched: Int
    public var truncated: Bool
    /// Nodes whose `viewerDidAuthor` was absent. A missing flag counts as *not
    /// mine* — and a quiet queue of "nobody's" reads exactly like an empty one,
    /// so the count must be reported rather than folded away.
    public var authorshipUnknown: Int

    public init(
        all: [OpenPullRequest], totalCount: Int, pagesFetched: Int, truncated: Bool,
        authorshipUnknown: Int = 0
    ) {
        self.all = all
        self.totalCount = totalCount
        self.pagesFetched = pagesFetched
        self.truncated = truncated
        self.authorshipUnknown = authorshipUnknown
    }

    /// The queue's population: open pull requests authored by the viewer. The asks
    /// on everyone else's are addressed to someone else.
    public var mine: [OpenPullRequest] { all.filter(\.viewerDidAuthor) }
}

/// The `OpenPullRequests.graphql` response envelope. Every field is optional, the
/// same rule as `ThreadDetailResponse`: a missing `repository` is "not found" and a
/// missing node field decodes as far as it can rather than guessing.
struct OpenPullRequestsResponse: Decodable {
    var data: Payload?
    var errors: [GraphQLError]?

    struct GraphQLError: Decodable {
        var message: String
    }

    struct Payload: Decodable {
        var repository: Repository?
    }

    struct Repository: Decodable {
        var pullRequests: Connection?
    }

    struct Connection: Decodable {
        var totalCount: Int?
        var pageInfo: PageInfo?
        var nodes: [Node]?
    }

    struct PageInfo: Decodable {
        var hasNextPage: Bool?
        var endCursor: String?
    }

    struct Node: Decodable {
        var number: Int?
        var title: String?
        var isDraft: Bool?
        var viewerDidAuthor: Bool?
    }
}
