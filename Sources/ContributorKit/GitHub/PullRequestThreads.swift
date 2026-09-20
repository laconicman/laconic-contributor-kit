import Foundation

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
    /// **Never trust a truncated fetch** (<doc:Design>). The 09-04 miss was literally
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
