import Foundation

/// `gh api graphql`, behind `GitHubClient`.
///
/// Shelling out rather than generating a client: GitHub's REST OpenAPI description is
/// 12.9 MB over 813 paths, GraphQL cannot be generated from it at all, and `gh`
/// already solves auth, pagination, retries, rate-limit backoff and Enterprise hosts
/// (<doc:Design>). **No credential is ever read, stored or invented here** — `gh` holds
/// the token and this never asks for it.
///
/// The per-thread fetch is GraphQL and not REST because of one measured fact: REST's
/// review schema carries `submitted_at` and nothing else — no `created_at`, no
/// `updated_at` — so the channel with no reply mechanism, the one that carried the
/// historical misses, is also the one REST cannot diff (<doc:Design>).
public struct GHCommandClient: GitHubClient {
    public let runner: any CommandRunner
    public let queryPath: String
    public let maxPages: Int

    public init(runner: any CommandRunner, queryPath: String, maxPages: Int = 50) {
        self.runner = runner
        self.queryPath = queryPath
        self.maxPages = maxPages
    }

    public static func bundledQueryPath() throws -> String {
        guard
            let url = Bundle.module.url(
                forResource: "Resources/ThreadDetail", withExtension: "graphql")
        else { throw ConfigurationError.missingResource("ThreadDetail.graphql") }
        return url.path
    }

    public func threads(repository: String, number: Int) async throws -> PullRequestThreads {
        let parts = repository.split(separator: "/")
        guard parts.count == 2 else { throw GitHubError.badRepository(repository) }
        let owner = String(parts[0]), name = String(parts[1])

        var commentCursor: String?
        var reviewCursor: String?
        var threadCursor: String?
        var issueComments: [RemoteComment] = []
        var reviewBodies: [RemoteComment] = []
        var threads: [RemoteThread] = []
        var truncated: [String] = []
        var meta: ThreadDetailResponse.Subject?
        var pages = 0

        while pages < maxPages {
            var argv = [
                "gh", "api", "graphql",
                "-F", "query=@\(queryPath)",
                "-f", "owner=\(owner)",
                "-f", "name=\(name)",
                // `-F` sends a typed value: `number` is `Int!` and fails with `-f`,
                // which sends a String (the Design article).
                "-F", "number=\(number)",
            ]
            if let commentCursor { argv += ["-f", "commentCursor=\(commentCursor)"] }
            if let reviewCursor { argv += ["-f", "reviewCursor=\(reviewCursor)"] }
            if let threadCursor { argv += ["-f", "threadCursor=\(threadCursor)"] }

            let out = try await runner.runExpectingOutput(argv)
            let response = try JSONDecoder().decode(ThreadDetailResponse.self, from: out.stdout)
            if let errors = response.errors, !errors.isEmpty {
                throw GitHubError.graphQL(errors.map(\.message))
            }
            guard let subject = response.data?.repository?.issueOrPullRequest else {
                throw GitHubError.notFound(repository: repository, number: number)
            }
            meta = subject
            pages += 1

            issueComments += (subject.comments?.nodes ?? []).compactMap {
                $0.remoteComment(channel: .issueComment)
            }
            reviewBodies += (subject.reviews?.nodes ?? []).compactMap {
                $0.remoteComment(channel: .reviewBody)
            }
            for node in subject.reviewThreads?.nodes ?? [] {
                let comments = (node.comments?.nodes ?? []).compactMap {
                    $0.remoteComment(channel: .inlineThread)
                }
                guard !comments.isEmpty else { continue }
                if node.comments?.pageInfo?.hasNextPage == true {
                    truncated.append("reviewThread(\(comments[0].id)).comments")
                }
                threads.append(
                    RemoteThread(
                        comments: comments,
                        isResolved: node.isResolved,
                        resolvedBy: node.resolvedBy?.login,
                        isOutdated: node.isOutdated ?? false,
                        path: node.path))
            }

            // Always advance to the page just read, even on a connection that is
            // finished: re-sending a stale cursor re-reads page one and double-counts.
            //
            // Re-sending a *finished* connection's own `endCursor` is safe — verified
            // live against this repository's PR: `after:` the final cursor returns
            // `nodes: []` and `hasNextPage: false`, because a cursor marks the position
            // after the last item rather than the item itself. So an exhausted
            // connection contributes nothing while the others keep paging.
            commentCursor = subject.comments?.pageInfo?.endCursor ?? commentCursor
            reviewCursor = subject.reviews?.pageInfo?.endCursor ?? reviewCursor
            threadCursor = subject.reviewThreads?.pageInfo?.endCursor ?? threadCursor

            let more = [
                subject.comments?.pageInfo?.hasNextPage,
                subject.reviews?.pageInfo?.hasNextPage,
                subject.reviewThreads?.pageInfo?.hasNextPage,
            ].contains(true)
            if !more { break }
            if pages == maxPages {
                truncated.append("stopped at the \(maxPages)-page ceiling")
            }
        }

        // The subject's own body rides the issue-comments channel, first: for an
        // issue it IS the ask, and a pull request's description can carry one.
        // `viewerDidAuthor` filters the contributor's own for free, and an empty
        // body lands as `no-prose` — a recorded fact, never a vanished item.
        if let body = meta?.bodyComment() {
            issueComments.insert(body, at: 0)
        }

        return PullRequestThreads(
            repository: repository, number: number,
            title: meta?.title ?? "", url: meta?.url ?? "",
            state: meta?.pullRequestState ?? meta?.issueState ?? "UNKNOWN",
            isMerged: meta?.merged ?? false,
            threads: threads, reviewBodies: reviewBodies, issueComments: issueComments,
            pagesFetched: pages, truncatedConnections: truncated,
            bodiesAreExcerpts: false)
    }
}

public enum GitHubError: Error, CustomStringConvertible {
    case badRepository(String)
    case notFound(repository: String, number: Int)
    case graphQL([String])

    public var description: String {
        switch self {
        case .badRepository(let text):
            return "`\(text)` is not <owner>/<repo>"
        case .notFound(let repository, let number):
            return "\(repository)#\(number) was not found"
        case .graphQL(let messages):
            return "GitHub returned \(messages.count) error(s): " + messages.joined(separator: "; ")
        }
    }
}
