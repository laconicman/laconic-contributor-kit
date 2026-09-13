import Foundation

/// Fixture playback — the whole testability story (TASK §2.1).
///
/// A recording matches when every one of its `match` fragments appears in the joined
/// argv. Unmatched commands throw rather than returning empty output: a recorded
/// runner that silently answers "nothing" to a command nobody recorded is the
/// unexecuted check the feedback's rule 5 is about.
public final class RecordedCommandRunner: CommandRunner, @unchecked Sendable {
    public struct Recording: Sendable {
        public let match: [String]
        public let status: Int32
        public let stdout: Data
        public let stderr: Data

        public init(match: [String], status: Int32 = 0, stdout: Data, stderr: Data = Data()) {
            self.match = match
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }

        public static func file(
            match: [String], _ url: URL, status: Int32 = 0
        ) throws -> Recording {
            Recording(match: match, status: status, stdout: try Data(contentsOf: url))
        }
    }

    private let recordings: [Recording]
    private let lock = NSLock()
    private var _calls: [[String]] = []
    private var _used: Set<Int> = []

    public init(_ recordings: [Recording]) {
        self.recordings = recordings
    }

    /// Every argv this runner was asked for, in order. Tests assert on it to prove the
    /// code under test actually reached the subprocess seam.
    public var calls: [[String]] {
        lock.withLock { _calls }
    }

    /// Recordings nobody asked for. A non-empty list means the code took a path the
    /// fixture did not expect — usually a channel that was silently skipped.
    public var unusedRecordings: [[String]] {
        lock.withLock {
            recordings.enumerated().filter { !_used.contains($0.offset) }.map(\.element.match)
        }
    }

    public func run(_ argv: [String], cwd: URL?) async throws -> CommandOutput {
        let joined = argv.joined(separator: " ")
        return try lock.withLock {
            _calls.append(argv)
            guard
                let hit = recordings.enumerated().first(where: { _, r in
                    r.match.allSatisfy { joined.contains($0) }
                })
            else {
                throw CommandError.noRecording(argv: argv)
            }
            _used.insert(hit.offset)
            return CommandOutput(
                argv: argv, status: hit.element.status,
                stdout: hit.element.stdout, stderr: hit.element.stderr)
        }
    }
}
