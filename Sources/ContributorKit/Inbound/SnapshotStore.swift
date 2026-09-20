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

    /// Where snapshots lived before the collision fix: `<dir>/<owner>__<repo>.json`.
    ///
    /// Read for migration only. Changing a storage path silently abandons every
    /// existing state directory, and a lost snapshot is not a cosmetic loss — the
    /// history is what makes a second round a differ rather than a fresh baseline.
    public func legacyURL(for repository: String) -> URL {
        directory.appending(
            path: repository.replacingOccurrences(of: "/", with: "__") + ".json")
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
        let current = try decode(url(for: repository), expecting: repository)
        // A legacy file is best-effort: the old layout was not injective, so the path
        // this repository would have used may belong to a different one. That is the
        // collision being migrated away from — it must not make a perfectly good current
        // snapshot unreadable.
        let legacy = (try? decode(legacyURL(for: repository), expecting: repository)) ?? nil

        // **Merged, never preferred.** Both files can exist and hold *different*
        // subjects: a run on the new path after the collision fix leaves the old file
        // untouched, so choosing one would make the other's pull requests invisible and
        // the next save would delete them. Observed on a real state directory, where the
        // two files held #28 and #29 of the same repository.
        switch (current, legacy) {
        case (nil, nil): return nil
        case (let only?, nil): return only
        case (nil, let only?): return only
        case (var merged?, let old?):
            for (id, entry) in old.entries where merged.entries[id] == nil {
                merged.entries[id] = entry
            }
            merged.authored.formUnion(old.authored)
            return merged
        }
    }

    private func decode(_ url: URL, expecting repository: String) throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: try Data(contentsOf: url))
        guard snapshot.schemaVersion == Snapshot.currentSchemaVersion else {
            throw SnapshotError.schemaMismatch(
                found: snapshot.schemaVersion, expected: Snapshot.currentSchemaVersion)
        }
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

        // The pre-collision-fix file has been superseded by this write. Removed only
        // after the new one is safely on disk, only when the two are different paths,
        // and only when it actually belongs to this repository — the old layout could
        // alias, so deleting on filename alone would destroy another repo's history.
        let legacy = legacyURL(for: snapshot.repository)
        let owned = (try? decode(legacy, expecting: snapshot.repository)) ?? nil
        if legacy != url, owned != nil {
            try? FileManager.default.removeItem(at: legacy)
        }
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
