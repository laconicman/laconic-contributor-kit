import Foundation

/// Decodes the REST-shaped capture the fixtures hold — and the same shape live from
/// `gh api repos/{owner}/{repo}/pulls/{n}/comments`.
///
/// The fixtures are the specification (TASK §6), and they are REST-shaped, so this
/// path has to exist regardless of §13.4's requirement that the *live* per-thread
/// fetch be GraphQL. The two produce the same `RemoteComment.id`, so a snapshot
/// written by one is comparable with a fetch by the other.
public enum RESTThreadDecoder {
    /// One record of `threads/pr-N.comments.json`.
    struct InlineRecord: Decodable {
        var id: Int
        var in_reply_to_id: Int?
        var login: String
        var created_at: String
        var path: String?
        var review_id: Int?
        var excerpt: String?
        var body: String?
    }

    struct ReviewRecord: Decodable {
        var id: Int
        var login: String
        var submitted_at: String
        var state: String?
        var excerpt: String?
        var body: String?
    }

    struct IssueCommentRecord: Decodable {
        var id: Int
        var login: String
        var created_at: String
        var excerpt: String?
        var body: String?
    }

    public struct Input: Sendable {
        public var repository: String
        public var number: Int
        public var me: String
        public var comments: Data
        public var reviews: Data
        public var issueComments: Data

        public init(
            repository: String, number: Int, me: String,
            comments: Data, reviews: Data, issueComments: Data
        ) {
            self.repository = repository
            self.number = number
            self.me = me
            self.comments = comments
            self.reviews = reviews
            self.issueComments = issueComments
        }
    }

    public static func decode(_ input: Input) throws -> PullRequestThreads {
        let decoder = JSONDecoder()
        let inline = try decoder.decode([InlineRecord].self, from: input.comments)
        let reviews = try decoder.decode([ReviewRecord].self, from: input.reviews)
        let issues = try decoder.decode([IssueCommentRecord].self, from: input.issueComments)

        let base = "https://github.com/\(input.repository)/pull/\(input.number)"
        var sawExcerpt = false

        func text(_ body: String?, _ excerpt: String?) -> (String, Bool) {
            if let body { return (body, false) }
            sawExcerpt = true
            return (excerpt ?? "", true)
        }

        // Inline comments → threads, grouped by `in_reply_to_id`. A reply's parent is
        // the root; a root is its own thread. Replies are ordered by creation.
        var inlineComments: [Int: RemoteComment] = [:]
        for record in inline {
            let (body, isExcerpt) = text(record.body, record.excerpt)
            let id = "discussion_r\(record.id)"
            inlineComments[record.id] = RemoteComment(
                id: id, channel: .inlineThread, author: record.login,
                viewerDidAuthor: record.login == input.me,
                createdAt: GitHubTime.parse(record.created_at) ?? .distantPast,
                body: body, bodyIsExcerpt: isExcerpt,
                permalink: "\(base)#\(id)",
                reviewID: record.review_id.map(String.init))
        }

        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for record in inline {
            if let parent = record.in_reply_to_id {
                children[parent, default: []].append(record.id)
            } else {
                roots.append(record.id)
            }
        }

        let threads: [RemoteThread] = roots.compactMap { rootID in
            guard let root = inlineComments[rootID] else { return nil }
            let replies = (children[rootID] ?? [])
                .compactMap { inlineComments[$0] }
                .sorted { $0.createdAt < $1.createdAt }
            let path = inline.first { $0.id == rootID }?.path
            // The REST capture carries no `isResolved`; `false` is the honest default,
            // and §12.3 rule 3 says resolution is not "answered" anyway.
            return RemoteThread(comments: [root] + replies, path: path)
        }

        let reviewBodies: [RemoteComment] = reviews.map { record in
            let (body, isExcerpt) = text(record.body, record.excerpt)
            let id = "pullrequestreview-\(record.id)"
            return RemoteComment(
                id: id, channel: .reviewBody, author: record.login,
                viewerDidAuthor: record.login == input.me,
                createdAt: GitHubTime.parse(record.submitted_at) ?? .distantPast,
                body: body, bodyIsExcerpt: isExcerpt, permalink: "\(base)#\(id)")
        }

        let issueComments: [RemoteComment] = issues.map { record in
            let (body, isExcerpt) = text(record.body, record.excerpt)
            let id = "issuecomment-\(record.id)"
            return RemoteComment(
                id: id, channel: .issueComment, author: record.login,
                viewerDidAuthor: record.login == input.me,
                createdAt: GitHubTime.parse(record.created_at) ?? .distantPast,
                body: body, bodyIsExcerpt: isExcerpt, permalink: "\(base)#\(id)")
        }

        return PullRequestThreads(
            repository: input.repository, number: input.number,
            title: "", url: base, state: "UNKNOWN", isMerged: false,
            threads: threads, reviewBodies: reviewBodies, issueComments: issueComments,
            pagesFetched: 3, truncatedConnections: [], bodiesAreExcerpts: sawExcerpt)
    }
}
