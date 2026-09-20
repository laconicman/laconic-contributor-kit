import Foundation

/// Where the snapshot lives, and the lock that keeps two audits from losing each
/// other's history.
///
/// **Outside the work tree**, under the XDG state directory, so "it must not reach an
/// upstream-bound branch" is true by construction rather than by an exclude file
/// somebody has to maintain. `--state-dir` overrides it.
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

    /// `<dir>/<owner>/<repo>.json`.
    ///
    /// The separator used to be `__`, which is **not injective**: `a/b__c` and `a__b/c`
    /// are both valid GitHub names and both collided on `a__b__c.json`, so auditing one
    /// could load and then overwrite the other's history. A path component per name
    /// cannot collide, because `/` is the one character a GitHub owner or repo name
    /// cannot contain.
    public func url(for repository: String) -> URL {
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return directory.appending(path: sanitized(repository) + ".json")
        }
        return directory.appending(path: sanitized(parts[0]))
            .appending(path: sanitized(parts[1]) + ".json")
    }

    /// Defence for the one case the path split cannot cover: a name carrying `.` or `/`
    /// that GitHub would reject but a caller could still pass.
    private func sanitized(_ component: String) -> String {
        component.replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "..", with: "%2E%2E")
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
        // A file that names a different repository is an aliasing bug, not prior state.
        guard snapshot.repository == repository else {
            throw SnapshotError.repositoryMismatch(
                found: snapshot.repository, expected: repository, path: url.path)
        }
        return snapshot
    }

    public func save(_ snapshot: Snapshot) throws {
        let url = url(for: snapshot.repository)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// Runs `body` holding an exclusive lock on this repository's snapshot.
    ///
    /// A snapshot holds every audited pull request and issue for one repository, and
    /// `contrib in` is a read-modify-write across the whole file. Atomic replacement
    /// stops a torn file; it does not stop two audits of different PRs in the same
    /// repository from both reading version N and each writing their own N+1, so the
    /// later write silently drops the earlier one's subject.
    public func withLock<T>(repository: String, _ body: () throws -> T) throws -> T {
        let url = url(for: repository)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = url.deletingPathExtension().appendingPathExtension("lock").path

        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw SnapshotError.lockFailed(path: lockPath, errno: errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw SnapshotError.lockFailed(path: lockPath, errno: errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
