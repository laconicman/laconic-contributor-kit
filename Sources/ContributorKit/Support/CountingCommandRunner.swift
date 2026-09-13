import Foundation

/// Wraps another runner and counts what it was actually asked to run.
///
/// This is the provenance block's evidence of execution. A command that reports
/// "0 anomalies" having run nothing is the failure mode the field report's rule 5
/// names: a verification that cannot distinguish "ran and passed" from "did not run"
/// reports success in both cases. The count is cheap and makes the difference visible.
public final class CountingCommandRunner: CommandRunner, @unchecked Sendable {
    private let wrapped: any CommandRunner
    private let lock = NSLock()
    private var _count = 0
    private var _failures = 0

    public init(_ wrapped: any CommandRunner) {
        self.wrapped = wrapped
    }

    public var count: Int { lock.withLock { _count } }
    public var failures: Int { lock.withLock { _failures } }

    public func run(_ argv: [String], cwd: URL?) async throws -> CommandOutput {
        lock.withLock { _count += 1 }
        let out = try await wrapped.run(argv, cwd: cwd)
        if out.status != 0 { lock.withLock { _failures += 1 } }
        return out
    }
}
