import Foundation

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
    /// The review that carried an inline comment — the round it belongs to (<doc:Design>).
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
    /// the channel with no reply mechanism is also the one REST cannot diff (<doc:Design>).
    public var bodySHA256: String { SHA256.hex(of: body) }
}
