import Foundation

/// One `contrib loc` result: the range, the totals, the optional per-role and
/// per-commit breakdowns, and the whitespace-corrected churn.
public struct LocReport: Codable, Sendable {
    public var repository: String
    public var refA: String
    public var refB: String
    public var capturedAt: Date
    public var languages: [String]

    public var total: DiffStats
    /// Modified *code* with `--ignore-whitespace`, when it was measured.
    /// Reported beside the raw figure in one row — `churn 35 (20 excluding whitespace)`
    /// — because hiding the reindentation share overstates the work (TASK §3.4).
    public var modifiedCodeIgnoringWhitespace: Int?

    public var byRole: [String: DiffStats]?
    public var byPath: [String: String]?
    public var commits: [CommitReport]?

    public struct CommitReport: Codable, Sendable {
        public var sha: String
        public var subject: String
        public var stats: DiffStats
    }

}
