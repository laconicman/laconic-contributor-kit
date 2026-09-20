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

        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw LedgerError.cannotOpen(path: url.path, errno: errno)
        }
        defer { close(descriptor) }

        // The whole seek/write/rollback is one transaction, and `start` is captured
        // only once the lock is held. `O_APPEND` places a write at the then-current
        // end but reserves nothing: without the lock another process could append a
        // complete row after `start` was read, and a rollback would then delete that
        // row along with this one's remains.
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw LedgerError.lockFailed(path: url.path, errno: errno)
        }
        defer { flock(descriptor, LOCK_UN) }

        let start = lseek(descriptor, 0, SEEK_END)
        var writeError: Int32?
        var written = 0
        line.withUnsafeBytes { buffer in
            while written < buffer.count {
                let n = write(descriptor, buffer.baseAddress! + written, buffer.count - written)
                if n > 0 {
                    written += n
                } else {
                    writeError = errno
                    return
                }
            }
        }
        guard let failure = writeError else { return }

        // The original write error is what the caller needs; a rollback that also
        // fails is a second, worse fact and is reported rather than swallowed.
        if written > 0, start >= 0, ftruncate(descriptor, start) != 0 {
            throw LedgerError.rollbackFailed(
                path: url.path, writeErrno: failure, truncateErrno: errno, offset: start)
        }
        throw LedgerError.writeFailed(path: url.path, errno: failure)
    }
}

public enum LedgerError: Error, CustomStringConvertible {
    case cannotOpen(path: String, errno: Int32)
    case writeFailed(path: String, errno: Int32)
    case lockFailed(path: String, errno: Int32)
    case rollbackFailed(path: String, writeErrno: Int32, truncateErrno: Int32, offset: off_t)

    public var description: String {
        switch self {
        case .cannotOpen(let path, let code):
            return "could not open ledger \(path): \(String(cString: strerror(code)))"
        case .writeFailed(let path, let code):
            return "could not append to ledger \(path): \(String(cString: strerror(code)))"
        case .lockFailed(let path, let code):
            return "could not lock ledger \(path): \(String(cString: strerror(code)))"
        case .rollbackFailed(let path, let write, let truncate, let offset):
            return """
                ledger \(path) is left with a partial row: the append failed \
                (\(String(cString: strerror(write)))) and rolling back to offset \
                \(offset) also failed (\(String(cString: strerror(truncate)))). \
                Trim the last line by hand before reading it.
                """
        }
    }
}
