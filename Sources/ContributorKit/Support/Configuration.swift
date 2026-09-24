import Foundation
import Yams

/// `.contributorkit.yml`, layered over the shipped defaults.
///
/// The shipped `contributorkit.default.yml` is a byte-identical copy of the fixtures'
/// file, which is itself generated from the script that measured the role
/// distribution. `ConfigurationTests` asserts the two are identical, so the shipped
/// defaults and the measured numbers cannot drift (fixtures README).
public struct Configuration: Codable, Sendable {
    public var roles: [RoleRule]
    public var offerPhrases: [String]
    public var cloc: ClocSettings
    public var register: RegisterSettings
    public var inbound: InboundSettings

    public struct RoleRule: Codable, Sendable {
        public var role: String
        public var globs: [String]
    }

    public struct ClocSettings: Codable, Sendable {
        public var forceLang: [String: String]
        public var defaultLanguages: [String]
    }

    public struct RegisterSettings: Codable, Sendable {
        public var referenceStyle: String
    }

    public struct InboundSettings: Codable, Sendable {
        /// `horizon` parsed, or `nil` when unset. An unparseable value throws rather
        /// than being ignored — a horizon that quietly does nothing hides exactly what
        /// it was set to scope.
        public func horizonDate() throws -> Date? {
            guard let horizon, !horizon.isEmpty else { return nil }
            if let date = GitHubTime.parse(horizon) { return date }
            if let date = try? Date(horizon, strategy: .iso8601.year().month().day()) {
                return date
            }
            throw ConfigurationError.badHorizon(horizon)
        }

        public var boilerplateBlocks: [String]
        public var boilerplatePatterns: [String]
        public var supersessionPhrases: [String]
        public var informationalPatterns: [String]
        /// `<summary>` phrases whose `<details>` block unwraps into prose;
        /// anything else collapses to a `[collapsed: …]` marker line.
        public var keptDetailsSummaries: [String]
        /// A review-history boundary, `YYYY-MM-DD` or an ISO timestamp.
        ///
        /// Items raised before it are **counted and not listed** — the repository
        /// declaring, in a file a human reads and git versions, that an era is not
        /// under audit. Nothing is cleared and nothing is claimed absorbed: writing
        /// dozens of acknowledgements asserting an absorption that did not happen is
        /// the bulk-ack the obligation model refuses, and burying it in a state
        /// directory makes it less visible, not more.
        public var horizon: String?
        public var acknowledgementKinds: [String]
    }

    // A file may override any subset, so every key is optional on the way in.
    fileprivate struct Partial: Decodable {
        var roles: [RoleRule]?
        var offerPhrases: [String]?
        var cloc: ClocSettings?
        var register: RegisterSettings?
        var inbound: PartialInbound?

        /// `inbound:` merges per sub-key, unlike `roles:`.
        ///
        /// The whole-key rule exists because the role list's **order** is the contract
        /// and a merged order is nobody's. Nothing in `inbound` is ordered against
        /// anything else, so demanding that a repo restate every pattern list to set a
        /// single horizon is cost with no reason — and the failure was a decoding error
        /// naming an unrelated key.
        struct PartialInbound: Decodable {
            var boilerplateBlocks: [String]?
            var boilerplatePatterns: [String]?
            var supersessionPhrases: [String]?
            var informationalPatterns: [String]?
            var keptDetailsSummaries: [String]?
            var acknowledgementKinds: [String]?
            var horizon: String?

            func merged(into base: InboundSettings) -> InboundSettings {
                var out = base
                if let v = boilerplateBlocks { out.boilerplateBlocks = v }
                if let v = boilerplatePatterns { out.boilerplatePatterns = v }
                if let v = supersessionPhrases { out.supersessionPhrases = v }
                if let v = informationalPatterns { out.informationalPatterns = v }
                if let v = keptDetailsSummaries { out.keptDetailsSummaries = v }
                if let v = acknowledgementKinds { out.acknowledgementKinds = v }
                if let v = horizon { out.horizon = v }
                return out
            }
        }

        static func from(resource name: String) throws -> Self {
            guard
                let url = Bundle.module.url(
                    forResource: "Resources/\(name)", withExtension: nil)
            else { throw ConfigurationError.missingResource(name) }
            return try from(yaml: try String(contentsOf: url, encoding: .utf8))
        }

        static func from(yaml: String) throws -> Self {
            try YAMLDecoder().decode(Self.self, from: yaml)
        }
    }

