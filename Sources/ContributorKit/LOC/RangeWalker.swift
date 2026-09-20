import Foundation

/// Resolves a `base..head` range against git and walks it — the branch total, and the
/// per-commit loop when asked for.
///
/// `--range` never touches the network, and must stay that way: the LOC half has to
/// remain usable offline and on a repo with no GitHub remote at all (<doc:Design>).
public struct RangeWalker: Sendable {
    public let repository: URL
    public let runner: any CommandRunner
    public let cloc: Cloc

    public init(repository: URL, runner: any CommandRunner, cloc: Cloc) {
        self.repository = repository
        self.runner = runner
        self.cloc = cloc
    }

    public struct Range: Sendable {
        public var base: String
        public var head: String
    }

    public static func parseRange(_ text: String) throws -> Range {
        // `a...b` (merge base) and `a..b` mean different things to git; cloc is handed
        // two refs either way, so resolve the three-dot form to a merge base first.
        if let r = text.range(of: "...") {
            return Range(base: String(text[..<r.lowerBound]), head: String(text[r.upperBound...]))
        }
        guard let r = text.range(of: "..") else {
            throw LocError.badRange(text)
        }
        let base = String(text[..<r.lowerBound]), head = String(text[r.upperBound...])
        guard !base.isEmpty, !head.isEmpty else { throw LocError.badRange(text) }
        return Range(base: base, head: head)
    }

    public func resolve(_ ref: String) async throws -> String {
        let out = try await runner.runExpectingOutput(
            ["git", "rev-parse", ref], cwd: repository)
        return out.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public struct Commit: Sendable {
        public var sha: String
        public var subject: String
    }

    public func commits(in range: Range) async throws -> [Commit] {
        let out = try await runner.runExpectingOutput(
            ["git", "log", "--reverse", "--format=%H%x1f%s", "\(range.base)..\(range.head)"],
            cwd: repository)
        return out.stdoutText.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Commit(sha: String(parts[0]), subject: String(parts[1]))
        }
    }

    /// The whole report for a range. `perCommit` and `byRole` are opt-in because each
    /// costs a `cloc` run per commit and a second run of the range respectively.
    public func report(
        range: Range, languages: [String], forceLang: [String: String],
        perCommit: Bool, byRole: Bool, ignoreWhitespace: Bool,
        classifier: FileRoleClassifier
    ) async throws -> LocReport {
        let plain = Cloc.Options(languages: languages, forceLang: forceLang)
        let total = try await cloc.diff(
            refA: range.base, refB: range.head, options: plain, cwd: repository)

        var modifiedIgnoringWhitespace: Int?
        if ignoreWhitespace {
            var options = plain
            options.ignoreWhitespace = true
            let doc = try await cloc.diff(
                refA: range.base, refB: range.head, options: options, cwd: repository)
            modifiedIgnoringWhitespace = doc.stats.modified.code
        }

        var roleStats: [String: DiffStats]?
        var pathRoles: [String: String]?
        if byRole {
            var options = plain
            options.byFile = true
            let doc = try await cloc.diff(
                refA: range.base, refB: range.head, options: options, cwd: repository)
            var stats: [String: DiffStats] = [:]
            var roles: [String: String] = [:]
            for (path, pathStats) in doc.byKey {
                let role = classifier.role(of: path) ?? "unclassified"
                roles[path] = role
                stats[role] = (stats[role] ?? DiffStats()) + pathStats
            }
            roleStats = stats
            pathRoles = roles
        }

        var commitReports: [LocReport.CommitReport]?
        if perCommit {
            var reports: [LocReport.CommitReport] = []
            for commit in try await commits(in: range) {
                let doc = try await cloc.diff(
                    refA: "\(commit.sha)^", refB: commit.sha, options: plain, cwd: repository)
                reports.append(
                    .init(sha: commit.sha, subject: commit.subject, stats: doc.stats))
            }
            commitReports = reports
        }

        return LocReport(
            repository: repository.lastPathComponent,
            refA: range.base, refB: range.head,
            capturedAt: Date(), languages: languages,
            total: total.stats,
            modifiedCodeIgnoringWhitespace: modifiedIgnoringWhitespace,
            byRole: roleStats, byPath: pathRoles, commits: commitReports)
    }
}

public enum LocError: Error, CustomStringConvertible {
    case badRange(String)

    public var description: String {
        switch self {
        case .badRange(let text):
            return "`\(text)` is not a range — expected <base>..<head>"
        }
    }
}
