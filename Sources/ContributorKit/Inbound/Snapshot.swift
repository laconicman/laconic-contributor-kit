import Foundation

/// The local, per-repository record of what the world looked like last run.
///
/// This is the piece §§1–12 do not have, and the field report is right that it is the
/// capability rather than an optimisation: one round's raw fetch was 18 inline
/// comments, of which six were new findings, four were reviewer resolutions, four were
/// our own replies and four were already answered. Set arithmetic over
/// `in_reply_to_id` does not distinguish any of those. **A `contrib in` run without
/// prior-round state is not a weaker version of the tool — on a second round it is
/// actively misleading.**
public struct Snapshot: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Snapshot.currentSchemaVersion
    public var repository: String
    public var updatedAt: Date
    public var entries: [String: Entry]
    /// Ids of comments **I** authored, recorded as authored rather than as items.
    ///
    /// My own comments are never entries — the audit skips them before it records
    /// anything — so without this the one comment worth pointing an acknowledgement at
    /// is the one kind that could never verify.
    public var authored: Set<String> = []

    public struct Entry: Codable, Sendable {
        public var kind: Channel
        public var url: String
        public var author: String
        public var createdAt: Date
        public var updatedAt: Date?
        public var lastEditedAt: Date?
        public var bodySha256: String
        /// What the audit concluded about this item last run.
        ///
        /// Without it the differ compares bodies and authorship only, so it can see a
        /// new or edited comment and **structurally cannot see a resolution** — it
        /// reported "nothing moved" in the run immediately after six threads were
        /// answered and one obligation acknowledged. That is a report of absence that
        /// cannot tell *nothing happened* from *this check cannot see what happened*.
        public var state: ItemState?
        public var firstSeen: Date
        public var myReplyID: String?
        public var myReplyAt: Date?
        public var acknowledged: Acknowledgement?
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, repository, updatedAt, entries, authored
    }

    /// Hand-written so that fields added after a snapshot was written decode as absent
    /// rather than throwing. Synthesized `Decodable` ignores property defaults: adding
    /// `authored` broke every existing state dir on upgrade with `keyNotFound`, thrown
    /// before the schema-version guard could say anything useful. Every field added
    /// from here on is `decodeIfPresent`, and gets a fixture in
    /// `SnapshotCompatibilityTests`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        repository = try container.decode(String.self, forKey: .repository)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        entries = try container.decode([String: Entry].self, forKey: .entries)
        authored = try container.decodeIfPresent(Set<String>.self, forKey: .authored) ?? []
    }

    public init(
        repository: String, updatedAt: Date = Date(),
        entries: [String: Entry] = [:], authored: Set<String> = []
    ) {
        self.repository = repository
        self.updatedAt = updatedAt
        self.entries = entries
        self.authored = authored
    }

    public var age: TimeInterval { Date().timeIntervalSince(updatedAt) }
}

/// Where the snapshot lives.
///
/// **Outside the work tree**, under the XDG state directory, so "it must not reach an
/// upstream-bound branch" (TASK §13.7.1) is true by construction rather than by an
/// exclude file somebody has to maintain. `--state-dir` overrides it.
public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base =
                ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map {
                    URL(fileURLWithPath: $0)
                }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: ".local/state")
            self.directory = base.appending(path: "contributorkit")
        }
    }

    public func url(for repository: String) -> URL {
        directory.appending(path: repository.replacingOccurrences(of: "/", with: "__") + ".json")
    }

    /// `nil` when no snapshot exists yet — the first run, which every caller must
    /// report rather than silently treat as "nothing changed".
    public func load(repository: String) throws -> Snapshot? {
        let url = url(for: repository)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: try Data(contentsOf: url))
        guard snapshot.schemaVersion == Snapshot.currentSchemaVersion else {
            throw SnapshotError.schemaMismatch(
                found: snapshot.schemaVersion, expected: Snapshot.currentSchemaVersion)
        }
        return snapshot
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url(for: snapshot.repository), options: .atomic)
    }
}

public enum SnapshotError: Error, CustomStringConvertible {
    case schemaMismatch(found: Int, expected: Int)
    case unknownItem(String)

    public var description: String {
        switch self {
        case .schemaMismatch(let found, let expected):
            return "snapshot schema v\(found) cannot be read by this build (expects v\(expected)) — delete it to start a fresh baseline"
        case .unknownItem(let id):
            return "no item `\(id)` in the snapshot — run `contrib in` for this PR first"
        }
    }
}
