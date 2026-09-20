import Foundation

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