    /// The shipped `contributorkit.default.yml`, verbatim.
    ///
    /// Exposed so the drift test can compare it byte-for-byte with the fixtures' copy
    /// — the fixtures README's rule is that the shipped defaults and the measured role
    /// distribution cannot drift, and a comparison of parsed structures would not
    /// catch a comment or an ordering change that a later reader would trust.
    public static func defaultYAMLText() throws -> String {
        guard
            let url = Bundle.module.url(
                forResource: "Resources/contributorkit.default.yml", withExtension: nil)
        else { throw ConfigurationError.missingResource("contributorkit.default.yml") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The defaults as shipped. Two files, because they have two different
    /// provenances and <doc:Design> states provenance per claim.
    public static func builtInDefaults() throws -> Configuration {
        let measured = try Partial.from(resource: "contributorkit.default.yml")
        let reasoned = try Partial.from(resource: "inbound.default.yml")
        guard
            let roles = measured.roles, let offerPhrases = measured.offerPhrases,
            let cloc = measured.cloc, let register = measured.register,
            let partial = reasoned.inbound,
            let blocks = partial.boilerplateBlocks,
            let patterns = partial.boilerplatePatterns,
            let supersession = partial.supersessionPhrases,
            let informational = partial.informationalPatterns,
            let keptDetails = partial.keptDetailsSummaries,
            let kinds = partial.acknowledgementKinds
        else {
            throw ConfigurationError.incompleteDefaults
        }
        return Configuration(
            roles: roles, offerPhrases: offerPhrases, cloc: cloc, register: register,
            inbound: InboundSettings(
                boilerplateBlocks: blocks, boilerplatePatterns: patterns,
                supersessionPhrases: supersession, informationalPatterns: informational,
                keptDetailsSummaries: keptDetails,
                horizon: partial.horizon, acknowledgementKinds: kinds))
    }

    /// Defaults, then `.contributorkit.yml` from `directory` if one is there.
    /// Overriding is per top-level key, not a deep merge: a file that supplies
    /// `roles:` replaces the whole ordered list, because the *order* is the contract
    /// (<doc:Design>) and a merged order is nobody's.
    public static func load(directory: URL) throws -> Configuration {
        var config = try builtInDefaults()
        let url = directory.appending(path: ".contributorkit.yml")
        guard FileManager.default.fileExists(atPath: url.path) else { return config }
        let partial = try Partial.from(yaml: try String(contentsOf: url, encoding: .utf8))
        if let v = partial.roles { config.roles = v }
        if let v = partial.offerPhrases { config.offerPhrases = v }
        if let v = partial.cloc { config.cloc = v }
        if let v = partial.register { config.register = v }
        if let v = partial.inbound { config.inbound = v.merged(into: config.inbound) }
        return config
    }

    /// The role rules compiled once, in order. First match wins.
    public func roleClassifier() throws -> FileRoleClassifier {
        try FileRoleClassifier(rules: roles)
    }
}

public enum ConfigurationError: Error, CustomStringConvertible {
    case missingResource(String)
    case incompleteDefaults
    case badHorizon(String)

    public var description: String {
        switch self {
        case .missingResource(let name):
            return "bundled resource \(name) is missing from the ContributorKit bundle"
        case .incompleteDefaults:
            return "the bundled defaults do not cover every configuration key"
        case .badHorizon(let text):
            return "inbound.horizon `\(text)` is not a date — expected YYYY-MM-DD or an ISO timestamp"
        }
    }
}
