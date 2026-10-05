import Foundation

/// The seam a generated client could replace if `gh` ever became unacceptable
/// (<doc:Design>).
public protocol GitHubClient: Sendable {
    func threads(repository: String, number: Int) async throws -> PullRequestThreads
    func openPullRequests(repository: String) async throws -> OpenPullRequestList
}
