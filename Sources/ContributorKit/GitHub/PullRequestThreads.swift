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
    /// The head commit's oid — the `last: 1` node of `commits`. `nil` on issues and
    /// on fetches that predate the field.
    public var headCommitOID: String?
    /// Status/check contexts on the head commit, verbatim — reviewer coverage
    /// (issue #10). Empty both when nothing reported and when the field was never
    /// fetched; `headContextsTruncated` separates a short page from none.
    public var headContexts: [HeadContext]
    /// The contexts connection still had a next page. Coverage is reported, so a
    /// truncated page is a note — *may be incomplete* — never a fetch anomaly:
    /// a busy CI PR's context list must not hold the snapshot write gate hostage
    /// for a field that feeds no obligation.
    public var headContextsTruncated: Bool

    /// One status/check context on the head commit — a legacy `StatusContext` or a
    /// `CheckRun`, flattened so the audit reads one shape either way.
    public struct HeadContext: Codable, Sendable, Equatable {
        /// True when the source was a CheckRun rather than a legacy status.
        public var isCheckRun: Bool
        /// `context` on a status, `name` on a run.
        public var name: String
        /// `state` on a status; `conclusion ?? status` on a run.
        public var state: String
        /// `description` on a status, `title` on a run — the free-text detail that
        /// carries "Full review skipped: trial expired" verbatim.
        public var detail: String?
        /// `targetUrl` on a status, `detailsUrl` on a run.
        public var url: String?

        public init(
            isCheckRun: Bool, name: String, state: String,
            detail: String? = nil, url: String? = nil
        ) {
            self.isCheckRun = isCheckRun
            self.name = name
            self.state = state
            self.detail = detail
            self.url = url
        }
    }

    public init(
        repository: String, number: Int, title: String, url: String,
        state: String, isMerged: Bool, threads: [RemoteThread],
        reviewBodies: [RemoteComment], issueComments: [RemoteComment],
        pagesFetched: Int, truncatedConnections: [String] = [],
        bodiesAreExcerpts: Bool = false,
        headCommitOID: String? = nil, headContexts: [HeadContext] = [],
        headContextsTruncated: Bool = false
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
        self.headCommitOID = headCommitOID
        self.headContexts = headContexts
        self.headContextsTruncated = headContextsTruncated
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
