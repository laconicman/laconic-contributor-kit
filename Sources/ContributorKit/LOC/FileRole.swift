import Foundation

/// Ordered, first match wins. The order is part of the contract, not an accident
/// (TASK §3.3): `tests/automated/Makefile` lands in `build`, and
/// `third_party/**/test/**` lands in `vendor`. Both are defensible; both are one move
/// in `.contributorkit.yml` to change.
public struct FileRoleClassifier: Sendable {
    public struct CompiledRule: Sendable {
        public let role: String
        public let globs: [Glob]
    }

    public let rules: [CompiledRule]

    public init(rules: [Configuration.RoleRule]) throws {
        self.rules = try rules.map {
            CompiledRule(role: $0.role, globs: try $0.globs.map(Glob.init))
        }
    }

    /// The role of `path`, or `nil` if no rule matches. The shipped defaults end with
    /// `source: ["**"]`, so `nil` means someone removed the catch-all — which is worth
    /// reporting rather than silently bucketing.
    public func role(of path: String) -> String? {
        for rule in rules where rule.globs.contains(where: { $0.matches(path) }) {
            return rule.role
        }
        return nil
    }
}
