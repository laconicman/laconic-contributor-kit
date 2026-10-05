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
    /// The `--open` queue's document; empty where the surface is not used (tests,
    /// and commands that never list pull requests).
    public let openPullRequestsQueryPath: String
    public let maxPages: Int

    public init(
        runner: any CommandRunner, queryPath: String,
        openPullRequestsQueryPath: String = "", maxPages: Int = 50
    ) {
        self.runner = runner
        self.queryPath = queryPath
        self.openPullRequestsQueryPath = openPullRequestsQueryPath
        self.maxPages = maxPages
    }

    public static func bundledQueryPath(_ document: String = "ThreadDetail") throws
        -> String
    {
        guard
            let url = Bundle.module.url(
                forResource: "Resources/\(document)", withExtension: "graphql")
        else { throw ConfigurationError.missingResource("\(document).graphql") }
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

        // Reviewer coverage: the head commit's status/check contexts, verbatim
        // (issue #10). `commits(last: 1)` is not paginated — it names THIS head —
        // but the contexts inside it are. Truncation there is recorded as a note,
        // not an anomaly: a busy CI PR can exceed 100 check runs, and a coverage
        // field that feeds no obligation must not hold the snapshot write gate
        // hostage (DeepWiki pre-review of the same change).
        let headCommit = meta?.commits?.nodes?.last?.commit
        let headContextsTruncated =
            headCommit?.statusCheckRollup?.contexts?.pageInfo?.hasNextPage == true
        let headContexts: [PullRequestThreads.HeadContext] =
            (headCommit?.statusCheckRollup?.contexts?.nodes ?? []).compactMap { node in
                guard let name = node.label, let state = node.reportedState
                else { return nil }
                return PullRequestThreads.HeadContext(
                    isCheckRun: node.isCheckRun, name: name, state: state,
                    detail: node.detail, url: node.link)
            }

        return PullRequestThreads(
            repository: repository, number: number,
            title: meta?.title ?? "", url: meta?.url ?? "",
            state: meta?.pullRequestState ?? meta?.issueState ?? "UNKNOWN",
            isMerged: meta?.merged ?? false,
            threads: threads, reviewBodies: reviewBodies, issueComments: issueComments,
            pagesFetched: pages, truncatedConnections: truncated,
            bodiesAreExcerpts: false,
            headCommitOID: headCommit?.oid, headContexts: headContexts,
            headContextsTruncated: headContextsTruncated,
            isPullRequest: meta?.__typename == "PullRequest" ? true
                : meta?.__typename == "Issue" ? false : nil)
    }

    /// The `--open` queue's fetch (issue #12): every open pull request, paged
    /// explicitly so a cut list is reported rather than mistaken for complete.
    public func openPullRequests(repository: String) async throws -> OpenPullRequestList {
        let parts = repository.split(separator: "/")
        guard parts.count == 2 else { throw GitHubError.badRepository(repository) }
        let owner = String(parts[0]), name = String(parts[1])

        var cursor: String?
        var pullRequests: [OpenPullRequest] = []
        var totalCount = 0
        var truncated = false
        var authorshipUnknown = 0
        var pages = 0

        while pages < maxPages {
            var argv = [
                "gh", "api", "graphql",
                "-F", "query=@\(openPullRequestsQueryPath)",
                "-f", "owner=\(owner)",
                "-f", "name=\(name)",
            ]
            if let cursor { argv += ["-f", "cursor=\(cursor)"] }

            let out = try await runner.runExpectingOutput(argv)
            let response = try JSONDecoder().decode(
                OpenPullRequestsResponse.self, from: out.stdout)
            if let errors = response.errors, !errors.isEmpty {
                throw GitHubError.graphQL(errors.map(\.message))
            }
            guard let connection = response.data?.repository?.pullRequests else {
                throw GitHubError.repositoryNotFound(repository)
            }
            pages += 1
            totalCount = connection.totalCount ?? totalCount
            pullRequests += (connection.nodes ?? []).compactMap { node in
                guard let number = node.number else { return nil }
                if node.viewerDidAuthor == nil { authorshipUnknown += 1 }
                return OpenPullRequest(
                    number: number, title: node.title ?? "",
                    isDraft: node.isDraft ?? false,
                    viewerDidAuthor: node.viewerDidAuthor ?? false)
            }

            // Advance to the page just read, even on a finished connection:
            // re-sending a stale cursor re-reads page one and double-counts (the
            // `threads` comment records the live verification of that).
            cursor = connection.pageInfo?.endCursor ?? cursor

            guard connection.pageInfo?.hasNextPage == true else { break }
            if pages == maxPages {
                truncated = true
            } else if connection.pageInfo?.endCursor == nil {
                // `hasNextPage` with no cursor cannot be paged — the list is cut.
                truncated = true
                break
            }
        }

        return OpenPullRequestList(
            all: pullRequests, totalCount: totalCount,
            pagesFetched: pages, truncated: truncated,
            authorshipUnknown: authorshipUnknown)
    }
}

public enum GitHubError: Error, CustomStringConvertible {
    case badRepository(String)
    case notFound(repository: String, number: Int)
    case repositoryNotFound(String)
    case graphQL([String])

    public var description: String {
        switch self {
        case .badRepository(let text):
            return "`\(text)` is not <owner>/<repo>"
        case .notFound(let repository, let number):
            return "\(repository)#\(number) was not found"
        case .repositoryNotFound(let name):
            return "\(name) was not found — or `gh` cannot see it"
        case .graphQL(let messages):
            return "GitHub returned \(messages.count) error(s): " + messages.joined(separator: "; ")
        }
    }
}
