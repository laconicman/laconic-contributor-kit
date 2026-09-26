import Foundation
import Testing

@testable import ContributorKit

/// The fixtures are the specification (<doc:Design>). Assertions read `manifest.json`
/// rather than numbers retyped into Swift, so a figure that drifts shows up as a
/// failing comparison against a measured document instead of against a memory.
enum Fixtures {
    static let root: URL = {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures/ is missing from the test bundle")
        }
        return url
    }()

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appending(path: relativePath))
    }

    struct Manifest: Decodable {
        var clocVersion: String
        var fixtures: [Fixture]

        struct Fixture: Decodable {
            var file: String
            var kind: String
            var refA: String
            var refB: String
            var cloc: Sections
            var net: Counts
            var commentToCodeRatio: Double?
            var byRole: [String: RoleSections]?
            var paths: [String: String]?
            var heuristic: Heuristic?
            var agrees: Bool?
        }

        struct Sections: Decodable {
            var added: Counts
            var removed: Counts
            var modified: Counts
        }

        struct RoleSections: Decodable {
            var added: Counts
            var removed: Counts
            var modified: Counts
            var net: Counts
        }

        struct Heuristic: Decodable {
            var source: String
            var code: Int
            var comment: Int
            var blank: Int?
        }
    }

    static func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: try data("manifest.json"))
    }

    struct ThreadsManifest: Decodable {
        var repo: String
        var me: String
        var prs: [String: PR]

        struct PR: Decodable {
            var comments_total: Int
            var root_threads_from_others: Int
            var answered: Int
            var unanswered: Int
            var unanswered_ids: [Int]
            var review_bodies: Int
            var rounds: [String: Int]
        }
    }

    static func threadsManifest() throws -> ThreadsManifest {
        try JSONDecoder().decode(ThreadsManifest.self, from: try data("threads-manifest.json"))
    }

    /// A `RecordedCommandRunner` that answers one `cloc` invocation from a fixture.
    static func clocRunner(_ file: String, match: [String] = ["--diff"]) throws
        -> RecordedCommandRunner
    {
        RecordedCommandRunner([
            try .file(match: match, root.appending(path: file))
        ])
    }

    static func cloc(_ runner: RecordedCommandRunner) -> Cloc {
        Cloc(executable: "cloc", runner: runner)
    }
}

extension Fixtures {
    /// Decode one PR's three channels from the REST-shaped capture.
    ///
    /// `comments` selects between the live capture and the derived positive case;
    /// `reviews` between the capture and the derived self-authored one.
    static func threads(
        pr: Int, comments: String? = nil, reviews: String? = nil, me: String = "laconicman"
    ) throws -> PullRequestThreads {
        try RESTThreadDecoder.decode(
            .init(
                repository: "pjsip/pjproject", number: pr, me: me,
                comments: try data("threads/" + (comments ?? "pr-\(pr).comments.json")),
                reviews: try data("threads/" + (reviews ?? "pr-\(pr).reviews.json")),
                issueComments: try data("threads/pr-\(pr).issuecomments.json")))
    }

    /// One `laconicman/telegram-kb` pull request from `Fixtures/resolution/`, decoded by
    /// the live client rather than a test decoder: each file is a one-page
    /// `ThreadDetail.graphql` response whose thread nodes were copied verbatim from the
    /// captures issue #7 was written from (each file's `_fixture` key says which).
    static func resolution(pr: Int) async throws -> PullRequestThreads {
        let runner = RecordedCommandRunner([
            try .file(
                match: ["api", "graphql"],
                root.appending(path: "resolution/telegram-kb-pr-\(pr).json"))
        ])
        return try await GHCommandClient(runner: runner, queryPath: "unused")
            .threads(repository: "laconicman/telegram-kb", number: pr)
    }

    static func audit(me: String? = "laconicman", horizon: Date? = nil) throws -> InboundAudit {
        let config = try Configuration.builtInDefaults()
        return InboundAudit(
            me: me,
            stripper: try BoilerplateStripper(settings: config.inbound),
            supersession: SupersessionDetector(phrases: config.inbound.supersessionPhrases),
            informational: try InformationalDetector(
                patterns: config.inbound.informationalPatterns),
            verdicts: VerdictDetector(phrases: config.inbound.verdictPhrases),
            horizon: horizon)
    }
}
