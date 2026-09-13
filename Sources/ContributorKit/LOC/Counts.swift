import Foundation

/// Code, comment and blank — **never summed** (TASK §1, §3.4). There is deliberately
/// no `total` property on this type; a quality score built from one number is the
/// thing the whole LOC half exists to not produce.
public struct Counts: Codable, Sendable, Equatable, CustomStringConvertible {
    public var description: String { "code \(code) / comment \(comment) / blank \(blank)" }

    public var code: Int
    public var comment: Int
    public var blank: Int

    public init(code: Int = 0, comment: Int = 0, blank: Int = 0) {
        self.code = code
        self.comment = comment
        self.blank = blank
    }

    public static func + (a: Counts, b: Counts) -> Counts {
        Counts(code: a.code + b.code, comment: a.comment + b.comment, blank: a.blank + b.blank)
    }

    public static func - (a: Counts, b: Counts) -> Counts {
        Counts(code: a.code - b.code, comment: a.comment - b.comment, blank: a.blank - b.blank)
    }
}

/// One `cloc --diff` result: the four sections it emits, plus the two derived figures
/// TASK §3.4 asks for.
public struct DiffStats: Codable, Sendable, Equatable {
    public var added: Counts
    public var removed: Counts
    public var modified: Counts
    public var same: Counts

    public init(
        added: Counts = .init(), removed: Counts = .init(),
        modified: Counts = .init(), same: Counts = .init()
    ) {
        self.added = added
        self.removed = removed
        self.modified = modified
        self.same = same
    }

    /// `added - removed`. This is the figure that agrees with git and with the
    /// heuristic TASK §6 pinned; `modified` is churn in place and belongs to neither
    /// side of it.
    public var net: Counts { added - removed }

    /// Comment lines per net code line — **nil when net code ≤ 0**.
    ///
    /// Commit `56e706f7d` is `code −33 / comment +21`; a ratio there prints `−0.64`,
    /// which is worse than printing nothing (TASK §3.4). That commit is the most
    /// interesting row in the fixture set, so this is the main case, not an edge one.
    public var commentToCodeRatio: Double? {
        guard net.code > 0 else { return nil }
        return (Double(net.comment) / Double(net.code) * 100).rounded() / 100
    }

    public static func + (a: DiffStats, b: DiffStats) -> DiffStats {
        DiffStats(
            added: a.added + b.added, removed: a.removed + b.removed,
            modified: a.modified + b.modified, same: a.same + b.same)
    }
}
