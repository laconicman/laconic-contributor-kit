import Foundation

/// Append-only JSONL: it diffs, it greps, `jq` reads it, git versions it. No SQLite in
/// pass 1 — `cloc --sql` exists if that ever changes (TASK §3.5).
public struct Ledger: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func append(_ report: LocReport) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(report)
        line.append(0x0A)

        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
