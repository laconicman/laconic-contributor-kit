import Foundation

/// The seam a generated client could replace if `gh` ever became unacceptable
/// (TASK §4.1).
public protocol GitHubClient: Sendable {
    func threads(repository: String, number: Int) async throws -> PullRequestThreads
}
