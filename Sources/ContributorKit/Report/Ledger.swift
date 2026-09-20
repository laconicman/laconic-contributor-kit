import Foundation

/// Append-only JSONL: it diffs, it greps, `jq` reads it, git versions it. No SQLite in
/// pass 1 — `cloc --sql` exists if that ever changes (<doc:Design>).
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

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // `O_APPEND` plus a single `write` — not seek-then-write on a shared handle.
        // Two CI jobs appending to one ledger could both seek to the same offset and
        // then both write there, losing a row or interleaving two into a malformed one.
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw LedgerError.cannotOpen(path: url.path, errno: errno)
        }
        defer { close(descriptor) }

        try line.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let n = write(descriptor, buffer.baseAddress! + written, buffer.count - written)
                guard n > 0 else {
                    throw LedgerError.writeFailed(path: url.path, errno: errno)
                }
                written += n
            }
        }
    }
}

public enum LedgerError: Error, CustomStringConvertible {
    case cannotOpen(path: String, errno: Int32)
    case writeFailed(path: String, errno: Int32)

    public var description: String {
        switch self {
        case .cannotOpen(let path, let code):
            return "could not open ledger \(path): \(String(cString: strerror(code)))"
        case .writeFailed(let path, let code):
            return "could not append to ledger \(path): \(String(cString: strerror(code)))"
        }
    }
}
