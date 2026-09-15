import Foundation

/// The three channels TASK §12.3 rule 1 requires. A run that skips review bodies
/// reproduces the original bug: the two historical #5233 misses were both review
/// bodies carrying no inline comment of their own.
public enum Channel: String, Codable, Sendable, CaseIterable {
    case inlineThread = "inline-thread"
    case reviewBody = "review-body"
    case issueComment = "issue-comment"

    public var label: String {
        switch self {
        case .inlineThread: return "inline thread"
        case .reviewBody: return "review body"
        case .issueComment: return "issue comment"
        }
    }

    public var plural: String {
        switch self {
        case .inlineThread: return "inline threads"
        case .reviewBody: return "review bodies"
        case .issueComment: return "issue comments"
        }
    }
}

/// One comment, from any channel.
///
/// `id` is the **permalink fragment** — `discussion_r3948887913`,
/// `issuecomment-5539554145`, `pullrequestreview-5095816383` — and not a REST integer
/// or a GraphQL node id. That is what lets the live GraphQL path and the REST-shaped
/// fixtures produce the same identity for the same comment, which in turn is what
/// makes a snapshot written by one comparable with a fetch by the other.
public struct RemoteComment: Codable, Sendable, Equatable {
    public var id: String
    public var channel: Channel
    public var author: String
    public var viewerDidAuthor: Bool
    public var createdAt: Date
    public var updatedAt: Date?
    public var lastEditedAt: Date?
    public var body: String
    /// True when `body` is a truncated excerpt rather than the whole thing. The
    /// fixtures store 120 characters per comment and 160 per review body and no full
    /// body at all, so anything that reads text — boilerplate stripping, supersession
    /// matching — is working on a fragment and must say so (fixtures README).
    public var bodyIsExcerpt: Bool
    public var permalink: String
    /// The review that carried an inline comment — the round it belongs to (§12.4).
    public var reviewID: String?

    public init(
        id: String, channel: Channel, author: String, viewerDidAuthor: Bool,
        createdAt: Date, updatedAt: Date? = nil, lastEditedAt: Date? = nil,
        body: String, bodyIsExcerpt: Bool = false, permalink: String,
        reviewID: String? = nil
    ) {
        self.id = id
        self.channel = channel
        self.author = author
        self.viewerDidAuthor = viewerDidAuthor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEditedAt = lastEditedAt
        self.body = body
        self.bodyIsExcerpt = bodyIsExcerpt
        self.permalink = permalink
        self.reviewID = reviewID
    }

    /// The API-independent backstop for edit detection. For review bodies it is not an
    /// optimisation: REST's review schema carries `submitted_at` and nothing else, so
    /// the channel with no reply mechanism is also the one REST cannot diff (§13.4).
    public var bodySHA256: String { SHA256.hex(of: body) }
}

/// An inline review thread: ordered comments, the first of which is the root ask.
///
/// `isResolved` is carried because the API supplies it and the snapshot should not have
/// to re-fetch it — but the audit never consults it. **`isResolved` is not "answered"**
/// (TASK §12.3 rule 3): the maintainer sets resolution, a thread can be resolved with no
/// reply from us, and an open thread can be fully answered. Never substitute one for the
/// other.
public struct RemoteThread: Codable, Sendable {
    public var comments: [RemoteComment]
    public var isResolved: Bool
    public var isOutdated: Bool
    public var path: String?

    public init(
        comments: [RemoteComment], isResolved: Bool = false,
        isOutdated: Bool = false, path: String? = nil
    ) {
        self.comments = comments
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.path = path
    }

    public var root: RemoteComment? { comments.first }
    public var replies: ArraySlice<RemoteComment> { comments.dropFirst() }
}

/// Everything one PR's three channels hold, plus the evidence that the fetch was
/// complete.
public struct PullRequestThreads: Sendable {
    public var repository: String
    public var number: Int
    public var title: String
    public var url: String
    public var state: String
    public var isMerged: Bool

    public var threads: [RemoteThread]
    public var reviewBodies: [RemoteComment]
    public var issueComments: [RemoteComment]

    public var pagesFetched: Int
    /// Any connection that still reported `hasNextPage` when fetching stopped.
    ///
    /// **Never trust a truncated fetch** (§12.3 rule 4). The 09-04 miss was literally
    /// `sort | tail -6`: the earliest comment fell off and the truncation propagated
    /// silently into "the round is done". A non-empty list here is an anomaly, not a
    /// footnote.
    public var truncatedConnections: [String]
    /// True when the bodies came from a source that stores excerpts.
    public var bodiesAreExcerpts: Bool

    public init(
        repository: String, number: Int, title: String, url: String,
        state: String, isMerged: Bool, threads: [RemoteThread],
        reviewBodies: [RemoteComment], issueComments: [RemoteComment],
        pagesFetched: Int, truncatedConnections: [String] = [],
        bodiesAreExcerpts: Bool = false
    ) {
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isMerged = isMerged
        self.threads = threads
        self.reviewBodies = reviewBodies
        self.issueComments = issueComments
        self.pagesFetched = pagesFetched
        self.truncatedConnections = truncatedConnections
        self.bodiesAreExcerpts = bodiesAreExcerpts
    }

    /// Closed or merged. `UNKNOWN` — the REST fixtures carry no state — reads as open,
    /// so a missing fact never hides anything.
    public var isClosed: Bool {
        isMerged || state == "CLOSED" || state == "MERGED"
    }

    public var allComments: [RemoteComment] {
        threads.flatMap(\.comments) + reviewBodies + issueComments
    }
}

/// The seam a generated client could replace if `gh` ever became unacceptable
/// (TASK §4.1).
public protocol GitHubClient: Sendable {
    func threads(repository: String, number: Int) async throws -> PullRequestThreads
}
